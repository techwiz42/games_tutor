defmodule GamesTutor.Repo.Migrations.CreateSkillProfiles do
  use Ecto.Migration

  def change do
    create table(:skill_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("uuid_generate_v4()")
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :game_type, :string, null: false
      add :estimated_rating, :float, null: false
      add :rating_sigma, :float, null: false
      add :display_label, :string
      add :games_count, :integer, null: false, default: 0
      add :last_played_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:skill_profiles, [:user_id, :game_type])

    create table(:skill_profile_histories, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("uuid_generate_v4()")

      add :skill_profile_id, references(:skill_profiles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :mu_before, :float, null: false
      add :sigma_before, :float, null: false
      add :acpl, :float, null: false
      add :moves_counted, :integer, null: false
      add :observed_rating, :float, null: false
      add :sigma_obs, :float, null: false
      add :mu_after, :float, null: false
      add :sigma_after, :float, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:skill_profile_histories, [:skill_profile_id])
  end
end
