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

  defp recycle_conn(auth_header) do
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", hd(auth_header))
  end
end
