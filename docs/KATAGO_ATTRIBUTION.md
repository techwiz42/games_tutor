# KataGo attribution

games_tutor's Go opponent and move-analysis engine is
[KataGo](https://github.com/lightvector/KataGo), licensed under the
[MIT License](https://github.com/lightvector/KataGo/blob/master/LICENSE).

## How it's used here

KataGo runs **server-side only**, as an independent OS subprocess the
backend talks to over its JSON analysis-engine protocol (stdin/stdout),
started fresh per active game and torn down when the game's process is
idle-evicted (see `GamesTutor.Go.GameServer`). The binary and neural
network are never compiled into the `games_tutor` release and never
distributed to end-user devices.

## Where it comes from

- **Engine binary**: KataGo v1.17.1, the official Eigen (generic CPU, not
  AVX2-specific) Linux x64 release build — chosen for the same
  host-CPU-portability reason Stockfish uses Debian's generic package
  rather than an AVX2-only binary (see `docs/STOCKFISH_ATTRIBUTION.md`).
  Source: https://github.com/lightvector/KataGo/releases/tag/v1.17.1
- **Neural network**: `g170-b6c96-s175395328-d26788732`, a small (6 block,
  96 channel, ~1M parameter) network from KataGo's public "g170" training
  run archive (https://katagoarchive.org/g170/neuralnets/). Confirmed in
  the Phase 0 spike to be dramatically faster than KataGo's flagship nets
  on this CPU-only machine (0.18-0.68s for 100-500 visits, vs. 4.5-18.7s
  for the same visit range on the `b18c384nbt` net) — see
  `spikes/SPIKE_NOTES.md`. A tutoring bot doesn't need research-grade
  playing strength, and a small net is what makes CPU-only viable at all.

Both are fetched fresh from their official sources in `backend/Dockerfile`'s
`katago-fetch` build stage (not vendored/modified binaries); local
dev/test reuses the Phase 0 spike's already-downloaded copies under
`spikes/engines/` rather than re-fetching.

## Not legal advice

Same note as `docs/STOCKFISH_ATTRIBUTION.md`: this documents the actual
technical arrangement for anyone auditing the project later, not a
substitute for real legal review at commercial scale.
