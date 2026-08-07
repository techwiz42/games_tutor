defmodule GamesTutorWeb.GameJSON do
  alias GamesTutor.Games

  @doc "For list views -- no per-move detail, so no need to preload moves."
  def summary(game) do
    %{
      id: game.id,
      game_type: game.game_type,
      status: game.status,
      result: game.result,
      # "white_wins"/"black_wins" name the literal board color that won --
      # human_color tells the caller which color that is (White in chess,
      # Black in Go), so displaying "did I win?" doesn't need to hardcode
      # a game-type assumption.
      human_color: Games.human_color(game),
      is_calibration: game.is_calibration,
      opponent_engine_config: game.opponent_engine_config,
      started_at: game.started_at,
      ended_at: game.ended_at
    }
  end

  @doc "For the single-game view -- includes the full move list and current position."
  def show(game, skill_profile \\ nil) do
    game
    |> summary()
    |> Map.merge(%{
      fen: Games.current_fen(game),
      moves: Enum.map(game.moves, &move/1),
      skill_profile: skill_profile && skill_profile(skill_profile)
    })
  end

  def move_result(%{game: game, human_move: human_move, engine_move: engine_move, skill_profile: skill_profile}) do
    %{
      game: summary(game),
      fen: (engine_move || human_move).fen_after,
      human_move: move(human_move),
      engine_move: engine_move && move(engine_move),
      skill_profile: skill_profile && skill_profile(skill_profile)
    }
  end

  def skill_profile(profile) do
    %{
      game_type: profile.game_type,
      estimated_rating: round(profile.estimated_rating),
      rating_sigma: Float.round(profile.rating_sigma, 1),
      display_label: profile.display_label,
      games_count: profile.games_count
    }
  end

  def move(move) do
    %{
      ply: move.ply,
      player: move.player,
      notation: move.notation,
      uci: move.uci,
      fen_after: move.fen_after,
      eval_before: move.eval_before,
      eval_after: move.eval_after,
      loss: move.loss,
      engine_best_move: move.engine_best_move,
      classification: move.classification,
      think_time_ms: move.think_time_ms,
      prior: move.prior
    }
  end
end
