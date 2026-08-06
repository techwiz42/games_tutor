import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :games_tutor, GamesTutor.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "games_tutor_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :games_tutor, GamesTutorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ivM5VIa5KpU/IbaG+3wtZhzgUaAFJiBpd5zlZLEtdnLI+vPyedt5JcvHwdi6ljZ+",
  server: false

# In test we don't send emails
config :games_tutor, GamesTutor.Mailer, adapter: Swoosh.Adapters.Test
config :games_tutor, :frontend_base_url, "http://localhost:3020"
config :games_tutor, :public_base_url, "http://localhost:4002"
config :games_tutor, :mail_from, "pete@cyberiad.ai"

config :games_tutor, GamesTutor.Guardian,
  issuer: "games_tutor",
  secret_key: "test-only-secret-key-not-used-in-any-real-environment"

# Real stockfish binary -- integration tests run the actual engine (this
# project's convention throughout has been no mocks), just at the fast end
# of its options for test speed.
config :games_tutor, :stockfish_path, System.get_env("STOCKFISH_PATH", "/usr/games/stockfish")

# Real docker-compose redis (see docker-compose.yml's port mapping) -- same
# no-mocks convention as Postgres/Stockfish above.
config :games_tutor, :redis, host: "localhost", port: 6380

# Real OpenAI API key -- used sparingly, by the one dedicated integration
# test that actually mints a session (a real, small, billed API call; not
# hit by the rest of the suite).
default_openai_key_file = Path.expand("../../secrets/openai_api_key.txt", __DIR__)

config :games_tutor,
       :openai_api_key,
       System.get_env("OPENAI_API_KEY_FILE", default_openai_key_file)
       |> File.read!()
       |> String.trim()

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
