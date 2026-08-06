"use client";

import { useCallback, useRef, useState } from "react";
import { startVoiceSession, endVoiceSession } from "./voice-api";
import { getBoardState, getMoveAnalysis, requestHint, updateExplanationDepth, listSkillProfiles } from "./games-api";

export type VoiceStatus = "idle" | "requesting-permission" | "connecting" | "connected" | "ended" | "error";

export type TranscriptEntry = { role: "assistant"; text: string };

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
  const [transcript, setTranscript] = useState<TranscriptEntry[]>([]);
  const [isAssistantSpeaking, setIsAssistantSpeaking] = useState(false);
  const [isUserSpeaking, setIsUserSpeaking] = useState(false);

  const pcRef = useRef<RTCPeerConnection | null>(null);
  const dcRef = useRef<RTCDataChannel | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const sessionIdRef = useRef<string | null>(null);
  const maxDurationTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const currentUtteranceRef = useRef("");
  const audioElRef = useRef<HTMLAudioElement | null>(null);

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
          currentUtteranceRef.current += (event.delta as string) ?? "";
          break;

        case "response.done": {
          setIsAssistantSpeaking(false);
          if (currentUtteranceRef.current) {
            setTranscript((prev) => [...prev, { role: "assistant", text: currentUtteranceRef.current }]);
            currentUtteranceRef.current = "";
          }

          const response = event.response as { output?: Array<Record<string, unknown>> };
          for (const item of response?.output ?? []) {
            if (item.type === "function_call") {
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
          break;
        }
      }
    },
    [callTool]
  );

  const cleanup = useCallback(() => {
    if (maxDurationTimerRef.current) clearTimeout(maxDurationTimerRef.current);
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
      await endVoiceSession(sessionId).catch(() => {
        // Best-effort -- the session's Redis guard has its own TTL safety net.
      });
    }
    setStatus("ended");
    setIsAssistantSpeaking(false);
    setIsUserSpeaking(false);
  }, [cleanup]);

  const connect = useCallback(async () => {
    setError(null);
    setTranscript([]);
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

  return {
    status,
    error,
    transcript,
    isAssistantSpeaking,
    isUserSpeaking,
    connect,
    disconnect,
    audioElRef,
  };
}
