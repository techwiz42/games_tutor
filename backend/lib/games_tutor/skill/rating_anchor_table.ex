defmodule GamesTutor.Skill.RatingAnchorTable do
  @moduledoc """
  Maps average centipawn loss (ACPL) to an approximate Elo rating via a
  monotonic anchor table, piecewise log-linearly interpolated between
  points (equal *ratios* of ACPL move the rating estimate by roughly equal
  amounts, matching the intuition that the gap between 10cp and 20cp ACPL
  is much more meaningful than the gap between 300cp and 310cp).

  Anchors are a v1 approximation reflecting rough, publicly-known
  correlations between playing strength and centipawn loss (not derived
  from this project's own data yet) -- endpoints match the plan's stated
  ceiling/floor (<=10cp -> 2600, >=400cp -> 400).
  """

  @anchors [
    {10, 2600},
    {20, 2400},
    {35, 2200},
    {55, 2000},
    {80, 1800},
    {115, 1600},
    {160, 1400},
    {220, 1200},
    {300, 900},
    {400, 400}
  ]

  @doc "acpl is in centipawns (non-negative). Returns a float Elo estimate."
  def acpl_to_elo(acpl) when is_number(acpl) and acpl >= 0 do
    {min_acpl, min_elo} = List.first(@anchors)
    {max_acpl, max_elo} = List.last(@anchors)

    cond do
      acpl <= min_acpl -> min_elo * 1.0
      acpl >= max_acpl -> max_elo * 1.0
      true -> interpolate(acpl)
    end
  end

  defp interpolate(acpl) do
    {{lo_acpl, lo_elo}, {hi_acpl, hi_elo}} = bracket(acpl)
    t = (:math.log(acpl) - :math.log(lo_acpl)) / (:math.log(hi_acpl) - :math.log(lo_acpl))
    lo_elo + t * (hi_elo - lo_elo)
  end

  defp bracket(acpl) do
    @anchors
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [{lo_acpl, _}, {hi_acpl, _}] -> acpl >= lo_acpl and acpl <= hi_acpl end)
    |> then(fn [lo, hi] -> {lo, hi} end)
  end
end
