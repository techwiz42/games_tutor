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
             "human_move" =>
               %{"uci" => "E5", "player" => "human", "classification" => classification, "prior" => prior} = human,
             "engine_move" => %{"player" => "engine"}
           } = json_response(move_conn, 200)

    assert classification in ~w(best good inaccuracy mistake blunder)
    # Regression: GameJSON.move/1 forgot classification_version when it was
    # added (finding 3) -- correctly stored in the DB but silently missing
    # from every JSON response, caught by exercising the actual HTTP
    # boundary rather than only the internal GameServer return value.
    assert human["classification_version"] == 2
    assert is_float(prior) and prior >= 0.0 and prior <= 1.0
    assert %{"ownership" => ownership} = Jason.decode!(human["fen_after"])
    assert length(ownership) == 81

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

  test "choosing White creates a Go game with a real Black opening move already played", %{conn: conn} do
    create_conn =
      post(conn, "/api/games", %{"game_type" => "go", "opponent_max_visits" => 10, "human_color" => "white"})

    assert %{
             "id" => id,
             "human_color" => "white",
             "moves" => [%{"ply" => 1, "player" => "engine", "uci" => opening_uci}]
           } = json_response(create_conn, 201)

    assert opening_uci == "pass" or opening_uci =~ ~r/^[A-Za-z]\d{1,2}$/

    # It's genuinely White's (the human's) turn -- a live reply applies cleanly.
    move_conn = fresh_conn(conn) |> post("/api/games/#{id}/moves", %{"move" => "E5"})
    assert %{"human_move" => %{"ply" => 2, "player" => "human"}} = json_response(move_conn, 200)
  end

  test "hint is hard-refused for a Go calibration game", %{conn: conn} do
    create_conn = post(conn, "/api/games", %{"game_type" => "go", "is_calibration" => true})
    %{"id" => id} = json_response(create_conn, 201)

    hint_conn = fresh_conn(conn) |> post("/api/games/#{id}/hint")
    assert %{"code" => "hint_refused_calibration"} = json_response(hint_conn, 403)
  end
end
