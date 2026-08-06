defmodule GamesTutor.Repo.Migrations.AddTotalTokensToVoiceSessions do
  use Ecto.Migration

  def change do
    alter table(:voice_sessions) do
      add :total_tokens, :integer
    end
  end
end
