defmodule GamesTutor.Repo.Migrations.WidenMovesFenAfterToText do
  use Ecto.Migration

  # `fen_after` was `:string` (Postgres varchar(255)) -- fine for the
  # previous {size, grid} JSON blob (well under 255 chars: a 9x9 grid of
  # -1/0/1 integers), but finding 2's ownership map (81 floats, embedded
  # into this same blob -- see GameServer.board_json/2) is comfortably
  # over 255 characters and was silently truncating with a Postgrex
  # string_data_right_truncation error on every Go move. `:text` has no
  # length limit in Postgres.
  def change do
    alter table(:moves) do
      modify :fen_after, :text, from: :string
    end
  end
end
