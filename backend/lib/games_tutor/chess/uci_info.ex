defmodule GamesTutor.Chess.UciInfo do
  @moduledoc """
  Parses raw UCI `info ...` lines (as delivered by binbo's custom message
  handler) for the `score` field. Kept separate from the engine GenServer
  so the parsing itself is a plain, unit-testable pure function.
  """

  @type score :: {:cp, integer()} | {:mate, integer()}

  @doc """
  Extracts the score from one `info` line, e.g.:

      "info depth 10 seldepth 10 multipv 1 score cp 106 upperbound nodes ..."
      "info depth 12 ... score mate 3 ..."

  Returns `nil` if the line has no `score` field (e.g. the final `bestmove`
  line, or an unrelated engine log message).
  """
  @spec parse_score(binary()) :: score() | nil
  def parse_score(line) when is_binary(line) do
    case Regex.run(~r/score (cp|mate) (-?\d+)/, line) do
      [_, "cp", n] -> {:cp, String.to_integer(n)}
      [_, "mate", n] -> {:mate, String.to_integer(n)}
      _ -> nil
    end
  end

  @doc """
  Converts a score to a plain centipawn integer for storage/arithmetic.
  Mate scores are clamped to a fixed magnitude far outside any real
  centipawn evaluation (so they still sort/compare correctly) rather than
  left as a distinct unbounded unit.
  """
  @spec to_centipawns(score()) :: integer()
  def to_centipawns({:cp, n}), do: n
  def to_centipawns({:mate, n}) when n >= 0, do: 10_000
  def to_centipawns({:mate, _n}), do: -10_000

  @doc """
  Folds a stream of parsed `info` lines down to the score of the last
  (deepest) one seen -- UCI engines emit one `info` line per completed
  depth, each superseding the last.
  """
  @spec last_score([binary()]) :: score() | nil
  def last_score(lines) when is_list(lines) do
    lines
    |> Enum.map(&parse_score/1)
    |> Enum.reject(&is_nil/1)
    |> List.last()
  end
end
