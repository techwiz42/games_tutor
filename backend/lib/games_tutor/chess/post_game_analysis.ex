defmodule GamesTutor.Chess.PostGameAnalysis do
  @moduledoc """
  Re-analyzes a finished game's moves at a higher depth than live play uses
  (live play trades accuracy for HTTP response latency; this background
  pass has no such constraint) and backfills eval/loss/classification.
  Runs in its own throwaway binbo/Stockfish process, independent of the
  game's (likely already idle-evicted, since the game just ended) GameServer.
  """
  require Logger
  import Ecto.Query

  alias GamesTutor.Repo
  alias GamesTutor.Games.Move
  alias GamesTutor.Chess.{MoveClassifier, UciInfo}

  @deep_analysis_depth 18
  @decisive_score 10_000

  @doc "Fire-and-forget: runs on GamesTutor.Chess.AnalysisTaskSupervisor."
  def enqueue(game_id) do
    Task.Supervisor.start_child(GamesTutor.Chess.AnalysisTaskSupervisor, fn -> run(game_id) end)
  end

  def run(game_id) do
    moves = Repo.all(from(m in Move, where: m.game_id == ^game_id, order_by: m.ply))
    stockfish_path = Application.fetch_env!(:games_tutor, :stockfish_path)

    {:ok, pid} = :binbo.new_server()
    {:ok, :continue} = :binbo.new_uci_game(pid, %{engine_path: stockfish_path})
    parent = self()
    :binbo.set_uci_handler(pid, fn msg -> send(parent, {:uci_info, msg}) end)

    last_analysis = analyze(pid)

    Enum.reduce(moves, last_analysis, fn move, prior_analysis ->
      # prior_analysis.score is the current position's eval from the
      # perspective of whoever is about to move -- i.e. this move's mover,
      # no sign flip needed.
      eval_before = UciInfo.to_centipawns(prior_analysis.score)
      engine_best_move = prior_analysis.bestmove

      {:ok, status} = :binbo.move(pid, move.uci)

      {eval_after, next_analysis} =
        case status do
          :continue ->
            :binbo.uci_sync_position(pid)
            analysis = analyze(pid)
            # analysis.score is from the *next* mover's perspective (the
            # other side), so flip it to get this move's mover's eval_after.
            {-UciInfo.to_centipawns(analysis.score), analysis}

          {:checkmate, _} ->
            {@decisive_score, nil}

          _draw_or_other ->
            {0, nil}
        end

      loss = max(eval_before - eval_after, 0)

      move
      |> Move.analysis_changeset(%{
        eval_before: eval_before,
        eval_after: eval_after,
        loss: loss,
        engine_best_move: engine_best_move,
        classification: Atom.to_string(MoveClassifier.classify(loss))
      })
      |> Repo.update!()

      next_analysis || prior_analysis
    end)

    :binbo.stop_server(pid)
    Logger.info("Post-game analysis complete for game #{game_id} (#{length(moves)} moves)")
    :ok
  end

  defp analyze(pid) do
    {:ok, bestmove} = :binbo.uci_bestmove(pid, %{depth: @deep_analysis_depth})
    score = drain_uci_score() || {:cp, 0}
    %{score: score, bestmove: bestmove}
  end

  defp drain_uci_score(lines \\ []) do
    receive do
      {:uci_info, line} -> drain_uci_score([line | lines])
    after
      0 -> UciInfo.last_score(Enum.reverse(lines))
    end
  end
end
