defmodule GamesTutor.Repo.Migrations.AddClassificationVersionToMoves do
  use Ecto.Migration

  # Engine-layer review finding 3: existing moves.classification rows were
  # computed under the old fixed centipoint thresholds; backfilling them
  # under the new volatility-scaled thresholds isn't practical -- the
  # scoreStdev volatility figure the new thresholds need was never stored
  # for historical moves, only captured starting with finding 2's
  # extract_analysis/1 change, so an accurate backfill would mean
  # re-querying a live engine for every historical position. Versioning
  # instead: nil = classified under the old (Go.MoveClassifier's original)
  # fixed thresholds; 2 = classified under the volatility-scaled scheme.
  def change do
    alter table(:moves) do
      add :classification_version, :integer
    end
  end
end
