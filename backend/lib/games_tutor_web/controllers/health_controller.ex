defmodule GamesTutorWeb.HealthController do
  use GamesTutorWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
