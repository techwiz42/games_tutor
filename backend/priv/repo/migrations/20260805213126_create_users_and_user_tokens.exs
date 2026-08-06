defmodule GamesTutor.Repo.Migrations.CreateUsersAndUserTokens do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"", ""

    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("uuid_generate_v4()")
      add :email, :string, null: false
      add :hashed_password, :string
      add :google_id, :string
      add :display_name, :string
      add :avatar_url, :string
      add :confirmed_at, :utc_datetime
      add :last_login_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:google_id])

    # Unified token table for refresh tokens, email confirmation, and password
    # reset -- one context field, matching phx.gen.auth's own UserToken
    # convention rather than three separate near-identical tables.
    create table(:user_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("uuid_generate_v4()")
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token_hash, :string, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      add :replaced_by_token_id, :binary_id

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:user_tokens, [:context, :token_hash])
    create index(:user_tokens, [:user_id])
  end
end
