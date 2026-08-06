defmodule GamesTutorWeb.AdminJSON do
  def index(%{users: users}) do
    %{users: Enum.map(users, &user_row/1)}
  end

  # Only the fields that changed -- the caller already has the rest of this
  # row from index/2 and merges this in, rather than this route re-deriving
  # game/token stats it doesn't need for a ban action.
  def ban(%{user: user}) do
    %{id: user.id, banned_at: user.banned_at, ban_reason: user.ban_reason}
  end

  defp user_row(row) do
    %{
      id: row.id,
      email: row.email,
      last_login_ip: row.last_login_ip,
      chess_games_played: row.chess_games_played,
      chess_rating: row.chess_rating,
      go_games_played: row.go_games_played,
      total_tokens_used: row.total_tokens_used,
      is_admin: row.is_admin,
      banned_at: row.banned_at,
      ban_reason: row.ban_reason
    }
  end
end
