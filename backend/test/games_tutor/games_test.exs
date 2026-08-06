defmodule GamesTutor.GamesTest do
  # Not async: the "ends on the human's own move" case starts a real
  # Chess.GameServer (real Stockfish subprocesses) to replay the truncated
  # move list, same convention as the GameServer integration tests.
  use GamesTutor.DataCase, async: false

  alias GamesTutor.{Accounts, Games}
  alias GamesTutor.Games.{Game, Move}

  defp register_user do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "games-test-#{System.unique_integer([:positive])}@example.com",
        "password" => "correcthorsebattery"
      })

    user
  end

  defp insert_game!(user, attrs) do
    base = %{
      user_id: user.id,
      game_type: "chess",
      human_color: "white",
      # Real games always get a resolved opponent config via
      # Games.resolve_opponent_config/3 before insert (create_game/2) --
      # an empty map only happens here because this fixture builds the
      # changeset directly, and Chess.GameServer.configure_opponent_strength/2
      # has no clause for it.
      opponent_engine_config: %{"elo" => 800},
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    {:ok, game} = %Game{} |> Game.create_changeset(Map.merge(base, attrs)) |> Repo.insert()
    game
  end

  defp insert_move!(game, ply, player, uci) do
    attrs = %{game_id: game.id, ply: ply, player: player, notation: uci, uci: uci, fen_after: "irrelevant-for-undo"}
    {:ok, move} = %Move{} |> Move.create_changeset(attrs) |> Repo.insert()
    move
  end

  test "undo_move drops the human's last move and the engine's reply, restoring \"your turn\"" do
    user = register_user()
    game = insert_game!(user, %{})
    insert_move!(game, 1, "human", "e2e4")
    insert_move!(game, 2, "engine", "e7e5")

    assert {:ok, updated} = Games.undo_move(user, game.id)
    assert updated.moves == []
    assert updated.status == "in_progress"
  end

  test "undo_move reopens a game that ended on the human's own move (no engine reply to drop)" do
    user = register_user()
    game = insert_game!(user, %{status: "checkmate", result: "white_wins", ended_at: DateTime.utc_now() |> DateTime.truncate(:second)})

    # Scholar's Mate -- a known-legal 7-ply line (same sequence the
    # Chess.GameServer test uses), inserted directly so this test is
    # deterministic instead of depending on a live opponent falling for it.
    ~w(e2e4 e7e5 f1c4 b8c6 d1h5 g8f6 h5f7)
    |> Enum.with_index(1)
    |> Enum.each(fn {uci, ply} ->
      player = if rem(ply, 2) == 1, do: "human", else: "engine"
      insert_move!(game, ply, player, uci)
    end)

    assert {:ok, updated} = Games.undo_move(user, game.id)
    assert updated.status == "in_progress"
    assert updated.result == nil
    assert updated.ended_at == nil
    assert Enum.map(updated.moves, & &1.uci) == ~w(e2e4 e7e5 f1c4 b8c6 d1h5 g8f6)
  end

  test "undo_move refuses calibration games (would contaminate the skill measurement)" do
    user = register_user()
    game = insert_game!(user, %{is_calibration: true})
    insert_move!(game, 1, "human", "e2e4")
    insert_move!(game, 2, "engine", "e7e5")

    assert {:error, :undo_refused_calibration} = Games.undo_move(user, game.id)
  end

  test "undo_move refuses a game with no moves yet" do
    user = register_user()
    game = insert_game!(user, %{})

    assert {:error, :no_moves_to_undo} = Games.undo_move(user, game.id)
  end
end
