defmodule GamesTutorWeb.GameController do
  use GamesTutorWeb, :controller

  alias GamesTutor.Games
  alias GamesTutor.Guardian

  action_fallback GamesTutorWeb.FallbackController

  def index(conn, _params) do
    games = Games.list_games(current_user(conn))
    json(conn, %{games: Enum.map(games, &GamesTutorWeb.GameJSON.summary/1)})
  end

  # Real Stockfish/KataGo subprocesses get spun up per game -- bound how
  # many a user can create per hour (generous for legitimate play, bounds
  # subprocess-spam abuse).
  @game_creation_limit 20
  @game_creation_window_seconds 3600

  def create(conn, params) do
    user = current_user(conn)

    with :ok <- GamesTutor.RateLimit.check("ratelimit:create_game:#{user.id}", @game_creation_limit, @game_creation_window_seconds),
         {:ok, game} <- Games.create_game(user, params) do
      conn
      |> put_status(:created)
      |> json(GamesTutorWeb.GameJSON.show(game))
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, game} <- Games.get_game(current_user(conn), id) do
      json(conn, GamesTutorWeb.GameJSON.show(game))
    end
  end

  def create_move(conn, %{"id" => id, "move" => uci_move}) do
    with {:ok, result} <- Games.submit_move(current_user(conn), id, uci_move) do
      json(conn, GamesTutorWeb.GameJSON.move_result(result))
    end
  end

  def create_move(_conn, _params), do: {:error, :bad_request}

  def resign(conn, %{"id" => id}) do
    with {:ok, %{game: game, skill_profile: skill_profile}} <- Games.resign(current_user(conn), id) do
      json(conn, GamesTutorWeb.GameJSON.show(game, skill_profile))
    end
  end

  def undo(conn, %{"id" => id}) do
    with {:ok, game} <- Games.undo_move(current_user(conn), id) do
      json(conn, GamesTutorWeb.GameJSON.show(game))
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _game} <- Games.delete_game(current_user(conn), id) do
      json(conn, %{})
    end
  end

  ## Voice tool endpoints

  def board_state(conn, %{"id" => id}) do
    with {:ok, state} <- Games.board_state(current_user(conn), id) do
      json(conn, state)
    end
  end

  def move_analysis(conn, %{"id" => id} = params) do
    ply = params["ply"] && String.to_integer(params["ply"])

    with {:ok, move} <- Games.move_analysis(current_user(conn), id, ply) do
      json(conn, GamesTutorWeb.GameJSON.move(move))
    end
  end

  # Each hint is a real engine query -- bound per-user cost.
  @hint_limit 30
  @hint_window_seconds 3600

  def hint(conn, %{"id" => id}) do
    user = current_user(conn)

    with :ok <- GamesTutor.RateLimit.check("ratelimit:hint:#{user.id}", @hint_limit, @hint_window_seconds),
         {:ok, uci} <- Games.hint(user, id) do
      json(conn, %{move: uci})
    end
  end

  defp current_user(conn), do: Guardian.Plug.current_resource(conn)
end
