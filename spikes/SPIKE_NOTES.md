# Phase 0 spike findings

## Stockfish (chess) — DONE

- Installed via direct binary download (official `sf_18`, `avx2` build — matches this
  CPU's AVX2/BMI2 support), no root/apt needed: `spikes/engines/bin/stockfish`.
- `UCI_Elo`'s floor is **hard-enforced at 1320** (`min=1320, max=3190`) — Stockfish
  rejects anything below with a clean `EngineError`, it does not silently clamp. For any
  opponent strength below ~1320 (true beginners), use **`Skill Level` (0-20)** instead,
  with `UCI_LimitStrength=False`.
- `Skill Level` always used the full time budget in testing (didn't finish early) —
  weaker play comes from search-skipping/noise, not less thinking time.
- Confirmed two independently-configured `SimpleEngine` subprocess instances (one weak
  opponent via `Skill Level`, one full-strength analysis) coexist fine with no
  interference — validates the plan's decoupled opponent/analysis engine design.
- Script: `spikes/stockfish_check.py`.

## KataGo (Go) — DONE

- No GPU on this machine (confirmed via `nvidia-smi` absence). Installed the **Eigen
  (CPU) `avx2` build, v1.17.1** (`spikes/engines/bin/katago`) — note **v1.17.2 dropped
  CPU/Eigen builds entirely**, only ships CUDA now; had to use v1.17.1's release assets.
- Analysis-engine mode (JSON over stdin/stdout, not GTP) confirmed working —
  `rootInfo.winrate`/`rootInfo.scoreLead` are exactly the tutoring signal needed.
- **Network size dominates CPU latency far more than visit count.** With the mid-size
  `b18c384nbt` net (26M params): 100-500 visits took **4.5s-18.7s per query** — far too
  slow for live per-move classification. Swapping to the small `b6c96` net (1M params,
  from KataGo's older g170 archive, since `katagotraining.org`'s current listings only
  surface b28/b40-class networks now): 100-500 visits took **0.18s-0.68s** — comfortably
  fast for both live classification and even a deeper post-game pass.
- **Decision: use `b6c96` (or similar small net) for v1**, not a bigger "stronger"
  network — matches the plan's stated preference (a tutoring bot doesn't need
  research-grade playing strength, and a small net is what makes CPU-only viable at all).
- Config: `spikes/engines/katago_cfg/spike_analysis.cfg` (reduced from the shipped
  example's `numAnalysisThreads=2 * numSearchThreadsPerAnalysisThread=16` — oversubscribed
  for this 8-core CPU box — to `1 * 8`).
- Scripts: `spikes/katago_check.py` (b18c384nbt), `spikes/katago_check_small.py` (b6c96).
- Models are gitignored (`*.gz` in `.gitignore`) — not vendored in git; re-download via
  the URLs in the scripts.

## Go board UI (Shudan) — DONE

- `spikes/web/` — Next.js 16.3.0 (Turbopack) + React 19 scaffold, shared by this spike and
  the upcoming voice spikes. **Note: this Next.js version is new enough that its own
  bundled docs (`node_modules/next/dist/docs/`) actively warn training-data APIs may be
  stale — verify against those docs, not assumptions, for anything version-sensitive.**
- Installed `@sabaki/shudan` (`spikes/web/node_modules/@sabaki/shudan`). It's a **Preact**
  component, not native React — its own docs' documented compatibility trick is aliasing
  `preact`/`preact/hooks` → `react`. For this Next.js version that's
  `turbopack.resolveAlias` in `next.config.ts` (the docs' webpack-alias example is stale
  for Turbopack-default dev — confirmed the correct current option by reading the bundled
  Turbopack config doc directly).
- **Real, load-bearing finding**: Shudan's render is non-deterministic between SSR and
  client passes (an internal `random` prop, likely for fuzzy stone placement), which
  produces a live hydration-mismatch warning under Next.js App Router's default SSR —
  verified via a real headless-browser console-error check (Playwright), not just visual
  inspection. **Fix applied and verified**: `next/dynamic(..., {ssr: false})` — a Go
  board has no SSR/SEO value anyway, so client-only rendering is the correct fix, not a
  workaround. Confirmed zero console/page errors after the fix.
- Confirmed via headless browser: 19x19 board renders correctly (grid, star points,
  coordinates, board texture), and `onVertexClick` returns correct, usable `(x, y)`
  vertex coordinates on click.
- **Decision: Shudan is viable for v1**, no need for the hand-rolled-SVG fallback
  considered in the plan — but budget time in Phase 5 for the `ssr:false` pattern (and
  possibly others like it) across every place the board UI is embedded, not just this
  spike page.
- Files: `spikes/web/src/app/go-board-spike/page.tsx` (dynamic client-only wrapper),
  `GoBoardSpikeInner.tsx` (actual board + click handling).

## OpenAI Realtime voice (WebRTC connection + tool-calling round trip) — DONE

Both spikes verified end-to-end in one page, real API calls throughout (no mocking):
`spikes/web/src/app/voice-spike/`.

- **Verified current API mechanics directly against OpenAI's live docs** (not assumed
  from the plan) — some details had changed since the plan was written:
  - Model name is now **`gpt-realtime-2.1-mini`** (released 2026-07-06), not
    `gpt-realtime-mini` as the plan guessed. Update the plan's Phase 4 section when
    implementing for real.
  - Ephemeral token endpoint: `POST https://api.openai.com/v1/realtime/client_secrets`,
    body `{"session": {"type": "realtime", "model": ..., "instructions": ..., "audio":
    {"output": {"voice": ...}}, "tools": [...], "tool_choice": "auto"}}` — confirmed tools
    **do** attach directly to the session config at mint time (the plan's design doc had
    flagged this as unverified).
  - Function-call requests arrive inside a **`response.done`** event's
    `response.output[]` array (items with `type: "function_call"`, containing `call_id`,
    `name`, `arguments` as a JSON string) — not the streaming
    `response.function_call_arguments.done` event the plan's design doc mentioned as an
    alternative. Listen for `response.done` and scan its output array.
  - Client sends the result back as `conversation.item.create` with
    `item.type: "function_call_output"`, `call_id`, `output` (JSON string), then a
    separate `{"type": "response.create"}` to prompt the model to continue.
