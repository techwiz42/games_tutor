defmodule GamesTutor.Skill.RatingAnchorTableTest do
  use ExUnit.Case, async: true

  alias GamesTutor.Skill.RatingAnchorTable, as: Table

  test "clamps to the ceiling at/below the lowest anchor" do
    assert Table.acpl_to_elo(0) == 2600.0
    assert Table.acpl_to_elo(10) == 2600.0
  end

  test "clamps to the floor at/above the highest anchor" do
    assert Table.acpl_to_elo(400) == 400.0
    assert Table.acpl_to_elo(1000) == 400.0
  end

  test "hits exact anchor points" do
    assert Table.acpl_to_elo(80) == 1800.0
    assert Table.acpl_to_elo(300) == 900.0
  end

  test "is monotonically non-increasing as acpl increases" do
    samples = for acpl <- 10..400//5, do: Table.acpl_to_elo(acpl)
    assert samples == Enum.sort(samples, :desc)
  end

  test "interpolates strictly between bracketing anchors" do
    elo = Table.acpl_to_elo(60)
    assert elo < 2000.0
    assert elo > 1800.0
  end
end
