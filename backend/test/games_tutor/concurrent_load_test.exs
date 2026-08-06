defmodule GamesTutor.ConcurrentLoadTest do
  @moduledoc """
  Phase 6's "concurrent-load test of the engine process pool" -- confirms
  the per-game GenServer/DynamicSupervisor/Registry architecture (real
  Stockfish/KataGo subprocesses, a pair/one process per active game, not a
  shared worker pool) holds up when multiple games run at once, not just
  one at a time like every other GameServer test exercises.

  Tagged :load and excluded from the default `mix test` run (see
  test_helper.exs) -- this spins up real engine subprocesses concurrently
  and is meaningfully heavier than the rest of the suite. Run explicitly:

      mix test --only load

  Concurrency here is deliberately modest (8 chess / 4 go, matching this
  host's 8 cores) -- this droplet also runs other production tenants
  side by side with games_tutor, not a scale rehearsal for a much larger
  fleet.
  """
  use ExUnit.Case, async: false
  @moduletag :load
  @moduletag timeout: 120_000

  alias GamesTutor.Chess.GameServer, as: ChessServer
  alias GamesTutor.Go.GameServer, as: GoServer

  @chess_concurrency 8
  @go_concurrency 4

  test "8 concurrent chess games each complete a real move exchange" do
    results =
      1..@chess_concurrency
      |> Task.async_stream(
        fn _ ->
          game_id = Ecto.UUID.generate()
          {:ok, _pid} = ChessServer.ensure_started(game_id, %{"skill_level" => 0})
          {us, result} = :timer.tc(fn -> ChessServer.submit_human_move(game_id, "e2e4") end)
          {result, us}
        end,
        max_concurrency: @chess_concurrency,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    for {result, _us} <- results do
      assert {:ok, %{status: :continue, engine_move: %{uci: uci}}} = result
      assert uci =~ ~r/^[a-h][1-8][a-h][1-8][qrbn]?$/
    end

    report("chess", results)
  end

  test "4 concurrent go games each complete a real move exchange" do
    results =
      1..@go_concurrency
      |> Task.async_stream(
        fn _ ->
          game_id = Ecto.UUID.generate()
          {:ok, _pid} = GoServer.ensure_started(game_id, %{"max_visits" => 20})
          {us, result} = :timer.tc(fn -> GoServer.submit_human_move(game_id, "E5") end)
          {result, us}
        end,
        max_concurrency: @go_concurrency,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    for {result, _us} <- results do
      assert {:ok, %{status: :continue}} = result
    end

    report("go", results)
  end

  defp report(label, results) do
    times_ms = Enum.map(results, fn {_result, us} -> us / 1000 end)

    IO.puts(
      "\n[load] #{length(results)} concurrent #{label} games -- move latency (ms): " <>
        "min=#{Float.round(Enum.min(times_ms), 1)} " <>
        "max=#{Float.round(Enum.max(times_ms), 1)} " <>
        "avg=#{Float.round(Enum.sum(times_ms) / length(times_ms), 1)}"
    )
  end
end
