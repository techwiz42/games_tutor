defmodule GamesTutor.Chess.GameServerTest do
  # Not async: shares the global Registry/DynamicSupervisor and spawns real
  # Stockfish subprocesses -- consistent with this project's "no mocks"
  # convention (see CLAUDE.md), but still a real integration test.
  use ExUnit.Case, async: false

  alias GamesTutor.Chess.GameServer

  defp new_game_id, do: Ecto.UUID.generate()

  test "plays a legal move and gets a real engine reply" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"skill_level" => 0})

    assert {:ok, %{status: :continue, human_move: human, engine_move: engine}} =
             GameServer.submit_human_move(game_id, "e2e4")

    assert human.player == "human"
    assert human.uci == "e2e4"
    assert is_integer(human.eval_before)
    assert is_integer(human.eval_after)
    assert human.loss >= 0
    assert human.classification in ~w(best good inaccuracy mistake blunder)

    assert engine.player == "engine"
    assert engine.ply == human.ply + 1
    # A real engine reply -- 4 or 5 chars of strict square notation.
    assert engine.uci =~ ~r/^[a-h][1-8][a-h][1-8][qrbn]?$/
  end

  test "rejects an illegal move without mutating game state" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"skill_level" => 0})

    assert {:error, {:illegal_move, _reason}} = GameServer.submit_human_move(game_id, "e2e5")

    # Board is still at the starting position -- e2e4 should still succeed.
    assert {:ok, %{status: :continue}} = GameServer.submit_human_move(game_id, "e2e4")
  end

  test "ensure_started is idempotent -- returns the same pid for an already-running game" do
    game_id = new_game_id()
    {:ok, pid1} = GameServer.ensure_started(game_id, %{"skill_level" => 0})
    {:ok, pid2} = GameServer.ensure_started(game_id, %{"skill_level" => 0})
    assert pid1 == pid2
  end

  test "restores from a move list (idle-eviction / process-restart recovery)" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"skill_level" => 0}, ["e2e4", "e7e5"])
    assert {:ok, fen} = GameServer.fen(game_id)
    assert fen =~ ~r/^rnbqkbnr\/pppp1ppp\/8\/4p3\/4P3\/8\/PPPP1PPP\/RNBQKBNR/
  end

  test "resign ends the game in the engine's favor" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"skill_level" => 0})
    assert {:ok, {:winner, :black, {:manual, :human_resigned}}} = GameServer.resign(game_id)
    assert {:error, :game_over} = GameServer.submit_human_move(game_id, "e2e4")
  end

  test "delivering checkmate ends the game with no engine_move on the final ply" do
    game_id = new_game_id()

    # Restore-from-moves replays a hand-picked sequence for BOTH sides (no
    # live opponent-engine decisions involved), so this sets up a
    # deterministic mate-in-1 (the textbook Scholar's Mate line, with
    # Black's final ...Nf6 blunder scripted rather than relying on a real
    # engine -- even a weak one -- reliably falling for the trap live).
    setup_moves = ~w(e2e4 e7e5 f1c4 b8c6 d1h5 g8f6)
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"skill_level" => 0}, setup_moves)

    assert {:ok, %{status: {:checkmate, :white_wins}, human_move: human, engine_move: nil}} =
             GameServer.submit_human_move(game_id, "h5f7")

    assert human.classification == "best"
    assert human.loss == 0
  end

  test "maybe_play_opening_move is a no-op when the human plays the default color (White)" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"skill_level" => 0})
    assert {:ok, :not_applicable} = GameServer.maybe_play_opening_move(game_id)
  end

  test "maybe_play_opening_move plays a real White opening move when the human chose Black" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"skill_level" => 0}, [], "black")

    assert {:ok, %{engine_move: move}} = GameServer.maybe_play_opening_move(game_id)
    assert move.player == "engine"
    assert move.ply == 1
    assert move.uci =~ ~r/^[a-h][1-8][a-h][1-8][qrbn]?$/

    # It's genuinely the human's (Black's) turn now -- a live move applies cleanly.
    assert {:ok, %{status: :continue, human_move: human}} = GameServer.submit_human_move(game_id, "e7e5")
    assert human.ply == 2
  end

  test "maybe_play_opening_move only acts once, even if called again" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"skill_level" => 0}, [], "black")
    assert {:ok, %{engine_move: _}} = GameServer.maybe_play_opening_move(game_id)
    assert {:ok, :not_applicable} = GameServer.maybe_play_opening_move(game_id)
  end

  test "resign favors the human's actual opponent color when the human plays Black" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"skill_level" => 0}, [], "black")
    assert {:ok, {:winner, :white, {:manual, :human_resigned}}} = GameServer.resign(game_id)
  end

  test "undo rebuilds the engine at a truncated move list, and the rewound position is playable" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"skill_level" => 0}, ["e2e4", "e7e5"])

    assert :ok = GameServer.undo(game_id, ["e2e4"])
    assert {:ok, fen} = GameServer.fen(game_id)
    assert fen =~ ~r/^rnbqkbnr\/pppppppp\/8\/8\/4P3\/8\/PPPP1PPP\/RNBQKBNR/

    assert {:ok, %{status: :continue}} = GameServer.submit_human_move(game_id, "e7e5")
  end

  test "undo to an empty move list restores the starting position" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"skill_level" => 0}, ["e2e4"])

    assert :ok = GameServer.undo(game_id, [])
    assert {:ok, fen} = GameServer.fen(game_id)
    assert fen =~ ~r/^rnbqkbnr\/pppppppp\/8\/8\/8\/8\/PPPPPPPP\/RNBQKBNR/
  end
end
