import Config

# Force using SSL in production. This also sets the "strict-security-transport" header,
# known as HSTS. If you have a health check endpoint, you may want to exclude it below.
# Note `:force_ssl` is required to be set at compile-time.
config :games_tutor, GamesTutorWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      # paths: ["/health"],
      # "backend" is the docker-compose internal service hostname the
      # frontend's server-to-server proxy (next.config.ts's rewrites())
      # talks to -- that traffic never leaves the docker network, so
      # forcing https on it (there's no cert for it) just breaks the proxy.
      hosts: ["localhost", "127.0.0.1", "backend"]
    ]
  ]

# Configure Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
