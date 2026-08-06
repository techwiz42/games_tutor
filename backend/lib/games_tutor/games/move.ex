defmodule GamesTutor.Games.Move do
  @moduledoc """
  A single ply. `uci` (e.g. "e2e4", "a7a8q") is the exact string applied to
  the board and is what replay/restore uses; `notation` (SAN, e.g. "Nf3",
  "O-O", "Qxf7#") is what the record/UI display. `eval_*`/`loss` are
  centipawns from the moving player's perspective; nil when analysis wasn't
  computed (e.g. non-calibration games at low depth, or the opponent's own
  moves).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @players ~w(human engine)
  @classifications ~w(best good inaccuracy mistake blunder)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "moves" do
    belongs_to :game, GamesTutor.Games.Game
    field :ply, :integer
    field :player, :string
    field :notation, :string
    field :uci, :string
    field :fen_after, :string
    field :eval_before, :integer
    field :eval_after, :integer
    field :loss, :integer
    field :engine_best_move, :string
    field :classification, :string
    field :think_time_ms, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def create_changeset(move, attrs) do
    move
    |> cast(attrs, [
      :game_id,
      :ply,
      :player,
      :notation,
      :uci,
      :fen_after,
      :eval_before,
      :eval_after,
      :loss,
      :engine_best_move,
      :classification,
      :think_time_ms
    ])
    |> validate_required([:game_id, :ply, :player, :notation, :uci, :fen_after])
    |> validate_inclusion(:player, @players)
    |> validate_inclusion(:classification, @classifications ++ [nil])
    |> foreign_key_constraint(:game_id)
    |> unique_constraint([:game_id, :ply])
  end

  def analysis_changeset(move, attrs) do
    cast(move, attrs, [:eval_before, :eval_after, :loss, :engine_best_move, :classification])
  end

  def classifications, do: @classifications
end
