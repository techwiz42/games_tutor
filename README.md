# games_tutor

An AI-powered tutor for chess and Go. Users authenticate to keep their skill profile and
game history persistent across sessions. On a user's first game in each discipline, the
tutor plays a calibration game against them — mostly silent, just gauging their natural
level of play — then tutors from that baseline in subsequent games using a real-time voice
agent for spoken instruction.

Status: **planning complete, implementation not started.** See
[`docs/PLAN.md`](docs/PLAN.md) for the full design.

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

## Architecture at a glance

```
backend/     FastAPI + async SQLAlchemy + Postgres + Alembic
  auth/      JWT (rotated, hashed refresh tokens) + Google OAuth
  voice/     OpenAI Realtime session minting + tool endpoints
  models/    User, Game, Move, SkillProfile, VoiceSession, ...
  api/       REST routers
  games/     game orchestration (turn loop, calibration mode)
  engines/   chess_adapter.py (Stockfish/UCI), go_adapter.py (KataGo)
frontend/    Next.js + React — board UI (react-chessboard / Shudan), auth, voice hook
migrations/  Alembic
docker-compose.yml   backend + frontend + Postgres 16 + Redis
```

Full rationale for every one of these choices — including the OpenAI Realtime integration
shape, the skill-calibration math, the database schema, and a phased build order with
per-phase verification criteria — is in [`docs/PLAN.md`](docs/PLAN.md).

## Status

Nothing is implemented yet. The plan's Phase 0 (spikes: a minimal OpenAI Realtime voice
connection, confirming Stockfish/KataGo strength-limiting behavior, measuring real KataGo
latency on this hardware, and prototyping the Go board UI) is the next work.
