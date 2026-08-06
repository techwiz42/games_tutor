defmodule GamesTutorWeb.AdminController do
  use GamesTutorWeb, :controller

  alias GamesTutor.Accounts
  alias GamesTutor.Admin

  action_fallback GamesTutorWeb.FallbackController

  def index(conn, _params) do
    json(conn, GamesTutorWeb.AdminJSON.index(%{users: Admin.list_users_with_stats()}))
  end

  def ban(conn, %{"id" => id, "reason" => reason}) when is_binary(reason) do
    with %Accounts.User{} = target <- Accounts.get_user(id) || {:error, :not_found},
         {:ok, banned} <- Accounts.ban_user(target, reason) do
      json(conn, GamesTutorWeb.AdminJSON.ban(%{user: banned}))
    end
  end

  def ban(_conn, _params), do: {:error, :bad_request}
end
