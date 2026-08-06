defmodule GamesTutorWeb.RequireAdmin do
  @moduledoc "Gates the /api/admin/* scope. Must run after AuthPipeline (needs a loaded resource)."
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias GamesTutor.Accounts.User

  def init(opts), do: opts

  def call(conn, _opts) do
    case Guardian.Plug.current_resource(conn) do
      %User{is_admin: true} ->
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{detail: "Admin access required"})
        |> halt()
    end
  end
end
