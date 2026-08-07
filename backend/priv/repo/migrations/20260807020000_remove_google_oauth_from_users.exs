defmodule GamesTutor.Repo.Migrations.RemoveGoogleOauthFromUsers do
  use Ecto.Migration

  # Google sign-in removed entirely -- confirmed no existing user rows had
  # google_id set (nobody had ever actually used it) before dropping these.
  # avatar_url was only ever populated via Google's profile picture claim
  # (link_google_changeset/google_changeset, both removed), so it goes too.
  def change do
    drop unique_index(:users, [:google_id])

    alter table(:users) do
      remove :google_id, :string
      remove :avatar_url, :string
    end
  end
end
