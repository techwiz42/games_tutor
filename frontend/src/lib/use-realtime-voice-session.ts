"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { startVoiceSession, endVoiceSession } from "./voice-api";
import { getBoardState, getMoveAnalysis, requestHint, updateExplanationDepth, listSkillProfiles } from "./games-api";

export type VoiceStatus = "idle" | "requesting-permission" | "connecting" | "connected" | "ended" | "error";

// response.done means the server finished GENERATING the response, not
// that the browser has finished PLAYING its audio -- confirmed against
// OpenAI's Realtime API community docs, not assumed: audio synthesis can
// run well ahead of real-time, so response.done can fire while most of a
// longer explanation's audio is still only queued for delivery. An
// earlier version disconnected a fixed 1500ms after response.done, which
// was nowhere near enough and clipped most of the explanation, not just
// its last words. output_audio_buffer.stopped (WebRTC-only, undocumented
// in the official API reference but confirmed live and in community
// threads) is the real "the server has finished sending audio for this
// response" signal; FINAL_ANSWER_GRACE_MS after THAT only needs to cover
// the browser's own WebRTC jitter buffer draining what it already
// received, not the whole utterance.
const FINAL_ANSWER_GRACE_MS = 400;

// Backstop only, in case output_audio_buffer.stopped never arrives for
// some reason (e.g. a rare text-only turn with no synthesized audio) --
// without this, awaitingFinalAudioRef would never clear and the session
// would sit connected (mic hot) indefinitely instead of ending.
const FINAL_ANSWER_FALLBACK_MS = 20_000;

// dcRef.current flips to "open" slightly after `status` becomes "connected"
// (WebRTC data-channel negotiation, not gated on anything this hook awaits) --
// askAboutMove can be called right after a cold `connect()`, so it polls the
// ref (always current) rather than trusting a possibly-stale `status` closure.
function waitForOpenChannel(dcRef: { current: RTCDataChannel | null }, timeoutMs = 5000): Promise<boolean> {
  return new Promise((resolve) => {
    const startedAt = Date.now();
    const check = () => {
      if (dcRef.current?.readyState === "open") return resolve(true);
      if (Date.now() - startedAt > timeoutMs) return resolve(false);
      setTimeout(check, 100);
    };
    check();
  });
}

/**
 * Real-time voice tutor over WebRTC (OpenAI Realtime API), following the
 * Phase 0 spike's confirmed-working protocol exactly: backend mints a
 * short-lived ephemeral credential, the browser holds the actual WebRTC
 * connection directly to OpenAI, and tool calls arrive over the data
 * channel in `response.done` events (not the streaming
 * `response.function_call_arguments.done` event the plan's design doc
 * had guessed at as an alternative).
 *
 * make_move-by-voice is intentionally not a tool here -- the board UI is
 * the sole authoritative move input; voice is a read/narrate sidecar.
 */
