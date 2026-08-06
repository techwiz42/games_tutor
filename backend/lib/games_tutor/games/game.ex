defmodule GamesTutor.Games.Game do
  @moduledoc """
  A played game against the engine, generic across chess and Go (not
  chess-specific): `record` is reserved for a future PGN/SGF export
  feature (unused for now -- board state on process restore is
  reconstructed by replaying `moves`, not cached here). Human is always
  White in chess, always Black in Go (see each game type's GameServer
  moduledoc) -- `result` stores the literal board-color winner
  ("white_wins"/"black_wins"), so callers must know which color the human
  is playing to interpret it (see `GameJSON.summary/1`'s `human_color`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @game_types ~w(chess go)
  @statuses ~w(in_progress checkmate stalemate draw scored resigned aborted)
  @results ~w(white_wins black_wins draw)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "games" do
    belongs_to :user, GamesTutor.Accounts.User
    field :game_type, :string, default: "chess"
    field :status, :string, default: "in_progress"
    field :result, :string
    field :is_calibration, :boolean, default: false
    field :opponent_engine_config, :map, default: %{}
    field :record, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    has_many :moves, GamesTutor.Games.Move

    timestamps(type: :utc_datetime)
  end

  def create_changeset(game, attrs) do
    game
    |> cast(attrs, [
      :user_id,
      :game_type,
      :is_calibration,
      :opponent_engine_config,
      :started_at
    ])
    |> validate_required([:user_id, :game_type, :started_at])
    |> validate_inclusion(:game_type, @game_types)
    |> foreign_key_constraint(:user_id)
  end

  def finish_changeset(game, attrs) do
    game
    |> cast(attrs, [:status, :result, :record, :ended_at])
    |> validate_required([:status, :ended_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:result, @results ++ [nil])
  end

  def record_changeset(game, attrs) do
    cast(game, attrs, [:record])
  end

  def game_types, do: @game_types
  def statuses, do: @statuses
end
