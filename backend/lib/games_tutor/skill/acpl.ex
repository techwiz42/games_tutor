defmodule GamesTutor.Skill.Acpl do
  @moduledoc """
  Average centipawn loss (ACPL) for a game's human moves -- the same shape
  of idea behind Lichess's own centipawn-loss-based accuracy formula.

  v1 simplification (documented, not hidden): excludes the first
  `opening_plies` plies of "book" moves, but does NOT detect forced
  positions (only one legal move available) the way the plan's design
  doc mentions -- that needs a legal-move-count per move, which isn't
  currently stored. This whole system is explicitly framed as an
  approximate v1 heuristic that improves across games, not a precise
  single-game measurement, so the omission is acceptable for now.
  """

  @default_opening_plies 10

  @doc """
  `moves` is a list of maps/structs with `:player` ("human"/"engine") and
  `:loss` (integer centipawns, possibly nil if analysis wasn't computed).
  Returns `{:ok, %{acpl: float, moves_counted: integer}}` or
  `{:error, :no_countable_moves}` if nothing is left after filtering.
  """
  def compute(moves, opts \\ []) do
    opening_plies = Keyword.get(opts, :opening_plies, @default_opening_plies)

    losses =
      moves
      |> Enum.filter(&(&1.player == "human" and &1.ply > opening_plies and not is_nil(&1.loss)))
      |> Enum.map(& &1.loss)

    case losses do
      [] ->
        {:error, :no_countable_moves}

      _ ->
        acpl = Enum.sum(losses) / length(losses)
        {:ok, %{acpl: acpl, moves_counted: length(losses), losses: losses}}
    end
  end
end
