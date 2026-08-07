import Config

# This file runs for every environment (dev, test, prod), but everything in it
# is gated by `unless config_env() == :test` -- tests use config/test.exs's
# static, no-external-dependency config (fake secret_key_base, Swoosh.Adapters.Test,
# no real Postgres/SendGrid credentials needed to run the suite).
#
# For dev and prod alike, secrets are read via GamesTutor.Secrets (env var, or
# an env var + "_FILE" pointing at a Docker secret file) -- matching the
# pattern already established for the frontend and (previously) the Python
# backend. Real Postgres, real SendGrid sends, even in dev -- this project's
# working convention has been "no mocks" throughout.

alias GamesTutor.Secrets

if System.get_env("PHX_SERVER") do
  config :games_tutor, GamesTutorWeb.Endpoint, server: true
end

unless config_env() == :test do
  config :games_tutor, GamesTutorWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "8000"))],
    url: [host: System.get_env("PHX_HOST", "localhost")],
    secret_key_base: Secrets.read("APP_SECRET_KEY")

  db_host = System.get_env("DB_HOST", "localhost")

  db_port =
    String.to_integer(
      System.get_env("DB_PORT", if(db_host == "localhost", do: "5433", else: "5432"))
    )

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :games_tutor, GamesTutor.Repo,
    hostname: db_host,
    port: db_port,
    database: System.get_env("DB_NAME", "games_tutor"),
    username: System.get_env("DB_USER", "games_tutor"),
    password: Secrets.read("POSTGRES_PASSWORD"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    show_sensitive_data_on_connection_error: config_env() != :prod,
    socket_options: maybe_ipv6

  config :games_tutor,
    :frontend_base_url,
    System.get_env("FRONTEND_BASE_URL", "http://localhost:3020")

  config :games_tutor, :public_base_url, System.get_env("PUBLIC_BASE_URL", "http://localhost:8000")

  config :games_tutor, GamesTutor.Mailer,
    adapter: Swoosh.Adapters.Sendgrid,
    api_key: Secrets.read("SENDGRID_API_KEY")

  config :games_tutor, :mail_from, System.get_env("MAIL_FROM", "pete@cyberiad.ai")

  config :games_tutor, GamesTutor.Guardian,
    issuer: "games_tutor",
    secret_key: Secrets.read("APP_SECRET_KEY")

  config :games_tutor,
    :stockfish_path,
    System.get_env("STOCKFISH_PATH", "/usr/games/stockfish")

  # KATAGO_MODEL_PATH picks between the two nets baked into the image (see
  # backend/Dockerfile's katago-fetch stage and docs/PLAN.md's Phase 2
  # findings) -- switchable at container start, no rebuild needed. The
  # Dockerfile itself sets this env var to the default (b6c96); the
  # fallback here only matters when running the release outside that image.
  config :games_tutor, :katago,
    path: System.get_env("KATAGO_PATH", "/usr/local/bin/katago"),
    model_path: System.get_env("KATAGO_MODEL_PATH", "/opt/katago/models/b6c96.bin.gz"),
    config_path: System.get_env("KATAGO_CONFIG_PATH", "/opt/katago/analysis.cfg")

  config :games_tutor, :openai_api_key, Secrets.read("OPENAI_API_KEY")

  redis_host = System.get_env("REDIS_HOST", "localhost")

  redis_port =
    String.to_integer(
      System.get_env("REDIS_PORT", if(redis_host == "localhost", do: "6380", else: "6379"))
    )

  config :games_tutor, :redis, host: redis_host, port: redis_port

  # Swoosh's API client (Req) must be explicitly enabled to actually send over
  # HTTP -- the phx.new default disables it in dev (local mailbox preview only).
  config :swoosh, :api_client, Swoosh.ApiClient.Req
end
