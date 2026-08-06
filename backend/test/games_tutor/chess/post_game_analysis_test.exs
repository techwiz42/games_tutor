defmodule GamesTutor.Chess.PostGameAnalysisTest do
  use GamesTutor.DataCase, async: false

  alias GamesTutor.{Accounts, Games}
  alias GamesTutor.Chess.PostGameAnalysis
  alias GamesTutor.Games.Move

  test "backfills eval/loss/classification for every move in a finished game" do
    {:ok, user} =
      Accounts.register_user(%{"email" => "pgatest@example.com", "password" => "correcthorsebattery"})

    {:ok, game} = Games.create_game(user, %{"opponent_elo" => 800})

    {:ok, _} = Games.submit_move(user, game.id, "e2e4")
    {:ok, _} = Games.submit_move(user, game.id, "d2d4")

    :ok = PostGameAnalysis.run(game.id)

    moves = Repo.all(Ecto.Query.from(m in Move, where: m.game_id == ^game.id, order_by: m.ply))
    assert length(moves) == 4

    Enum.each(moves, fn move ->
      assert is_integer(move.eval_before)
      assert is_integer(move.eval_after)
      assert is_integer(move.loss)
      assert move.loss >= 0
      assert move.classification in ~w(best good inaccuracy mistake blunder)
      assert is_binary(move.engine_best_move)
    end)
  end
end
