defmodule GamesTutorWeb.VoiceControllerTest do
  use GamesTutorWeb.ConnCase, async: false

  alias GamesTutor.{Accounts, Guardian}

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "voicehttp-#{System.unique_integer([:positive])}@example.com",
        "password" => "correcthorsebattery"
      })

    token = Guardian.issue_access_token(user)
    conn = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

    on_exit(fn ->
      Redix.command(GamesTutor.Redis, ["KEYS", "voice:*"])
      |> case do
        {:ok, []} -> :ok
        {:ok, keys} -> Redix.command(GamesTutor.Redis, ["DEL" | keys])
      end
    end)

    {:ok, conn: conn}
  end

  defp fresh_conn(conn) do
    auth = Plug.Conn.get_req_header(conn, "authorization")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", hd(auth))
  end

  test "starts and ends a real voice session over HTTP for a tutoring game", %{conn: conn} do
    game_conn = post(conn, "/api/games", %{})
    %{"id" => game_id} = json_response(game_conn, 201)

    start_conn = fresh_conn(conn) |> post("/api/voice/session", %{"game_id" => game_id})

    assert %{
             "session_id" => session_id,
             "mode" => "tutoring",
             "model" => "gpt-realtime-2.1-mini",
             "ephemeral_key" => key,
             "max_session_seconds" => 900
           } = json_response(start_conn, 201)

    assert is_binary(key)

    end_conn = fresh_conn(conn) |> post("/api/voice/session/#{session_id}/end")
    assert %{"status" => "ended", "duration_seconds" => duration} = json_response(end_conn, 200)
    assert duration >= 0
  end

  test "rejects a second concurrent session for the same user", %{conn: conn} do
    game_conn = post(conn, "/api/games", %{})
    %{"id" => game_id} = json_response(game_conn, 201)

    first_conn = fresh_conn(conn) |> post("/api/voice/session", %{"game_id" => game_id})
    assert json_response(first_conn, 201)

    second_conn = fresh_conn(conn) |> post("/api/voice/session", %{"game_id" => game_id})
    assert %{"code" => "session_already_active"} = json_response(second_conn, 409)
  end

  test "derives calibration_proctor mode over HTTP without trusting client input", %{conn: conn} do
    game_conn = post(conn, "/api/games", %{"is_calibration" => true})
    %{"id" => game_id} = json_response(game_conn, 201)

    start_conn = fresh_conn(conn) |> post("/api/voice/session", %{"game_id" => game_id, "mode" => "tutoring"})
    assert %{"mode" => "calibration_proctor"} = json_response(start_conn, 201)
  end
end
