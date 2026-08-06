defmodule GamesTutorWeb.VoiceController do
  use GamesTutorWeb, :controller

  alias GamesTutor.Voice
  alias GamesTutor.Guardian

  action_fallback GamesTutorWeb.FallbackController

  def create(conn, %{"game_id" => game_id}) do
    with {:ok, result} <- Voice.start_session(current_user(conn), game_id) do
      conn
      |> put_status(:created)
      |> json(GamesTutorWeb.VoiceJSON.started(result))
    end
  end

  def create(_conn, _params), do: {:error, :bad_request}

  def end_session(conn, %{"id" => id}) do
    with {:ok, session} <- Voice.end_session(current_user(conn), id) do
      json(conn, GamesTutorWeb.VoiceJSON.ended(session))
    end
  end

  defp current_user(conn), do: Guardian.Plug.current_resource(conn)
end
