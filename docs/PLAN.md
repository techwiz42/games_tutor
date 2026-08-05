# games_tutor — Implementation Plan

## Context

New, standalone project: an AI-powered tutor for chess and Go. Requires authenticated
users so skill/progress persists across sessions. A "rate my play" game mode plays
against the user mostly silently to gauge their level, then tutors from that baseline in
subsequent games using a real-time voice agent for spoken instruction. "Rate my play" is
not a one-time first-game event — the user can request it again any time to
recalibrate.

Confirmed decisions (already asked and answered):
1. **Standalone new repo** — not built inside `agent_framework`'s module/builder system.
2. **Real engines** — Stockfish (chess) and KataGo (Go), not custom-built game logic.
3. **Real-time browser voice** (WebRTC) — not a telephony-style pipeline.

This plan is grounded in: (a) a read-only environment check (what's actually installed —
nothing chess/Go-specific yet, but Postgres/Docker/Node/Python are ready, `OPENAI_API_KEY`
is available), and (b) a full read of this user's other FastAPI/Next.js projects
(`thanotopolis`, `memchat`, `cyberiad`, `orca-validator`) for proven, reusable patterns —
auth module shape, and critically, `memchat`'s browser-direct real-time-voice architecture,
which is the closest existing analog to what this project needs.

## Architecture

**Stack**: FastAPI + async SQLAlchemy 2.0 + Postgres 16 + Alembic (backend); Next.js +
React (frontend); Redis for session/rate-limit state — the pattern proven across
`thanotopolis`/`memchat`/`orca-validator`, no reason for a greenfield project to deviate.

**Repo layout** (mirrors `memchat`'s proven shape):
```
games_tutor/
├── backend/
│   ├── auth/        # JWT + Google OAuth (adapted from thanotopolis + memchat)
│   ├── voice/        # OpenAI Realtime session minting + tool endpoints
│   ├── models/        # User, Game, Move, SkillProfile, VoiceSession, ...
│   ├── api/           # REST routers
│   ├── games/          # game orchestration (turn loop, calibration mode)
│   ├── engines/         # chess_adapter.py, go_adapter.py (Stockfish/KataGo)
│   └── database.py       # pool_pre_ping/pool_timeout — see AUTH_LOGIN_SESSION_RACE.md
├── frontend/                # Next.js: board UI, auth pages, voice hook/UI
├── migrations/                # Alembic
└── docker-compose.yml           # backend + frontend + Postgres 16 + Redis
```

**Auth**: JWT access token (short-lived) + a **DB-persisted, hashed, rotated** refresh
token (`refresh_tokens` table) — this is `thanotopolis`'s pattern (individually revocable),
improved with hashing-at-rest and rotation-on-use (neither sibling project does both;
memchat's refresh token is a long-lived stateless JWT with no revocation path, which is a
real gap). Optional Google OAuth login, following `memchat/backend/auth/google.py`'s
state-token-CSRF + ID-token-verification pattern; `User.hashed_password` and `google_id`
both nullable so either path works alone.

Carry forward `agent_framework/docs/design/AUTH_LOGIN_SESSION_RACE.md`'s lessons directly:
collapse post-login bookkeeping into one commit (not sequential commits on one session),
and bound any background `asyncio.create_task()` usage (post-game analysis, voice-session
cleanup) with a tracked task set — cheap now, expensive to retrofit under load.

**Chess engine**: Stockfish via `python-chess`'s `chess.engine` UCI wrapper. Two decoupled
engine configurations per game — a skill-limited **opponent** (`UCI_LimitStrength`/
`UCI_Elo`, or `Skill Level` for true-beginner strengths below Stockfish's calibrated Elo
floor) and a separate **full-strength analysis** instance (fixed depth/time) that scores
the human's move quality independent of what the opponent is doing. A persistent engine
process pool (not spawn-per-request) from day one — process/model-load cost multiplies
under concurrent games.

**Go engine**: KataGo in **analysis-engine mode** (JSON over stdin/stdout, not plain GTP)
— it returns win-rate/score-lead per candidate move directly, which is exactly the signal
a tutor needs to explain *why* a move was a mistake. CPU-only assumed (GPU not confirmed
available); default to a smaller network and capped visit counts (~100-300 for live
per-move classification, a deeper uncapped pass for the post-game calibration estimate).
Real measured latency on this machine is a Phase 0 spike, not an assumption.

**Licensing**: Stockfish (GPLv3) and KataGo (MIT) both run server-side as subprocesses via
a stable text/JSON protocol, never distributed to end-user devices or linked into
games_tutor's own binary — the same pattern every chess/Go SaaS (Lichess, etc.) relies on.
Low real risk; not legal advice, but no reason this blocks the project.

**Chess/Go abstraction**: resist unifying chess and Go behind one `GameEngine` interface
prematurely — they're different enough (SAN/PGN vs SGF, UCI vs KataGo's JSON protocol,
material eval vs territory scoring) that a forced-early abstraction would leak. Build chess
first as its own working thing; extract only what's genuinely shared once Go exists
(Phase 5) — in practice that's a thin `SkillEstimator` (the Bayesian update math, which
really is identical once you have a per-move "loss" number in the engine's native unit),
not the engines themselves.

