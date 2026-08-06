defmodule GamesTutorWeb.AuthErrorHandler do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {_type, _reason}, _opts) do
    conn
    |> put_status(:unauthorized)
    |> json(%{detail: "Not authenticated"})
  end
end
