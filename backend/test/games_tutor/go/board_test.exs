defmodule GamesTutor.Go.BoardTest do
  use ExUnit.Case, async: true

  alias GamesTutor.Go.Board

  describe "coordinate parsing/formatting" do
    test "round-trips through format/parse" do
      for coord <- [{0, 0}, {3, 4}, {8, 8}] do
        assert Board.parse_coord(Board.format_coord(coord)) == coord
      end
    end

    test "column letters skip I" do
      assert Board.format_coord({8, 0}) == "J1"
      assert Board.format_coord({0, 0}) == "A1"
    end

    test "pass round-trips" do
      assert Board.format_coord(:pass) == "pass"
      assert Board.parse_coord("pass") == :pass
    end

    test "parse_coord rejects garbage" do
      assert Board.parse_coord("") == :error
      assert Board.parse_coord("Z99Z") == :error
      assert Board.parse_coord(nil) == :error
    end

    test "parse_coord is case-insensitive" do
      assert Board.parse_coord("d5") == Board.parse_coord("D5")
    end
  end

  describe "apply_move/3" do
    test "placing a stone with no captures" do
      board = Board.new(9)
      {board, captured} = Board.apply_move(board, :black, {4, 4})
      assert captured == []
      assert Board.to_grid(board) |> List.flatten() |> Enum.sum() == 1
    end

    test "pass does not change the board" do
      board = Board.new(9)
      {board, _} = Board.apply_move(board, :black, {4, 4})
      {board_after_pass, captured} = Board.apply_move(board, :white, :pass)
      assert captured == []
      assert board_after_pass == board
    end

    test "a single stone with zero liberties gets captured" do
      board = Board.new(9)
      # Surround a single white stone at (1,1) with black on all 4 sides.
      {board, _} = Board.apply_move(board, :white, {1, 1})
      {board, _} = Board.apply_move(board, :black, {0, 1})
      {board, _} = Board.apply_move(board, :black, {2, 1})
      {board, _} = Board.apply_move(board, :black, {1, 0})
      {board, captured} = Board.apply_move(board, :black, {1, 2})

      assert length(captured) == 1
      grid = Board.to_grid(board)
      assert List.flatten(grid) |> Enum.count(&(&1 == -1)) == 0
    end

    test "a connected group is captured together, not stone by stone" do
      board = Board.new(9)
      # White group of 2 at (1,1)-(2,1), surrounded except one shared liberty.
      {board, _} = Board.apply_move(board, :white, {1, 1})
      {board, _} = Board.apply_move(board, :white, {2, 1})
      {board, _} = Board.apply_move(board, :black, {0, 1})
      {board, _} = Board.apply_move(board, :black, {1, 0})
      {board, _} = Board.apply_move(board, :black, {2, 0})
      {board, _} = Board.apply_move(board, :black, {3, 1})
      {board, _} = Board.apply_move(board, :black, {1, 2})
      {_board, captured} = Board.apply_move(board, :black, {2, 2})

      assert length(captured) == 2
    end

    test "a group with a remaining liberty is not captured" do
      board = Board.new(9)
      {board, _} = Board.apply_move(board, :white, {1, 1})
      {board, _} = Board.apply_move(board, :black, {0, 1})
      {board, _} = Board.apply_move(board, :black, {1, 0})
      {_board, captured} = Board.apply_move(board, :black, {1, 2})

      # (2,1) still open -- the white stone survives.
      assert captured == []
    end

    test "does not capture the placing player's own group" do
      board = Board.new(9)
      {board, _} = Board.apply_move(board, :black, {1, 1})
      {board, _} = Board.apply_move(board, :black, {2, 1})
      {_board, captured} = Board.apply_move(board, :white, {0, 1})

      refute {1, 1} in captured
    end
  end

  # Finding 1c (engine-layer review): KataGo's analysis engine, as
  # configured (rules: "tromp-taylor" -- see GameServer.query/4), allows
  # multi-stone suicide -- confirmed empirically against the real engine,
  # across every named ruleset preset it accepts, not assumed (see the
  # commit message for finding 1c). These positions are exactly what was
  # sent to and verified against the live engine; they're hardcoded here
  # (not re-querying a live engine in the test) per the "recorded fixture,
  # not a live engine" rule for engine-behavior-dependent tests.
  describe "apply_move/3 self-capture (suicide) -- finding 1c" do
    test "a multi-stone group filling its own last liberty is removed" do
      board = Board.new(9)
      # Black B4,D4 ({1,3},{3,3}) each down to one shared liberty at C4
      # ({2,3}), surrounded by White everywhere else -- same position
      # verified against the live engine.
      {board, _} = Board.apply_move(board, :black, {1, 3})
      {board, _} = Board.apply_move(board, :black, {3, 3})
      {board, _} = Board.apply_move(board, :white, {0, 3})
      {board, _} = Board.apply_move(board, :white, {4, 3})
      {board, _} = Board.apply_move(board, :white, {1, 4})
      {board, _} = Board.apply_move(board, :white, {3, 4})
      {board, _} = Board.apply_move(board, :white, {2, 4})
      {board, _} = Board.apply_move(board, :white, {1, 2})
      {board, _} = Board.apply_move(board, :white, {3, 2})
      {board, _} = Board.apply_move(board, :white, {2, 2})

      {board, captured} = Board.apply_move(board, :black, {2, 3})

      assert Enum.sort(captured) == Enum.sort([index(9, 1, 3), index(9, 2, 3), index(9, 3, 3)])
      flat = List.flatten(Board.to_grid(board))
      assert Enum.count(flat, &(&1 == 1)) == 0
      # The surrounding White stones are untouched.
      assert Enum.count(flat, &(&1 == -1)) == 8
    end

    test "a single stone filling its own last liberty is removed" do
      board = Board.new(9)
      # (1,4)'s four neighbors: (0,4),(2,4),(1,3),(1,5) -- all White.
      {board, _} = Board.apply_move(board, :white, {0, 4})
      {board, _} = Board.apply_move(board, :white, {2, 4})
      {board, _} = Board.apply_move(board, :white, {1, 3})
      {board, _} = Board.apply_move(board, :white, {1, 5})
      {board, captured} = Board.apply_move(board, :black, {1, 4})

      assert captured == [index(9, 1, 4)]
      assert Board.to_grid(board) |> List.flatten() |> Enum.count(&(&1 == 1)) == 0
    end

    test "opponent captures are resolved BEFORE checking self-capture -- a move that captures its way to a liberty is not suicide" do
      board = Board.new(9)
      # White single stone at (3,4)'s only liberty is (3,3) -- its other
      # neighbors (3,5),(2,4),(4,4) are pre-occupied (by Black).
      {board, _} = Board.apply_move(board, :black, {3, 5})
      {board, _} = Board.apply_move(board, :black, {2, 4})
      {board, _} = Board.apply_move(board, :black, {4, 4})
      {board, _} = Board.apply_move(board, :white, {3, 4})
      # Black's about-to-be-played (3,3) is otherwise boxed in by White on
      # its other 3 sides -- in isolation this would be suicide, UNLESS
      # playing it also captures White's (3,4) stone first, which it does.
      {board, _} = Board.apply_move(board, :white, {2, 3})
      {board, _} = Board.apply_move(board, :white, {4, 3})
      {board, _} = Board.apply_move(board, :white, {3, 2})

      {board, captured} = Board.apply_move(board, :black, {3, 3})

      assert captured == [index(9, 3, 4)]
      # Black's new stone at (3,3) survived (not self-captured), alongside
      # the 3 setup stones -- 4 total, not 3 (which is what a wrongly
      # self-captured (3,3) would leave).
      grid = Board.to_grid(board)
      assert grid |> List.flatten() |> Enum.count(&(&1 == 1)) == 4
      assert stone_at(grid, {3, 3}) == 1
    end
  end

  defp stone_at(grid, {x, y}) do
    row = 8 - y
    Enum.at(grid, row) |> Enum.at(x)
  end

  # Mirrors Board's own private index/2 (y * size + x) -- duplicated here
  # (not making Board's private one public) so the single-stone test above
  # can assert on the exact captured index without hardcoding the
  # arithmetic redundantly inline.
  defp index(size, x, y), do: y * size + x

  describe "to_grid/1" do
    test "row 0 is the top (highest rank), matching Shudan's expected orientation" do
      board = Board.new(9)
      {board, _} = Board.apply_move(board, :black, {0, 8})
      grid = Board.to_grid(board)
      assert List.first(grid) |> List.first() == 1
    end
  end
end
