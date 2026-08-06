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

  describe "to_grid/1" do
    test "row 0 is the top (highest rank), matching Shudan's expected orientation" do
      board = Board.new(9)
      {board, _} = Board.apply_move(board, :black, {0, 8})
      grid = Board.to_grid(board)
      assert List.first(grid) |> List.first() == 1
    end
  end
end
