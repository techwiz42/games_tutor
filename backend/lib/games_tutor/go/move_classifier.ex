defmodule GamesTutor.Go.MoveClassifier do
  @moduledoc """
  Buckets a move's score-lead loss into a human-facing quality label.
  Input is **centi-points** (score-lead points * 100), matching the
  `moves.loss` column's integer type and mirroring chess's own
  centipawns-are-just-scaled-integer-pawns convention (see
  `GamesTutor.Chess.MoveClassifier`) -- Go's natural unit (points) is on a
  much smaller numeric scale than chess's, so the threshold *values*
  differ, but the "scale up 100x to keep an integer column precise"
  pattern is shared.

  ## Volatility scaling (engine-layer review, finding 3)

  Thresholds scale by `volatility_centipoints` -- the position's
  `rootInfo.scoreStdev` right before the move was played (in the same
  cp scale as `loss`; see `GameServer.extract_analysis/1` and
  `round_centipoints/1`), passed in explicitly to keep this a pure
  function. The same absolute point loss means different things at
  different volatility levels: in a position where the ultimate outcome
  is still wide open (many plausible ways the rest of the game could go),
  a given loss is weaker evidence of a real mistake than the identical
  loss in a position where the outcome is nearly settled.

  This is deliberately NOT the same thing as `classify/1`'s own
  measurement precision. Phase 0 of the review measured that separately:
  run-to-run standard deviation of `scoreLead` at production's 300 visits
  was 0.9-13.7cp across an empty/midgame/endgame sample -- comfortably
  under the 50cp best/good boundary, so classification itself is not
  reporting search noise as student error, and the boundary did not need
  to be raised or the distinction dropped. `scoreStdev` is a different,
  much larger-scale quantity (KataGo's own estimate of how much the FINAL
  outcome could still vary given how the rest of the game plays out --
  measured at ~1300-2500cp for realistic positions in the same Phase 0
  work, roughly 100x the run-to-run estimator noise) -- using it here is
  answering "how much should this particular loss count as evidence,
  given how undecided the position still is," not "is this loss bigger
  than our measurement error."

  Still an approximate v1 (like the base thresholds always were): the
  reference volatility and clamp bounds below are chosen to keep scaling
  bounded and directionally sensible, not calibrated against a labeled
  dataset -- there isn't one yet. `classification_version` (see
  `GamesTutor.Games.Move`) marks which scheme classified a given row,
  since existing rows can't be retroactively rescaled (no stored
  volatility to rescale them with).
  """

  @type classification :: :best | :good | :inaccuracy | :mistake | :blunder

  @base_thresholds %{best: 50, good: 200, inaccuracy: 500, mistake: 1000}

  # Representative "typical position" volatility, centipoints -- the
  # rough midpoint of Phase 0's measured midgame/empty-position
  # scoreStdev range (~1300-2500cp). Positions at this volatility get
  # ~unscaled (scale_factor ~= 1.0) thresholds, matching the base values
  # above, which were themselves tuned against ordinary mid-game play.
  @reference_volatility_centipoints 1800

  # Bounds scale_factor to [0.5x, 2x] the base thresholds -- wide enough
  # to meaningfully differentiate a settled endgame (Phase 0 measured
  # ~79cp scoreStdev there, which without a floor would shrink the best/
  # good boundary to ~2cp, an absurdly small, effectively-meaningless
  # threshold) from a wide-open position, without letting either extreme
  # produce a degenerate (near-zero or implausibly huge) threshold.
  @min_scale 0.5
  @max_scale 2.0

  @doc """
  `volatility_centipoints` is the pre-move position's scoreStdev, same cp
  scale as `loss_centipoints`. Pass `nil` (or omit -- see `classify/1`
  below) when volatility isn't available (e.g. an :opponent_move-derived
  loss, which never requests it -- see `GameServer.query/4`); falls back
  to the unscaled base thresholds rather than crashing on missing data.
  """
  @spec classify(integer(), number() | nil) :: classification()
  def classify(loss_centipoints, volatility_centipoints) when is_integer(loss_centipoints) do
    loss = max(loss_centipoints, 0)
    scale = scale_factor(volatility_centipoints)

    cond do
      loss <= @base_thresholds.best * scale -> :best
      loss <= @base_thresholds.good * scale -> :good
      loss <= @base_thresholds.inaccuracy * scale -> :inaccuracy
      loss <= @base_thresholds.mistake * scale -> :mistake
      true -> :blunder
    end
  end

  @doc "Unscaled fallback (scale_factor 1.0) -- see classify/2 for the volatility-aware version."
  @spec classify(integer()) :: classification()
  def classify(loss_centipoints), do: classify(loss_centipoints, nil)

  defp scale_factor(nil), do: 1.0

  defp scale_factor(volatility_centipoints) when is_number(volatility_centipoints) do
    (volatility_centipoints / @reference_volatility_centipoints)
    |> max(@min_scale)
    |> min(@max_scale)
  end
end
