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

  def end_session(conn, %{"id" => id} = params) do
    total_tokens = case params["total_tokens"] do
      n when is_integer(n) -> n
      _ -> nil
    end

    with {:ok, session} <- Voice.end_session(current_user(conn), id, total_tokens) do
      json(conn, GamesTutorWeb.VoiceJSON.ended(session))
    end
  end

  defp current_user(conn), do: Guardian.Plug.current_resource(conn)
end
