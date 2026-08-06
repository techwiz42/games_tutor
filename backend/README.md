# games_tutor backend

Phoenix API backend for [games_tutor](../README.md) -- no HTML views, JSON only, consumed
by the Next.js frontend (see [`../frontend/README.md`](../frontend/README.md)) via a
server-to-server proxy. Owns auth, game orchestration, the real Stockfish/KataGo engine
subprocesses, skill calibration, and OpenAI Realtime voice session minting. See
[`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) for the full system design and
[`../docs/PLAN.md`](../docs/PLAN.md) for the original phased build plan.

## Normal way to run this

In practice this always runs via the root [`docker-compose.yml`](../docker-compose.yml)
(`docker compose up` from the repo root), alongside Postgres, Redis, and the frontend --
see the root README. The steps below are for running the backend bare, e.g. to use `iex`
or run `mix test` directly on the host.

## Requirements

- Elixir `~> 1.17` (see `mix.exs`)
- Postgres 16 and Redis reachable (the root `docker-compose.yml` exposes them on
  `127.0.0.1:5433` and `127.0.0.1:6380` respectively for exactly this purpose)
- A real `stockfish` binary and a real KataGo binary + network model -- this project runs
  actual engine subprocesses, never a simulated/mocked engine. See
  `config/runtime.exs`/`config/test.exs` for the env vars that locate them.

## Setup

```
mix setup   # deps.get, ecto.create, ecto.migrate, priv/repo/seeds.exs
```

Secrets (`APP_SECRET_KEY`, `POSTGRES_PASSWORD`, `SENDGRID_API_KEY`, `OPENAI_API_KEY`,
`GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`) are read by `GamesTutor.Secrets` from either a
plain env var or an `<NAME>_FILE` path (the Docker secrets pattern the compose file uses)
-- see [`../secrets/README.md`](../secrets/README.md) for the local-dev files this expects.

## Running

```
mix phx.server            # or: iex -S mix phx.server
```

Listens on `PORT` (default **8000**, not Phoenix's usual 4000 -- see `config/runtime.exs`).
This is a JSON API only; there's nothing to open directly in a browser. In dev, hit it
through the frontend's `/api/*` proxy at `http://localhost:3020` (or whatever
`FRONTEND_BASE_URL`/the frontend's own dev port is) instead of calling `:8000` yourself.

## Testing

```
mix test        # via the `test` alias: ecto.create/migrate --quiet, then ExUnit
mix precommit    # compile --warnings-as-errors, deps.unlock --unused, format, test
```

`config/test.exs` is fully self-contained (fake secret key, `Swoosh.Adapters.Test`, no real
Postgres credentials needed beyond a local test DB) -- no external services are mocked out
at the code level, only swapped for local/test-safe real implementations.

## Layout

```
lib/games_tutor/
  accounts/     User schema, Google OAuth, hashed refresh tokens; accounts.ex is the
                context (registration, login, OAuth linking, password reset, bans)
  admin.ex      aggregated per-user stats (games, rating, voice spend) for the admin page
  chess/        GameServer (one process per game, Stockfish via binbo/UCI), move
                classification, post-game analysis
  go/           GameServer (one process per game, KataGo over a raw JSON port protocol)
  skill/        ACPL, anchor tables, Bayesian skill-belief update, SkillProfile(+History)
  voice/        OpenAI Realtime session minting + tool schemas/instructions
  games.ex      Game/Move orchestration
  rate_limit.ex shared Redis fixed-window limiter (auth, game creation, hints, voice)
  secrets.ex    env var / Docker-secrets-file reader used throughout config/runtime.exs
lib/games_tutor_web/
  controllers/                        auth, game, skill_profile, user_settings, voice,
                                       admin, health
  reject_banned.ex, require_admin.ex  auth-pipeline plugs enforcing bans / admin-only routes
```
