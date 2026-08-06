defmodule GamesTutor.Games do
  @moduledoc """
  Chess games against the Stockfish opponent. Human is always White (see
  `GamesTutor.Chess.GameServer`'s moduledoc) -- `white_wins` means the human
  won, `black_wins` means the engine won.

  "Rate my play" (`is_calibration: true`) opponent strength resolution
  follows the plan's documented order: (1) an explicit `opponent_elo`
  override, (2) the user's existing chess `SkillProfile` if one exists,
  (3) a platform default (seeded from an optional `self_reported_elo` on
  first-ever calibration, else a wide blind prior).
  """
  import Ecto.Query

  alias GamesTutor.Repo
  alias GamesTutor.Games.{Game, Move}
  alias GamesTutor.Chess.{GameServer, PostGameAnalysis}
  alias GamesTutor.Skill

  # Below Stockfish's UCI_Elo floor (1320, confirmed in Phase 0) on purpose:
  # a calibration game needs to run long enough to sample many moves, and a
  # full-strength opponent would end games (via losses) too quickly for
  # that. Not scientifically tuned -- a documented v1 default, not a
  # constant silently duplicated elsewhere.
  @default_calibration_elo 1200

  @starting_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  @doc "Current position, derived from stored moves -- no live engine process needed just to view a game."
  def current_fen(%Game{moves: moves}) when is_list(moves) and moves != [] do
    List.last(moves).fen_after
  end

  def current_fen(%Game{}), do: @starting_fen

  def list_games(user) do
    Game
    |> where([g], g.user_id == ^user.id)
    |> order_by([g], desc: g.inserted_at)
    |> Repo.all()
  end

  def get_game(user, id) do
    case Repo.get_by(Game, id: id, user_id: user.id) do
      nil -> {:error, :not_found}
      game -> {:ok, Repo.preload(game, moves: from(m in Move, order_by: m.ply))}
    end
  end

  def create_game(user, attrs) do
    opponent_config = resolve_opponent_config(user, attrs)

    game_attrs = %{
      user_id: user.id,
      game_type: "chess",
      is_calibration: !!Map.get(attrs, "is_calibration", false),
      opponent_engine_config: opponent_config,
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    with {:ok, game} <- %Game{} |> Game.create_changeset(game_attrs) |> Repo.insert() do
      {:ok, _pid} = GameServer.ensure_started(game.id, opponent_config)
      # A freshly inserted game has no moves yet -- known structurally, so
      # set it directly rather than issuing a wasted preload query.
      {:ok, %{game | moves: []}}
    end
  end

  @doc """
  Applies the human's move. Returns `{:ok, %{game:, human_move:, engine_move:}}`,
  `{:error, :illegal_move}`, `{:error, :game_over}`, or `{:error, :not_found}`.
  """
  def submit_move(user, game_id, uci_move) do
    with {:ok, game} <- get_game(user, game_id),
         :ok <- ensure_in_progress(game) do
      {:ok, _pid} = GameServer.ensure_started(game.id, game.opponent_engine_config, move_ucis(game))

      case GameServer.submit_human_move(game.id, uci_move) do
        {:error, {:illegal_move, _reason}} -> {:error, :illegal_move}
        {:ok, result} -> persist_result(game, result)
      end
    end
  end

  def resign(user, game_id) do
    with {:ok, game} <- get_game(user, game_id),
         :ok <- ensure_in_progress(game) do
      {:ok, _pid} = GameServer.ensure_started(game.id, game.opponent_engine_config, move_ucis(game))
      {:ok, status} = GameServer.resign(game.id)
      {game, skill_profile} = finish_game(game, status)
      {:ok, %{game: game, skill_profile: skill_profile}}
    end
  end

  @doc "For the get_board_state voice tool."
  def board_state(user, game_id) do
    with {:ok, game} <- get_game(user, game_id) do
      fen = current_fen(game)
      to_move = if game.status == "in_progress", do: side_to_move(fen), else: nil

      {:ok, %{fen: fen, status: game.status, result: game.result, to_move: to_move, is_calibration: game.is_calibration}}
    end
  end

  @doc "For the get_last_move_analysis / explain_move voice tools. `ply` nil means the most recent move."
  def move_analysis(user, game_id, ply \\ nil) do
    with {:ok, game} <- get_game(user, game_id) do
      move = if ply, do: Enum.find(game.moves, &(&1.ply == ply)), else: List.last(game.moves)
      if move, do: {:ok, move}, else: {:error, :not_found}
    end
  end

  @doc """
  For the request_hint voice tool. Hard-refused for calibration games --
  enforced here in code (not just in the voice agent's prompted behavior),
  since hinting would contaminate the skill measurement.
  """
  def hint(user, game_id) do
    with {:ok, game} <- get_game(user, game_id) do
      cond do
        game.is_calibration ->
          {:error, :hint_refused_calibration}

        game.status != "in_progress" ->
          {:error, :game_over}

        true ->
          {:ok, _pid} = GameServer.ensure_started(game.id, game.opponent_engine_config, move_ucis(game))
          GameServer.hint(game.id)
      end
    end
  end

  ## Internal

  defp side_to_move(fen) do
    case String.split(fen) do
      [_placement, "w" | _] -> "human"
      [_placement, "b" | _] -> "engine"
    end
  end

  defp resolve_opponent_config(_user, %{"opponent_elo" => elo}) when is_integer(elo), do: %{"elo" => elo}

  defp resolve_opponent_config(user, %{"is_calibration" => true} = attrs) do
    self_reported = Map.get(attrs, "self_reported_elo")
    opts = if is_integer(self_reported), do: [self_reported_elo: self_reported], else: []
    profile = Skill.get_or_init_profile(user, "chess", opts)
    %{"elo" => round(profile.estimated_rating)}
  end

  defp resolve_opponent_config(_user, _attrs), do: %{"elo" => @default_calibration_elo}

  defp ensure_in_progress(%Game{status: "in_progress"}), do: :ok
  defp ensure_in_progress(%Game{}), do: {:error, :game_over}

  defp move_ucis(%Game{moves: moves}) when is_list(moves), do: Enum.map(moves, & &1.uci)
  defp move_ucis(%Game{}), do: []

  defp persist_result(game, %{status: status, human_move: human_attrs, engine_move: engine_attrs}) do
    Repo.transaction(fn ->
      {:ok, human_move} = insert_move(game, human_attrs)
      engine_move = engine_attrs && insert_move!(game, engine_attrs)

      {game, skill_profile} =
        case status do
          :continue -> {game, nil}
          terminal -> finish_game(game, terminal)
        end

      %{game: game, human_move: human_move, engine_move: engine_move, skill_profile: skill_profile}
    end)
  end

  defp insert_move(game, attrs) do
    %Move{} |> Move.create_changeset(Map.put(attrs, :game_id, game.id)) |> Repo.insert()
  end

  defp insert_move!(game, attrs) do
    {:ok, move} = insert_move(game, attrs)
    move
  end

  # Returns `{game, skill_profile_or_nil}` -- the profile is only non-nil
  # when this was a calibration game with analyzable moves (see
  # `Skill.record_calibration_result/1`).
  defp finish_game(game, status) do
    {db_status, result} = translate_status(status)

    game =
      game
      |> Game.finish_changeset(%{
        status: db_status,
        result: result,
        ended_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

    {:ok, _pid} = PostGameAnalysis.enqueue(game.id)

    skill_profile =
      if game.is_calibration do
        {:ok, profile} = Skill.record_calibration_result(game)
        profile
      end

    {game, skill_profile}
  end

  defp translate_status({:checkmate, :white_wins}), do: {"checkmate", "white_wins"}
  defp translate_status({:checkmate, :black_wins}), do: {"checkmate", "black_wins"}
  defp translate_status({:draw, :stalemate}), do: {"stalemate", "draw"}
  defp translate_status({:draw, _reason}), do: {"draw", "draw"}
  defp translate_status({:winner, :black, {:manual, :human_resigned}}), do: {"resigned", "black_wins"}
  defp translate_status({:winner, :white, _reason}), do: {"aborted", "white_wins"}
end
