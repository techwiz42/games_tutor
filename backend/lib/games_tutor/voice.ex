defmodule GamesTutor.Voice do
  @moduledoc """
  Real-time voice tutoring sessions (OpenAI Realtime API over WebRTC).
  Backend mints a short-lived ephemeral credential; the browser holds the
  actual WebRTC connection directly to OpenAI (see the plan's "Voice"
  design section) -- this context only handles minting, rate-limiting,
  and session bookkeeping, never the audio itself.
  """

  alias GamesTutor.{Repo, Games}
  alias GamesTutor.Voice.{Tools, VoiceSession}

  # Confirmed correct in the Phase 0 spike (the plan's original guess,
  # "gpt-realtime-mini", was wrong -- OpenAI renamed it before this was
  # built for real).
  @model "gpt-realtime-2.1-mini"
  @openai_voice "marin"

  # Cost guardrails, built in from the start rather than retrofitted:
  # mini-only model (no standard-model opt-in exposed in v1 -- not offering
  # it in the UI *is* the gate), a hard max session duration, and a rough
  # per-minute cost estimate logged for every session (not real OpenAI
  # billing data -- there's no per-session usage readout from this API --
  # just a documented order-of-magnitude figure from the plan's own
  # research, $0.05-0.10/min with prompt caching).
  @max_session_seconds 900
  @estimated_cost_per_minute_usd 0.08

  @rate_limit_window_seconds 3600
  @rate_limit_max_starts 10

  @doc """
  Starts a voice session for `game_id`. Mode is derived server-side from
  the game's own `is_calibration` flag -- never trust client input for
  this, since request_hint's calibration refusal depends on it being real.

  Returns `{:ok, %{session:, ephemeral_key:, expires_at:}}` or
  `{:error, :rate_limited | :session_already_active | :not_found | {:openai_error, ...}}`.
  """
  def start_session(user, game_id) do
    with {:ok, game} <- Games.get_game(user, game_id),
         :ok <- check_rate_limit(user),
         :ok <- acquire_active_session_guard(user) do
      mode = if game.is_calibration, do: "calibration_proctor", else: "tutoring"

      case mint_ephemeral_key(mode, game.game_type) do
        {:ok, minted} ->
          {:ok, session} =
            %VoiceSession{}
            |> VoiceSession.create_changeset(%{
              user_id: user.id,
              game_id: game.id,
              mode: mode,
              model: @model,
              started_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })
            |> Repo.insert()

          :telemetry.execute([:games_tutor, :voice, :session_started], %{count: 1}, %{mode: mode})

          {:ok, %{session: session, ephemeral_key: minted.ephemeral_key, expires_at: minted.expires_at}}

        {:error, reason} ->
          release_active_session_guard(user)
          {:error, reason}
      end
    end
  end

  @doc """
  Ends an active session, recording duration, a rough cost estimate, and (if
  the browser captured any) real OpenAI-reported token usage accumulated
  across the session's response.done events.
  """
  def end_session(user, session_id, total_tokens \\ nil) do
    case Repo.get_by(VoiceSession, id: session_id, user_id: user.id) do
      nil ->
        {:error, :not_found}

      %VoiceSession{status: "ended"} ->
        {:error, :already_ended}

      %VoiceSession{} = session ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        duration = DateTime.diff(now, session.started_at)
        cost = duration / 60 * @estimated_cost_per_minute_usd

        {:ok, session} =
          session
          |> VoiceSession.end_changeset(%{
            status: "ended",
            ended_at: now,
            duration_seconds: duration,
            estimated_cost_usd: Float.round(cost, 4),
            total_tokens: total_tokens
          })
          |> Repo.update()

        release_active_session_guard(user)

        :telemetry.execute(
          [:games_tutor, :voice, :session_ended],
          %{duration_seconds: duration, estimated_cost_usd: cost},
          %{mode: session.mode}
        )

        {:ok, session}
    end
  end

  def max_session_seconds, do: @max_session_seconds

  ## Internal

  defp check_rate_limit(user) do
    GamesTutor.RateLimit.check("voice:rate:#{user.id}", @rate_limit_max_starts, @rate_limit_window_seconds)
  end

  defp acquire_active_session_guard(user) do
    case Redix.command(GamesTutor.Redis, [
           "SET",
           active_session_key(user),
           "1",
           "NX",
           "EX",
           to_string(@max_session_seconds)
         ]) do
      {:ok, "OK"} -> :ok
      {:ok, nil} -> {:error, :session_already_active}
    end
  end

  defp release_active_session_guard(user) do
    Redix.command(GamesTutor.Redis, ["DEL", active_session_key(user)])
    :ok
  end

  defp active_session_key(user), do: "voice:active:#{user.id}"

  defp mint_ephemeral_key(mode, game_type) do
    api_key = Application.fetch_env!(:games_tutor, :openai_api_key)

    body = %{
      session: %{
        type: "realtime",
        model: @model,
        instructions: Tools.instructions(mode, game_type),
        audio: %{output: %{voice: @openai_voice}},
        tools: Tools.schema(game_type),
        tool_choice: "auto"
      }
    }

    case Req.post("https://api.openai.com/v1/realtime/client_secrets",
           headers: [{"authorization", "Bearer #{api_key}"}],
           json: body,
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: %{"value" => key} = resp_body}} ->
        {:ok, %{ephemeral_key: key, expires_at: resp_body["expires_at"]}}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:openai_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:openai_request_failed, reason}}
    end
  end
end
