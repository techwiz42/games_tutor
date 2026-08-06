defmodule GamesTutorWeb.VoiceJSON do
  alias GamesTutor.Voice

  def started(%{session: session, ephemeral_key: key, expires_at: expires_at}) do
    %{
      session_id: session.id,
      mode: session.mode,
      model: session.model,
      ephemeral_key: key,
      expires_at: expires_at,
      max_session_seconds: Voice.max_session_seconds()
    }
  end

  def ended(session) do
    %{
      session_id: session.id,
      status: session.status,
      duration_seconds: session.duration_seconds,
      estimated_cost_usd: session.estimated_cost_usd,
      total_tokens: session.total_tokens
    }
  end
end
