defmodule GamesTutor.Go.GameServer do
  @moduledoc """
  One process per active Go game, owning a single real KataGo analysis-
  engine subprocess (a raw Elixir `Port` -- there's no Go equivalent of
  binbo, so this module hand-rolls the newline-delimited JSON
  request/response protocol KataGo's `analysis` mode speaks).

  Unlike chess's two-Stockfish-process design (Stockfish's strength knobs
  are per-process UCI options), KataGo's strength knob (`maxVisits`) is a
  per-*query* parameter, so ONE process serves both roles: full-strength
  analysis (high visits, for move-quality scoring/hints) and the weaker
  opponent's move choice (low visits, for the same "just search less/more
  randomly" weakening effect as chess's Skill Level).

  Human plays Black by default (moves first -- the conventional "student"
  role in a teaching game), but can choose White instead (see
  `maybe_play_opening_move/1`) -- unlike chess, every KataGo query needs an
  explicit "B"/"W" tag per move (see `query/4`'s `history`), so (unlike
  `Chess.GameServer`) color threads through `do_submit_human_move/2` and
  `play_opponent_reply/3` too, not just the opening-move special case.

  KataGo is the sole legality authority: every query re-sends the full
  move history, and KataGo rejects illegal moves (including suicide/ko)
  with a structured `{"error": ...}` response -- confirmed empirically in
  the Phase 0/5 spike work, not assumed. `GamesTutor.Go.Board` is used
  only to track stone positions (placement + capture) for rendering and
  storage, never for legality.

  Evaluation threading mirrors the chess GameServer's one-fresh-analysis-
  per-ply pattern: `last_analysis` is the analysis of the *current*
  position (whoever is to move), reused as both the next mover's
  eval_before and (sign-flipped) the previous mover's eval_after.

  `query/4` failures (`{:error, :katago_timeout}` -- see `await_response/3`)
  never crash this process on their own: every call site replies
  `{:error, {:engine_unavailable, reason}}` to the caller and leaves `state`
  exactly as it was before the failed query, so a transient timeout costs
  the player a retry, not the whole game session. The child spec is
  `restart: :temporary` (see `Application.child_spec/1` at the bottom) --
  this process is *only* ever meant to be resurrected via `ensure_started/4`
  reading fresh history from the DB, never via the supervisor silently
  respawning it with whatever `history` it happened to start with (which
  goes stale the moment a move is played, and would otherwise also fire on
  the deliberate `:normal` stop from idle-eviction below, defeating the
  point of evicting it at all -- confirmed empirically, not assumed: with
  the default `:permanent` restart this module inherited from `use
  GenServer`, idle-eviction was silently a no-op).
  """
  # restart: :temporary -- see the moduledoc above. Never let the
  # DynamicSupervisor auto-respawn this with stale start args; recovery
  # only ever happens through ensure_started/4 re-reading history from the DB.
  use GenServer, restart: :temporary
  require Logger

  alias GamesTutor.Go.{Board, MoveClassifier}

  @default_size 9
  @default_komi 7.5
  @analysis_max_visits 300
  @default_opponent_max_visits 20
  @idle_timeout :timer.minutes(30)
  @query_timeout 60_000

  # ---- Public API ----

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    GenServer.start_link(__MODULE__, opts, name: via(game_id))
  end

  @doc """
  Starts (or returns the existing) GameServer for `game_id`. `history` is
  the ordered list of already-played `["B"|"W", coord]` pairs (empty for
  a brand-new game), for restore after idle-eviction. `opponent_config`
  is `%{"max_visits" => integer}`; `human_color` is `"black"` (default) or
  `"white"`.
  """
  def ensure_started(game_id, opponent_config, history \\ [], human_color \\ "black") do
    case Registry.lookup(GamesTutor.Games.GameRegistry, {:go, game_id}) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec =
          {__MODULE__,
           game_id: game_id, opponent_config: opponent_config, history: history, human_color: human_color}

        case DynamicSupervisor.start_child(GamesTutor.Games.GameSupervisor, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end

  @doc "coord_str is e.g. \"D5\" or \"pass\". Returns `{:ok, %{status:, human_move:, engine_move:}}`."
  def submit_human_move(game_id, coord_str) do
    GenServer.call(via(game_id), {:submit_human_move, coord_str}, @query_timeout)
  end

  def resign(game_id), do: GenServer.call(via(game_id), :resign)
  def board_grid(game_id), do: GenServer.call(via(game_id), :board_grid)
  def hint(game_id), do: GenServer.call(via(game_id), :hint)

  @doc """
  Plays the engine's opening move if (and only if) this is a brand-new game
  where the human chose to play White. Returns `{:ok, %{engine_move:
  attrs}}` (persisted by the caller as ply 1) or `{:ok, :not_applicable}`.
  """
  def maybe_play_opening_move(game_id), do: GenServer.call(via(game_id), :maybe_play_opening_move, @query_timeout)

  @doc """
  Takes back to the position implied by `new_history` (a prefix of the previously
  played `["B"|"W", coord]` list). Unlike chess, this doesn't need to touch the
  KataGo process at all -- every query already re-sends the full move history from
  scratch (stateless), so undo is just recomputing local state (`board`,
  `consecutive_passes`, `next_ply`, `last_analysis`) from the shorter list, the same
  way `init/1` derives it after an idle-eviction restore.
  """
  def undo(game_id, new_history), do: GenServer.call(via(game_id), {:undo, new_history}, @query_timeout)

  defp via(game_id), do: {:via, Registry, {GamesTutor.Games.GameRegistry, {:go, game_id}}}

  # ---- Server callbacks ----

  @impl true
  def init(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    opponent_config = Keyword.fetch!(opts, :opponent_config)
    history = Keyword.get(opts, :history, [])
    human_color = Keyword.get(opts, :human_color, "black")
    katago = Application.fetch_env!(:games_tutor, :katago)

    port =
      Port.open({:spawn_executable, katago[:path]}, [
        :binary,
        :exit_status,
        args: ["analysis", "-config", katago[:config_path], "-model", katago[:model_path]]
      ])

    state = %{
      game_id: game_id,
      port: port,
      size: @default_size,
      komi: @default_komi,
      history: history,
      board: rebuild_board(history),
      human_color: human_color,
      next_ply: length(history) + 1,
      consecutive_passes: trailing_pass_count(history),
      resigned: false,
      last_move_at: System.monotonic_time(:millisecond),
      opponent_max_visits: Map.get(opponent_config, "max_visits", @default_opponent_max_visits),
      last_analysis: nil
    }

    # The initial analysis query (a real engine call, including model load
    # on a cold KataGo process) does NOT happen here. init/1 blocking on it
    # means DynamicSupervisor.start_child/2 -- and therefore the whole
    # GameSupervisor, which starts every game's engine process one at a
    # time -- blocks for that entire duration too, so one slow cold start
    # head-of-line-blocks every other concurrent game trying to start at the
    # same moment. Returning immediately here and doing the query in
    # handle_continue/2 unblocks the supervisor as soon as the port is
    # spawned; a handle_call arriving before the continue finishes still
    # waits (correctly -- there's no analysis to answer with yet), but that
    # wait no longer holds up anyone else's game from starting.
    {:ok, state, {:continue, :initial_analysis}}
  end

  @impl true
  def handle_continue(:initial_analysis, state) do
    case query(state, state.history, @analysis_max_visits, :analysis) do
      {:ok, resp} ->
        {:noreply, %{state | last_analysis: extract_analysis(resp)}, @idle_timeout}

      {:error, reason} ->
        # Nothing to roll back to (there's no prior good state) and no
        # in-flight caller reply to give a structured error to at this
        # point -- start_link/DynamicSupervisor.start_child already
        # returned {:ok, pid} before this ran. Stopping is the honest
        # response: a caller mid-`GenServer.call` at this moment sees the
        # ordinary `:noproc`/timeout an exited process produces, and the
        # *next* ensure_started/4 for this game gets a clean fresh attempt
        # (restart: :temporary means the supervisor won't loop retrying
        # this on its own).
        Logger.error("Go GameServer for #{state.game_id}: initial analysis failed (#{inspect(reason)}), stopping")
        {:stop, {:initial_analysis_failed, reason}, state}
    end
  end

  @impl true
  def handle_call({:submit_human_move, coord_str}, _from, state) do
    if game_over?(state) do
      {:reply, {:error, :game_over}, state, @idle_timeout}
    else
      do_submit_human_move(coord_str, state)
    end
  end

  @impl true
  def handle_call(:resign, _from, state) do
    state = %{state | resigned: true}
    {:reply, {:ok, {:winner, engine_color_atom(state), {:manual, :human_resigned}}}, state, @idle_timeout}
  end

  @impl true
  def handle_call(:board_grid, _from, state) do
    {:reply, {:ok, Board.to_grid(state.board)}, state, @idle_timeout}
  end

  @impl true
  def handle_call(:hint, _from, state) do
    {:reply, {:ok, state.last_analysis.best_move}, state, @idle_timeout}
  end

  @impl true
  def handle_call(:maybe_play_opening_move, _from, %{next_ply: 1, human_color: "white"} = state) do
    play_opening_engine_move(state)
  end

  @impl true
  def handle_call(:maybe_play_opening_move, _from, state) do
    {:reply, {:ok, :not_applicable}, state, @idle_timeout}
  end

  @impl true
  def handle_call({:undo, new_history}, _from, state) do
    case query(state, new_history, @analysis_max_visits, :analysis) do
      {:error, reason} ->
        reply_engine_unavailable(state, reason)

      {:ok, resp} ->
        new_state = %{
          state
          | history: new_history,
            board: rebuild_board(new_history),
            consecutive_passes: trailing_pass_count(new_history),
            next_ply: length(new_history) + 1,
            resigned: false,
            last_move_at: System.monotonic_time(:millisecond),
            last_analysis: extract_analysis(resp)
        }

        {:reply, :ok, new_state, @idle_timeout}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("KataGo process for game #{state.game_id} exited unexpectedly: #{status}")
    {:stop, {:katago_exited, status}, state}
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.info("Go GameServer for #{state.game_id} idle-timed-out, stopping katago")
    Port.close(state.port)
    {:stop, :normal, state}
  end

  # ---- Move handling ----

  defp game_over?(state), do: state.resigned or state.consecutive_passes >= 2

  # A query/4 failure (e.g. {:error, :katago_timeout}) replies to the
  # caller and keeps this process alive with `state` untouched -- see the
  # moduledoc. GamesTutor.Games/FallbackController turn this into a plain
  # {:error, :engine_unavailable} at the HTTP boundary; the reason is kept
  # here only for the log line.
  defp reply_engine_unavailable(state, reason) do
    Logger.warning("Go GameServer for #{state.game_id}: KataGo query failed (#{inspect(reason)})")
    {:reply, {:error, {:engine_unavailable, reason}}, state, @idle_timeout}
  end

  defp do_submit_human_move(coord_str, state) do
    think_time_ms = System.monotonic_time(:millisecond) - state.last_move_at

    case Board.parse_coord(coord_str) do
      :error ->
        {:reply, {:error, {:illegal_move, :unparseable_coord}}, state, @idle_timeout}

      coord ->
        eval_before_human = round_centipoints(state.last_analysis.score_lead)
        engine_best_move = state.last_analysis.best_move
        new_history = state.history ++ [[human_color_tag(state), coord_str]]

        case query(state, new_history, @analysis_max_visits, :analysis) do
          {:error, reason} ->
            reply_engine_unavailable(state, reason)

          {:ok, %{"error" => reason}} ->
            {:reply, {:error, {:illegal_move, reason}}, state, @idle_timeout}

          {:ok, resp} ->
            {new_board, _captured} = Board.apply_move(state.board, human_color_atom(state), coord)
            new_passes = pass_delta(coord_str, state.consecutive_passes)
            analysis = extract_analysis(resp)
            eval_after_human = round_centipoints(-analysis.score_lead)
            loss = max(eval_before_human - eval_after_human, 0)

            human_move = %{
              ply: state.next_ply,
              player: "human",
              notation: coord_str,
              uci: coord_str,
              fen_after: board_json(new_board),
              eval_before: eval_before_human,
              eval_after: eval_after_human,
              loss: loss,
              engine_best_move: engine_best_move,
              classification: Atom.to_string(MoveClassifier.classify(loss)),
              think_time_ms: think_time_ms
            }

            moved_state = %{
              state
              | history: new_history,
                board: new_board,
                consecutive_passes: new_passes,
                last_analysis: analysis
            }

            if new_passes >= 2 do
              status = final_status(analysis)

              moved_state = %{
                moved_state
                | next_ply: state.next_ply + 1,
                  last_move_at: System.monotonic_time(:millisecond)
              }

              {:reply, {:ok, %{status: status, human_move: human_move, engine_move: nil}}, moved_state, @idle_timeout}
            else
              play_opponent_reply(state, moved_state, human_move, System.monotonic_time(:millisecond))
            end
        end
    end
  end

  # `original_state` (pre-human-move) vs. `moved_state` (human move already
  # applied locally): if either query below fails, this replies with an
  # error and rolls all the way back to `original_state`, as if the human's
  # move never happened -- deliberately, not just for convenience. The
  # human's move is only ever persisted by the caller (GamesTutor.Games)
  # after seeing a {:ok, ...} reply, so keeping this GenServer's own state
  # in lockstep with "nothing committed yet" means a failed opponent-reply
  # query never leaves the in-memory game one move ahead of the DB. The
  # player just retries the same move.
  defp play_opponent_reply(original_state, moved_state, human_move, move_started_at) do
    case query(moved_state, moved_state.history, moved_state.opponent_max_visits, :opponent_move) do
      {:error, reason} ->
        reply_engine_unavailable(original_state, reason)

      {:ok, pick_resp} ->
        engine_coord_str = (List.first(pick_resp["moveInfos"]) || %{})["move"] || "pass"
        engine_coord = Board.parse_coord(engine_coord_str)
        new_history = moved_state.history ++ [[engine_color_tag(moved_state), engine_coord_str]]

        case query(moved_state, new_history, @analysis_max_visits, :analysis) do
          {:error, reason} ->
            reply_engine_unavailable(original_state, reason)

          {:ok, eval_resp} ->
            {new_board, _captured} = Board.apply_move(moved_state.board, engine_color_atom(moved_state), engine_coord)
            new_passes = pass_delta(engine_coord_str, moved_state.consecutive_passes)
            analysis = extract_analysis(eval_resp)

            eval_before_engine = round_centipoints(moved_state.last_analysis.score_lead)
            eval_after_engine = round_centipoints(-analysis.score_lead)
            loss = max(eval_before_engine - eval_after_engine, 0)

            engine_move = %{
              ply: moved_state.next_ply + 1,
              player: "engine",
              notation: engine_coord_str,
              uci: engine_coord_str,
              fen_after: board_json(new_board),
              eval_before: eval_before_engine,
              eval_after: eval_after_engine,
              loss: loss,
              engine_best_move: moved_state.last_analysis.best_move,
              classification: Atom.to_string(MoveClassifier.classify(loss)),
              think_time_ms: System.monotonic_time(:millisecond) - move_started_at
            }

            status = if new_passes >= 2, do: final_status(analysis), else: :continue

            final_state = %{
              moved_state
              | history: new_history,
                board: new_board,
                consecutive_passes: new_passes,
                next_ply: moved_state.next_ply + 2,
                last_move_at: System.monotonic_time(:millisecond),
                last_analysis: analysis
            }

            {:reply, {:ok, %{status: status, human_move: human_move, engine_move: engine_move}}, final_state,
             @idle_timeout}
        end
    end
  end

  # Black moves first in Go -- when the human chose White, the engine (as
  # Black) must play move 1 itself, against the empty board/history.
  defp play_opening_engine_move(state) do
    move_started_at = System.monotonic_time(:millisecond)

    case query(state, [], state.opponent_max_visits, :opponent_move) do
      {:error, reason} ->
        reply_engine_unavailable(state, reason)

      {:ok, pick_resp} ->
        engine_coord_str = (List.first(pick_resp["moveInfos"]) || %{})["move"] || "pass"
        engine_coord = Board.parse_coord(engine_coord_str)
        new_history = [[engine_color_tag(state), engine_coord_str]]

        case query(state, new_history, @analysis_max_visits, :analysis) do
          {:error, reason} ->
            reply_engine_unavailable(state, reason)

          {:ok, eval_resp} ->
            {new_board, _captured} = Board.apply_move(state.board, engine_color_atom(state), engine_coord)
            new_passes = pass_delta(engine_coord_str, 0)
            analysis = extract_analysis(eval_resp)

            eval_before_engine = round_centipoints(state.last_analysis.score_lead)
            eval_after_engine = round_centipoints(-analysis.score_lead)
            loss = max(eval_before_engine - eval_after_engine, 0)

            engine_move = %{
              ply: 1,
              player: "engine",
              notation: engine_coord_str,
              uci: engine_coord_str,
              fen_after: board_json(new_board),
              eval_before: eval_before_engine,
              eval_after: eval_after_engine,
              loss: loss,
              engine_best_move: state.last_analysis.best_move,
              classification: Atom.to_string(MoveClassifier.classify(loss)),
              think_time_ms: System.monotonic_time(:millisecond) - move_started_at
            }

            new_state = %{
              state
              | history: new_history,
                board: new_board,
                consecutive_passes: new_passes,
                next_ply: 2,
                last_move_at: System.monotonic_time(:millisecond),
                last_analysis: analysis
            }

            {:reply, {:ok, %{engine_move: engine_move}}, new_state, @idle_timeout}
        end
    end
  end

  ## KataGo protocol

  defp query(state, history, max_visits, kind) do
    :telemetry.span([:games_tutor, :engine, :query], %{engine: :katago, kind: kind}, fn ->
      id = "q#{System.unique_integer([:positive])}"

      request = %{
        id: id,
        moves: history,
        rules: "tromp-taylor",
        komi: state.komi,
        boardXSize: state.size,
        boardYSize: state.size,
        analyzeTurns: [length(history)],
        maxVisits: max_visits
      }

      Port.command(state.port, Jason.encode!(request) <> "\n")
      result = await_response(state.port, id, "")
      {result, %{engine: :katago, kind: kind}}
    end)
  end

  # Public (not `defp`) so the buffer-draining logic below is directly
  # testable with a fake `port` term and messages pre-loaded into the test
  # process's own mailbox -- see game_server_test.exs.
  @doc false
  def await_response(port, expected_id, buffer) do
    case pop_line(buffer) do
      {:ok, decoded, rest} ->
        if decoded["id"] == expected_id, do: {:ok, decoded}, else: await_response(port, expected_id, rest)

      :incomplete ->
        receive do
          {^port, {:data, data}} -> await_response(port, expected_id, buffer <> data)
        after
          query_timeout_ms() -> {:error, :katago_timeout}
        end
    end
  end

  # Overridable (default @query_timeout, 60s) so tests can force a fast,
  # deterministic {:error, :katago_timeout} instead of actually waiting 60s
  # for a response that will never come -- see game_server_test.exs's
  # "query failure" describe block.
  defp query_timeout_ms, do: Application.get_env(:games_tutor, :go_query_timeout_ms, @query_timeout)

  # Pops one complete newline-terminated line off the front of `buffer`. A
  # single {:data, ...} chunk from the port can contain more than one
  # complete response (KataGo writes them back-to-back) -- this drains every
  # already-buffered complete line before ever blocking in `receive` again;
  # the previous version only checked the newest chunk, so a second response
  # already sitting in `buffer` after an id mismatch would sit unparsed until
  # (maybe never) more data arrived, producing a spurious @query_timeout.
  #
  # Also skips (rather than crashes on) any line that isn't valid JSON --
  # analysis.cfg points KataGo's own logging at `logDir`, not stdout, so this
  # shouldn't normally trigger, but a stray non-JSON line on stdout must not
  # take down the whole GameServer via Jason.decode!/1.
  defp pop_line(buffer) do
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

  defp extract_analysis(resp) do
    root = resp["rootInfo"]

    %{
      score_lead: root["scoreLead"] * 1.0,
      current_player: root["currentPlayer"],
      best_move: (List.first(resp["moveInfos"]) || %{})["move"]
    }
  end

  ## Helpers

  # Shared by init/1 (fresh/restored game) and the :undo handler (rewound game) --
  # the local `Board` is only ever derived from a history list, never mutated in
  # place from a diff, so undo just re-derives it from a shorter list.
  defp rebuild_board(history) do
    Enum.reduce(history, Board.new(@default_size), fn [color_str, coord_str], b ->
      {b, _captured} = Board.apply_move(b, color_from_str(color_str), Board.parse_coord(coord_str))
      b
    end)
  end

  defp pass_delta("pass", count), do: count + 1
  defp pass_delta(_coord, _count), do: 0

  defp trailing_pass_count(history) do
    history |> Enum.reverse() |> Enum.take_while(fn [_c, coord] -> coord == "pass" end) |> length()
  end

  defp color_from_str("B"), do: :black
  defp color_from_str("W"), do: :white

  defp human_color_tag(%{human_color: "black"}), do: "B"
  defp human_color_tag(%{human_color: "white"}), do: "W"
  defp engine_color_tag(state), do: if(human_color_tag(state) == "B", do: "W", else: "B")
  defp human_color_atom(state), do: color_from_str(human_color_tag(state))
  defp engine_color_atom(state), do: color_from_str(engine_color_tag(state))

  # Score-lead points scaled 100x to an integer, matching chess's own
  # centipawns-are-scaled-pawns convention -- keeps the shared `moves`
  # table's integer eval/loss columns precise for Go's much smaller
  # natural-unit scale (sub-point differences matter a lot here).
  defp round_centipoints(points), do: round(points * 100)

  defp final_status(%{score_lead: lead, current_player: "W"}) when lead > 0, do: {:scored, :white_wins}
  defp final_status(%{score_lead: lead, current_player: "W"}) when lead < 0, do: {:scored, :black_wins}
  defp final_status(%{score_lead: lead, current_player: "B"}) when lead > 0, do: {:scored, :black_wins}
  defp final_status(%{score_lead: lead, current_player: "B"}) when lead < 0, do: {:scored, :white_wins}
  defp final_status(_analysis), do: {:scored, :draw}

  defp board_json(board), do: Jason.encode!(%{size: board.size, grid: Board.to_grid(board)})
end
