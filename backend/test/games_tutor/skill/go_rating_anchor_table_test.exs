defmodule GamesTutor.Skill.GoRatingAnchorTableTest do
  use ExUnit.Case, async: true

  alias GamesTutor.Skill.GoRatingAnchorTable, as: Table

  test "clamps to the ceiling at/below the lowest anchor" do
    assert Table.score_loss_to_rating(0) == 2500.0
    assert Table.score_loss_to_rating(50) == 2500.0
  end

  test "clamps to the floor at/above the highest anchor" do
    assert Table.score_loss_to_rating(4000) == 400.0
    assert Table.score_loss_to_rating(10_000) == 400.0
  end

  test "is monotonically non-increasing as score-loss increases" do
    samples = for cp <- 50..4000//50, do: Table.score_loss_to_rating(cp)
    assert samples == Enum.sort(samples, :desc)
  end

  test "lands on the same shared scale chess ratings use" do
    assert Table.score_loss_to_rating(50) <= 2600.0
    assert Table.score_loss_to_rating(4000) >= 400.0
  end

  describe "rating_to_label/1" do
    test "covers the full kyu -> dan range in the right order" do
      assert Table.rating_to_label(400) == "20+ kyu"
      assert Table.rating_to_label(1000) == "7 kyu"
      assert Table.rating_to_label(1800) == "1 dan"
      assert Table.rating_to_label(2600) == "7 dan+"
    end

    test "is monotonic (weaker rating never gets a stronger label)" do
      order = ["20+ kyu", "15 kyu", "10 kyu", "7 kyu", "5 kyu", "3 kyu", "1 kyu", "1 dan", "3 dan", "5 dan", "7 dan+"]

      ratings = [400, 600, 800, 1000, 1200, 1400, 1600, 1800, 2000, 2200, 2600]
      labels = Enum.map(ratings, &Table.rating_to_label/1)

      indices = Enum.map(labels, fn l -> Enum.find_index(order, &(&1 == l)) end)
      assert indices == Enum.sort(indices)
    end
  end
end
