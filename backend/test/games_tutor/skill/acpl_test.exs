defmodule GamesTutor.Skill.AcplTest do
  use ExUnit.Case, async: true

  alias GamesTutor.Skill.Acpl

  defp move(ply, player, loss), do: %{ply: ply, player: player, loss: loss}

  test "averages loss over human moves past the opening" do
    moves = [
      move(1, "human", 500),
      move(2, "engine", 500),
      move(11, "human", 10),
      move(12, "engine", 999),
      move(13, "human", 30)
    ]

    assert {:ok, %{acpl: acpl, moves_counted: 2}} = Acpl.compute(moves)
    assert_in_delta acpl, 20.0, 0.001
  end

  test "excludes engine moves entirely" do
    moves = [move(11, "engine", 1000), move(13, "engine", 1000)]
    assert {:error, :no_countable_moves} = Acpl.compute(moves)
  end

  test "excludes moves with nil loss (analysis not computed)" do
    moves = [move(11, "human", nil), move(13, "human", 40)]
    assert {:ok, %{acpl: 40.0, moves_counted: 1}} = Acpl.compute(moves)
  end

  test "opening_plies is configurable" do
    moves = [move(1, "human", 500), move(3, "human", 100)]
    assert {:ok, %{acpl: 100.0, moves_counted: 1}} = Acpl.compute(moves, opening_plies: 2)
    assert {:error, :no_countable_moves} = Acpl.compute(moves, opening_plies: 10)
  end
end
