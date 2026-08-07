defmodule GamesTutor.Repo.Migrations.AddPriorToMoves do
  use Ecto.Migration

  # Engine-layer review finding 2: KataGo's raw policy-network prior for
  # the move as actually played (0.0-1.0), looked up from the pre-move
  # position's `policy` array -- covers every point, including ones the
  # search never visited, unlike moveInfos. Nullable: nil for existing
  # rows (computed before this migration existed) and for chess moves
  # (Stockfish has no equivalent concept).
  def change do
    alter table(:moves) do
      add :prior, :float
    end
  end
end
