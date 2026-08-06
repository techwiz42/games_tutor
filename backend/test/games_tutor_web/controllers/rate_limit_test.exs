defmodule GamesTutorWeb.RateLimitTest do
  use GamesTutorWeb.ConnCase, async: false

  alias GamesTutor.{Accounts, Guardian}

  setup do
    on_exit(fn ->
      Redix.command(GamesTutor.Redis, ["KEYS", "ratelimit:*"])
      |> case do
        {:ok, []} -> :ok
        {:ok, keys} -> Redix.command(GamesTutor.Redis, ["DEL" | keys])
      end
    end)

    :ok
  end

  test "register is rate-limited per IP", %{conn: conn} do
    for i <- 1..5 do
      conn = post(build_conn(), "/api/auth/register", %{"email" => "rl-reg-#{i}@example.com", "password" => "correcthorsebattery"})
      assert conn.status == 201
    end

    conn = post(conn, "/api/auth/register", %{"email" => "rl-reg-6@example.com", "password" => "correcthorsebattery"})
    assert %{"code" => "rate_limited"} = json_response(conn, 429)
  end

  test "login is rate-limited per IP", %{conn: conn} do
    for _ <- 1..20 do
      conn = post(build_conn(), "/api/auth/login", %{"email" => "nobody@example.com", "password" => "wrong"})
      assert conn.status == 401
    end

    conn = post(conn, "/api/auth/login", %{"email" => "nobody@example.com", "password" => "wrong"})
    assert %{"code" => "rate_limited"} = json_response(conn, 429)
  end

  test "forgot_password is rate-limited per IP (protects against email-bombing)", %{conn: conn} do
    for _ <- 1..5 do
      conn = post(build_conn(), "/api/auth/forgot-password", %{"email" => "someone@example.com"})
      assert conn.status == 200
    end

    conn = post(conn, "/api/auth/forgot-password", %{"email" => "someone@example.com"})
    assert %{"code" => "rate_limited"} = json_response(conn, 429)
  end

  test "game creation is rate-limited per user", %{conn: _conn} do
    {:ok, user} = Accounts.register_user(%{"email" => "rl-games@example.com", "password" => "correcthorsebattery"})
    token = Guardian.issue_access_token(user)
    auth_conn = fn -> build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}") end

    for _ <- 1..20 do
      conn = post(auth_conn.(), "/api/games", %{})
      assert conn.status == 201
    end

    conn = post(auth_conn.(), "/api/games", %{})
    assert %{"code" => "rate_limited"} = json_response(conn, 429)
  end

  test "hint requests are rate-limited per user", %{conn: _conn} do
    {:ok, user} = Accounts.register_user(%{"email" => "rl-hints@example.com", "password" => "correcthorsebattery"})
    token = Guardian.issue_access_token(user)
    auth_conn = fn -> build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}") end

    create_conn = post(auth_conn.(), "/api/games", %{})
    %{"id" => game_id} = json_response(create_conn, 201)

    for _ <- 1..30 do
      conn = post(auth_conn.(), "/api/games/#{game_id}/hint")
      assert conn.status == 200
    end

    conn = post(auth_conn.(), "/api/games/#{game_id}/hint")
    assert %{"code" => "rate_limited"} = json_response(conn, 429)
  end
end
