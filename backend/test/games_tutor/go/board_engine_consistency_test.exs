defmodule GamesTutor.Go.BoardEngineConsistencyTest do
  # Tagged :load (excluded by default, same convention as
  # concurrent_load_test.exs) -- spawns a real KataGo process and plays
  # several real games' worth of moves, each a live engine query. Run
  # explicitly with `mix test --include load`.
  #
  # Finding 1c (engine-layer review): "this is a class of bug, not a
  # single instance, and the current design has no guard against it."
  # board_test.exs hand-tests the ONE divergence shape found (multi-stone
  # suicide) with fixed positions; this instead plays real games -- every
  # move is KataGo's own top suggestion, so every move is genuinely legal,
  # no hand-crafted positions -- while independently maintaining a
  # GamesTutor.Go.Board in lockstep, then spot-checks: for a sample of
  # points our Board considers occupied, ask KataGo (a real query) whether
  # it would accept a stone there too. If KataGo says yes, our Board is
  # holding a stone KataGo no longer considers present -- a live
  # divergence, regardless of what specific mechanism caused it (not just
  # the suicide case already covered elsewhere).
  use ExUnit.Case, async: false
  @moduletag :load
  @moduletag timeout: 300_000

  alias GamesTutor.Go.{Board, GameServer}

  @games 3
  @moves_per_game 20
  @probe_sample_size 6

  test "Board's tracked stones never disagree with what the live engine still considers occupied, across real games" do
    katago = Application.fetch_env!(:games_tutor, :katago)

    port =
      Port.open({:spawn_executable, katago[:path]}, [
        :binary,
        :exit_status,
        args: ["analysis", "-config", katago[:config_path], "-model", katago[:model_path]]
      ])

    for game_n <- 1..@games do
      {final_history, final_board, next_color} = play_random_legal_game(port)

      final_board.stones
      |> Map.keys()
      |> Enum.map(&{rem(&1, final_board.size), div(&1, final_board.size)})
      |> Enum.shuffle()
      |> Enum.take(@probe_sample_size)
      |> Enum.each(fn coord ->
        probe_coord_str = Board.format_coord(coord)
        probe_history = final_history ++ [[next_color, probe_coord_str]]
        resp = raw_query(port, probe_history, 1)

        assert Map.has_key?(resp, "error"),
               "divergence in game #{game_n}: Board considers #{probe_coord_str} occupied, " <>
                 "but KataGo accepted a stone there. History: #{inspect(final_history)}"
      end)
    end

    Port.close(port)
  end

  defp play_random_legal_game(port) do
    Enum.reduce(1..@moves_per_game, {[], Board.new(9), "B"}, fn _n, {history, board, color} ->
      resp = raw_query(port, history, 100)
      move = (List.first(resp["moveInfos"]) || %{})["move"] || "pass"
      board_color = if color == "B", do: :black, else: :white
      {new_board, _captured} = Board.apply_move(board, board_color, Board.parse_coord(move))
      next_color = if color == "B", do: "W", else: "B"
      {history ++ [[color, move]], new_board, next_color}
    end)
  end

  defp raw_query(port, history, max_visits) do
    id = "probe#{System.unique_integer([:positive])}"

    request = %{
      id: id,
      moves: history,
      rules: "tromp-taylor",
      komi: 7.5,
      boardXSize: 9,
      boardYSize: 9,
      analyzeTurns: [length(history)],
      maxVisits: max_visits
    }

    Port.command(port, Jason.encode!(request) <> "\n")
    {:ok, resp} = GameServer.await_response(port, id, "")
    resp
  end
end
