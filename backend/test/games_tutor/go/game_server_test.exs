defmodule GamesTutor.Go.GameServerTest do
  # Not async: spawns real KataGo subprocesses, same convention as the
  # chess GameServer's integration tests.
  use ExUnit.Case, async: false

  alias GamesTutor.Go.GameServer

  defp new_game_id, do: Ecto.UUID.generate()

  test "plays a legal move and gets a real engine reply" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})

    assert {:ok, %{status: :continue, human_move: human, engine_move: engine}} =
             GameServer.submit_human_move(game_id, "E5")

    assert human.player == "human"
    assert human.uci == "E5"
    assert is_integer(human.eval_before)
    assert is_integer(human.eval_after)
    assert human.loss >= 0
    assert human.classification in ~w(best good inaccuracy mistake blunder)

    assert engine.player == "engine"
    assert engine.ply == human.ply + 1
    # A real move (or a legitimate pass) from the real weak-opponent query.
    assert engine.uci == "pass" or engine.uci =~ ~r/^[A-Za-z]\d{1,2}$/
  end

  test "rejects an illegal move (occupied point) without mutating game state" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})

    {:ok, %{status: :continue}} = GameServer.submit_human_move(game_id, "E5")

    # E5 is occupied now (by the human's own stone) -- illegal for anyone to play on.
    assert {:error, {:illegal_move, _reason}} = GameServer.submit_human_move(game_id, "E5")
  end

  test "rejects unparseable coordinates cheaply, without querying katago" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})

    assert {:error, {:illegal_move, :unparseable_coord}} = GameServer.submit_human_move(game_id, "Z99")
  end

  test "ensure_started is idempotent" do
    game_id = new_game_id()
    {:ok, pid1} = GameServer.ensure_started(game_id, %{"max_visits" => 10})
    {:ok, pid2} = GameServer.ensure_started(game_id, %{"max_visits" => 10})
    assert pid1 == pid2
  end

  test "restores from a move history (idle-eviction / process-restart recovery)" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, [["B", "E5"], ["W", "C3"]])
    assert {:ok, grid} = GameServer.board_grid(game_id)
    flat = List.flatten(grid)
    assert Enum.count(flat, &(&1 == 1)) == 1
    assert Enum.count(flat, &(&1 == -1)) == 1
  end

  test "hint returns a real suggested move for the current position" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})
    assert {:ok, coord} = GameServer.hint(game_id)
    assert coord == "pass" or coord =~ ~r/^[A-Za-z]\d{1,2}$/
  end

  test "resign ends the game in the engine's favor" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})
    assert {:ok, {:winner, :white, {:manual, :human_resigned}}} = GameServer.resign(game_id)
    assert {:error, :game_over} = GameServer.submit_human_move(game_id, "E5")
  end

  test "two consecutive passes ends the game with a scored result and no engine_move" do
    game_id = new_game_id()

    # Seed history ending in a White pass (consecutive_passes already at 1)
    # so the human's own single live pass deterministically reaches 2 --
    # the terminal check fires immediately, before any real opponent-reply
    # query, so this doesn't depend on the (real, not scripted) engine
    # choosing to pass too.
    history = [["B", "C5"], ["W", "pass"]]
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, history)

    assert {:ok, %{status: status, engine_move: nil}} = GameServer.submit_human_move(game_id, "pass")
    assert {:scored, result} = status
    assert result in [:black_wins, :white_wins, :draw]
  end

  test "captures are reflected in the board grid" do
    game_id = new_game_id()
    # Pre-set history that surrounds a lone white stone at C5, then black
    # plays the capturing move live through the real server.
    history = [
      ["W", "C5"],
      ["B", "B5"],
      ["W", "H1"],
      ["B", "D5"],
      ["W", "H2"],
      ["B", "C4"],
      # Filler White move -- keeps the history's move count odd (started
      # with White) so it's Black's (the default human color's) turn next.
      ["W", "H3"]
    ]

    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, history)
    assert {:ok, %{status: :continue, human_move: human}} = GameServer.submit_human_move(game_id, "C6")

    assert human.uci == "C6"
    assert {:ok, grid} = GameServer.board_grid(game_id)

    # C5 (the captured stone) must now be empty; the unrelated White filler
    # stones (H1/H2/H3, never surrounded) must still be present -- captures
    # should remove exactly the surrounded group, nothing more/less.
    assert stone_at(grid, "C5") == :empty
    assert stone_at(grid, "H1") == :white
    assert stone_at(grid, "H2") == :white
    assert stone_at(grid, "H3") == :white
    assert stone_at(grid, "B5") == :black
    assert stone_at(grid, "C6") == :black
  end

  test "maybe_play_opening_move is a no-op when the human plays the default color (Black)" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})
    assert {:ok, :not_applicable} = GameServer.maybe_play_opening_move(game_id)
  end

  test "maybe_play_opening_move plays a real Black opening move when the human chose White" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, [], "white")

    assert {:ok, %{engine_move: move}} = GameServer.maybe_play_opening_move(game_id)
    assert move.player == "engine"
    assert move.ply == 1
    assert move.uci == "pass" or move.uci =~ ~r/^[A-Za-z]\d{1,2}$/

    # It's genuinely the human's (White's) turn now -- a live move applies cleanly.
    assert {:ok, %{status: :continue, human_move: human}} = GameServer.submit_human_move(game_id, "E5")
    assert human.ply == 2
  end

  test "maybe_play_opening_move only acts once, even if called again" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, [], "white")
    assert {:ok, %{engine_move: _}} = GameServer.maybe_play_opening_move(game_id)
    assert {:ok, :not_applicable} = GameServer.maybe_play_opening_move(game_id)
  end

  test "with the human playing White, human moves are tagged W and engine replies are tagged B" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, [], "white")
    {:ok, %{engine_move: _}} = GameServer.maybe_play_opening_move(game_id)

    assert {:ok, %{status: :continue, human_move: human, engine_move: engine}} =
             GameServer.submit_human_move(game_id, "E5")

    assert human.player == "human"
    assert engine.player == "engine"
    # White (the human here) stones show as -1 on the grid; confirm the
    # human's own move landed as White, not Black.
    assert {:ok, grid} = GameServer.board_grid(game_id)
    assert stone_at(grid, "E5") == :white
  end

  test "undo rebuilds local board/history state from a truncated history" do
    game_id = new_game_id()
    history = [["B", "E5"], ["W", "C3"]]
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, history)

    assert :ok = GameServer.undo(game_id, [["B", "E5"]])

    assert {:ok, grid} = GameServer.board_grid(game_id)
    assert stone_at(grid, "E5") == :black
    assert stone_at(grid, "C3") == :empty
  end

  test "undo to an empty history clears the board and resets consecutive_passes" do
    game_id = new_game_id()
    history = [["B", "C5"], ["W", "pass"]]
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, history)

    assert :ok = GameServer.undo(game_id, [])

    assert {:ok, grid} = GameServer.board_grid(game_id)
    assert Enum.all?(List.flatten(grid), &(&1 == 0))

    # consecutive_passes reset to 0 -- a single live pass (ply 1, the default
    # human color's opening move) shouldn't end the game on its own.
    assert {:ok, %{status: :continue}} = GameServer.submit_human_move(game_id, "pass")
  end

  # grid is row-major with row 0 = top (rank 9 on a 9x9 board) -- see
  # GamesTutor.Go.Board.to_grid/1's moduledoc.
  defp stone_at(grid, coord_str) do
    {x, y} = GamesTutor.Go.Board.parse_coord(coord_str)
    row = 8 - y

    case Enum.at(grid, row) |> Enum.at(x) do
      1 -> :black
      -1 -> :white
      0 -> :empty
    end
  end
end
