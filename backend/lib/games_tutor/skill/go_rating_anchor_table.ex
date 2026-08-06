defmodule GamesTutor.Skill.GoRatingAnchorTable do
  @moduledoc """
  Maps average score-loss (centipoints -- score-lead points * 100, see
  `GamesTutor.Go.MoveClassifier`'s moduledoc for why the *100 scaling)
  onto the SAME shared internal rating scale chess Elo uses (~400-2600),
  via the same piecewise log-linear anchor-table approach as
  `GamesTutor.Skill.RatingAnchorTable` -- see `docs/PLAN.md`'s "Internally
  store both games on one continuous numeric scale... so the Bayesian
  update math is shared, only the display label differs."

  Anchors are a v1 approximation of the general shape used by existing
  KataGo-based teaching tools (e.g. KaTrain) that map score-loss to rank,
  re-centered onto games_tutor's own chess-Elo-shaped internal scale --
  not derived from this project's own data yet. Endpoints roughly match
  the plan's stated correlation (<=0.5pt -> 7d+, >=30pt -> 25k+).
  """
  alias GamesTutor.Skill.AnchorTable

  @anchors [
    {50, 2500},
    {100, 2300},
    {200, 2100},
    {400, 1900},
    {700, 1600},
    {1200, 1300},
    {2000, 1000},
    {3000, 700},
    {4000, 400}
  ]

  @doc "score_loss_centipoints is non-negative. Returns a float rating on the shared internal scale."
  def score_loss_to_rating(score_loss_centipoints), do: AnchorTable.interpolate(@anchors, score_loss_centipoints)

  @labels [
    {500, "20+ kyu"},
    {700, "15 kyu"},
    {900, "10 kyu"},
    {1100, "7 kyu"},
    {1300, "5 kyu"},
    {1500, "3 kyu"},
    {1700, "1 kyu"},
    {1900, "1 dan"},
    {2100, "3 dan"},
    {2300, "5 dan"}
  ]

  @doc "Formats a rating on the shared internal scale as an approximate kyu/dan label."
  def rating_to_label(rating) do
    Enum.find_value(@labels, "7 dan+", fn {ceiling, label} -> if rating < ceiling, do: label end)
  end
end
