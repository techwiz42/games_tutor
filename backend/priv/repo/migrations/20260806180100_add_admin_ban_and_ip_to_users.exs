defmodule GamesTutor.Repo.Migrations.AddAdminBanAndIpToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_admin, :boolean, default: false, null: false
      add :banned_at, :utc_datetime
      add :ban_reason, :text
      add :last_login_ip, :string
    end
  end
end
