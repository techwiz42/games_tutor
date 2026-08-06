defmodule GamesTutor.Go.Board do
  @moduledoc """
  Minimal Go board state tracker, for rendering/storage only. KataGo is
  the sole legality authority (see `GamesTutor.Go.GameServer` -- it
  rejects illegal moves, including suicide/ko, before we ever get here),
  so this module does NOT re-implement legality: it trusts the caller
  that `apply_move/3` is being given an already-legal move, and only
  computes the resulting stone positions (placement + capture via
  liberty flood-fill) so the frontend has something to render without
  needing to know Go rules itself.

  Coordinates are zero-indexed `{x, y}` with `y = 0` at rank 1 (the
  bottom row, matching how Go boards are conventionally described) --
  `to_grid/1` flips row order when producing a display grid, since board
  UI libraries (Shudan included) expect row 0 to be the top of the
  rendered grid.
  """

  @type color :: :black | :white
  @type coord :: {non_neg_integer(), non_neg_integer()} | :pass
  @type t :: %{size: pos_integer(), stones: %{non_neg_integer() => color}}

  @columns ~w(A B C D E F G H J K L M N O P Q R S T)

  def new(size), do: %{size: size, stones: %{}}

  @doc "Returns `{new_board, captured_indices}`. A pass leaves the board unchanged."
  def apply_move(board, _color, :pass), do: {board, []}

  def apply_move(%{size: size, stones: stones} = board, color, {x, y})
      when x >= 0 and x < size and y >= 0 and y < size do
    idx = index(size, x, y)
    stones = Map.put(stones, idx, color)
    opponent = opponent(color)

    {stones, captured} =
      idx
      |> neighbors(size)
      |> Enum.filter(fn n -> Map.get(stones, n) == opponent end)
      |> Enum.uniq()
      |> Enum.reduce({stones, []}, fn n, {stones_acc, captured_acc} ->
        if Map.has_key?(stones_acc, n) do
          case group_and_liberty_count(stones_acc, size, n) do
            {group, 0} -> {Map.drop(stones_acc, group), captured_acc ++ group}
            _has_liberties -> {stones_acc, captured_acc}
          end
        else
          {stones_acc, captured_acc}
        end
      end)

    {%{board | stones: stones}, captured}
  end

  @doc "Row-major grid (row 0 = top / highest rank), 1 = black, -1 = white, 0 = empty -- Sabaki/Shudan's convention."
  def to_grid(%{size: size, stones: stones}) do
    for y <- (size - 1)..0//-1 do
      for x <- 0..(size - 1) do
        case Map.get(stones, index(size, x, y)) do
          :black -> 1
          :white -> -1
          nil -> 0
        end
      end
    end
  end

  @doc "e.g. {3, 4} on a 9x9 board -> \"D5\". Column letters skip \"I\", matching standard Go notation."
  def format_coord({x, y}), do: Enum.at(@columns, x) <> Integer.to_string(y + 1)
  def format_coord(:pass), do: "pass"

  @doc "e.g. \"D5\" -> {3, 4}. Returns :error for anything unparseable."
  def parse_coord("pass"), do: :pass

  def parse_coord(str) when is_binary(str) do
    case Regex.run(~r/^([A-Za-z])(\d+)$/, str) do
      [_, col, rank] ->
        case Enum.find_index(@columns, &(&1 == String.upcase(col))) do
          nil -> :error
          x -> {x, String.to_integer(rank) - 1}
        end

      _ ->
        :error
    end
  end

  def parse_coord(_), do: :error

  def opponent(:black), do: :white
  def opponent(:white), do: :black

  ## Internal

  defp index(size, x, y), do: y * size + x

  defp neighbors(idx, size) do
    x = rem(idx, size)
    y = div(idx, size)

    [{x - 1, y}, {x + 1, y}, {x, y - 1}, {x, y + 1}]
    |> Enum.filter(fn {nx, ny} -> nx >= 0 and nx < size and ny >= 0 and ny < size end)
    |> Enum.map(fn {nx, ny} -> index(size, nx, ny) end)
  end

  # Flood-fills the same-color group containing `start_idx`, returns `{group_indices, liberty_count}`.
  defp group_and_liberty_count(stones, size, start_idx) do
    color = Map.fetch!(stones, start_idx)
    flood(stones, size, [start_idx], MapSet.new(), MapSet.new(), color)
  end

  defp flood(_stones, _size, [], group, liberties, _color) do
    {MapSet.to_list(group), MapSet.size(liberties)}
  end

  defp flood(stones, size, [idx | rest], group, liberties, color) do
    if MapSet.member?(group, idx) do
      flood(stones, size, rest, group, liberties, color)
    else
      group = MapSet.put(group, idx)

      {to_visit, liberties} =
        idx
        |> neighbors(size)
        |> Enum.reduce({[], liberties}, fn n, {visit_acc, lib_acc} ->
          case Map.get(stones, n) do
            nil -> {visit_acc, MapSet.put(lib_acc, n)}
            ^color -> {[n | visit_acc], lib_acc}
            _other_color -> {visit_acc, lib_acc}
          end
        end)

      flood(stones, size, to_visit ++ rest, group, liberties, color)
    end
  end
end
