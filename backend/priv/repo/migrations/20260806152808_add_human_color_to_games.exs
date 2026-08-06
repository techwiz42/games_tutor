defmodule GamesTutor.Repo.Migrations.AddHumanColorToGames do
  use Ecto.Migration

  # Nullable-then-backfill-then-not-null: existing rows must get the same
  # value the old hardcoded-by-game_type logic implied (chess -> white, go
  # -> black -- see GamesTutor.Games's prior human_color/1), not a single
  # blanket default, since a blanket "white" default would be wrong for
  # every existing Go game.
  def change do
    alter table(:games) do
      add :human_color, :string
    end

    execute(
      "UPDATE games SET human_color = 'white' WHERE game_type = 'chess'",
      "-- no-op down"
    )

    execute(
      "UPDATE games SET human_color = 'black' WHERE game_type = 'go'",
      "-- no-op down"
    )

    alter table(:games) do
      modify :human_color, :string, null: false
    end
  end
end
