# games_tutor: Architecture and Implementation

This document describes the system as actually built and deployed, not as originally
planned (see [`PLAN.md`](PLAN.md) for the original design rationale and phased build
order -- this doc describes where that plan landed, including the one major deviation:
the backend was switched from the originally planned FastAPI/Python to Elixir/Phoenix
early on, once it became clear the real requirement -- one long-lived, stateful process
per active game, each owning a real engine subprocess -- maps directly onto OTP rather
than needing to be built on top of it).

## 1. What the system does

games_tutor is a chess and Go tutoring web app. A user plays against a real engine
(Stockfish for chess, KataGo for Go), gets a data-driven estimate of their own skill
level from a "rate my play" calibration game, and can turn on a real-time spoken voice
tutor that narrates the game and answers questions -- without ever making moves itself.

## 2. Components, at a glance

```
                              ┌─────────────────────┐
                     HTTPS    │        nginx         │  TLS termination (Let's Encrypt),
        ┌────────────────────┤  games.cyberiad.ai    │  reverse proxy to the frontend only
        │                    └──────────┬───────────┘
        │                               │ 127.0.0.1:3020
        │                    ┌──────────▼───────────┐
  Browser (React UI,         │   Next.js frontend    │  App Router, server-to-server
  WebRTC audio ──────────┐   │   (games_tutor-       │  proxy of /api/* to the backend
  direct to OpenAI)      │   │    frontend-1)        │  (next.config.ts rewrites())
        │                │   └──────────┬───────────┘
        │                │              │ 127.0.0.1:8000 (docker network: backend:8000)
        │                │   ┌──────────▼───────────┐
        │                │   │   Phoenix backend     │  Elixir/OTP, JSON API only
        │                │   │   (games_tutor-       │
        │                │   │    backend-1)         │
        │                │   └──┬────────┬────────┬──┘
        │                │      │        │        │
        │                │  Postgres   Redis   Real engine subprocesses
        │                │  (users,    (rate   (Stockfish via UCI, KataGo via a
        │                │   games,    limits, JSON analysis-engine port protocol --
        │                │   moves,    voice   see §5. One process pool entry per
        │                │   skill,    session  ACTIVE GAME, not a shared worker pool)
        │                │   voice     guards)
        │                │   sessions)
        │                │
        └────────────────┴──► OpenAI Realtime API (WebRTC audio + function-calling
                               tool events; backend only ever mints a short-lived
                               ephemeral credential -- see §6)
```

