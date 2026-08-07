defmodule GamesTutor.Go.EngineTest do
  # Not async: exercises the one real, shared KataGo process every other Go
  # test file also queries (see GamesTutor.Go.Engine's moduledoc) -- same
  # convention as GameServerTest.
  use ExUnit.Case, async: false

  alias GamesTutor.Go.Engine

  defp base_request(history, opts) do
    %{
      moves: history,
      rules: "tromp-taylor",
      komi: 7.5,
      boardXSize: 9,
      boardYSize: 9,
      analyzeTurns: [length(history)],
      maxVisits: Keyword.fetch!(opts, :max_visits)
    }
  end

  test "query/2 runs a real query against the shared engine" do
    assert {:ok, resp} = Engine.query(base_request([], max_visits: 1), 30_000)
    assert %{"rootInfo" => %{"currentPlayer" => _}} = resp
  end

  test "concurrent queries are correctly multiplexed, not cross-wired" do
    # Five distinct, legal, non-overlapping histories of increasing length.
    # KataGo's analysis response echoes back `turnNumber` (== the
    # `analyzeTurns` entry that produced it, here always `length(history)`)
    # -- a real, deterministic signal (not a mock) that each concurrent
    # caller got back the response that actually answers *its* request,
    # not another caller's.
    histories = [
      [],
      [["B", "C3"]],
      [["B", "C3"], ["W", "G7"]],
      [["B", "C3"], ["W", "G7"], ["B", "C7"]],
      [["B", "C3"], ["W", "G7"], ["B", "C7"], ["W", "G3"]]
    ]

    results =
      histories
      |> Enum.map(fn history ->
        Task.async(fn -> {length(history), Engine.query(base_request(history, max_visits: 1), 30_000)} end)
      end)
      |> Task.await_many(30_000)

    assert length(results) == length(histories)

    for {expected_turn, result} <- results do
      assert {:ok, %{"turnNumber" => ^expected_turn}} = result
    end
  end

  test "a query that cannot possibly finish in time returns a real, deterministic timeout error" do
    # A never-before-queried position (so there's no NN-cache shortcut) at
    # a real analysis-sized visit budget genuinely cannot complete in 1ms --
    # forces the same {:error, :katago_timeout} path GameServer's own
    # timeout tests exercise indirectly, without waiting out a real long
    # timeout.
    history = [["B", "D2"], ["W", "F8"], ["B", "B6"], ["W", "H4"]]
    assert {:error, :katago_timeout} = Engine.query(base_request(history, max_visits: 500), 1)
  end

  describe "pop_line/1 line buffering" do
    import ExUnit.CaptureLog

    test "parses one complete line and returns the remainder" do
      chunk = Jason.encode!(%{"id" => "q1", "rootInfo" => %{}}) <> "\ntrailing"
      assert {:ok, %{"id" => "q1"}, "trailing"} = Engine.pop_line(chunk)
    end

    test "reports :incomplete when no newline has arrived yet" do
      partial = String.slice(Jason.encode!(%{"id" => "q1"}), 0..5)
      assert Engine.pop_line(partial) == :incomplete
    end

    test "skips a non-JSON stdout line (logging a warning) instead of crashing" do
      chunk = "not json at all\n" <> Jason.encode!(%{"id" => "q1", "rootInfo" => %{}}) <> "\n"

      log =
        capture_log(fn ->
          assert {:ok, %{"id" => "q1"}, ""} = Engine.pop_line(chunk)
        end)

      assert log =~ "Skipping non-JSON line"
    end
  end

  describe "backpressure (max_in_flight, default 1)" do
    # Every history here (and its A/B pairing) is unique across this whole
    # file/test run -- a cache hit on a position already queried by an
    # earlier test (this is the one shared, persistent engine every test
    # queries) would finish too fast to reliably observe mid-flight queue
    # state, which is exactly what broke this test the first time: reusing
    # one pair of histories across both tests below meant the second test
    # hit an already-warm cache from the first.
    test "a second concurrent query queues behind max_in_flight instead of piling onto the engine" do
      history_a = [["B", "A1"], ["W", "A9"], ["B", "H1"], ["W", "H9"]]
      history_b = [["B", "B1"], ["W", "B9"], ["B", "G1"], ["W", "G9"]]

      task_a = Task.async(fn -> Engine.query(base_request(history_a, max_visits: 1000), 60_000) end)
      # Give A a moment to actually be dispatched before B is even sent.
      Process.sleep(50)
      task_b = Task.async(fn -> Engine.query(base_request(history_b, max_visits: 1), 60_000) end)
      Process.sleep(50)

      state = :sys.get_state(Engine)
      assert MapSet.size(state.in_flight) == 1
      assert :queue.len(state.queue) == 1

      assert {:ok, _} = Task.await(task_a, 60_000)
      assert {:ok, _} = Task.await(task_b, 60_000)
    end

    test "a query that times out while still queued (never dispatched) is dropped, not sent late" do
      history_a = [["B", "C1"], ["W", "C9"], ["B", "F1"], ["W", "F9"]]
      history_b = [["B", "D1"], ["W", "D9"], ["B", "E1"], ["W", "E9"]]

      task_a = Task.async(fn -> Engine.query(base_request(history_a, max_visits: 1000), 60_000) end)
      Process.sleep(50)

      # B never gets a slot before its own 1ms timeout fires -- proves it
      # was genuinely waiting in our queue, not already sitting on KataGo's
      # stdin (which wouldn't care about Elixir's timeout at all).
      assert {:error, :katago_timeout} = Engine.query(base_request(history_b, max_visits: 1), 1)

      state = :sys.get_state(Engine)
      assert :queue.len(state.queue) == 0

      assert {:ok, _} = Task.await(task_a, 60_000)
    end
  end

  describe "wedged-engine detection and recovery" do
    defp wait_for_replacement(original_pid, attempts \\ 100)

    defp wait_for_replacement(_original_pid, 0), do: flunk("engine was never replaced by its supervisor")

    defp wait_for_replacement(original_pid, attempts) do
      case Process.whereis(Engine) do
        pid when is_pid(pid) and pid != original_pid -> pid
        _ -> Process.sleep(10) && wait_for_replacement(original_pid, attempts - 1)
      end
    end

    test "repeated failed health checks stop the engine, and the supervisor replaces it with a working one" do
      Application.put_env(:games_tutor, :go_max_consecutive_health_failures, 1)

      try do
        original_pid = Process.whereis(Engine)
        ref = Process.monitor(original_pid)

        # Drive the same state machine handle_info(:health_check_timeout, ...)
        # runs for real, without waiting out the real 30s/15s intervals: an
        # outstanding health check that will never get a reply, then its
        # deadline firing.
        :sys.replace_state(Engine, fn state -> %{state | health_check: "fake-wedge-id"} end)
        send(original_pid, :health_check_timeout)

        assert_receive {:DOWN, ^ref, :process, ^original_pid, :wedged}, 5_000

        new_pid = wait_for_replacement(original_pid)
        assert new_pid != original_pid

        assert {:ok, %{"rootInfo" => _}} = Engine.query(base_request([], max_visits: 1), 30_000)
      after
        Application.delete_env(:games_tutor, :go_max_consecutive_health_failures)
      end
    end
  end
end
