defmodule GamesTutor.Skill.AnchorTable do
  @moduledoc """
  Generic piecewise log-linear interpolation over a monotonic `{x, y}`
  anchor list -- equal *ratios* of x move y by roughly equal amounts,
  matching the intuition that (for chess) the gap between 10cp and 20cp
  ACPL is much more meaningful than the gap between 300cp and 310cp.

  Shared by chess's centipawn-loss->Elo and Go's score-loss->rating
  anchor tables (see `docs/PLAN.md`'s Phase 5 "extract the shared
  SkillEstimator" task -- this is that extraction).
  """

  @doc "x must be non-negative. Returns a float, clamped to the anchor list's own y range at the ends."
  def interpolate(anchors, x) when is_number(x) and x >= 0 do
    {min_x, min_y} = List.first(anchors)
    {max_x, max_y} = List.last(anchors)

    cond do
      x <= min_x -> min_y * 1.0
      x >= max_x -> max_y * 1.0
      true -> do_interpolate(anchors, x)
    end
  end

  defp do_interpolate(anchors, x) do
    {{lo_x, lo_y}, {hi_x, hi_y}} = bracket(anchors, x)
    t = (:math.log(x) - :math.log(lo_x)) / (:math.log(hi_x) - :math.log(lo_x))
    lo_y + t * (hi_y - lo_y)
  end

  defp bracket(anchors, x) do
    anchors
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [{lo_x, _}, {hi_x, _}] -> x >= lo_x and x <= hi_x end)
    |> then(fn [lo, hi] -> {lo, hi} end)
  end
end