Four Docker containers (`docker-compose.yml` + a `docker-compose.prod.yml` override for
the live deployment), all publishing to `127.0.0.1` only -- nginx is the sole public
entry point, terminating TLS and proxying to the frontend container. The frontend's own
Next.js server then proxies `/api/*` to the backend server-to-server, over the private
Docker network, so the browser never talks to the backend directly and there's no CORS
to configure (everything is same-origin from the browser's point of view). Real audio
never touches either of games_tutor's own servers at all -- see §6.

## 3. Backend: Elixir/Phoenix

`backend/lib/games_tutor/` is organized as a handful of Phoenix **contexts** (plain
modules that own a slice of the domain and are the only thing controllers call into --
controllers never touch `Ecto.Repo` directly):

| Context | Responsibility |
|---|---|
| `Accounts` | users, email/password + Google OAuth, hashed/rotated refresh tokens, email confirmation, password reset |
| `Games` | game lifecycle: create, submit a move, resign, current board state -- game-type-agnostic (chess vs. go dispatch happens once, at the bottom) |
| `Chess.GameServer` / `Go.GameServer` | one GenServer per **active** game, each owning real engine subprocess(es) -- see §5 |
| `Skill` | ACPL/score-loss → rating, Bayesian belief update across games -- see §4 |
| `Voice` | mints OpenAI Realtime ephemeral credentials, session bookkeeping, cost/duration tracking -- see §6 |
| `RateLimit` | shared Redis fixed-window limiter, used by `Voice` and by the auth/game controllers |

Controllers (`backend/lib/games_tutor_web/controllers/`) are thin: parse params, call a
context function, translate its `{:ok, _} | {:error, reason}` result to a status code via
a single shared `FallbackController` that maps every domain error atom
(`:invalid_credentials`, `:illegal_move`, `:rate_limited`, `:hint_refused_calibration`,
...) to its HTTP response once, in one place.

### Auth

JWT access tokens (`GamesTutor.Guardian`, 60-minute TTL, stateless) plus DB-persisted,
hashed, **rotated** refresh tokens (`GamesTutor.Accounts.UserToken`). Rotation on every
refresh forms a chain (`replaced_by_token_id`); presenting an already-rotated token is
treated as theft and revokes the *entire* chain, not just that token -- a password reset
also revokes every active refresh token, ending all other sessions. Registration requires
email confirmation before login is allowed; Google OAuth accounts are auto-confirmed
(Google already verified the email) and link onto an existing password account with the
same email rather than creating a duplicate. Password-reset and resend-confirmation
endpoints always return the same response regardless of whether the email exists, to
avoid leaking account existence.

### Rate limiting

`GamesTutor.RateLimit.check(key, max, window_seconds)` -- a Redis `INCR` + `EXPIRE`
fixed-window counter, generalized out of what was originally only the voice module's own
guard. Applied to: registration/login/password-reset/resend-confirmation (IP-keyed,
deliberately -- rate-limiting by *email* would let an attacker deliberately trip a
victim's own limit and lock them out), and game creation/hints/voice-session-starts
(user-keyed -- these are the endpoints that cost real CPU/subprocess time or real OpenAI
API spend).

## 4. Skill calibration ("rate my play")

A per-`(user, game_type)` Gaussian belief, `SkillProfile{estimated_rating, rating_sigma}`,
updated by each **calibration game** (`is_calibration: true` -- an explicit first-game
mode, not inferred):

1. **ACPL** (`Skill.Acpl`): average centipawn loss (chess) / score-loss (Go) across the
   human's moves in that game, excluding the first few "book" plies.
2. **Anchor table** (`Skill.AnchorTable`, shared by chess and Go): piecewise log-linear
   interpolation from ACPL to an approximate Elo-shaped rating -- endpoints and knot
   points are a documented v1 approximation of publicly-known strength/ACPL correlation,
   not derived from this project's own data yet.
3. **Bayesian update** (`Skill.BayesianUpdate`): the existing belief `(prior_mu,
   prior_sigma)` and this game's observation `(observed_rating, sigma_obs)` are combined
   as precision-weighted Gaussians (`1/sigma²` values add) -- a confident prior resists a
   noisy single-game observation, and vice versa. `sigma_obs` itself shrinks with more
   analyzable moves (more signal) and widens with erratic move-to-move loss (a proxy for
   inconsistent play), floored so no single game can collapse uncertainty at once.

This is explicitly framed (in the code's own docs and in the plan) as an approximate,
improves-across-games heuristic, not a precise single-game measurement --
`test/games_tutor/skill/bayesian_convergence_test.exs` simulates repeated games at known
true skill levels and asserts the belief actually converges within a reasonable number of
games, across a spread from beginner to master level, rather than only unit-testing the
single-update math in isolation.

Opponent strength for a calibration game is set *from* the current belief (`estimated_
rating` → Stockfish `UCI_Elo` / KataGo `maxVisits`, via a documented default when no
profile exists yet), long enough/weak enough to yield an informative multi-move sample
rather than ending too fast either way.

## 5. Real engines: one process per active game

There is no shared engine worker pool. `GamesTutor.Chess.GameServer` and
`GamesTutor.Go.GameServer` are `GenServer`s started on demand
(`DynamicSupervisor.start_child/2` under `GamesTutor.Games.GameSupervisor`, addressed via
`Registry` by game id) and idle-evicted after 30 minutes. On restart, board state is
reconstructed by replaying the DB-persisted move list -- nothing engine-derived is cached
across a process's death.

- **Chess** (`binbo`, an Erlang UCI library): each game owns **two** Stockfish
  subprocesses -- `board_pid` at full strength (used only for move-quality analysis: one
  fresh evaluation per ply, threaded so the position's eval-after-this-move IS the next
  mover's eval-before, no redundant engine queries) and a separate, artificially weakened
  `opp_pid` (via `UCI_LimitStrength`/`UCI_Elo`, or `Skill Level` below Stockfish's own
  Elo floor of 1320) that only ever picks the opponent's replies. Legality is checked by
  `binbo` itself (pure Erlang, no subprocess call) before any engine call is made.
- **Go** (`KataGo`, hand-rolled JSON protocol over a raw Erlang `Port` -- there's no Go
  equivalent of `binbo`): a single KataGo `analysis` mode process serves both roles, since
  KataGo's strength knob (`maxVisits`) is a per-*query* parameter rather than a
  per-process option the way Stockfish's is. KataGo is also the sole legality authority
  here (every query re-sends the full move history; illegal moves, including suicide/ko,
  come back as a structured error) -- a separate `Go.Board` module tracks stone
  placement/capture only for rendering and storage, never for legality.

A finished chess game also gets a **background** re-analysis pass
(`Chess.PostGameAnalysis`, on its own throwaway Stockfish process, depth 18 vs. live
play's depth 12) that backfills more accurate eval/loss/classification without making the
player wait for it during play.

`test/games_tutor/concurrent_load_test.exs` (tagged `:load`, excluded from the default
`mix test` run -- `mix test --only load`) exercises this architecture under real
concurrency: 8 simultaneous chess games and 4 simultaneous Go games, each submitting a
real move and getting a real engine reply, confirming the per-game-process design holds
up rather than serializing or starving under load.

### Engine latency telemetry

Both `GameServer`s wrap every real engine call in `:telemetry.span([:games_tutor, :engine,
:query], %{engine: :stockfish | :katago, kind: :analysis | :opponent_move}, fn -> ... end)`,
feeding `GamesTutorWeb.Telemetry`'s metrics (latency, tagged by engine and call kind) --
this is real per-query latency observability, not a synthetic benchmark.

## 6. Voice: real-time tutoring, audio never touches our servers

Voice sessions use OpenAI's Realtime API over WebRTC, and the split of responsibility is
deliberate:

- **Backend** (`GamesTutor.Voice`) only ever mints a short-lived ephemeral credential
  (`POST https://api.openai.com/v1/realtime/client_secrets`) scoped with mode-specific
  instructions and a tool schema (see below), enforces the per-user rate limit and
  "only one active voice session at a time" guard (Redis `SET NX EX`), and records session
  bookkeeping (duration, an estimated cost based on a documented $/minute figure -- not
  real OpenAI billing data, since the Realtime API doesn't expose per-session usage).
- **Browser** (`use-realtime-voice-session.ts`) holds the actual `RTCPeerConnection`
  directly to OpenAI. Microphone audio streams there directly; the model's spoken audio
  streams back directly. **Our servers never receive or store raw audio at any point.**

Mode is derived server-side from the game's own `is_calibration` flag, never trusted from
the client -- `calibration_proctor` instructions keep the tutor almost silent (so as not
to contaminate the skill measurement being taken), `tutoring` instructions are the normal
narrate-and-teach mode. **`make_move`-by-voice does not exist as a tool** -- the board UI
is the sole authoritative move input; voice is a read/narrate sidecar only, specifically
to avoid a mis-heard voice command ever illegally moving a piece.

**Tool-calling loop** (function calls the model can make mid-conversation --
`get_board_state`, `get_last_move_analysis`, `explain_move`, `request_hint`,
`adjust_explanation_depth`, `get_skill_profile`): OpenAI sends `function_call` items over
the WebRTC data channel inside `response.done` events. The **browser** (not the backend)
dispatches these to the same authenticated REST API the rest of the UI uses (the browser
already knows which game the session is for -- it started the session -- so tool schemas
don't carry a `game_id` the model could pick arbitrarily; ownership is still enforced
server-side regardless) and sends the JSON result back over the data channel as a
`function_call_output`. `request_hint` is hard-refused server-side for calibration games
regardless of what the voice agent is prompted to do, since a prompt is not an enforcement
mechanism.

Cost guardrails are built in, not retrofitted: a mini-only model (no standard-model
opt-in exposed in the UI), a hard max session duration (client-enforced via a timer, using
the value the backend returns), and the per-user rate limit on session starts. Both
session-start and session-end are emitted as `:telemetry.execute` events (mode, duration,
estimated cost -- no audio or PII) feeding the same metrics pipeline as engine latency.

## 7. Frontend: Next.js App Router

Deliberately minimal styling so far (plain inline styles / bare HTML elements in most
pages, Tailwind configured but barely used) -- the build effort has gone into the
functional plumbing, not visual polish.

- `src/lib/api.ts` -- authenticated fetch wrapper: attaches the access token, and on a 401
  transparently attempts exactly one refresh + retry (not an infinite loop) before giving
  up. All requests go to a relative `/api/*` path; `next.config.ts`'s `rewrites()` proxies
  that server-to-server to the Phoenix backend, so the browser never needs to know the
  backend's own host/port, and there's no CORS to configure.
- `src/lib/auth-context.tsx` -- React context wrapping login/register/logout and the
  current user, backed by `localStorage` for the token pair.
- `src/lib/protected-route.tsx` -- redirects to `/login` when not authenticated.
- `src/app/games/[id]/` -- the board UI: `react-chessboard` for chess,
  `@sabaki/shudan` (a Preact component, aliased to React via a Turbopack `resolveAlias`
  trick) for Go.
- `src/app/{attribution,terms,privacy}/` -- static informational pages (see §9).

## 8. Data model

Four migrations, four logical groups:

- **`users`** + **`user_tokens`** (confirm / reset_password / refresh, single table
  disambiguated by a `context` column) -- see §3.
- **`games`** + **`moves`** -- `games` is game-type-agnostic (`game_type: "chess" | "go"`);
  human is always White in chess and always Black in Go (a documented simplification, not
  yet a color choice), so `result`'s literal board-color winner needs `game_type` to
  interpret. `moves.uci` is the exact string used to replay/restore board state;
  `moves.notation` is what's displayed. `eval_before`/`eval_after`/`loss` are centipawns
  from the moving player's perspective, nullable (analysis isn't always computed
  synchronously -- see `PostGameAnalysis` in §5).
- **`skill_profiles`** + **`skill_profile_history`** -- current belief plus a full
  audit trail of every update (`mu_before/after`, `sigma_before/after`, the observation
  that produced it) -- see §4.
- **`voice_sessions`** + **`user_settings`** -- session bookkeeping (mode, model,
  duration, estimated cost -- never audio) and small user preferences (explanation depth,
  preferred voice).

## 9. Trust and safety pages

`/attribution`, `/terms`, and `/privacy` (added as part of Phase 6 hardening) are real,
specific content -- what the app actually collects, what third parties it actually talks
to (OpenAI, SendGrid, Google), and the actual Stockfish (GPLv3)/KataGo (MIT) licensing
arrangement -- not filler. `/terms` and `/privacy` are explicitly marked as drafts pending
real legal review, and both documents are honest about two known gaps rather than
papering over them: there is no technical age-gate at registration (a 13+ minimum is
stated as policy, not enforced), and there is no self-service account-deletion flow yet
(handled by emailing the operator).

## 10. Deployment and infrastructure

Live at **`https://games.cyberiad.ai`**, on a shared Digital Ocean droplet that also hosts
several unrelated apps.

- **`docker-compose.yml`** defines all four services (`postgres`, `redis`, `backend`,
  `frontend`) and is also what local dev runs directly. Every published port is bound to
  `127.0.0.1` only -- nothing needs to be internet-reachable directly: nginx reaches the
  frontend over loopback, containers reach each other over the internal Docker network
  regardless of host port publishing, and host-side port publishing exists purely for
  local `mix test`/`mix phx.server` convenience.
- **`docker-compose.prod.yml`** is a small override layered on top
  (`docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build`):
  the real public hostname (`PHX_HOST`/`PUBLIC_BASE_URL`/`FRONTEND_BASE_URL`, which
  default to `localhost` in the base file for a portable dev setup) and
  `restart: unless-stopped` on every service.
- **Secrets** (Postgres password, JWT signing key, SendGrid/Google/OpenAI API keys) are
  Docker secrets (`/run/secrets/*`, file-based), read at runtime via
  `GamesTutor.Secrets` -- never baked into the image or committed (`secrets/*.txt` is
  gitignored).
- **nginx** (`/etc/nginx/sites-available/games.cyberiad.ai`, outside this repo -- host
  config, not container config) terminates TLS and reverse-proxies to the frontend
  container over loopback; the frontend's own server does the `/api/*` proxy to the
  backend from there, over the Docker network.
- The backend image (`backend/Dockerfile`) is a multi-stage build producing a minimal
  Elixir release, with Stockfish installed from Debian's package and KataGo fetched
  directly from its GitHub release in its own build stage (KataGo isn't packaged for
  Debian/Ubuntu; its release ships as a self-mounting AppImage, extracted with
  `--appimage-extract` since Docker has no FUSE). Neither engine binary nor any neural
  network weights are ever shipped to the frontend or the browser.

## 11. Observability

`GamesTutorWeb.Telemetry` extends Phoenix's default scaffold (endpoint/router/DB-query
metrics, VM metrics) with two real, project-specific additions (see §5, §6): engine query
latency by engine and call kind, and voice session count/duration/estimated-cost by mode.
No raw audio or PII appears in any metric's tags or measurements.

## 12. Testing

Real dependencies throughout (real Postgres, real Stockfish/KataGo subprocesses, real
SendGrid sends even in dev) rather than mocks -- this project's working convention from
the start. `mix test` runs everything except the `:load`-tagged concurrent load test
(`mix test --only load`), which is heavier and deliberately excluded from routine runs.
Notable suites beyond ordinary unit/controller tests:

- `test/games_tutor/chess/game_server_test.exs`, `test/games_tutor/go/game_server_test.exs`
  -- real engine integration tests (a real move played, a real engine reply received).
- `test/games_tutor/skill/bayesian_convergence_test.exs` -- multi-game simulation, not
  just single-update unit tests (see §4).
- `test/games_tutor_web/controllers/rate_limit_test.exs` -- exercises every rate-limited
  endpoint end to end through the real Redis-backed limiter.
- `test/games_tutor/concurrent_load_test.exs` -- concurrent real-engine load (see §5).

## 13. Known gaps

- No self-service account deletion (manual, via email).
- No technical age-gate at registration (policy-only minimum age).
- `/terms` and `/privacy` are drafts, not lawyer-reviewed.
- Skill-calibration anchor tables are a documented v1 approximation, not derived from this
  project's own outcome data.
- Google OAuth credentials in the current deployment are placeholders -- Google sign-in is
  wired end-to-end in code but not yet configured with real credentials in production.
