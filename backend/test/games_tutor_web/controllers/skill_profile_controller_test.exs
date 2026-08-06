defmodule GamesTutorWeb.SkillProfileControllerTest do
  use GamesTutorWeb.ConnCase, async: false

  alias GamesTutor.{Accounts, Guardian}

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "skill-controller-#{System.unique_integer([:positive])}@example.com",
        "password" => "correcthorsebattery"
      })

    token = Guardian.issue_access_token(user)
    conn = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
    {:ok, conn: conn}
  end

  test "GET /api/skill-profiles is empty before any calibration game", %{conn: conn} do
    conn = get(conn, "/api/skill-profiles")
    assert %{"skill_profiles" => []} = json_response(conn, 200)
  end

  test "resigning a calibration game with enough real moves updates and returns the skill profile", %{conn: conn} do
    auth = Plug.Conn.get_req_header(conn, "authorization")
    recycle = fn -> Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", hd(auth)) end

    create_conn = post(conn, "/api/games", %{"is_calibration" => true, "self_reported_elo" => 1500})
    assert %{"id" => id, "is_calibration" => true} = json_response(create_conn, 201)

    # A knight shuttle -- 7 real, always-legal human moves (ply 1..13),
    # enough to clear ACPL's opening-plies exclusion (ply > 10) with real
    # Stockfish analysis on every ply.
    Enum.each(["g1f3", "f3g1", "g1f3", "f3g1", "g1f3", "f3g1", "g1f3"], fn uci ->
      move_conn = recycle.() |> post("/api/games/#{id}/moves", %{"move" => uci})
      assert %{"human_move" => %{"uci" => ^uci}} = json_response(move_conn, 200)
    end)

    resign_conn = recycle.() |> post("/api/games/#{id}/resign")

    assert %{
             "status" => "resigned",
             "skill_profile" => %{
               "game_type" => "chess",
               "estimated_rating" => rating,
               "rating_sigma" => sigma,
               "display_label" => label,
               "games_count" => 1
             }
           } = json_response(resign_conn, 200)

    assert is_integer(rating)
    assert is_float(sigma)
    assert is_binary(label)

    index_conn = recycle.() |> get("/api/skill-profiles")
    assert %{"skill_profiles" => [%{"games_count" => 1}]} = json_response(index_conn, 200)
  end
end
