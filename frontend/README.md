# games_tutor frontend

Next.js 16 (App Router) frontend for [games_tutor](../README.md) -- board UI
(`react-chessboard` for chess, `@sabaki/shudan` for Go), auth pages, the admin dashboard,
and the browser-side half of the real-time voice tutor (WebRTC straight to OpenAI's
Realtime API; see `src/lib/use-realtime-voice-session.ts`). See
[`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) for how this fits into the full
system.

## Normal way to run this

In practice this always runs via the root [`docker-compose.yml`](../docker-compose.yml)
(`docker compose up` from the repo root) alongside the Phoenix backend, Postgres, and
Redis -- see the root README. The steps below are for running the frontend bare against an
already-running backend.

## Requirements

- Node.js (see `frontend/Dockerfile` for the exact version this deploys with)
- A reachable backend -- see [`../backend/README.md`](../backend/README.md). By default
  this proxies `/api/*` to `http://localhost:8000` (see `next.config.ts`'s `rewrites()`);
  override with the `BACKEND_INTERNAL_URL` **build** arg if the backend is elsewhere.

## Running

```bash
npm install
npm run dev     # dev server on :3000
```

In the deployed stack this actually listens on container port 3000, mapped to
`127.0.0.1:3020` on the host, with nginx (`/etc/nginx/sites-available/games.cyberiad.ai`)
terminating TLS and proxying `games.cyberiad.ai` to it -- see `docker-compose.yml`'s
`frontend` service.

Other scripts: `npm run build` / `npm run start` (production build and serve).

## A few things that aren't obvious from the code alone

- **`/api/*` is proxied server-to-server**, not called directly from the browser -- the
  browser only ever talks to whatever origin Next.js itself is served from. This avoids
  needing the backend's port open to the outside world at all, and sidesteps CORS entirely
  (same-origin from the browser's point of view).
- **`BACKEND_INTERNAL_URL` must be a Docker build arg, not a runtime env var** -- `next
  build` freezes `rewrites()` into the build output, and `next start` never re-reads it
  afterward. See `frontend/Dockerfile` and the root `docker-compose.yml`'s `frontend.build.args`.
- **`allowedDevOrigins` includes `games.cyberiad.ai`** -- Next.js 16's dev server rejects
  requests whose `Host` header doesn't match a known dev origin (DNS-rebinding
  protection); without this, nginx proxying with the real `Host` header silently breaks
  every request through the real domain.
- **Shudan (the Go board) is a Preact component** -- aliased `preact` -> `react` in the
  Turbopack config, per its documented React-compatibility trick (confirmed working in
  `spikes/web/`; see `spikes/SPIKE_NOTES.md`).
- **Voice only ever starts from an explicit user action** (e.g. "Ask tutor why" on a
  move) -- there's no ambient/always-on listening session; see
  `src/lib/use-realtime-voice-session.ts`.

## Layout

```
src/app/
  dashboard/, games/, games/[id]/   the board UI itself
  admin/                            admin-only user-list dashboard (requires is_admin)
  login/, register/, forgot-password/, reset-password/, confirm-email/, auth/   auth flows
  terms/, privacy/, attribution/    legal + engine attribution pages
src/lib/
  games-api.ts, voice-api.ts, admin-api.ts   typed fetch wrappers over the backend's JSON API
  use-realtime-voice-session.ts              the WebRTC/OpenAI Realtime voice hook
  auth-context.tsx, protected-route.tsx      client-side auth state and route guarding
  auth-ui.ts                                 shared Tailwind class-name constants
```
