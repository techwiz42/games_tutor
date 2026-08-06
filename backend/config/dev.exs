import Config

# Repo and Endpoint (host/port/secret_key_base) are configured in
# config/runtime.exs for every environment -- see its module doc for why.

config :games_tutor, GamesTutorWeb.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  watchers: []

# Enable dev routes for dashboard and mailbox
config :games_tutor, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
