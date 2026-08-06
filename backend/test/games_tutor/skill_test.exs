defmodule GamesTutor.SkillTest do
  use GamesTutor.DataCase, async: false

  alias GamesTutor.{Accounts, Skill}
  alias GamesTutor.Games.{Game, Move}

  defp register_user(email) do
    {:ok, user} = Accounts.register_user(%{"email" => email, "password" => "correcthorsebattery"})
    user
  end

  defp create_finished_game(user, losses, opts \\ []) do
    game_type = Keyword.get(opts, :game_type, "chess")
    opening_plies = Keyword.get(opts, :opening_plies, 10)

    {:ok, game} =
      %Game{}
      |> Game.create_changeset(%{
        user_id: user.id,
        game_type: game_type,
        is_calibration: true,
        human_color: if(game_type == "go", do: "black", else: "white"),
        started_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    losses
    |> Enum.with_index(1)
    |> Enum.each(fn {loss, i} ->
      ply = opening_plies + i * 2 - 1

      %Move{}
      |> Move.create_changeset(%{
        game_id: game.id,
        ply: ply,
        player: "human",
        notation: "e2e4",
        uci: "e2e4",
        fen_after: "irrelevant",
        loss: loss
      })
      |> Repo.insert!()
    end)

    game
  end

  test "first calibration game creates a profile from the default prior" do
    user = register_user("skilltest1@example.com")
    game = create_finished_game(user, [10, 10, 10, 10, 10])

    assert {:ok, profile} = Skill.record_calibration_result(game)
    assert profile.games_count == 1
    # Strong (low-loss) play should have pulled the estimate up from the
    # 1200 default prior, not left it untouched.
    assert profile.estimated_rating > 1200.0
    assert profile.display_label in ~w(Beginner Intermediate Advanced Strong Expert)
  end

  test "a second calibration game updates the existing profile rather than creating a new one" do
    user = register_user("skilltest2@example.com")
    game1 = create_finished_game(user, [10, 10, 10, 10, 10])
    {:ok, profile1} = Skill.record_calibration_result(game1)

    game2 = create_finished_game(user, [15, 12, 8, 11, 9])
    {:ok, profile2} = Skill.record_calibration_result(game2)

    assert profile1.id == profile2.id
    assert profile2.games_count == 2
    assert Skill.list_profiles(user) |> length() == 1
  end

  test "sloppy play (high loss) pulls the estimate down" do
    user = register_user("skilltest3@example.com")
    game = create_finished_game(user, [400, 400, 400, 400, 400])

    assert {:ok, profile} = Skill.record_calibration_result(game)
    assert profile.estimated_rating < 1200.0
  end

  test "a game with no countable human moves is a harmless no-op" do
    user = register_user("skilltest4@example.com")
    game = create_finished_game(user, [])

    assert {:ok, nil} = Skill.record_calibration_result(game)
    assert Skill.list_profiles(user) == []
  end

  test "get_or_init_profile seeds a narrower prior from a self-reported onboarding rating" do
    user = register_user("skilltest5@example.com")
    profile = Skill.get_or_init_profile(user, "chess", self_reported_elo: 1600)
    assert profile.estimated_rating == 1600.0
    assert profile.rating_sigma < 400.0
  end

  describe "Go calibration" do
    test "strong (low score-loss) Go play creates a profile above the default prior with a kyu/dan label" do
      user = register_user("gotest1@example.com")
      # Centipoints -- see GamesTutor.Go.MoveClassifier. 50 = 0.5pt, "best".
      game = create_finished_game(user, [50, 50, 50, 50, 50], game_type: "go", opening_plies: 4)

      assert {:ok, profile} = Skill.record_calibration_result(game)
      assert profile.game_type == "go"
      assert profile.games_count == 1
      assert profile.estimated_rating > 1200.0
      assert profile.display_label =~ ~r/kyu|dan/
    end

    test "sloppy Go play (high score-loss) pulls the estimate down" do
      user = register_user("gotest2@example.com")
      game = create_finished_game(user, [3000, 3000, 3000, 3000, 3000], game_type: "go", opening_plies: 4)

      assert {:ok, profile} = Skill.record_calibration_result(game)
      assert profile.estimated_rating < 1200.0
    end

    test "chess and Go profiles for the same user are independent" do
      user = register_user("gotest3@example.com")
      chess_game = create_finished_game(user, [10, 10, 10, 10, 10], game_type: "chess", opening_plies: 10)
      go_game = create_finished_game(user, [3000, 3000, 3000, 3000, 3000], game_type: "go", opening_plies: 4)

      {:ok, chess_profile} = Skill.record_calibration_result(chess_game)
      {:ok, go_profile} = Skill.record_calibration_result(go_game)

      assert chess_profile.id != go_profile.id
      assert chess_profile.estimated_rating > go_profile.estimated_rating
      assert length(Skill.list_profiles(user)) == 2
    end

    test "Go's shorter opening exclusion (4 plies) counts moves chess's 10-ply exclusion would discard" do
      user = register_user("gotest4@example.com")
      # ply = 4 + i*2 - 1 for i in 1..3 => plies 5, 7, 9 -- all > 4 (Go's
      # exclusion) but <= 10 (chess's), so this would be a no-op under
      # chess's opening_plies default.
      game = create_finished_game(user, [50, 50, 50], game_type: "go", opening_plies: 4)

      assert {:ok, profile} = Skill.record_calibration_result(game)
      assert profile.games_count == 1
    end
  end
end