- **Server-side token mint**: a throwaway Next.js route handler
  (`src/app/api/voice-token/route.ts`) for the spike only — Phase 4 replaces this with a
  real JWT-authenticated FastAPI endpoint per the plan.
- **Client-side** (`VoiceSpikeInner.tsx`): `RTCPeerConnection` + mic track + data channel
  (`"oai-events"`) → SDP offer POSTed to `https://api.openai.com/v1/realtime/calls` with
  the ephemeral key as `Bearer` auth, `Content-Type: application/sdp` → remote description
  set from the returned answer SDP text → remote audio track attached to an `<audio>`
  element via `ontrack`.
- **Confirmed working live** (via headless Chromium + Playwright, using
  `--use-fake-device-for-media-stream --use-fake-ui-for-media-stream` launch args and
  `permissions: ["microphone"]` context, since this environment has no real mic): ephemeral
  token mint succeeds, WebRTC connects, data channel opens, server-side VAD fires on the
  fake audio device's synthetic input (`input_audio_buffer.speech_started/stopped`), model
  responds with real streamed audio (`response.output_audio_transcript.delta` events +
  actual audio on the remote track).
- **Tool-calling round trip confirmed working live**: added a deterministic
  text-message trigger button (`askForStatus`) rather than relying on the fake audio
  device's synthetic tone to coincidentally prompt a tool call — sends a
  `conversation.item.create` text turn asking the model to check status. Model correctly
  decided to call `get_spike_status`, browser dispatched it, sent back a real result, and
  the model narrated the result back in its spoken response. Zero console/page errors
  throughout.
- **Decision: proceed with OpenAI Realtime API as planned** — the memchat-adapted
  architecture (backend mints credentials, browser holds the connection, tool calls
  authenticated via the browser's own JWT rather than a second Redis-token system) works
  mechanically exactly as designed. Phase 4 mainly needs the real event-name corrections
  above, not a design change.
