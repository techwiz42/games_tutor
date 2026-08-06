defmodule GamesTutor.Repo.Migrations.CreateVoiceAndUserSettings do
  use Ecto.Migration

  def change do
    create table(:user_settings, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), primary_key: true
      add :default_explanation_depth, :string, null: false, default: "detailed"

      timestamps(type: :utc_datetime)
    end

    create table(:voice_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("uuid_generate_v4()")
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :mode, :string, null: false
      add :status, :string, null: false, default: "active"
      add :model, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :duration_seconds, :integer
      add :estimated_cost_usd, :float

      timestamps(type: :utc_datetime)
    end

    create index(:voice_sessions, [:user_id])
    create index(:voice_sessions, [:game_id])
  end
end