export function useRealtimeVoiceSession(gameId: string) {
  const [status, setStatus] = useState<VoiceStatus>("idle");
  const [error, setError] = useState<string | null>(null);
  const [isAssistantSpeaking, setIsAssistantSpeaking] = useState(false);
  const [isUserSpeaking, setIsUserSpeaking] = useState(false);

  const pcRef = useRef<RTCPeerConnection | null>(null);
  const dcRef = useRef<RTCDataChannel | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const sessionIdRef = useRef<string | null>(null);
  const maxDurationTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const autoStopTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  // True only once the FINAL response.done (no function_call -- the
  // tutor's actual answer, not a tool-call round-trip) has landed. Gates
  // the output_audio_buffer.stopped handler below so an EARLIER turn's
  // own audio finishing (e.g. a spoken "let me check..." aside alongside
  // a tool call) never triggers a disconnect -- only the final turn's.
  const awaitingFinalAudioRef = useRef(false);
  // Populated once `disconnect` exists (see the effect right after its
  // definition) -- handleDataChannelMessage needs to call it from inside a
  // response.done handler defined earlier in the file, without making
  // itself (and therefore dc.onmessage) get redefined every time
  // `disconnect`'s identity changes.
  const disconnectRef = useRef<() => void>(() => {});
  // Same reasoning as disconnectRef -- handleDataChannelMessage needs to
  // call this from inside a case defined earlier in the file than
  // reportFatalError itself, without making itself get redefined every
  // time reportFatalError's identity changes.
  const reportFatalErrorRef = useRef<(message: string) => void>(() => {});
  const audioElRef = useRef<HTMLAudioElement | null>(null);
  // Real OpenAI-reported usage, accumulated across every response.done event
  // this session sees -- never fabricated; a field this app can't parse just
  // isn't counted (see handleDataChannelMessage's response.done case).
  const totalTokensRef = useRef(0);

  const callTool = useCallback(
    async (name: string, args: Record<string, unknown>): Promise<object> => {
      try {
        switch (name) {
          case "get_board_state":
            return await getBoardState(gameId);
          case "get_last_move_analysis":
            return await getMoveAnalysis(gameId);
          case "explain_move":
            return await getMoveAnalysis(gameId, typeof args.ply === "number" ? args.ply : undefined);
          case "request_hint":
            return await requestHint(gameId);
          case "adjust_explanation_depth":
            await updateExplanationDepth(args.depth === "brief" ? "brief" : "detailed");
            return { ok: true };
          case "get_skill_profile": {
            const profiles = await listSkillProfiles();
            return profiles.find((p) => p.game_type === "chess") ?? { message: "No chess rating yet." };
          }
          default:
            return { error: `unknown tool: ${name}` };
        }
      } catch (err) {
        const code = (err as Error & { code?: string }).code;
        return { error: code ?? "tool_failed", message: err instanceof Error ? err.message : "Tool call failed" };
      }
    },
    [gameId]
  );

  const handleDataChannelMessage = useCallback(
    async (ev: MessageEvent) => {
      let event: Record<string, unknown>;
      try {
        event = JSON.parse(ev.data);
      } catch {
        return;
      }

      switch (event.type) {
        case "input_audio_buffer.speech_started":
          setIsUserSpeaking(true);
          break;

        case "input_audio_buffer.speech_stopped":
          setIsUserSpeaking(false);
          break;

        case "response.output_audio_transcript.delta":
          setIsAssistantSpeaking(true);
          break;

        case "response.done": {
          setIsAssistantSpeaking(false);

          const response = event.response as { output?: Array<Record<string, unknown>>; usage?: { total_tokens?: unknown } };

          // Defensive: this app has never captured Realtime API usage before,
          // and the exact response.usage shape isn't verified against live
          // OpenAI docs here -- only count it if it's genuinely a number,
          // never guess/fabricate a figure.
          const usageTokens = response?.usage?.total_tokens;
          if (typeof usageTokens === "number") {
            totalTokensRef.current += usageTokens;
          }

          const functionCalls = (response?.output ?? []).filter((item) => item.type === "function_call");

          if (functionCalls.length > 0) {
            // Every tool output for this turn must be submitted BEFORE
            // requesting one continuation -- sending response.create after
            // each individual result (the previous version) fires a second
            // response.create while the first is still being processed
            // whenever a turn makes more than one tool call (the tutoring
            // instructions offer several tools, e.g. get_board_state AND
            // explain_move together), which the Realtime API rejects as an
            // `error` event -- one this hook didn't handle at all until now,
            // so the failure was completely silent: the tutor would say its
            // opening line ("let me think this through...") and then never
            // respond again.
            const results = await Promise.all(
              functionCalls.map(async (item) => ({
                callId: item.call_id as string,
                result: await callTool(item.name as string, JSON.parse((item.arguments as string) || "{}")),
              }))
            );

            for (const { callId, result } of results) {
              dcRef.current?.send(
                JSON.stringify({
                  type: "conversation.item.create",
                  item: { type: "function_call_output", call_id: callId, output: JSON.stringify(result) },
                })
              );
            }

            dcRef.current?.send(JSON.stringify({ type: "response.create" }));
          } else {
            // A response with no function call is the tutor's actual spoken
            // answer -- a tool-call round-trip always produces a further
            // response.create above, which yields its own later
            // response.done. This is meant to be one grounded explanation,
            // not an open conversation (see tools.ex's tutoring
            // instructions), so the session should end once it's actually
            // finished playing -- but NOT here: see
            // output_audio_buffer.stopped below and FINAL_ANSWER_GRACE_MS's
            // comment for why reacting to response.done itself clipped most
            // of the explanation instead of just its last words.
            awaitingFinalAudioRef.current = true;
            autoStopTimerRef.current = setTimeout(() => {
              if (awaitingFinalAudioRef.current) disconnectRef.current();
            }, FINAL_ANSWER_FALLBACK_MS);
          }
          break;
        }

        case "output_audio_buffer.stopped": {
          if (awaitingFinalAudioRef.current) {
            awaitingFinalAudioRef.current = false;
            if (autoStopTimerRef.current) clearTimeout(autoStopTimerRef.current);
            autoStopTimerRef.current = setTimeout(() => disconnectRef.current(), FINAL_ANSWER_GRACE_MS);
          }
          break;
        }

        case "error": {
          // Previously unhandled entirely -- any server-side rejection
          // (e.g. the double-response.create case above, or anything else
          // going wrong mid-conversation) vanished with no trace, leaving
          // the player watching a "Connected"/"Explaining..." status that
          // would just never change. Surfacing it needs status: "error"
          // specifically, not "ended" -- VoicePanel renders on every status
          // except "idle"/"ended", so this is what keeps the panel (and the
          // error message) visible instead of silently disappearing the
          // way a normal end-of-explanation disconnect does.
          const apiError = event.error as { message?: string } | undefined;
          reportFatalErrorRef.current(apiError?.message || "The voice tutor hit an unexpected error.");
          break;
        }
      }
    },
    [callTool]
  );

  const cleanup = useCallback(() => {
    if (maxDurationTimerRef.current) clearTimeout(maxDurationTimerRef.current);
    if (autoStopTimerRef.current) clearTimeout(autoStopTimerRef.current);
    dcRef.current?.close();
    pcRef.current?.close();
    streamRef.current?.getTracks().forEach((t) => t.stop());
    dcRef.current = null;
    pcRef.current = null;
    streamRef.current = null;
  }, []);

  const disconnect = useCallback(async () => {
    cleanup();
    const sessionId = sessionIdRef.current;
    sessionIdRef.current = null;
    if (sessionId) {
      await endVoiceSession(sessionId, totalTokensRef.current || undefined).catch(() => {
        // Best-effort -- the session's Redis guard has its own TTL safety net.
      });
    }
    totalTokensRef.current = 0;
    setStatus("ended");
    setIsAssistantSpeaking(false);
    setIsUserSpeaking(false);
  }, [cleanup]);

  useEffect(() => {
    disconnectRef.current = disconnect;
  }, [disconnect]);

  // Like disconnect(), but lands on status "error" with a message instead
  // of "ended" -- see the "error" case in handleDataChannelMessage above
  // for why that distinction matters (it's what keeps VoicePanel visible).
  const reportFatalError = useCallback(
    (message: string) => {
      cleanup();
      const sessionId = sessionIdRef.current;
      sessionIdRef.current = null;
      if (sessionId) {
        endVoiceSession(sessionId, totalTokensRef.current || undefined).catch(() => {
          // Best-effort -- the session's Redis guard has its own TTL safety net.
        });
      }
      totalTokensRef.current = 0;
      setStatus("error");
      setError(message);
      setIsAssistantSpeaking(false);
      setIsUserSpeaking(false);
    },
    [cleanup]
  );

  useEffect(() => {
    reportFatalErrorRef.current = reportFatalError;
  }, [reportFatalError]);

  // The Stop button's action -- unlike the automatic end-of-explanation
  // disconnect above (which waits for output_audio_buffer.stopped, plus a
  // short FINAL_ANSWER_GRACE_MS, to avoid clipping trailing audio), this is
  // a deliberate interrupt: cancel any pending auto-stop, tell OpenAI to
  // stop generating right away, then tear down immediately rather than
  // waiting for anything to finish.
  const stop = useCallback(() => {
    awaitingFinalAudioRef.current = false;
    if (autoStopTimerRef.current) {
      clearTimeout(autoStopTimerRef.current);
      autoStopTimerRef.current = null;
    }
    if (dcRef.current?.readyState === "open") {
      dcRef.current.send(JSON.stringify({ type: "response.cancel" }));
    }
    disconnect();
  }, [disconnect]);

  // Without this, navigating away from the game page (e.g. to start a new
  // game) while a voice session is still connected -- the game just ended,
  // say -- never calls endVoiceSession: the per-user "one active session"
  // Redis guard and the VoiceSession DB row are then only released by the
  // 15-minute safety-net TTL, not immediately, blocking a new session on
  // any game until it expires. Mirrors disconnect()'s teardown, but
  // imperative-only (no setState -- the component is unmounting).
  useEffect(() => {
    return () => {
      cleanup();
      if (sessionIdRef.current) {
        endVoiceSession(sessionIdRef.current, totalTokensRef.current || undefined).catch(() => {
          // Best-effort -- the session's Redis guard has its own TTL safety net.
        });
      }
    };
  }, [cleanup]);

  const connect = useCallback(async () => {
    setError(null);
    totalTokensRef.current = 0;
    awaitingFinalAudioRef.current = false;
    setStatus("requesting-permission");

    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch {
      setStatus("error");
      setError("Microphone permission denied or unavailable.");
      return;
    }
    streamRef.current = stream;

    setStatus("connecting");

    let sessionStart;
    try {
      sessionStart = await startVoiceSession(gameId);
    } catch (err) {
      setStatus("error");
      setError(err instanceof Error ? err.message : "Failed to start voice session");
      stream.getTracks().forEach((t) => t.stop());
      return;
    }
    sessionIdRef.current = sessionStart.session_id;

    const pc = new RTCPeerConnection();
    pcRef.current = pc;

    pc.ontrack = (ev) => {
      if (audioElRef.current) audioElRef.current.srcObject = ev.streams[0];
    };

    stream.getTracks().forEach((track) => pc.addTrack(track, stream));

    const dc = pc.createDataChannel("oai-events");
    dcRef.current = dc;
    dc.onmessage = handleDataChannelMessage;

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    let sdpRes: Response;
    try {
      sdpRes = await fetch("https://api.openai.com/v1/realtime/calls", {
        method: "POST",
        body: offer.sdp,
        headers: {
          Authorization: `Bearer ${sessionStart.ephemeral_key}`,
          "Content-Type": "application/sdp",
        },
      });
    } catch {
      setStatus("error");
      setError("Failed to reach the voice service.");
      cleanup();
      return;
    }

    if (!sdpRes.ok) {
      setStatus("error");
      setError(`Voice connection failed (${sdpRes.status}).`);
      cleanup();
      return;
    }

    const answerSdp = await sdpRes.text();
    await pc.setRemoteDescription({ type: "answer", sdp: answerSdp });

    setStatus("connected");
    maxDurationTimerRef.current = setTimeout(() => {
      disconnect();
    }, sessionStart.max_session_seconds * 1000);
  }, [gameId, handleDataChannelMessage, cleanup, disconnect]);

  // The sole way a session starts -- there's no general-purpose "start voice
  // tutor" entry point, only this: auto-connects (mic permission prompt and
  // all) if no session is live yet, so "Ask tutor why" works as a single
  // click from a cold state, then asks over the data channel, mirroring the
  // exact conversation.item.create + response.create shape already used for
  // tool-call results above.
  const askAboutMove = useCallback(
    async (text: string) => {
      if (dcRef.current?.readyState !== "open") {
        await connect();
        if (!(await waitForOpenChannel(dcRef))) return;
      }

      dcRef.current?.send(
        JSON.stringify({
          type: "conversation.item.create",
          item: { type: "message", role: "user", content: [{ type: "input_text", text }] },
        })
      );
      dcRef.current?.send(JSON.stringify({ type: "response.create" }));
    },
    [connect]
  );

  return {
    status,
    error,
    isAssistantSpeaking,
    isUserSpeaking,
    disconnect,
    stop,
    askAboutMove,
    audioElRef,
  };
}
