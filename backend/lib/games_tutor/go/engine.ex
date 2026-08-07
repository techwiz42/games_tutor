defmodule GamesTutor.Go.Engine do
  @moduledoc """
  The single, shared, long-lived KataGo analysis-engine process serving
  every Go game concurrently.

  Previously each `GamesTutor.Go.GameServer` spawned and owned its *own*
  KataGo process. On a CPU-only, 8-vCPU droplet with
  `numSearchThreadsPerAnalysisThread` configured under the assumption that
  one process has the whole box to itself, N concurrent games meant N
  processes each independently demanding that many threads -- guaranteed
  CPU oversubscription past exactly one active game. This module replaces
  that with one process all games query.

  Queries are multiplexed over the one process's stdin/stdout using the
  same newline-delimited-JSON-with-an-`id` protocol `GameServer` used to
  speak directly: callers block on an ordinary `GenServer.call/3` (via
  `query/2`), but the call is answered asynchronously via
  `GenServer.reply/2` once the matching `id` comes back on stdout. This
  GenServer's own mailbox is never blocked waiting on KataGo I/O, so
  accepting concurrent callers' queries is genuinely concurrent from
  Elixir's side -- nothing here serializes them behind a mutex.

  ## Backpressure

  Accepting a query and *dispatching* it to KataGo are deliberately
  different things. `max_in_flight/0` (default 1, matching Phase 2's
  `analysis.cfg` `numAnalysisThreads = 1` -- KataGo itself only analyzes
  that many positions at once regardless of how many requests it's holding)
  caps how many queries are ever sitting on KataGo's stdin waiting on a
  reply at the same time; anything past that sits in `state.queue` (a plain
  FIFO) until a slot frees up. Without this, a burst of concurrent requests
  would all get written to KataGo's stdin immediately and queue *inside*
  KataGo instead -- invisible to us, with each request's own
  `query_timeout` clock already running from the moment we accepted it, so
  a large enough burst would spend real CPU computing searches whose
  callers already gave up and stopped waiting. Queuing in Elixir instead
  means a request that times out while still waiting for a slot is simply
  dropped from the queue and never dispatched at all -- no wasted search.
  (`numAnalysisThreads`/`numSearchThreadsPerAnalysisThread` still govern how
  much internal parallelism KataGo gives whatever it IS actively working
  on; that's Phase 2's job, not this module's.)

  ## Process-death guarantee

  `Port.close/1` alone only closes the port's pipes (EOF on stdin) and
  relies on KataGo noticing and exiting -- fine for a healthy, responsive
  process, useless for a wedged one, and no help at all if the whole BEAM
  is SIGKILLed (no Elixir code runs in that case, so nothing can even
  attempt `Port.close/1`). Two mechanisms cover both cases:

    1. `terminate/2` (guaranteed to run on every *controlled* stop --
       `init/1` traps exits) explicitly sends `SIGKILL` to the OS pid it
       captured at startup, covering the wedged/uncooperative-process case.
    2. The executable this GenServer spawns isn't KataGo directly -- it's
       `priv/pdeathsig_wrapper` (see `c_src/pdeathsig_wrapper.c`), which
       sets `PR_SET_PDEATHSIG` on itself before `execvp`-ing into KataGo.
       The kernel then SIGKILLs KataGo the instant its parent
       (`erl_child_setup`, which every `Port.open({:spawn_executable, ...})`
       child is parented to) goes away -- covering the
       BEAM-vanishes-with-no-chance-to-run-Elixir-code case #1 can't.

  ## Health check

  A trivial (`maxVisits: 1`) query is self-issued every
  `health_check_interval_ms/0`. `max_consecutive_health_failures/0` misses
  in a row (timeout or no reply) is treated as "wedged, not just briefly
  slow", and this process stops itself (`{:stop, :wedged, state}`); its
  supervisor (`GamesTutor.Go.Engine.Supervisor`) restarts it fresh. Any
  real queries still pending when that happens get
  `{:error, {:engine_unavailable, :wedged}}` rather than hanging forever.
  """
  use GenServer
  require Logger

  @default_query_timeout 60_000
  @health_check_interval_ms :timer.seconds(30)
  @health_check_timeout_ms 15_000
  @max_consecutive_health_failures 2
  @max_in_flight 1

  # Same shape as GameServer's initial-analysis query for a brand-new game
  # (empty history) -- a known-good request, just at maxVisits: 1 since
  # this only needs to prove the round trip works, not produce a useful
  # analysis.
  @health_check_request %{
    moves: [],
    rules: "tromp-taylor",
    komi: 7.5,
    boardXSize: 9,
    boardYSize: 9,
    analyzeTurns: [0],
    maxVisits: 1
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Runs one KataGo analysis-engine query. `request` is a map of every field
  except `id` (this fills that in). Always returns `{:ok, decoded_response}`
  or `{:error, reason}` -- never crashes the caller, even if this GenServer
  is mid-restart (or simply not up yet) when called.
  """
  def query(request, timeout \\ @default_query_timeout) do
    GenServer.call(__MODULE__, {:query, request, timeout}, :infinity)
  catch
    :exit, reason -> {:error, {:engine_unavailable, reason}}
  end

  ## Server callbacks

  @impl true
  def init(_opts) do
    # Guarantees terminate/2 runs (and therefore the explicit os_pid kill
    # below) for every controlled stop reason, not just :normal/:shutdown --
    # see the moduledoc's "Process-death guarantee" section.
    Process.flag(:trap_exit, true)

    katago = Application.fetch_env!(:games_tutor, :katago)
    wrapper_path = Application.app_dir(:games_tutor, "priv/pdeathsig_wrapper")

    port =
      Port.open({:spawn_executable, wrapper_path}, [
        :binary,
        :exit_status,
        args: [katago[:path], "analysis", "-config", katago[:config_path], "-model", katago[:model_path]]
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)

    state = %{
      port: port,
      os_pid: os_pid,
      buffer: "",
      pending: %{},
      in_flight: MapSet.new(),
      queue: :queue.new(),
      health_check: nil,
      health_check_failures: 0
    }

    {:ok, schedule_health_check(state)}
  end

  @impl true
  def handle_call({:query, request, timeout}, from, state) do
    id = new_id()
    timer = Process.send_after(self(), {:query_timeout, id}, timeout)
    state = put_in(state.pending[id], {from, timer})

    state =
      if MapSet.size(state.in_flight) < max_in_flight() do
        dispatch(state, id, request)
      else
        %{state | queue: :queue.in({id, request}, state.queue)}
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {:noreply, drain_buffer(%{state | buffer: state.buffer <> data})}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("KataGo engine process exited unexpectedly: #{status}")
    fail_all_pending(state, {:engine_unavailable, {:katago_exited, status}})
    {:stop, {:katago_exited, status}, reset_queue(%{state | pending: %{}})}
  end

  def handle_info({:query_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        {:noreply, state}

      {{from, _timer}, pending} ->
        GenServer.reply(from, {:error, :katago_timeout})
        # Covers both cases: if `id` was in_flight, complete/2 frees the
        # slot and advances the queue; if it was still sitting in the
        # queue (never dispatched), it must be struck out here too --
        # otherwise it lingers as a dead entry until some later dispatch
        # happens to pop it (dispatch_next/1's own pending-check would
        # still skip it correctly, but the queue would look backed up
        # longer than it really is).
        state = %{state | pending: pending, queue: drop_from_queue(state.queue, id)}
        {:noreply, complete(state, id)}
    end
  end

  # Stray timeout for a health check that already succeeded (health_check
  # reset to nil) -- ignore.
  def handle_info(:health_check_timeout, %{health_check: nil} = state), do: {:noreply, state}

  def handle_info(:health_check_timeout, state) do
    case record_health_check_failure(state) do
      {:continue, state} ->
        {:noreply, state}

      {:wedged, state} ->
        fail_all_pending(state, {:engine_unavailable, :wedged})
        {:stop, :wedged, reset_queue(%{state | pending: %{}})}
    end
  end

  # Bypasses in_flight/queue entirely, on purpose -- a health check needs to
  # measure whether KataGo itself is responsive, not how backed up our own
  # request queue happens to be. If it had to wait in line behind real user
  # queries, a perfectly healthy-but-busy engine would look wedged.
  def handle_info(:health_check_tick, state) do
    id = new_id()
    send_request(state.port, @health_check_request, id)
    Process.send_after(self(), :health_check_timeout, health_check_timeout_ms())
    {:noreply, %{state | health_check: id}}
  end

  @impl true
  def terminate(_reason, state) do
    fail_all_pending(state, {:engine_unavailable, :engine_terminated})
    System.cmd("kill", ["-9", to_string(state.os_pid)], stderr_to_stdout: true)
    :ok
  end

  ## Internals

  defp schedule_health_check(state) do
    Process.send_after(self(), :health_check_tick, health_check_interval_ms())
    state
  end

  defp new_id, do: "q#{System.unique_integer([:positive, :monotonic])}"

  defp send_request(port, request, id) do
    Port.command(port, Jason.encode!(Map.put(request, :id, id)) <> "\n")
  end

  # Actually writes `id`/`request` to KataGo's stdin and marks it in_flight
  # -- called either straight from handle_call (a slot was free) or from
  # dispatch_next/1 (a slot just freed up). Never called for more than
  # max_in_flight/0 ids at once -- see the moduledoc's "Backpressure" section.
  defp dispatch(state, id, request) do
    send_request(state.port, request, id)
    %{state | in_flight: MapSet.put(state.in_flight, id)}
  end

  # A query's response/timeout arrived. If it was actually in_flight (as
  # opposed to still sitting in the queue when it timed out), a real slot
  # just freed up -- try to fill it from the queue.
  defp complete(state, id) do
    if MapSet.member?(state.in_flight, id) do
      state |> Map.update!(:in_flight, &MapSet.delete(&1, id)) |> dispatch_next()
    else
      state
    end
  end

  defp dispatch_next(state) do
    case :queue.out(state.queue) do
      {{:value, {id, request}}, queue} ->
        # Still has a live caller waiting on it? Dispatch for real. Already
        # timed out while it was queued (pending entry removed by
        # handle_info({:query_timeout, id}, ...) before ever reaching the
        # front of the queue)? Drop it -- exactly the wasted-search case
        # this queue exists to avoid -- and try the next one.
        if Map.has_key?(state.pending, id) do
          dispatch(%{state | queue: queue}, id, request)
        else
          dispatch_next(%{state | queue: queue})
        end

      {:empty, _queue} ->
        state
    end
  end

  defp reset_queue(state), do: %{state | in_flight: MapSet.new(), queue: :queue.new()}

  defp drop_from_queue(queue, id), do: :queue.filter(fn {qid, _request} -> qid != id end, queue)

  defp drain_buffer(state) do
    case pop_line(state.buffer) do
      {:ok, decoded, rest} ->
        %{state | buffer: rest} |> route_response(decoded) |> drain_buffer()

      :incomplete ->
        state
    end
  end

  defp route_response(%{health_check: id} = state, %{"id" => id}) when not is_nil(id) do
    record_health_check_success(state)
  end

  defp route_response(state, decoded) do
    id = decoded["id"]

    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        state

      {{from, timer}, pending} ->
        Process.cancel_timer(timer)
        GenServer.reply(from, {:ok, decoded})
        complete(%{state | pending: pending}, id)
    end
  end

  defp record_health_check_success(state) do
    schedule_health_check(%{state | health_check: nil, health_check_failures: 0})
  end

  defp record_health_check_failure(state) do
    failures = state.health_check_failures + 1
    max = max_consecutive_health_failures()
    Logger.warning("KataGo health check failed (#{failures}/#{max})")

    if failures >= max do
      Logger.error("KataGo engine appears wedged after #{failures} failed health checks, restarting")
      {:wedged, %{state | health_check: nil}}
    else
      {:continue, schedule_health_check(%{state | health_check: nil, health_check_failures: failures})}
    end
  end

  # Pops one complete newline-terminated line off the front of `buffer`,
  # decoded as JSON. A single {:data, ...} chunk from the port can contain
  # more than one complete response (KataGo writes them back-to-back), so
  # drain_buffer/1 calls this in a loop rather than only checking the
  # newest chunk. Skips (rather than crashes on) any non-JSON line --
  # analysis.cfg points KataGo's own logging at `logDir`, not stdout, so
  # this shouldn't normally trigger, but a stray line on stdout must not
  # take down this process.
  #
  # Public (not `defp`) so it's directly unit-testable without a live port.
  @doc false
  def pop_line(buffer) do
    case String.split(buffer, "\n", parts: 2) do
      [line, rest] ->
        case Jason.decode(line) do
          {:ok, decoded} ->
            {:ok, decoded, rest}

          {:error, _reason} ->
            Logger.warning("Skipping non-JSON line from KataGo stdout: #{inspect(line)}")
            pop_line(rest)
        end

      [_incomplete] ->
        :incomplete
    end
  end

  defp fail_all_pending(state, reason) do
    Enum.each(state.pending, fn {_id, {from, timer}} ->
      Process.cancel_timer(timer)
      GenServer.reply(from, {:error, reason})
    end)
  end

  # Overridable so tests can use fast intervals instead of the real
  # 30s/15s/2-failures production values.
  defp health_check_interval_ms,
    do: Application.get_env(:games_tutor, :go_health_check_interval_ms, @health_check_interval_ms)

  defp health_check_timeout_ms,
    do: Application.get_env(:games_tutor, :go_health_check_timeout_ms, @health_check_timeout_ms)

  defp max_consecutive_health_failures,
    do: Application.get_env(:games_tutor, :go_max_consecutive_health_failures, @max_consecutive_health_failures)

  # Overridable so tests can exercise queuing without needing real
  # concurrent slow queries to fill a production-sized in-flight window.
  # Production default matches analysis.cfg's numAnalysisThreads -- see the
  # moduledoc's "Backpressure" section for why they're coupled.
  defp max_in_flight, do: Application.get_env(:games_tutor, :go_engine_max_in_flight, @max_in_flight)
end
