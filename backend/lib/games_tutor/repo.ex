defmodule GamesTutor.Repo do
  use Ecto.Repo,
    otp_app: :games_tutor,
    adapter: Ecto.Adapters.Postgres
end
