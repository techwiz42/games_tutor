defmodule GamesTutorWeb.RejectBanned do
  @moduledoc """
  Added to the :authenticated pipeline (after AuthPipeline, which loads the
  resource) so a ban takes effect on the banned user's very next request,
  everywhere -- not just at their next login. Without this, an
  already-issued access token would keep working for up to its full 60-minute
  TTL after Accounts.ban_user/2 runs.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias GamesTutor.Accounts.User

  def init(opts), do: opts

  def call(conn, _opts) do
    case Guardian.Plug.current_resource(conn) do
      %User{} = user ->
        if User.banned?(user) do
          conn
          |> put_status(:forbidden)
          |> json(%{detail: "This account has been suspended", code: "banned"})
          |> halt()
        else
          conn
        end

      _ ->
        conn
    end
  end
end
