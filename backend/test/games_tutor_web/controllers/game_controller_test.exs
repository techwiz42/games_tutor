defmodule GamesTutorWeb.GameControllerTest do
  use GamesTutorWeb.ConnCase, async: false

  alias GamesTutor.{Accounts, Guardian}

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "controller-test-#{System.unique_integer([:positive])}@example.com",
        "password" => "correcthorsebattery"
      })

    token = Guardian.issue_access_token(user)
    conn = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
    {:ok, conn: conn, user: user}
  end

  test "POST /api/games creates a game with an empty move list (regression: moves association must not be Ecto.Association.NotLoaded)",
       %{conn: conn} do
    conn = post(conn, "/api/games", %{"opponent_elo" => 800})
    assert %{"id" => id, "status" => "in_progress", "moves" => [], "fen" => fen} = json_response(conn, 201)
    assert is_binary(id)
    assert fen =~ ~r/^rnbqkbnr/
  end

  test "full HTTP flow: create -> legal move -> illegal move -> get -> resign", %{conn: conn} do
    auth = Plug.Conn.get_req_header(conn, "authorization")

    create_conn = post(conn, "/api/games", %{"opponent_elo" => 800})
    %{"id" => id} = json_response(create_conn, 201)

    move_conn =
      recycle_conn(auth) |> post("/api/games/#{id}/moves", %{"move" => "e2e4"})

    assert %{
             "human_move" => %{"uci" => "e2e4", "classification" => classification},
             "engine_move" => %{"player" => "engine"},
             "fen" => fen
           } = json_response(move_conn, 200)

    assert classification in ~w(best good inaccuracy mistake blunder)
    assert is_binary(fen)

    illegal_conn =
      recycle_conn(auth) |> post("/api/games/#{id}/moves", %{"move" => "e2e4"})

    assert %{"detail" => "Illegal move"} = json_response(illegal_conn, 422)

    show_conn = recycle_conn(auth) |> get("/api/games/#{id}")
    assert %{"moves" => moves} = json_response(show_conn, 200)
    assert length(moves) == 2

    resign_conn = recycle_conn(auth) |> post("/api/games/#{id}/resign")
    assert %{"status" => "resigned", "result" => "black_wins"} = json_response(resign_conn, 200)
  end

  test "choosing Black creates a game with a real White opening move already played", %{conn: conn} do
    auth = Plug.Conn.get_req_header(conn, "authorization")

    create_conn = post(conn, "/api/games", %{"opponent_elo" => 800, "human_color" => "black"})

    assert %{
             "id" => id,
             "human_color" => "black",
             "moves" => [%{"ply" => 1, "player" => "engine", "uci" => opening_uci}]
           } = json_response(create_conn, 201)

    assert opening_uci =~ ~r/^[a-h][1-8][a-h][1-8][qrbn]?$/

    # It's genuinely Black's (the human's) turn -- a live reply applies cleanly.
    move_conn = recycle_conn(auth) |> post("/api/games/#{id}/moves", %{"move" => "e7e5"})
    assert %{"human_move" => %{"ply" => 2, "player" => "human"}} = json_response(move_conn, 200)
  end

  test "full HTTP flow: create -> move -> undo restores the pre-move state", %{conn: conn} do
    auth = Plug.Conn.get_req_header(conn, "authorization")

    create_conn = post(conn, "/api/games", %{"opponent_elo" => 800})
    %{"id" => id} = json_response(create_conn, 201)

    move_conn = recycle_conn(auth) |> post("/api/games/#{id}/moves", %{"move" => "e2e4"})
    assert %{"engine_move" => %{"player" => "engine"}} = json_response(move_conn, 200)

    undo_conn = recycle_conn(auth) |> post("/api/games/#{id}/undo")
    assert %{"status" => "in_progress", "moves" => []} = json_response(undo_conn, 200)

    # The rewound position is genuinely playable again, not just visually reset.
    replay_conn = recycle_conn(auth) |> post("/api/games/#{id}/moves", %{"move" => "d2d4"})
    assert %{"human_move" => %{"uci" => "d2d4"}} = json_response(replay_conn, 200)
  end

  test "undo is refused during a calibration game", %{conn: conn} do
    auth = Plug.Conn.get_req_header(conn, "authorization")

    create_conn = post(conn, "/api/games", %{"is_calibration" => true})
    %{"id" => id} = json_response(create_conn, 201)

    recycle_conn(auth) |> post("/api/games/#{id}/moves", %{"move" => "e2e4"})

    undo_conn = recycle_conn(auth) |> post("/api/games/#{id}/undo")
    assert %{"code" => "undo_refused_calibration"} = json_response(undo_conn, 403)
  end

  test "undo is refused when there are no moves to take back yet", %{conn: conn} do
    auth = Plug.Conn.get_req_header(conn, "authorization")

    create_conn = post(conn, "/api/games", %{"opponent_elo" => 800})
    %{"id" => id} = json_response(create_conn, 201)

    undo_conn = recycle_conn(auth) |> post("/api/games/#{id}/undo")
    assert %{"code" => "no_moves_to_undo"} = json_response(undo_conn, 422)
  end

  test "DELETE /api/games/:id removes the game -- it 404s afterward and drops out of the list", %{conn: conn} do
    auth = Plug.Conn.get_req_header(conn, "authorization")

    create_conn = post(conn, "/api/games", %{"opponent_elo" => 800})
    %{"id" => id} = json_response(create_conn, 201)

    delete_conn = recycle_conn(auth) |> delete("/api/games/#{id}")
    assert json_response(delete_conn, 200)

    show_conn = recycle_conn(auth) |> get("/api/games/#{id}")
    assert %{"detail" => "Game not found"} = json_response(show_conn, 404)

    index_conn = recycle_conn(auth) |> get("/api/games")
    assert %{"games" => games} = json_response(index_conn, 200)
    refute Enum.any?(games, &(&1["id"] == id))
  end

  test "DELETE /api/games/:id refuses to delete another user's game", %{conn: conn} do
    auth = Plug.Conn.get_req_header(conn, "authorization")
    create_conn = post(conn, "/api/games", %{"opponent_elo" => 800})
    %{"id" => id} = json_response(create_conn, 201)

    {:ok, other_user} =
      Accounts.register_user(%{
        "email" => "other-controller-test-#{System.unique_integer([:positive])}@example.com",
        "password" => "correcthorsebattery"
      })

    other_token = Guardian.issue_access_token(other_user)
    other_conn = Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{other_token}")

    delete_conn = delete(other_conn, "/api/games/#{id}")
    assert %{"detail" => "Game not found"} = json_response(delete_conn, 404)

    # Untouched -- still visible to its real owner.
    show_conn = recycle_conn(auth) |> get("/api/games/#{id}")
    assert json_response(show_conn, 200)
  end

  defp recycle_conn(auth_header) do
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", hd(auth_header))
  end
end
