defmodule GamesTutor.Chess.GameServer do
  @moduledoc """
  One process per active game, owning two real Stockfish subprocesses via
  binbo: `board_pid` is the canonical board (full-strength engine attached,
  used for move-quality analysis) and `opp_pid` is a separate,
  skill-limited engine used only to generate the opponent's replies.

  Human plays White by default, but can choose Black instead (see
  `maybe_play_opening_move/1`) -- either way, `do_submit_human_move/2` and
  `play_opponent_reply/4` need no color-specific logic at all, since binbo
  tracks whose turn it actually is from the real board position; games_tutor
  only needs to know which literal color is "the human" for the one moment
  color actually matters -- whether the engine must open the game.

  Evaluation is threaded through as exactly one Stockfish analysis call per
  ply, not per side: `last_analysis` is the analysis of the *current*
  position (whoever is to move), computed once right after the previous
  move was applied (or, for the game's first move, once at `init/1`). Since
  a position's evaluation doesn't change between "the mover just finished"
  and "the next mover's turn starts", that cached analysis IS the next
  mover's eval_before *and* the previous mover's eval_after (sign-flipped),
  with no redundant engine queries.

  Legality is checked by `binbo:move/2` itself (pure Erlang, no subprocess)
  before any engine call is made, so illegal input never wastes an analysis
  pass.

  The child spec is `restart: :temporary` (mirrors `GamesTutor.Go.GameServer` --
  see its moduledoc for the full story): this process is *only* ever meant to
  be resurrected via `ensure_started/4` reading fresh moves/human_color from
  the DB, never via the supervisor silently respawning it with whatever
  `moves` it happened to start with. That list goes stale the moment a move
  is played, and with the default `:permanent` restart this module used to
  inherit from `use GenServer`, it also fired on the deliberate `:normal`
  stop from idle-eviction below -- silently resurrecting a chess game's two
  Stockfish subprocesses back at whatever position they started at, out of
  sync with however many moves the DB has recorded since, while
  `ensure_started/4`'s `Registry.lookup` found that stale pid already
  registered and never called `start_child` with the real current moves at
  all. That desync is what produced "resumed game has an incoherent board":
  a human move legal in the real (DB) position could be rejected as illegal
  against the stale in-memory one, or worse, silently misapplied against it.
  """
  use GenServer, restart: :temporary
  require Logger

  alias GamesTutor.Chess.{MoveClassifier, UciInfo}

  @analysis_depth 12
  @opponent_movetime 400
  @idle_timeout :timer.minutes(30)
  @decisive_score 10_000

  # ---- Public API ----

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    GenServer.start_link(__MODULE__, opts, name: via(game_id))
  end

  @doc """
  Starts (or returns the existing) GameServer for `game_id`.

  `moves` is the ordered list of already-played `uci` strings (empty for a
  brand-new game) used to replay/restore board state after this process was
  idle-evicted; `opponent_config` is `%{"elo" => integer}` or
  `%{"skill_level" => integer}`; `human_color` is `"white"` (default) or
  `"black"`.
  """
  def ensure_started(game_id, opponent_config, moves \\ [], human_color \\ "white") do
    case Registry.lookup(GamesTutor.Games.GameRegistry, game_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec =
          {__MODULE__,
           game_id: game_id, opponent_config: opponent_config, moves: moves, human_color: human_color}

        case DynamicSupervisor.start_child(GamesTutor.Games.GameSupervisor, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end

  @doc """
  Applies the human's move (strict square notation, e.g. "e2e4", "a7a8q").
  Returns `{:ok, %{status:, result:, human_move:, engine_move:}}` where
  `human_move`/`engine_move` are attrs maps ready for `GamesTutor.Games`'s
  changesets (`engine_move` is `nil` if the human's move ended the game).
  """
  def submit_human_move(game_id, uci_move) do
    GenServer.call(via(game_id), {:submit_human_move, uci_move}, 20_000)
  end

  def resign(game_id) do
    GenServer.call(via(game_id), :resign)
  end

  def fen(game_id), do: GenServer.call(via(game_id), :fen)

  @doc """
  A suggested move for whoever is currently to move -- free (no extra
  engine call): `last_analysis` is already the analysis of the current
  position, computed right after the previous move was applied.
  """
  def hint(game_id), do: GenServer.call(via(game_id), :hint)

  @doc """
  Plays the engine's opening move if (and only if) this is a brand-new game
  where the human chose to play second. Returns `{:ok, %{engine_move:
  attrs}}` (persisted by the caller as ply 1, same as any other move) or
  `{:ok, :not_applicable}`. Safe to call unconditionally/idempotently --
  only acts while `next_ply` is still 1.
  """
  def maybe_play_opening_move(game_id), do: GenServer.call(via(game_id), :maybe_play_opening_move, 20_000)

  @doc """
  Takes back to the position implied by `new_moves` (a prefix of the previously
  played `uci` list) -- stops and rebuilds both Stockfish subprocesses from scratch
  and replays `new_moves` into them, the same engine-startup path `init/1` uses, so
  there's no separate "undo" logic to keep in sync with normal game setup.
  """
  def undo(game_id, new_moves), do: GenServer.call(via(game_id), {:undo, new_moves}, 20_000)

  defp via(game_id), do: {:via, Registry, {GamesTutor.Games.GameRegistry, game_id}}

  # ---- Server callbacks ----

  @impl true
  def init(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    opponent_config = Keyword.fetch!(opts, :opponent_config)
    moves = Keyword.get(opts, :moves, [])
    human_color = Keyword.get(opts, :human_color, "white")
    stockfish_path = Application.fetch_env!(:games_tutor, :stockfish_path)

    {board_pid, opp_pid, last_analysis} = start_engines(moves, opponent_config, stockfish_path)

    state = %{
      game_id: game_id,
      board_pid: board_pid,
      opp_pid: opp_pid,
      opponent_config: opponent_config,
      stockfish_path: stockfish_path,
      human_color: human_color,
      next_ply: length(moves) + 1,
      last_move_at: System.monotonic_time(:millisecond),
      last_analysis: last_analysis
    }

    {:ok, state, @idle_timeout}
  end

  # Shared by init/1 (fresh/restored game) and the :undo handler (rewound game) --
  # spinning up two fresh Stockfish subprocesses and replaying `moves` into the
  # board one is the one true "give me a position" path; undo just calls it again
  # with a shorter list rather than trying to reverse-apply anything.
  defp start_engines(moves, opponent_config, stockfish_path) do
    {:ok, board_pid} = :binbo.new_server()
    {:ok, _status} = :binbo.new_uci_game(board_pid, %{engine_path: stockfish_path})
    :binbo.set_uci_handler(board_pid, uci_handler())

    Enum.each(moves, fn uci ->
      {:ok, _status} = :binbo.move(board_pid, uci)
    end)

    if moves != [], do: :binbo.uci_sync_position(board_pid)

    {:ok, opp_pid} = :binbo.new_server()
    {:ok, _status} = :binbo.new_uci_game(opp_pid, %{engine_path: stockfish_path})
    configure_opponent_strength(opp_pid, opponent_config)

    {board_pid, opp_pid, analyze(board_pid)}
  end

  @impl true
  def handle_call({:submit_human_move, uci_move}, _from, state) do
    case :binbo.game_status(state.board_pid) do
      {:ok, :continue} ->
        do_submit_human_move(uci_move, state)

      {:ok, _terminal} ->
        {:reply, {:error, :game_over}, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call(:resign, _from, state) do
    case :binbo.set_game_winner(state.board_pid, engine_color(state), :human_resigned) do
      :ok ->
        {:ok, status} = :binbo.game_status(state.board_pid)
        {:reply, {:ok, status}, state, @idle_timeout}

      {:error, _} = error ->
        {:reply, error, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call(:fen, _from, state) do
    {:ok, fen} = :binbo.get_fen(state.board_pid)
    {:reply, {:ok, fen}, state, @idle_timeout}
  end

  @impl true
  def handle_call(:hint, _from, state) do
    {:reply, {:ok, state.last_analysis.bestmove}, state, @idle_timeout}
  end

  @impl true
  def handle_call(:maybe_play_opening_move, _from, %{next_ply: 1, human_color: "black"} = state) do
    play_opening_engine_move(state)
  end

  @impl true
  def handle_call(:maybe_play_opening_move, _from, state) do
    {:reply, {:ok, :not_applicable}, state, @idle_timeout}
  end

  @impl true
  def handle_call({:undo, new_moves}, _from, state) do
    :binbo.stop_server(state.board_pid)
    :binbo.stop_server(state.opp_pid)

    {board_pid, opp_pid, last_analysis} = start_engines(new_moves, state.opponent_config, state.stockfish_path)

    state = %{
      state
      | board_pid: board_pid,
        opp_pid: opp_pid,
        next_ply: length(new_moves) + 1,
        last_move_at: System.monotonic_time(:millisecond),
        last_analysis: last_analysis
    }

    {:reply, :ok, state, @idle_timeout}
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.info("GameServer for #{state.game_id} idle-timed-out, stopping engines")
    :binbo.stop_server(state.board_pid)
    :binbo.stop_server(state.opp_pid)
    {:stop, :normal, state}
  end

  # Stray UCI info lines that arrive outside of an active drain (e.g. after
  # a bestmove's final line) -- harmless, just discard.
  @impl true
  def handle_info({:uci_info, _line}, state), do: {:noreply, state, @idle_timeout}

  # ---- Move handling ----

  defp do_submit_human_move(uci_move, state) do
    think_time_ms = System.monotonic_time(:millisecond) - state.last_move_at
    eval_before_human = UciInfo.to_centipawns(state.last_analysis.score)
    engine_best_move = state.last_analysis.bestmove

    case :binbo.move(state.board_pid, uci_move) do
      {:error, reason} ->
        {:reply, {:error, {:illegal_move, reason}}, state, @idle_timeout}

      {:ok, status} ->
        {:ok, fen_after} = :binbo.get_fen(state.board_pid)

        {eval_after_human, human_analysis} =
          case status do
            :continue ->
              :binbo.uci_sync_position(state.board_pid)
              analysis = analyze(state.board_pid)
              {-UciInfo.to_centipawns(analysis.score), analysis}

            {:checkmate, _} ->
              {@decisive_score, nil}

            _draw_or_other ->
              {0, nil}
          end

        loss = max(eval_before_human - eval_after_human, 0)

        human_move = %{
          ply: state.next_ply,
          player: "human",
          notation: uci_move,
          uci: uci_move,
          fen_after: fen_after,
          eval_before: eval_before_human,
          eval_after: eval_after_human,
          loss: loss,
          engine_best_move: engine_best_move,
          classification: Atom.to_string(MoveClassifier.classify(loss)),
          think_time_ms: think_time_ms
        }

        now = System.monotonic_time(:millisecond)

        case status do
          :continue ->
            play_opponent_reply(state, human_move, human_analysis, now)

          terminal ->
            state = %{state | next_ply: state.next_ply + 1, last_move_at: now}
            {:reply, {:ok, %{status: terminal, human_move: human_move, engine_move: nil}}, state, @idle_timeout}
        end
    end
  end

  defp play_opponent_reply(state, human_move, human_analysis, move_started_at) do
    :binbo.uci_set_position(state.opp_pid, human_move.fen_after)
    :binbo.uci_sync_position(state.opp_pid)

    {:ok, engine_uci} =
      :telemetry.span([:games_tutor, :engine, :query], %{engine: :stockfish, kind: :opponent_move}, fn ->
        result = :binbo.uci_bestmove(state.opp_pid, %{movetime: @opponent_movetime})
        {result, %{engine: :stockfish, kind: :opponent_move}}
      end)

    {:ok, status} = :binbo.move(state.board_pid, engine_uci)
    {:ok, fen_after} = :binbo.get_fen(state.board_pid)

    eval_before_engine = UciInfo.to_centipawns(human_analysis.score)

    {eval_after_engine, next_analysis} =
      case status do
        :continue ->
          :binbo.uci_sync_position(state.board_pid)
          analysis = analyze(state.board_pid)
          {-UciInfo.to_centipawns(analysis.score), analysis}

        {:checkmate, _} ->
          {@decisive_score, nil}

        _draw_or_other ->
          {0, nil}
      end

    loss = max(eval_before_engine - eval_after_engine, 0)

    engine_move = %{
      ply: state.next_ply + 1,
      player: "engine",
      notation: engine_uci,
      uci: engine_uci,
      fen_after: fen_after,
      eval_before: eval_before_engine,
      eval_after: eval_after_engine,
      loss: loss,
      engine_best_move: human_analysis.bestmove,
      classification: Atom.to_string(MoveClassifier.classify(loss)),
      think_time_ms: System.monotonic_time(:millisecond) - move_started_at
    }

    state = %{
      state
      | next_ply: state.next_ply + 2,
        last_move_at: System.monotonic_time(:millisecond),
        last_analysis: next_analysis || state.last_analysis
    }

    {:reply, {:ok, %{status: status, human_move: human_move, engine_move: engine_move}}, state, @idle_timeout}
  end

  # White moves first in real chess -- when the human chose Black, the
  # engine must play move 1 itself, from opp_pid's already-correct starting
  # position (freshly initialized in init/1, no moves applied yet).
  defp play_opening_engine_move(state) do
    move_started_at = System.monotonic_time(:millisecond)
    eval_before_engine = UciInfo.to_centipawns(state.last_analysis.score)

    {:ok, engine_uci} =
      :telemetry.span([:games_tutor, :engine, :query], %{engine: :stockfish, kind: :opponent_move}, fn ->
        result = :binbo.uci_bestmove(state.opp_pid, %{movetime: @opponent_movetime})
        {result, %{engine: :stockfish, kind: :opponent_move}}
      end)

    {:ok, :continue} = :binbo.move(state.board_pid, engine_uci)
    {:ok, fen_after} = :binbo.get_fen(state.board_pid)

    :binbo.uci_sync_position(state.board_pid)
    next_analysis = analyze(state.board_pid)
    eval_after_engine = -UciInfo.to_centipawns(next_analysis.score)
    loss = max(eval_before_engine - eval_after_engine, 0)

    engine_move = %{
      ply: 1,
      player: "engine",
      notation: engine_uci,
      uci: engine_uci,
      fen_after: fen_after,
      eval_before: eval_before_engine,
      eval_after: eval_after_engine,
      loss: loss,
      engine_best_move: state.last_analysis.bestmove,
      classification: Atom.to_string(MoveClassifier.classify(loss)),
      think_time_ms: System.monotonic_time(:millisecond) - move_started_at
    }

    state = %{
      state
      | next_ply: 2,
        last_move_at: System.monotonic_time(:millisecond),
        last_analysis: next_analysis
    }

    {:reply, {:ok, %{engine_move: engine_move}}, state, @idle_timeout}
  end

  # ---- Engine helpers ----

  defp analyze(board_pid) do
    :telemetry.span([:games_tutor, :engine, :query], %{engine: :stockfish, kind: :analysis}, fn ->
      {:ok, bestmove} = :binbo.uci_bestmove(board_pid, %{depth: @analysis_depth})
      score = drain_uci_score() || {:cp, 0}
      {%{score: score, bestmove: bestmove}, %{engine: :stockfish, kind: :analysis}}
    end)
  end

  # binbo delivers "info ..." lines to our mailbox asynchronously as the
  # engine searches; by the time uci_bestmove/2 returns they're already
  # queued (binbo's message-sending runs on its own process, concurrently
  # with our blocked call), so a non-blocking drain reliably collects them
  # all without needing a stateful buffer or handle_info round-trip.
  defp drain_uci_score(lines \\ []) do
    receive do
      {:uci_info, line} -> drain_uci_score([line | lines])
    after
      0 -> UciInfo.last_score(Enum.reverse(lines))
    end
  end

  defp uci_handler do
    parent = self()
    fn msg -> send(parent, {:uci_info, msg}) end
  end

  @stockfish_elo_floor 1320
  @stockfish_elo_ceiling 3190

  defp configure_opponent_strength(pid, %{"elo" => elo}) when elo >= @stockfish_elo_floor do
    elo = min(elo, @stockfish_elo_ceiling)
    :ok = :binbo.uci_command_call(pid, "setoption name UCI_LimitStrength value true")
    :ok = :binbo.uci_command_call(pid, "setoption name UCI_Elo value #{elo}")
  end

  # Below Stockfish's own hard UCI_Elo floor (confirmed 1320 in the Phase 0
  # spike), fall back to Skill Level, approximated via a documented linear
  # map -- Stockfish doesn't publish an Elo<->Skill Level table, so this is
  # a v1 heuristic, not a calibrated conversion.
  defp configure_opponent_strength(pid, %{"elo" => elo}) do
    skill = round(20 * (elo - 400) / (@stockfish_elo_floor - 400)) |> clamp(0, 20)
    configure_opponent_strength(pid, %{"skill_level" => skill})
  end

  defp configure_opponent_strength(pid, %{"skill_level" => level}) do
    level = clamp(level, 0, 20)
    :ok = :binbo.uci_command_call(pid, "setoption name UCI_LimitStrength value false")
    :ok = :binbo.uci_command_call(pid, "setoption name Skill Level value #{level}")
  end

  defp clamp(n, min, max), do: n |> Kernel.max(min) |> Kernel.min(max)

  defp engine_color(%{human_color: "black"}), do: :white
  defp engine_color(%{human_color: "white"}), do: :black
end