**Board UI**: `react-chessboard` for chess (mature, FEN-based, actively maintained). For
Go, `Shudan` (`@sabaki/shudan`) is the best existing option but unproven here — **Phase 0
spikes it explicitly** (render 19×19, get click coordinates, confirm it isn't broken in a
modern Next.js setup) with a documented fallback (hand-rolled SVG/Canvas board on
`@sabaki/go-board`'s core primitives) decided now, not discovered mid-Phase-5.

## Voice: OpenAI Realtime API (WebRTC)

Adapts `memchat`'s proven division of responsibility (backend mints credentials, browser
holds the real-time connection) to OpenAI's specific mechanics — **but simpler than
memchat's Omnia pattern in one important way**: OpenAI's browser-held `RTCDataChannel`
means tool calls arrive *in the browser*, not server-to-server, so tool-callback auth can
just reuse the user's existing JWT — no second Redis-token auth system is needed the way
memchat's Omnia integration required one.

**Backend** (`POST /api/voice/session`, normal JWT auth):
1. Build mode-specific `instructions` (`calibration_proctor` vs `tutoring`) + a fixed tool
   schema (below).
2. `POST https://api.openai.com/v1/realtime/client_secrets` with the real
   `OPENAI_API_KEY`, session config (model, instructions, tools) attached — returns a
   short-lived ephemeral key.
