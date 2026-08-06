defmodule GamesTutor.Go.MoveClassifier do
  @moduledoc """
  Buckets a move's score-lead loss into a human-facing quality label.
  Input is **centi-points** (score-lead points * 100), matching the
  `moves.loss` column's integer type and mirroring chess's own
  centipawns-are-just-scaled-integer-pawns convention (see
  `GamesTutor.Chess.MoveClassifier`) -- Go's natural unit (points) is on a
  much smaller numeric scale than chess's, so the threshold *values*
  differ, but the "scale up 100x to keep an integer column precise"
  pattern is shared. Approximate v1 thresholds, same spirit as chess's.
  """

  @type classification :: :best | :good | :inaccuracy | :mistake | :blunder

  @spec classify(integer()) :: classification()
  def classify(loss_centipoints) when is_integer(loss_centipoints) do
    loss = max(loss_centipoints, 0)

    cond do
      loss <= 50 -> :best
      loss <= 200 -> :good
      loss <= 500 -> :inaccuracy
      loss <= 1000 -> :mistake
      true -> :blunder
    end
  end
end
