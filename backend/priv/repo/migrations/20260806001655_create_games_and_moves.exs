defmodule GamesTutor.Repo.Migrations.CreateGamesAndMoves do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("uuid_generate_v4()")
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # "chess" today; "go" arrives in Phase 5 -- kept generic per the plan
      # rather than a chess-only table.
      add :game_type, :string, null: false, default: "chess"
      add :status, :string, null: false, default: "in_progress"
      add :result, :string
      add :is_calibration, :boolean, null: false, default: false
      add :opponent_engine_config, :map, null: false, default: %{}
      # PGN for chess, SGF for Go -- the move-record notation, not board state.
      # Board state on process restore is reconstructed by replaying/loading
      # this record rather than caching a redundant FEN/board column here.
      add :record, :text
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:games, [:user_id])
    create index(:games, [:status])

    create table(:moves, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("uuid_generate_v4()")
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :ply, :integer, null: false
      add :player, :string, null: false
      add :notation, :string, null: false
      add :uci, :string, null: false
      add :fen_after, :string, null: false
      add :eval_before, :integer
      add :eval_after, :integer
      add :loss, :integer
      add :engine_best_move, :string
      add :classification, :string
      add :think_time_ms, :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:moves, [:game_id, :ply])
  end
end
