defmodule GamesTutor.Chess.MoveClassifier do
  @moduledoc """
  Buckets a move's centipawn loss into a human-facing quality label.
  Thresholds mirror the general shape of Lichess's own accuracy
  classification -- an approximate v1 heuristic, not a scientific measure.
  """

  @type classification :: :best | :good | :inaccuracy | :mistake | :blunder

  @doc """
  `loss` is `max(0, eval_before - eval_after)` in centipawns, from the
  moving player's perspective. Clamped defensively so a mate-score-derived
  loss can't produce a nonsensical bucket.
  """
  @spec classify(integer()) :: classification()
  def classify(loss) when is_integer(loss) do
    loss = max(loss, 0)

    cond do
      loss <= 10 -> :best
      loss <= 50 -> :good
      loss <= 100 -> :inaccuracy
      loss <= 300 -> :mistake
      true -> :blunder
    end
  end
end
