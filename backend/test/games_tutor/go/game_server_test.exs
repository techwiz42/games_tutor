defmodule GamesTutor.Go.GameServerTest do
  # Not async: spawns real KataGo subprocesses, same convention as the
  # chess GameServer's integration tests.
  use ExUnit.Case, async: false

  alias GamesTutor.Go.GameServer

  defp new_game_id, do: Ecto.UUID.generate()

  # final_status/2's ownership-based math reduces to a clean identity worth
  # spelling out here: black_area - white_area == sum(ownership) (the +1/-1
  # constant terms in `(o+1)/2` vs `(1-o)/2` cancel), so these synthetic
  # ownership lists don't need to be realistic 81-point boards -- they're
  # testing the arithmetic in isolation, not any real position.
  describe "final_status/2 -- finding 2 (ownership-based real scoring, not a score_lead estimate)" do
    test "black wins when the area lead exceeds komi" do
      assert GameServer.final_status(%{ownership: [1.0, 1.0, 1.0]}, 2.5) == {:scored, :black_wins}
    end

    test "white wins when the area lead favors white" do
      assert GameServer.final_status(%{ownership: [-1.0, -1.0, -1.0]}, 7.5) == {:scored, :white_wins}
    end

    test "komi is genuinely applied, not just the raw area sign -- a small black area lead still loses to white once komi is subtracted" do
      # sum(ownership) = 1.0 -- a real black lead, but well under komi 7.5.
      assert GameServer.final_status(%{ownership: [1.0, -1.0, 1.0, -1.0, 1.0]}, 7.5) == {:scored, :white_wins}
    end

    test "an exact tie after komi is a draw" do
      # sum(ownership) = 7.5, exactly matching komi.
      ownership = List.duplicate(1.0, 7) ++ [0.5]
      assert GameServer.final_status(%{ownership: ownership}, 7.5) == {:scored, :draw}
    end

    test "contested (near-zero ownership) points contribute fractional credit, not a forced binary call" do
      # Two genuinely 50/50-contested points (ownership 0.0) contribute
      # 0.5 to each side -- net zero to the lead either way, unlike a
      # thresholding scheme that would have to arbitrarily assign them.
      assert GameServer.final_status(%{ownership: [0.0, 0.0, 1.0, 1.0, 1.0]}, 2.5) == {:scored, :black_wins}
      assert GameServer.final_status(%{ownership: [0.0, 0.0, 1.0, 1.0]}, 2.5) == {:scored, :white_wins}
    end

    test "falls back to the score_lead heuristic when ownership is absent (e.g. an older recorded fixture)" do
      assert GameServer.final_status(%{score_lead: 5.0, current_player: "B"}, 7.5) == {:scored, :black_wins}
      assert GameServer.final_status(%{score_lead: -5.0, current_player: "B"}, 7.5) == {:scored, :white_wins}
      assert GameServer.final_status(%{score_lead: 5.0, current_player: "W"}, 7.5) == {:scored, :white_wins}
    end
  end

  test "plays a legal move and gets a real engine reply" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})

    assert {:ok, %{status: :continue, human_move: human, engine_move: engine}} =
             GameServer.submit_human_move(game_id, "E5")

    assert human.player == "human"
    assert human.uci == "E5"
    assert is_integer(human.eval_before)
    assert is_integer(human.eval_after)
    assert human.loss >= 0
    assert human.classification in ~w(best good inaccuracy mistake blunder)

    assert engine.player == "engine"
    assert engine.ply == human.ply + 1
    # A real move (or a legitimate pass) from the real weak-opponent query.
    assert engine.uci == "pass" or engine.uci =~ ~r/^[A-Za-z]\d{1,2}$/
  end

  test "a submitted move is classified under the volatility-scaled scheme (finding 3)" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})

    assert {:ok, %{human_move: human}} = GameServer.submit_human_move(game_id, "E5")

    assert human.classification_version == 2
    assert human.classification in ~w(best good inaccuracy mistake blunder)
  end

  test "a submitted move carries a real prior from the engine's policy network (finding 2)" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})

    assert {:ok, %{human_move: human}} = GameServer.submit_human_move(game_id, "E5")

    assert is_float(human.prior)
    assert human.prior >= 0.0 and human.prior <= 1.0
  end

  test "a submitted move's fen_after embeds the real per-point ownership map (finding 2)" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})

    assert {:ok, %{human_move: human}} = GameServer.submit_human_move(game_id, "E5")

    decoded = Jason.decode!(human.fen_after)
    assert length(decoded["ownership"]) == 81
    assert Enum.all?(decoded["ownership"], &is_number/1)
  end

  test "rejects an illegal move (occupied point) without mutating game state" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})

    {:ok, %{status: :continue}} = GameServer.submit_human_move(game_id, "E5")

    # E5 is occupied now (by the human's own stone) -- illegal for anyone to play on.
    assert {:error, {:illegal_move, _reason}} = GameServer.submit_human_move(game_id, "E5")
  end

  test "rejects unparseable coordinates cheaply, without querying katago" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})

    assert {:error, {:illegal_move, :unparseable_coord}} = GameServer.submit_human_move(game_id, "Z99")
  end

  test "ensure_started is idempotent" do
    game_id = new_game_id()
    {:ok, pid1} = GameServer.ensure_started(game_id, %{"max_visits" => 10})
    {:ok, pid2} = GameServer.ensure_started(game_id, %{"max_visits" => 10})
    assert pid1 == pid2
  end

  test "restores from a move history (idle-eviction / process-restart recovery)" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, [["B", "E5"], ["W", "C3"]])
    assert {:ok, grid} = GameServer.board_grid(game_id)
    flat = List.flatten(grid)
    assert Enum.count(flat, &(&1 == 1)) == 1
    assert Enum.count(flat, &(&1 == -1)) == 1
  end

  test "hint returns a real suggested move for the current position" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})
    assert {:ok, coord} = GameServer.hint(game_id)
    assert coord == "pass" or coord =~ ~r/^[A-Za-z]\d{1,2}$/
  end

  test "resign ends the game in the engine's favor" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})
    assert {:ok, {:winner, :white, {:manual, :human_resigned}}} = GameServer.resign(game_id)
    assert {:error, :game_over} = GameServer.submit_human_move(game_id, "E5")
  end

  test "two consecutive passes ends the game with a scored result and no engine_move" do
    game_id = new_game_id()

    # Seed history ending in a White pass (consecutive_passes already at 1)
    # so the human's own single live pass deterministically reaches 2 --
    # the terminal check fires immediately, before any real opponent-reply
    # query, so this doesn't depend on the (real, not scripted) engine
    # choosing to pass too.
    history = [["B", "C5"], ["W", "pass"]]
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, history)

    assert {:ok, %{status: status, engine_move: nil}} = GameServer.submit_human_move(game_id, "pass")
    assert {:scored, result} = status
    assert result in [:black_wins, :white_wins, :draw]
  end

  test "captures are reflected in the board grid" do
    game_id = new_game_id()
    # Pre-set history that surrounds a lone white stone at C5, then black
    # plays the capturing move live through the real server.
    history = [
      ["W", "C5"],
      ["B", "B5"],
      ["W", "H1"],
      ["B", "D5"],
      ["W", "H2"],
      ["B", "C4"],
      # Filler White move -- keeps the history's move count odd (started
      # with White) so it's Black's (the default human color's) turn next.
      ["W", "H3"]
    ]

    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, history)
    assert {:ok, %{status: :continue, human_move: human}} = GameServer.submit_human_move(game_id, "C6")

    assert human.uci == "C6"
    assert {:ok, grid} = GameServer.board_grid(game_id)

    # C5 (the captured stone) must now be empty; the unrelated White filler
    # stones (H1/H2/H3, never surrounded) must still be present -- captures
    # should remove exactly the surrounded group, nothing more/less.
    assert stone_at(grid, "C5") == :empty
    assert stone_at(grid, "H1") == :white
    assert stone_at(grid, "H2") == :white
    assert stone_at(grid, "H3") == :white
    assert stone_at(grid, "B5") == :black
    assert stone_at(grid, "C6") == :black
  end

  test "maybe_play_opening_move is a no-op when the human plays the default color (Black)" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10})
    assert {:ok, :not_applicable} = GameServer.maybe_play_opening_move(game_id)
  end

  test "maybe_play_opening_move plays a real Black opening move when the human chose White" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, [], "white")

    assert {:ok, %{engine_move: move}} = GameServer.maybe_play_opening_move(game_id)
    assert move.player == "engine"
    assert move.ply == 1
    assert move.uci == "pass" or move.uci =~ ~r/^[A-Za-z]\d{1,2}$/

    # It's genuinely the human's (White's) turn now -- a live move applies cleanly.
    assert {:ok, %{status: :continue, human_move: human}} = GameServer.submit_human_move(game_id, "E5")
    assert human.ply == 2
  end

  test "maybe_play_opening_move only acts once, even if called again" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, [], "white")
    assert {:ok, %{engine_move: _}} = GameServer.maybe_play_opening_move(game_id)
    assert {:ok, :not_applicable} = GameServer.maybe_play_opening_move(game_id)
  end

  test "with the human playing White, human moves are tagged W and engine replies are tagged B" do
    game_id = new_game_id()
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, [], "white")
    {:ok, %{engine_move: _}} = GameServer.maybe_play_opening_move(game_id)

    assert {:ok, %{status: :continue, human_move: human, engine_move: engine}} =
             GameServer.submit_human_move(game_id, "E5")

    assert human.player == "human"
    assert engine.player == "engine"
    # White (the human here) stones show as -1 on the grid; confirm the
    # human's own move landed as White, not Black.
    assert {:ok, grid} = GameServer.board_grid(game_id)
    assert stone_at(grid, "E5") == :white
  end

  test "undo rebuilds local board/history state from a truncated history" do
    game_id = new_game_id()
    history = [["B", "E5"], ["W", "C3"]]
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, history)

    assert :ok = GameServer.undo(game_id, [["B", "E5"]])

    assert {:ok, grid} = GameServer.board_grid(game_id)
    assert stone_at(grid, "E5") == :black
    assert stone_at(grid, "C3") == :empty
  end

  test "undo to an empty history clears the board and resets consecutive_passes" do
    game_id = new_game_id()
    history = [["B", "C5"], ["W", "pass"]]
    {:ok, _pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, history)

    assert :ok = GameServer.undo(game_id, [])

    assert {:ok, grid} = GameServer.board_grid(game_id)
    assert Enum.all?(List.flatten(grid), &(&1 == 0))

    # consecutive_passes reset to 0 -- a single live pass (ply 1, the default
    # human color's opening move) shouldn't end the game on its own.
    assert {:ok, %{status: :continue}} = GameServer.submit_human_move(game_id, "pass")
  end

  describe "query/4 failure handling (finding 1b)" do
    # go_query_timeout_ms is a test-only override (see game_server.ex's
    # query_timeout_ms/0) -- forces a real, fast, deterministic
    # {:error, :katago_timeout} from the live engine (300+ visits genuinely
    # cannot complete in 1ms) instead of either mocking the port or waiting
    # out the real 60s production timeout.
    #
    # Must NOT be set until *after* the server has finished its initial
    # analysis (handle_continue/2) -- that query runs under the same
    # timeout, and if it's forced to fail too, the server stops itself
    # (correctly, per finding 1b's design) before ever reaching the call
    # this test is actually trying to exercise. `board_grid/1` is a plain
    # handle_call, which -- like any message -- only gets processed after
    # the continue completes, so calling it once is a synchronous "wait
    # until ready" barrier under the real, un-shortened timeout.
    defp start_and_await_ready(game_id, opponent_config, history \\ [], human_color \\ "black") do
      {:ok, pid} = GameServer.ensure_started(game_id, opponent_config, history, human_color)
      {:ok, _grid} = GameServer.board_grid(game_id)
      {:ok, pid}
    end

    defp with_forced_timeout(fun) do
      Application.put_env(:games_tutor, :go_query_timeout_ms, 1)

      try do
        fun.()
      after
        Application.delete_env(:games_tutor, :go_query_timeout_ms)
      end
    end

    test "submit_human_move replies :engine_unavailable and leaves state untouched, so the same move can be retried" do
      game_id = new_game_id()
      {:ok, _pid} = start_and_await_ready(game_id, %{"max_visits" => 10})

      with_forced_timeout(fn ->
        assert {:error, {:engine_unavailable, :katago_timeout}} = GameServer.submit_human_move(game_id, "E5")
      end)

      # Prove nothing was committed: with the real timeout restored, the
      # exact same move still applies cleanly at ply 1 (not ply 2 -- if the
      # failed attempt had mutated state, this would either fail as
      # "occupied" or land at the wrong ply).
      assert {:ok, %{status: :continue, human_move: human}} = GameServer.submit_human_move(game_id, "E5")
      assert human.ply == 1
    end

    test "maybe_play_opening_move replies :engine_unavailable and can be retried" do
      game_id = new_game_id()
      {:ok, _pid} = start_and_await_ready(game_id, %{"max_visits" => 10}, [], "white")

      with_forced_timeout(fn ->
        assert {:error, {:engine_unavailable, :katago_timeout}} = GameServer.maybe_play_opening_move(game_id)
      end)

      assert {:ok, %{engine_move: move}} = GameServer.maybe_play_opening_move(game_id)
      assert move.ply == 1
    end

    test "undo replies :engine_unavailable and leaves state untouched" do
      game_id = new_game_id()
      history = [["B", "E5"], ["W", "C3"]]
      {:ok, _pid} = start_and_await_ready(game_id, %{"max_visits" => 10}, history)

      with_forced_timeout(fn ->
        assert {:error, {:engine_unavailable, :katago_timeout}} = GameServer.undo(game_id, [["B", "E5"]])
      end)

      # Board still reflects the ORIGINAL history (undo never applied) --
      # both E5 and C3 present.
      assert {:ok, grid} = GameServer.board_grid(game_id)
      assert stone_at(grid, "E5") == :black
      assert stone_at(grid, "C3") == :white
    end

    test "a timed-out query does not crash the GameServer -- it stays alive and registered" do
      game_id = new_game_id()
      {:ok, pid} = start_and_await_ready(game_id, %{"max_visits" => 10})

      with_forced_timeout(fn ->
        assert {:error, {:engine_unavailable, :katago_timeout}} = GameServer.submit_human_move(game_id, "E5")
      end)

      assert Process.alive?(pid)
      assert [{^pid, _}] = Registry.lookup(GamesTutor.Games.GameRegistry, {:go, game_id})
    end
  end

  describe "sample_move_weighted_by_prior/2 -- finding 4 (temperature-weighted opponent move selection)" do
    test "empty moveInfos falls back to pass" do
      assert GameServer.sample_move_weighted_by_prior([], 1.0) == "pass"
    end

    test "a single candidate is always picked regardless of temperature" do
      move_infos = [%{"move" => "D4", "prior" => 0.3}]

      for temperature <- [0.1, 1.0, 5.0] do
        assert GameServer.sample_move_weighted_by_prior(move_infos, temperature) == "D4"
      end
    end

    test "very low temperature converges to always picking the highest-prior move (the old List.first/1 behavior)" do
      move_infos = [
        %{"move" => "D4", "prior" => 0.6},
        %{"move" => "C3", "prior" => 0.3},
        %{"move" => "E5", "prior" => 0.1}
      ]

      picks = for _ <- 1..200, do: GameServer.sample_move_weighted_by_prior(move_infos, 0.01)
      assert Enum.all?(picks, &(&1 == "D4"))
    end

    test "sampling frequency roughly tracks each candidate's prior weight at temperature 1.0" do
      move_infos = [
        %{"move" => "D4", "prior" => 0.6},
        %{"move" => "C3", "prior" => 0.3},
        %{"move" => "E5", "prior" => 0.1}
      ]

      n = 5000
      freq = for(_ <- 1..n, do: GameServer.sample_move_weighted_by_prior(move_infos, 1.0)) |> Enum.frequencies()

      # A randomized statistical test -- generous tolerance, not an exact match.
      assert_in_delta Map.get(freq, "D4", 0) / n, 0.6, 0.05
      assert_in_delta Map.get(freq, "C3", 0) / n, 0.3, 0.05
      assert_in_delta Map.get(freq, "E5", 0) / n, 0.1, 0.05
    end

    test "higher temperature flattens a skewed distribution toward uniform" do
      move_infos = [
        %{"move" => "D4", "prior" => 0.9},
        %{"move" => "C3", "prior" => 0.05},
        %{"move" => "E5", "prior" => 0.05}
      ]

      n = 5000
      freq = for(_ <- 1..n, do: GameServer.sample_move_weighted_by_prior(move_infos, 20.0)) |> Enum.frequencies()

      assert_in_delta Map.get(freq, "D4", 0) / n, 0.333, 0.08
      assert_in_delta Map.get(freq, "C3", 0) / n, 0.333, 0.08
      assert_in_delta Map.get(freq, "E5", 0) / n, 0.333, 0.08
    end

    test "a missing prior field is treated as effectively zero, not a crash" do
      move_infos = [%{"move" => "D4", "prior" => 0.5}, %{"move" => "C3"}]
      assert GameServer.sample_move_weighted_by_prior(move_infos, 1.0) in ["D4", "C3"]
    end
  end

  describe "restart: :temporary (finding 1b)" do
    # Process.monitor/1's :DOWN and Registry's own internal deregistration
    # are two independent observers of the same process death -- both get
    # notified, but not necessarily in lockstep, since Registry updates its
    # own ETS table from ITS OWN monitor's mailbox, asynchronously relative
    # to any other monitor (like a test's). Polling here (rather than
    # trusting that receiving our own :DOWN means Registry has already
    # cleaned up too) is what makes these tests deterministic instead of
    # occasionally flaky.
    defp wait_until_deregistered(game_id, attempts \\ 50)

    defp wait_until_deregistered(_game_id, 0), do: flunk("Registry entry was never cleared")

    defp wait_until_deregistered(game_id, attempts) do
      case Registry.lookup(GamesTutor.Games.GameRegistry, {:go, game_id}) do
        [] -> :ok
        _ -> Process.sleep(10) && wait_until_deregistered(game_id, attempts - 1)
      end
    end

    test "idle-eviction's deliberate :normal stop is NOT auto-restarted by the supervisor" do
      game_id = new_game_id()
      {:ok, pid} = start_and_await_ready(game_id, %{"max_visits" => 10})
      ref = Process.monitor(pid)

      # Exactly what handle_info(:timeout, state) does.
      send(pid, :timeout)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
      wait_until_deregistered(game_id)

      # With the previous default (:permanent), the supervisor would have
      # already respawned a new process under this same game_id by now --
      # give it a moment to do so if it's going to, then confirm it hasn't.
      Process.sleep(200)
      assert Registry.lookup(GamesTutor.Games.GameRegistry, {:go, game_id}) == []
    end

    test "recovery after a stop goes through ensure_started/4 with fresh (not stale) history" do
      game_id = new_game_id()
      {:ok, pid} = start_and_await_ready(game_id, %{"max_visits" => 10})
      ref = Process.monitor(pid)
      send(pid, :timeout)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
      wait_until_deregistered(game_id)

      # The caller (GamesTutor.Games, in production) always re-reads
      # history from the DB before calling ensure_started/4 -- simulated
      # here by passing a non-empty history, unlike this game's original
      # (empty) start args, to prove recovery isn't just replaying whatever
      # the long-dead process happened to start with.
      {:ok, new_pid} = GameServer.ensure_started(game_id, %{"max_visits" => 10}, [["B", "E5"]])
      assert new_pid != pid

      assert {:ok, grid} = GameServer.board_grid(game_id)
      assert stone_at(grid, "E5") == :black
    end
  end

  # await_response/3 is `def` (not `defp`) specifically so these can call it
  # directly with a fake `port` term -- any term works, since the `receive`
  # inside only ever pattern-matches `{^port, {:data, data}}`, never touches
  # the real Port API. Messages are pre-loaded into this test process's own
  # mailbox before calling, so `receive` finds them immediately.
  describe "await_response/3 line buffering" do
    import ExUnit.CaptureLog

    test "drains a second complete response already in the buffer instead of blocking on receive" do
      port = make_ref()

      chunk =
        Jason.encode!(%{"id" => "q1", "rootInfo" => %{}}) <>
          "\n" <> Jason.encode!(%{"id" => "q2", "rootInfo" => %{}}) <> "\n"

      send(self(), {port, {:data, chunk}})

      # Before the fix: after the "q1" mismatch, this recursed straight into
      # `receive` without checking whether "q2" was already sitting in the
      # leftover buffer -- since no second message is ever sent here, that
      # version of the code would hang until @query_timeout (60s).
      assert {:ok, %{"id" => "q2"}} = GameServer.await_response(port, "q2", "")
    end

    test "reassembles a response whose JSON line is split across two chunks" do
      port = make_ref()
      line = Jason.encode!(%{"id" => "q1", "rootInfo" => %{}}) <> "\n"
      split_at = div(String.length(line), 2)
      {first, second} = String.split_at(line, split_at)

      send(self(), {port, {:data, first}})
      send(self(), {port, {:data, second}})

      assert {:ok, %{"id" => "q1"}} = GameServer.await_response(port, "q1", "")
    end

    test "skips a non-JSON stdout line (logging a warning) instead of crashing" do
      port = make_ref()
      chunk = "not json at all\n" <> Jason.encode!(%{"id" => "q1", "rootInfo" => %{}}) <> "\n"

      log =
        capture_log(fn ->
          send(self(), {port, {:data, chunk}})
          assert {:ok, %{"id" => "q1"}} = GameServer.await_response(port, "q1", "")
        end)

      assert log =~ "Skipping non-JSON line"
    end
  end

  # grid is row-major with row 0 = top (rank 9 on a 9x9 board) -- see
  # GamesTutor.Go.Board.to_grid/1's moduledoc.
  defp stone_at(grid, coord_str) do
    {x, y} = GamesTutor.Go.Board.parse_coord(coord_str)
    row = 8 - y

    case Enum.at(grid, row) |> Enum.at(x) do
      1 -> :black
      -1 -> :white
      0 -> :empty
    end
  end
end
