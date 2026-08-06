defmodule GamesTutorWeb.GoGameControllerTest do
  use GamesTutorWeb.ConnCase, async: false

  alias GamesTutor.{Accounts, Guardian}

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "go-controller-#{System.unique_integer([:positive])}@example.com",
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

  test "POST /api/games with game_type=go creates a playable Go game with an empty board", %{conn: conn} do
    conn = post(conn, "/api/games", %{"game_type" => "go", "opponent_max_visits" => 10})

    assert %{
             "id" => id,
             "game_type" => "go",
             "human_color" => "black",
             "status" => "in_progress",
             "moves" => [],
             "fen" => fen
           } = json_response(conn, 201)

    assert is_binary(id)
    decoded = Jason.decode!(fen)
    assert decoded["size"] == 9
    assert List.flatten(decoded["grid"]) |> Enum.all?(&(&1 == 0))
  end

  test "full HTTP flow: create -> legal move -> engine reply -> illegal move -> board-state/hint tools", %{conn: conn} do
    create_conn = post(conn, "/api/games", %{"game_type" => "go", "opponent_max_visits" => 10})
    %{"id" => id} = json_response(create_conn, 201)

    move_conn = fresh_conn(conn) |> post("/api/games/#{id}/moves", %{"move" => "E5"})

    assert %{
             "human_move" => %{"uci" => "E5", "player" => "human", "classification" => classification},
             "engine_move" => %{"player" => "engine"}
           } = json_response(move_conn, 200)

    assert classification in ~w(best good inaccuracy mistake blunder)

    illegal_conn = fresh_conn(conn) |> post("/api/games/#{id}/moves", %{"move" => "E5"})
    assert %{"code" => "illegal_move"} = json_response(illegal_conn, 422)

    board_conn = fresh_conn(conn) |> get("/api/games/#{id}/board-state")
    assert %{"game_type" => "go", "to_move" => "human", "status" => "in_progress"} = json_response(board_conn, 200)

    hint_conn = fresh_conn(conn) |> post("/api/games/#{id}/hint")
    assert %{"move" => hint_move} = json_response(hint_conn, 200)
    assert hint_move == "pass" or hint_move =~ ~r/^[A-Za-z]\d{1,2}$/

    resign_conn = fresh_conn(conn) |> post("/api/games/#{id}/resign")
    assert %{"status" => "resigned", "result" => "white_wins", "human_color" => "black"} = json_response(resign_conn, 200)
  end

  test "hint is hard-refused for a Go calibration game", %{conn: conn} do
    create_conn = post(conn, "/api/games", %{"game_type" => "go", "is_calibration" => true})
    %{"id" => id} = json_response(create_conn, 201)

    hint_conn = fresh_conn(conn) |> post("/api/games/#{id}/hint")
    assert %{"code" => "hint_refused_calibration"} = json_response(hint_conn, 403)
  end
end
