defmodule GamesTutorWeb.GameController do
  use GamesTutorWeb, :controller

  alias GamesTutor.Games
  alias GamesTutor.Guardian

  action_fallback GamesTutorWeb.FallbackController

  def index(conn, _params) do
    games = Games.list_games(current_user(conn))
    json(conn, %{games: Enum.map(games, &GamesTutorWeb.GameJSON.summary/1)})
  end

  def create(conn, params) do
    with {:ok, game} <- Games.create_game(current_user(conn), params) do
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

  def hint(conn, %{"id" => id}) do
    with {:ok, uci} <- Games.hint(current_user(conn), id) do
      json(conn, %{move: uci})
    end
  end

  defp current_user(conn), do: Guardian.Plug.current_resource(conn)
end
