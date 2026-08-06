defmodule GamesTutorWeb.VoiceToolsControllerTest do
  use GamesTutorWeb.ConnCase, async: false

  alias GamesTutor.{Accounts, Guardian}

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "voicetools-#{System.unique_integer([:positive])}@example.com",
        "password" => "correcthorsebattery"
      })

    token = Guardian.issue_access_token(user)
    conn = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
    {:ok, conn: conn}
  end

  defp fresh_conn(conn) do
    auth = Plug.Conn.get_req_header(conn, "authorization")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", hd(auth))
  end

  test "board_state, move_analysis, and hint work for a tutoring game", %{conn: conn} do
    create_conn = post(conn, "/api/games", %{})
    %{"id" => id} = json_response(create_conn, 201)

    board_conn = fresh_conn(conn) |> get("/api/games/#{id}/board-state")
    assert %{"to_move" => "human", "status" => "in_progress"} = json_response(board_conn, 200)

    hint_conn = fresh_conn(conn) |> post("/api/games/#{id}/hint")
    assert %{"move" => hint_move} = json_response(hint_conn, 200)
    assert hint_move =~ ~r/^[a-h][1-8][a-h][1-8][qrbn]?$/

    move_conn = fresh_conn(conn) |> post("/api/games/#{id}/moves", %{"move" => hint_move})
    assert %{"human_move" => %{"uci" => ^hint_move}} = json_response(move_conn, 200)

    analysis_conn = fresh_conn(conn) |> get("/api/games/#{id}/move-analysis")
    assert %{"player" => "engine", "ply" => 2} = json_response(analysis_conn, 200)

    explain_conn = fresh_conn(conn) |> get("/api/games/#{id}/move-analysis?ply=1")
    assert %{"player" => "human", "ply" => 1, "uci" => ^hint_move} = json_response(explain_conn, 200)
  end

  test "hint is hard-refused for a calibration game even though the game is otherwise playable", %{conn: conn} do
    create_conn = post(conn, "/api/games", %{"is_calibration" => true})
    %{"id" => id} = json_response(create_conn, 201)

    hint_conn = fresh_conn(conn) |> post("/api/games/#{id}/hint")
    assert %{"code" => "hint_refused_calibration"} = json_response(hint_conn, 403)

    # The game itself is still fully playable -- only the hint is refused.
    board_conn = fresh_conn(conn) |> get("/api/games/#{id}/board-state")
    assert %{"is_calibration" => true, "status" => "in_progress"} = json_response(board_conn, 200)
  end

  test "board_state/hint 404 for a game owned by someone else", %{conn: conn} do
    {:ok, other} =
      Accounts.register_user(%{"email" => "otherowner@example.com", "password" => "correcthorsebattery"})

    other_token = Guardian.issue_access_token(other)
    other_conn = Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{other_token}")

    create_conn = post(other_conn, "/api/games", %{})
    %{"id" => id} = json_response(create_conn, 201)

    board_conn = fresh_conn(conn) |> get("/api/games/#{id}/board-state")
    assert json_response(board_conn, 404)
  end

  test "GET/PATCH /api/user-settings adjusts explanation depth", %{conn: conn} do
    show_conn = get(conn, "/api/user-settings")
    assert %{"default_explanation_depth" => "detailed"} = json_response(show_conn, 200)

    update_conn = fresh_conn(conn) |> patch("/api/user-settings", %{"default_explanation_depth" => "brief"})
    assert %{"default_explanation_depth" => "brief"} = json_response(update_conn, 200)

    show_again_conn = fresh_conn(conn) |> get("/api/user-settings")
    assert %{"default_explanation_depth" => "brief"} = json_response(show_again_conn, 200)
  end
end
