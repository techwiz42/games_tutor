defmodule GamesTutorWeb.UserSettingsController do
  use GamesTutorWeb, :controller

  alias GamesTutor.Accounts
  alias GamesTutor.Guardian

  action_fallback GamesTutorWeb.FallbackController

  def show(conn, _params) do
    settings = Accounts.get_settings(current_user(conn))
    json(conn, render_settings(settings))
  end

  def update(conn, params) do
    with {:ok, settings} <- Accounts.update_settings(current_user(conn), params) do
      json(conn, render_settings(settings))
    end
  end

  defp render_settings(settings), do: %{default_explanation_depth: settings.default_explanation_depth}

  defp current_user(conn), do: Guardian.Plug.current_resource(conn)
end
