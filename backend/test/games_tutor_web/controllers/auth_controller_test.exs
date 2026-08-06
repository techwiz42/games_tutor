defmodule GamesTutorWeb.AuthControllerTest do
  use GamesTutorWeb.ConnCase, async: false

  alias GamesTutor.{Accounts, Repo}

  defp confirmed_user(email) do
    {:ok, user} = Accounts.register_user(%{"email" => email, "password" => "correcthorsebattery"})
    user |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)) |> Repo.update!()
  end

  test "login records the real client IP from X-Forwarded-For, not the proxy hop", %{conn: conn} do
    user = confirmed_user("ip-test-#{System.unique_integer([:positive])}@example.com")

    conn
    |> Plug.Conn.put_req_header("x-forwarded-for", "203.0.113.7")
    |> post("/api/auth/login", %{"email" => user.email, "password" => "correcthorsebattery"})
    |> json_response(200)

    assert %{last_login_ip: "203.0.113.7"} = Accounts.get_user(user.id)
  end

  test "login is refused for a banned account", %{conn: conn} do
    user = confirmed_user("banned-login-#{System.unique_integer([:positive])}@example.com")
    {:ok, _} = Accounts.ban_user(user, "cheating")

    conn = post(conn, "/api/auth/login", %{"email" => user.email, "password" => "correcthorsebattery"})
    assert %{"code" => "banned"} = json_response(conn, 403)
  end

  test "a banned account's already-issued access token is rejected on its next request", %{conn: conn} do
    user = confirmed_user("banned-midsession-#{System.unique_integer([:positive])}@example.com")
    token = GamesTutor.Guardian.issue_access_token(user)

    {:ok, _} = Accounts.ban_user(user, "abusive language")

    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      |> get("/api/auth/me")

    assert %{"code" => "banned"} = json_response(conn, 403)
  end
end
