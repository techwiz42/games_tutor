defmodule GamesTutorWeb.AdminControllerTest do
  use GamesTutorWeb.ConnCase, async: false
  import Swoosh.TestAssertions

  alias GamesTutor.{Accounts, Games, Guardian, Repo}

  defp confirmed_user(email) do
    {:ok, user} = Accounts.register_user(%{"email" => email, "password" => "correcthorsebattery"})
    user |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)) |> Repo.update!()
  end

  defp admin_user do
    confirmed_user("admin-#{System.unique_integer([:positive])}@example.com")
    |> Ecto.Changeset.change(is_admin: true)
    |> Repo.update!()
  end

  defp auth(conn, user), do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{Guardian.issue_access_token(user)}")

  test "non-admins are refused", %{conn: conn} do
    user = confirmed_user("not-admin-#{System.unique_integer([:positive])}@example.com")
    conn = conn |> auth(user) |> get("/api/admin/users")
    assert json_response(conn, 403)
  end

  test "admins see every user with real game/rating stats", %{conn: conn} do
    admin = admin_user()
    player = confirmed_user("player-#{System.unique_integer([:positive])}@example.com")
    {:ok, _} = Games.create_game(player, %{"opponent_elo" => 800})

    conn = conn |> auth(admin) |> get("/api/admin/users")
    %{"users" => users} = json_response(conn, 200)

    row = Enum.find(users, &(&1["id"] == player.id))
    assert row["email"] == player.email
    assert row["chess_games_played"] == 1
    assert row["go_games_played"] == 0
    assert row["is_admin"] == false
    assert row["banned_at"] == nil
  end

  test "banning a user persists the reason, revokes sessions, and emails them", %{conn: conn} do
    admin = admin_user()
    target = confirmed_user("target-#{System.unique_integer([:positive])}@example.com")
    {:ok, refresh_token} = Accounts.issue_refresh_token(target, [])

    conn = conn |> auth(admin) |> post("/api/admin/users/#{target.id}/ban", %{"reason" => "spamming other players"})
    assert %{"banned_at" => banned_at, "ban_reason" => "spamming other players"} = json_response(conn, 200)
    assert banned_at

    assert %{banned_at: %DateTime{}, ban_reason: "spamming other players"} = Accounts.get_user(target.id)
    assert {:error, :revoked} = Accounts.get_valid_refresh_token(refresh_token)

    # assert_email_sent/1 consumes mailbox messages FIFO, and confirmed_user/1
    # (called twice above, for admin and target) each sent a confirmation
    # email first -- drain those two before asserting on the ban email.
    assert_email_sent()
    assert_email_sent()
    assert_email_sent(subject: "Your games_tutor account has been suspended")
  end

  test "banning without a reason is rejected", %{conn: conn} do
    admin = admin_user()
    target = confirmed_user("noreason-#{System.unique_integer([:positive])}@example.com")

    conn = conn |> auth(admin) |> post("/api/admin/users/#{target.id}/ban", %{"reason" => ""})
    assert json_response(conn, 422)
    assert %{banned_at: nil} = Accounts.get_user(target.id)
  end
end
