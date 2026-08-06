defmodule GamesTutor.Admin do
  @moduledoc """
  Aggregated per-user data for the admin user-list page. Deliberately 4 flat
  queries merged in Elixir by user_id rather than one multi-table join --
  Game/SkillProfile/VoiceSession all have different cardinalities relative to
  User, so a single join would either fan out row counts (breaking the
  aggregates) or need subqueries per column anyway. This is simpler and
  avoids N+1 (constant query count regardless of user count).
  """
  import Ecto.Query

  alias GamesTutor.Repo
  alias GamesTutor.Accounts.User
  alias GamesTutor.Games.Game
  alias GamesTutor.Skill.SkillProfile
  alias GamesTutor.Voice.VoiceSession

  def list_users_with_stats do
    users = Repo.all(from u in User, order_by: u.inserted_at)

    game_counts =
      Repo.all(from g in Game, group_by: [g.user_id, g.game_type], select: {g.user_id, g.game_type, count(g.id)})
      |> Enum.reduce(%{}, fn {user_id, game_type, count}, acc ->
        Map.update(acc, user_id, %{game_type => count}, &Map.put(&1, game_type, count))
      end)

    chess_ratings =
      Repo.all(from s in SkillProfile, where: s.game_type == "chess", select: {s.user_id, s.estimated_rating})
      |> Map.new()

    total_tokens =
      Repo.all(
        from v in VoiceSession,
          where: not is_nil(v.total_tokens),
          group_by: v.user_id,
          select: {v.user_id, sum(v.total_tokens)}
      )
      |> Map.new()

    Enum.map(users, fn user ->
      counts = Map.get(game_counts, user.id, %{})

      %{
        id: user.id,
        email: user.email,
        last_login_ip: user.last_login_ip,
        chess_games_played: Map.get(counts, "chess", 0),
        chess_rating: chess_ratings[user.id] && round(chess_ratings[user.id]),
        go_games_played: Map.get(counts, "go", 0),
        total_tokens_used: total_tokens[user.id] || 0,
        is_admin: user.is_admin,
        banned_at: user.banned_at,
        ban_reason: user.ban_reason
      }
    end)
  end
end
