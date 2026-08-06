"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { startVoiceSession, endVoiceSession } from "./voice-api";
import { getBoardState, getMoveAnalysis, requestHint, updateExplanationDepth, listSkillProfiles } from "./games-api";

export type VoiceStatus = "idle" | "requesting-permission" | "connecting" | "connected" | "ended" | "error";

// How long to wait after OpenAI reports a response done before actually
// tearing down the connection -- response.done means generation finished
// server-side, not that the last audio frames have finished draining out of
// the <audio> element's playback buffer. Cutting the connection immediately
// clips the last words of the explanation.
const EXPLANATION_END_GRACE_MS = 1500;

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
  // Populated once `disconnect` exists (see the effect right after its
  // definition) -- handleDataChannelMessage needs to call it from inside a
  // response.done handler defined earlier in the file, without making
  // itself (and therefore dc.onmessage) get redefined every time
  // `disconnect`'s identity changes.
  const disconnectRef = useRef<() => void>(() => {});
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

          let hadFunctionCall = false;
          for (const item of response?.output ?? []) {
            if (item.type === "function_call") {
              hadFunctionCall = true;
              const callId = item.call_id as string;
              const name = item.name as string;
              const args = JSON.parse((item.arguments as string) || "{}");
              const result = await callTool(name, args);

              dcRef.current?.send(
                JSON.stringify({
                  type: "conversation.item.create",
                  item: { type: "function_call_output", call_id: callId, output: JSON.stringify(result) },
                })
              );
              dcRef.current?.send(JSON.stringify({ type: "response.create" }));
            }
          }

          // A response with no function call is the tutor's actual spoken
          // answer -- a tool-call round-trip always produces a further
          // response.create above, which yields its own later response.done.
          // This is meant to be one grounded explanation, not an open
          // conversation (see tools.ex's tutoring instructions), so end the
          // session once it lands rather than sitting connected/listening.
          if (!hadFunctionCall) {
            autoStopTimerRef.current = setTimeout(() => disconnectRef.current(), EXPLANATION_END_GRACE_MS);
          }
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

  // The Stop button's action -- unlike the automatic end-of-explanation
  // disconnect above (which waits EXPLANATION_END_GRACE_MS to avoid clipping
  // trailing audio), this is a deliberate interrupt: cancel any pending
  // auto-stop, tell OpenAI to stop generating right away, then tear down
  // immediately rather than waiting for anything to finish.
  const stop = useCallback(() => {
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
