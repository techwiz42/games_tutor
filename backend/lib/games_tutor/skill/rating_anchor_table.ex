defmodule GamesTutor.Skill.RatingAnchorTable do
  @moduledoc """
  Maps average centipawn loss (ACPL) to an approximate Elo rating via
  `GamesTutor.Skill.AnchorTable`'s piecewise log-linear interpolation.

  Anchors are a v1 approximation reflecting rough, publicly-known
  correlations between playing strength and centipawn loss (not derived
  from this project's own data yet) -- endpoints match the plan's stated
  ceiling/floor (<=10cp -> 2600, >=400cp -> 400).
  """
  alias GamesTutor.Skill.AnchorTable

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
  def acpl_to_elo(acpl), do: AnchorTable.interpolate(@anchors, acpl)
end
