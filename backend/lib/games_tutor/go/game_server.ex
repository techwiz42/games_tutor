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
  """
  use GenServer
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

    {:ok, resp} = query(state, state.history, @analysis_max_visits, :analysis)
    {:ok, %{state | last_analysis: extract_analysis(resp)}, @idle_timeout}
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
    {:ok, resp} = query(state, new_history, @analysis_max_visits, :analysis)

    state = %{
      state
      | history: new_history,
        board: rebuild_board(new_history),
        consecutive_passes: trailing_pass_count(new_history),
        next_ply: length(new_history) + 1,
        resigned: false,
        last_move_at: System.monotonic_time(:millisecond),
        last_analysis: extract_analysis(resp)
    }

    {:reply, :ok, state, @idle_timeout}
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

            state = %{
              state
              | history: new_history,
                board: new_board,
                consecutive_passes: new_passes,
                last_analysis: analysis
            }

            if new_passes >= 2 do
              status = final_status(analysis)
              state = %{state | next_ply: state.next_ply + 1, last_move_at: System.monotonic_time(:millisecond)}
              {:reply, {:ok, %{status: status, human_move: human_move, engine_move: nil}}, state, @idle_timeout}
            else
              play_opponent_reply(state, human_move, System.monotonic_time(:millisecond))
            end
        end
    end
  end

  defp play_opponent_reply(state, human_move, move_started_at) do
    {:ok, pick_resp} = query(state, state.history, state.opponent_max_visits, :opponent_move)
    engine_coord_str = (List.first(pick_resp["moveInfos"]) || %{})["move"] || "pass"
    engine_coord = Board.parse_coord(engine_coord_str)

    new_history = state.history ++ [[engine_color_tag(state), engine_coord_str]]
    {:ok, eval_resp} = query(state, new_history, @analysis_max_visits, :analysis)

    {new_board, _captured} = Board.apply_move(state.board, engine_color_atom(state), engine_coord)
    new_passes = pass_delta(engine_coord_str, state.consecutive_passes)
    analysis = extract_analysis(eval_resp)

    eval_before_engine = round_centipoints(state.last_analysis.score_lead)
    eval_after_engine = round_centipoints(-analysis.score_lead)
    loss = max(eval_before_engine - eval_after_engine, 0)

    engine_move = %{
      ply: state.next_ply + 1,
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

    status = if new_passes >= 2, do: final_status(analysis), else: :continue

    state = %{
      state
      | history: new_history,
        board: new_board,
        consecutive_passes: new_passes,
        next_ply: state.next_ply + 2,
        last_move_at: System.monotonic_time(:millisecond),
        last_analysis: analysis
    }

    {:reply, {:ok, %{status: status, human_move: human_move, engine_move: engine_move}}, state, @idle_timeout}
  end

  # Black moves first in Go -- when the human chose White, the engine (as
  # Black) must play move 1 itself, against the empty board/history.
  defp play_opening_engine_move(state) do
    move_started_at = System.monotonic_time(:millisecond)
    {:ok, pick_resp} = query(state, [], state.opponent_max_visits, :opponent_move)
    engine_coord_str = (List.first(pick_resp["moveInfos"]) || %{})["move"] || "pass"
    engine_coord = Board.parse_coord(engine_coord_str)

    new_history = [[engine_color_tag(state), engine_coord_str]]
    {:ok, eval_resp} = query(state, new_history, @analysis_max_visits, :analysis)

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

    state = %{
      state
      | history: new_history,
        board: new_board,
        consecutive_passes: new_passes,
        next_ply: 2,
        last_move_at: System.monotonic_time(:millisecond),
        last_analysis: analysis
    }

    {:reply, {:ok, %{engine_move: engine_move}}, state, @idle_timeout}
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

  defp await_response(port, expected_id, buffer) do
    receive do
      {^port, {:data, data}} ->
        buffer = buffer <> data

        case String.split(buffer, "\n", parts: 2) do
          [line, rest] ->
            decoded = Jason.decode!(line)
            if decoded["id"] == expected_id, do: {:ok, decoded}, else: await_response(port, expected_id, rest)

          [_incomplete] ->
            await_response(port, expected_id, buffer)
        end
    after
      @query_timeout -> {:error, :katago_timeout}
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
