defmodule GamesTutor.VoiceTest do
  use GamesTutor.DataCase, async: false

  alias GamesTutor.{Accounts, Games, Voice}

  defp register_user(email) do
    {:ok, user} = Accounts.register_user(%{"email" => email, "password" => "correcthorsebattery"})
    user
  end

  setup do
    on_exit(fn ->
      # Real Redis keys aren't rolled back by the DB sandbox -- clean up
      # explicitly so runs don't interfere with each other.
      Redix.command(GamesTutor.Redis, ["KEYS", "voice:*"])
      |> case do
        {:ok, []} -> :ok
        {:ok, keys} -> Redix.command(GamesTutor.Redis, ["DEL" | keys])
      end
    end)

    :ok
  end

  test "starts a real voice session for a tutoring game and mints a real OpenAI ephemeral key" do
    user = register_user("voicetest1@example.com")
    {:ok, game} = Games.create_game(user, %{})

    assert {:ok, %{session: session, ephemeral_key: key}} = Voice.start_session(user, game.id)
    assert session.mode == "tutoring"
    assert session.status == "active"
    assert session.model == "gpt-realtime-2.1-mini"
    assert is_binary(key)
    assert String.starts_with?(key, "ek_")
  end

  test "derives calibration_proctor mode from the game, not client input" do
    user = register_user("voicetest2@example.com")
    {:ok, game} = Games.create_game(user, %{"is_calibration" => true})

    assert {:ok, %{session: session}} = Voice.start_session(user, game.id)
    assert session.mode == "calibration_proctor"
  end

  test "only one active session per user at a time" do
    user = register_user("voicetest3@example.com")
    {:ok, game} = Games.create_game(user, %{})

    assert {:ok, _} = Voice.start_session(user, game.id)
    assert {:error, :session_already_active} = Voice.start_session(user, game.id)
  end

  test "ending a session releases the guard and records duration/cost" do
    user = register_user("voicetest4@example.com")
    {:ok, game} = Games.create_game(user, %{})

    {:ok, %{session: session}} = Voice.start_session(user, game.id)
    assert {:ok, ended} = Voice.end_session(user, session.id)
    assert ended.status == "ended"
    assert is_integer(ended.duration_seconds)
    assert ended.estimated_cost_usd >= 0.0

    # Guard released -- a new session can start immediately.
    assert {:ok, _} = Voice.start_session(user, game.id)
  end

  test "rejects starting a session for a game the user doesn't own" do
    owner = register_user("voicetest5a@example.com")
    other = register_user("voicetest5b@example.com")
    {:ok, game} = Games.create_game(owner, %{})

    assert {:error, :not_found} = Voice.start_session(other, game.id)
  end
end
