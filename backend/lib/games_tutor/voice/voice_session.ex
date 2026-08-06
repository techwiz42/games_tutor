defmodule GamesTutor.Voice.VoiceSession do
  @moduledoc """
  A record of one real-time voice connection -- minted for cost/duration
  tracking and rate-limiting, not for gating tool access (tool endpoints
  are ordinary JWT-authenticated, game-ownership-checked REST endpoints;
  see `GamesTutorWeb.GameController`'s board-state/move-analysis/hint
  actions).

  `mode` is derived server-side from `game.is_calibration` at session
  start, never taken from client input -- the calibration-proctor
  restriction (esp. `request_hint`'s hard refusal) has to hold even against
  a client that lies about the mode.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @modes ~w(calibration_proctor tutoring)
  @statuses ~w(active ended)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "voice_sessions" do
    belongs_to :user, GamesTutor.Accounts.User
    belongs_to :game, GamesTutor.Games.Game
    field :mode, :string
    field :status, :string, default: "active"
    field :model, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :duration_seconds, :integer
    field :estimated_cost_usd, :float

    timestamps(type: :utc_datetime)
  end

  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [:user_id, :game_id, :mode, :model, :started_at])
    |> validate_required([:user_id, :game_id, :mode, :model, :started_at])
    |> validate_inclusion(:mode, @modes)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:game_id)
  end

  def end_changeset(session, attrs) do
    session
    |> cast(attrs, [:status, :ended_at, :duration_seconds, :estimated_cost_usd])
    |> validate_required([:status, :ended_at, :duration_seconds, :estimated_cost_usd])
    |> validate_inclusion(:status, @statuses)
  end

  def modes, do: @modes
end