3. Persist a `voice_sessions` row; enforce one active session per user + a session-creation
   rate limit via Redis (mirrors memchat's `/voice/start` guard).
4. Return the ephemeral key to the browser.

**Browser** (`useRealtimeVoiceSession` hook, replacing memchat's `ultravox-client` SDK
calls with raw WebRTC): `RTCPeerConnection` + mic track + data channel → exchange SDP with
OpenAI's `/v1/realtime/calls` using the ephemeral key → attach remote audio → listen for
`response.function_call_arguments.done` on the data channel → dispatch to the matching
authenticated `fetch` against games_tutor's own backend (same JWT) → send the result back
as `function_call_output`.

**Tools** (all normal JWT-authenticated REST endpoints): `get_board_state`,
`get_last_move_analysis` (pre-computed at move-submission time, not live in the tool call,
to keep voice-turn latency low), `explain_move`, `request_hint` (**server-side hard
refusal** when `voice_session.mode == calibration_proctor` — enforced in code, not just by
prompting), `adjust_explanation_depth`, `get_skill_profile`. **`make_move`-by-voice is
explicitly out of scope for v1** — the board UI is the sole authoritative move input;
voice is a read/narrate sidecar. Legality-critical mis-hears are a worse failure mode than
occasionally needing to say a hint twice.

**Calibration-game voice behavior**: mostly silent, explicitly framed as a proctor, not a
teacher — coaching commentary mid-calibration would change how the player plays and
contaminate the skill measurement. One line at game start ("play your best, I'll stay
quiet and we'll talk after"), move confirmations and pure rules-legality answers only
during play, one honest/hedged spoken summary at game end. This is where tutoring begins.

**Cost guardrails** (built in from Phase 4, not retrofitted): default to `gpt-realtime-mini`,
enforce a max session duration, track per-user voice-minutes in Postgres from
`voice_sessions`, gate the pricier standard model behind explicit opt-in. Realtime audio
is priced per-token and non-trivial at scale (order of $0.05-0.10/min with prompt caching,
more without) — worth monitoring from day one.

## Skill calibration (the genuinely novel part — no library does this)

Framed explicitly to users as an approximate v1 heuristic that improves over multiple
games, not a scientifically precise single-game measurement.

**Chess**: per human ply, `loss = max(0, min(1000, eval_best − eval_actual))` in
centipawns from the full-strength analysis engine, excluding early-opening plies and
forced positions. `ACPL = mean(loss)`. Map ACPL → Elo via a monotonic anchor table
(≤10cp→2600 ... 400cp+→400 floor), log-linearly interpolated — the same shape of idea
behind Lichess's own centipawn-loss-based accuracy formula. Store per-move classification
buckets too (blunder/mistake/inaccuracy/good/best), not just the mean — a single-blunder
player and a consistently-sloppy player can share an ACPL but need different tutoring.

**Decision (2026-08-05, revised): "rate my play" opponent starting strength is
system-determined by default, and user-overridable.** Not a hardcoded constant (an
earlier version of this doc floated a fixed 1800 minimum — superseded). Resolution order
when starting a "rate my play" game:
1. If the caller explicitly supplies a starting Elo/rank override, use it (validated
   against the engine's supported range — Stockfish's `UCI_Elo` floor is 1320, confirmed
   in Phase 0; below that, fall back to `Skill Level` per the Phase 0 findings).
2. Else if the user already has a `SkillProfile` for this `game_type` (from a prior "rate
   my play" game), seed the opponent from the current `estimated_rating`.
3. Else (first-ever "rate my play" game, no profile yet), use a sensible platform default
   (exact value TBD at implementation time — no longer fixed at 1800; pick something
   reasonable and document it in code, not silently baked into multiple places in this
   doc).

"Rate my play" is a repeatable game mode (`Game.is_calibration = true` marks any game as
one, not just a user's first game ever), triggerable on demand — the `POST /games`
endpoint (or a dedicated `POST /games/rate-my-play`) accepts an optional
`starting_elo_override` param implementing step 1 above.

**Go**: per human move, `score_loss = max(0, scoreLead_best − scoreLead_actual)` from
KataGo's analysis engine, excluding opening and dame-filling moves. Average → rank via an
anchor table (≤0.5pt→7d+ ... 30pt+→25k+), modeled on the general shape used by existing
KataGo-based teaching tools (e.g. KaTrain) that already do this. Internally store both
games on **one continuous numeric scale** (kyu/dan and Elo both map to a single number) so
the Bayesian update math is shared, only the display label differs.

**Cross-game update** (shared `SkillEstimator`, extracted in Phase 5): Gaussian belief
`(mu, sigma)` per `(user, game_type)`, precision-weighted update per game
(`sigma_obs` shrinks with more informative moves, widens with erratic play). Wide prior
(`sigma≈400`) before any games, optionally narrowed by an onboarding self-report question.
Game 1 swings the estimate a lot; later games mostly tighten `sigma` without big `mu`
swings — append-only `skill_profile_history` for progress charts and auditability.

## Data model (key tables)

`users` (email, hashed_password nullable, google_id nullable, ...) · `refresh_tokens`
(token_hash, expires_at, revoked_at, replaced_by_token_id — rotation chain) · `games`
(game_type chess|go, status, is_calibration, opponent_engine_config jsonb, record as
PGN/SGF, result) · `moves` (ply, player, notation, eval_before/after, loss,
engine_best_move, classification, think_time_ms) · `skill_profiles` (per user+game_type:
estimated_rating, rating_sigma, display_label, games_count) · `skill_profile_history`
(append-only mu/sigma before/observed/after per game) · `voice_sessions` (mode, status,
estimated_cost_usd) · `user_settings` (default_explanation_depth, preferred_voice).

## Risks worth tracking explicitly

- **Voice cost** at scale — mitigated by mini-model default + duration/usage caps (above).
- **CPU-only KataGo latency** — unmeasured until the Phase 0 spike; use two visit budgets
  (fast live classification vs. deep post-game calibration pass).
- **Engine process cost under concurrency** — persistent process pools from Phase 2, not
  spawn-per-request.
- **Nondeterministic engine output** complicates testing — mock at the adapter boundary
  for fast unit tests of loss/classification logic; keep a small, explicitly-marked
  integration suite against the real binaries.
- **The `/tmp/ek.txt` key from the agent_framework session is unlabeled/unverified** — do
  not wire it into games_tutor speculatively; if ElevenLabs TTS becomes a desired upgrade
  later, verify provenance and get explicit go-ahead first.
- **Minors as a likely audience** for a chess/Go tutor, combined with voice/audio data
  collection — not solved by this plan, but flagged as a conscious Phase 6 decision (age
  gate vs. proper minor-data handling), not an accidental gap.
- **Mic-permission UX / WebRTC secure-context requirement** — plan HTTPS or localhost dev
  proxy into the docker-compose dev setup from the start; test Safari/iOS early.

## Task breakdown

**Phase 0 — Spikes** (de-risk before committing to a timeline): minimal OpenAI Realtime
WebRTC connection (hear a greeting, no tools) → extend with one trivial tool round-trip →
install Stockfish, confirm `UCI_LimitStrength`/`UCI_Elo` behavior and real Elo floor →
install KataGo (CPU build) + a small network, measure real per-query latency at a few
visit counts → prototype Shudan in a bare Next.js page, decide fallback now if needed.

**Phase 1 — Scaffold, auth, DB, docker-compose**: repo layout, Postgres 16 + Redis
containers (own stack, not the host's systemd cluster), `User` model + migration, auth
(register/login/refresh/logout, rotated hashed refresh tokens, single-commit login
bookkeeping), Google OAuth, Next.js app shell + protected routes, smoke test.

**Phase 2 — Chess engine + game loop (no voice yet)**: Stockfish in the backend image +
attribution doc, `engines/chess_adapter.py` with a persistent process pool, `Game`/`Move`
models (designed generically enough to reuse for Go), REST (create/get game, submit move
with server-side legality + engine reply + eval/loss/classification), `react-chessboard`
frontend wired to the loop, background job for post-game full analysis.

**Phase 3 — Chess skill calibration**: ACPL computation, anchor-table interpolation
(unit-tested pure function), `SkillProfile` model + Bayesian update (unit-tested) +
history table, wire calibration-game completion → profile update, onboarding self-report
question, honest/hedged post-calibration summary UI.

**Phase 4 — Voice (OpenAI Realtime, chess only)**: session-mint endpoint + tool endpoints
+ Redis guard/rate-limit, `useRealtimeVoiceSession` hook, voice UI (permission/connecting/
listening/speaking states, transcript), calibration-proctor vs tutoring instruction
templates, cost guardrails, manual end-to-end test of a full calibration game + a tutoring
session with real tool calls.

**Phase 5 — Go (KataGo + Shudan)**: KataGo in the backend image + attribution doc,
`engines/go_adapter.py`, extract the shared `SkillEstimator` from Phase 3's chess code
(the abstraction question resolved empirically now that Go exists), Go anchor table,
Shudan (or spike's fallback) frontend, Go-specific voice tool responses/prompt variants,
manual end-to-end test.

**Phase 6 — Polish/hardening**: multi-game Bayesian convergence validation, rate-limiting
audit, observability (engine latency, voice cost/duration — no raw audio/PII logged),
concurrent-load test of the engine process pool, attribution page + age-appropriate
ToS/privacy policy covering voice data, production docker-compose/hosting profile.

## Verification

Each phase ends in a concrete, runnable check rather than "looks right": Phase 0 spikes
are pass/fail on their own (hear the model, see the tool round-trip, see real KataGo
latency numbers, see a rendered Go board). Phase 1 ends with a real register→login→
`/me`→refresh→logout smoke test against the dockerized Postgres. Phase 2 ends with a full
human-vs-Stockfish game playable end-to-end through the UI. Phase 3 ends with unit tests on
the ACPL/anchor-table/Bayesian-update pure functions plus one real calibration game
producing a plausible rating. Phase 4 ends with a real browser voice session narrating a
real game via real tool calls (manually verified — WebRTC/audio isn't practically
unit-testable). Phase 5 mirrors Phase 2-4's checks for Go. No phase is "done" without its
own runnable verification, not just code existing.

## Immediate next steps (this session, once this plan is approved)

1. Commit this plan document into the new repo (`docs/PLAN.md` or similar) as the
   project's initial design record.
2. Create the `games_tutor` repository at `/home/trurl/games_tutor` (`git init`), with a
   `README.md` describing the project (what it is, the architecture summary above, current
   status = planning-complete/Phase-0-not-started).
3. Initial commit and (if a remote is set up) push — repo creation and remote setup details
   to be confirmed with the user at that point (e.g. GitHub org/visibility), not assumed.
