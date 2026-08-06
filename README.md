# games_tutor

An AI-powered tutor for chess and Go. Users authenticate to keep their skill profile and
game history persistent across sessions. On a user's first game in each discipline, the
tutor plays a calibration game against them — mostly silent, just gauging their natural
level of play — then tutors from that baseline in subsequent games using a real-time voice
agent for spoken instruction.

Status: **live** at [games.cyberiad.ai](https://games.cyberiad.ai) -- all six of the plan's
phases (scaffold/auth, chess, skill calibration, voice, Go, hardening) are built and
deployed. See [`docs/PLAN.md`](docs/PLAN.md) for the full design and phase breakdown.

## What this is

- **Two games, real engines.** Chess via Stockfish, Go via KataGo — both run server-side
  as subprocesses through their native protocols (UCI and KataGo's JSON analysis-engine
  mode), not reimplemented from scratch.
- **Skill calibration, not a difficulty picker.** The first game against each engine is
  played at a moderate default strength while the tutor stays quiet; average
  centipawn-loss (chess) or score-loss (Go) per move during that game maps to an initial
  skill estimate, which then keeps updating (Bayesian, not overwritten) across later
  games.
- **Voice-first tutoring.** A real-time voice agent (OpenAI's Realtime API, browser-native
  WebRTC) narrates and answers questions during tutoring sessions — reading the board and
  move-quality analysis, not driving moves. Moves are always made on the board UI; voice is
  a spoken sidecar, not a control surface, to avoid legality-critical mis-hears.
- **Authenticated by design.** Skill profiles, game history, and tutoring continuity all
  require a persistent user identity (email/password or Google OAuth).
- **Moderation and admin.** Admin accounts (`User.is_admin`) get a user-list dashboard
  (games played, chess rating, voice token spend per user) and can ban accounts; a banned
  user is rejected on their very next request, not just their next login.

## Architecture at a glance

Backend is Elixir/Phoenix, not the FastAPI backend originally planned -- switched early
(see git history) once the plan's actual concurrency needs (one process per active game,
each owning a real engine subprocess) turned out to map more directly onto OTP than onto
async Python.

```
backend/lib/games_tutor/
  accounts/     auth (User, Google OAuth, hashed refresh tokens); accounts.ex is the
                context (registration, login, OAuth linking, password reset, bans)
  admin.ex      aggregated per-user stats (games, rating, voice spend) for the admin page
  chess/        GameServer (one process per game, Stockfish via binbo/UCI), move
                classification, post-game analysis
  go/           GameServer (one process per game, KataGo over a raw JSON port protocol),
                board state
  skill/        ACPL, anchor tables, Bayesian skill-belief update, SkillProfile(+History)
  voice/        OpenAI Realtime session minting + tool schemas/instructions
  games.ex      Game/Move orchestration
  rate_limit.ex shared Redis fixed-window limiter (auth, game creation, hints, voice)
backend/lib/games_tutor_web/
  controllers/    auth, game, skill_profile, user_settings, voice, admin, health
  reject_banned.ex, require_admin.ex   auth-pipeline plugs enforcing bans / admin-only routes
frontend/src/app/   Next.js App Router -- auth pages, dashboard, board UI
                     (react-chessboard / Shudan), admin, attribution/terms/privacy
docker-compose.yml       dev stack: backend + frontend + Postgres 16 + Redis
docker-compose.prod.yml  production overrides (real domain, restart policy) --
                         see docs/PLAN.md's Phase 6 for what "production" means here
```

Full rationale for the original design -- the OpenAI Realtime integration shape, the
skill-calibration math, the database schema, and the phased build order with per-phase
verification criteria -- is in [`docs/PLAN.md`](docs/PLAN.md). For how the system is
actually built and deployed today (including the Python -> Elixir switch and a full
component diagram), see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Engine attribution
notices are in [`docs/STOCKFISH_ATTRIBUTION.md`](docs/STOCKFISH_ATTRIBUTION.md) and
[`docs/KATAGO_ATTRIBUTION.md`](docs/KATAGO_ATTRIBUTION.md) (also surfaced in-app at
`/attribution`).

## Status

All six phases are built: auth/DB scaffold, a real Stockfish game loop, chess skill
calibration ("rate my play"), real-time voice tutoring, Go via KataGo, and Phase 6
hardening (rate limiting, engine/voice telemetry, a multi-game convergence check, a
concurrent-load test of the engine process pool, attribution/terms/privacy pages, and the
production deployment itself). Since then: an admin dashboard and account-ban support have
been added. Known open item: no self-service account deletion or technical age-gate yet --
see the Privacy Policy and Terms pages for how that's currently handled.
