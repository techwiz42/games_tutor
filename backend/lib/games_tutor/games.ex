defmodule GamesTutor.Games do
  @moduledoc """
  Chess games against the Stockfish opponent. Human is always White (see
  `GamesTutor.Chess.GameServer`'s moduledoc) -- `white_wins` means the human
  won, `black_wins` means the engine won.

  No `SkillProfile` exists yet (Phase 3), so "rate my play" opponent
  strength resolution here only implements the plan's step 1 (explicit
  override) and step 3 (platform default) -- step 2 (seed from the user's
  existing profile) arrives with Phase 3.
  """
  import Ecto.Query

  alias GamesTutor.Repo
  alias GamesTutor.Games.{Game, Move}
  alias GamesTutor.Chess.{GameServer, PostGameAnalysis}

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
    opponent_config = resolve_opponent_config(attrs)

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
      {:ok, finish_game(game, status)}
    end
  end

  ## Internal

  defp resolve_opponent_config(%{"opponent_elo" => elo}) when is_integer(elo), do: %{"elo" => elo}
  defp resolve_opponent_config(_attrs), do: %{"elo" => @default_calibration_elo}

  defp ensure_in_progress(%Game{status: "in_progress"}), do: :ok
  defp ensure_in_progress(%Game{}), do: {:error, :game_over}

  defp move_ucis(%Game{moves: moves}) when is_list(moves), do: Enum.map(moves, & &1.uci)
  defp move_ucis(%Game{}), do: []

  defp persist_result(game, %{status: status, human_move: human_attrs, engine_move: engine_attrs}) do
    Repo.transaction(fn ->
      {:ok, human_move} = insert_move(game, human_attrs)
      engine_move = engine_attrs && insert_move!(game, engine_attrs)

      game =
        case status do
          :continue -> game
          terminal -> finish_game(game, terminal)
        end

      %{game: game, human_move: human_move, engine_move: engine_move}
    end)
  end

  defp insert_move(game, attrs) do
    %Move{} |> Move.create_changeset(Map.put(attrs, :game_id, game.id)) |> Repo.insert()
  end

  defp insert_move!(game, attrs) do
    {:ok, move} = insert_move(game, attrs)
    move
  end

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
    game
  end

  defp translate_status({:checkmate, :white_wins}), do: {"checkmate", "white_wins"}
  defp translate_status({:checkmate, :black_wins}), do: {"checkmate", "black_wins"}
  defp translate_status({:draw, :stalemate}), do: {"stalemate", "draw"}
  defp translate_status({:draw, _reason}), do: {"draw", "draw"}
  defp translate_status({:winner, :black, {:manual, :human_resigned}}), do: {"resigned", "black_wins"}
  defp translate_status({:winner, :white, _reason}), do: {"aborted", "white_wins"}
end
