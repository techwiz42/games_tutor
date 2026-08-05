"use client";

import { useRef, useState } from "react";

type LogEntry = { t: string; msg: string };

export default function VoiceSpike() {
  const [status, setStatus] = useState("idle");
  const [log, setLog] = useState<LogEntry[]>([]);
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const dcRef = useRef<RTCDataChannel | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  const appendLog = (msg: string) =>
    setLog((prev) => [...prev, { t: new Date().toLocaleTimeString(), msg }].slice(-100));

  // The one spike tool: returns a fixed string. Proves the full round trip --
  // model decides to call it, browser dispatches it, model narrates the result.
  const callTool = async (name: string, _args: Record<string, unknown>): Promise<string> => {
    if (name === "get_spike_status") {
      return JSON.stringify({
        status: "ok",
        message: "games_tutor Phase 0 voice spike tool call succeeded.",
      });
    }
    return JSON.stringify({ error: `unknown tool: ${name}` });
  };

  const handleDataChannelMessage = async (ev: MessageEvent) => {
    let event: Record<string, unknown>;
    try {
      event = JSON.parse(ev.data);
    } catch {
      return;
    }

    appendLog(`event: ${event.type}`);

    if (event.type === "response.done") {
      const response = event.response as { output?: Array<Record<string, unknown>> };
      const output = response?.output ?? [];
      for (const item of output) {
        if (item.type === "function_call") {
          const callId = item.call_id as string;
          const name = item.name as string;
          const args = JSON.parse((item.arguments as string) || "{}");
          appendLog(`>>> tool call requested: ${name}(${JSON.stringify(args)})`);

          const result = await callTool(name, args);
          appendLog(`<<< tool result: ${result}`);

          dcRef.current?.send(
            JSON.stringify({
              type: "conversation.item.create",
              item: {
                type: "function_call_output",
                call_id: callId,
                output: result,
              },
            })
          );
          dcRef.current?.send(JSON.stringify({ type: "response.create" }));
        }
      }
    }
  };

  const connect = async () => {
    setStatus("requesting mic permission...");
    setLog([]);

    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch (e) {
      setStatus(`mic permission denied or unavailable: ${e}`);
      return;
    }

    setStatus("minting ephemeral token...");
    const tokenRes = await fetch("/api/voice-token");
    const tokenData = await tokenRes.json();
    if (!tokenRes.ok) {
      setStatus(`token mint failed: ${JSON.stringify(tokenData)}`);
      return;
    }
    const ephemeralKey = tokenData.value as string;
    appendLog("ephemeral token minted");

    setStatus("connecting WebRTC...");
    const pc = new RTCPeerConnection();
    pcRef.current = pc;

    pc.ontrack = (ev) => {
      if (audioRef.current) {
        audioRef.current.srcObject = ev.streams[0];
      }
      appendLog("remote audio track attached");
    };

    stream.getTracks().forEach((track) => pc.addTrack(track, stream));

    const dc = pc.createDataChannel("oai-events");
    dcRef.current = dc;
    dc.onopen = () => appendLog("data channel open");
    dc.onmessage = handleDataChannelMessage;

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    const sdpRes = await fetch("https://api.openai.com/v1/realtime/calls", {
      method: "POST",
      body: offer.sdp,
      headers: {
        Authorization: `Bearer ${ephemeralKey}`,
        "Content-Type": "application/sdp",
      },
    });

    if (!sdpRes.ok) {
      const text = await sdpRes.text();
      setStatus(`SDP exchange failed: ${sdpRes.status} ${text}`);
      return;
    }

    const answerSdp = await sdpRes.text();
    await pc.setRemoteDescription({ type: "answer", sdp: answerSdp });

    setStatus("connected");
    appendLog("WebRTC connected -- listening");
  };

  const askForStatus = () => {
    // Deterministic trigger for the tool-calling round trip -- headless/fake-audio
    // testing can't reliably rely on the model choosing to call a tool from
    // synthetic mic noise alone, so send an explicit text turn instead.
    dcRef.current?.send(
      JSON.stringify({
        type: "conversation.item.create",
        item: {
          type: "message",
          role: "user",
          content: [{ type: "input_text", text: "Please check and tell me the spike status." }],
        },
      })
    );
    dcRef.current?.send(JSON.stringify({ type: "response.create" }));
  };

  const disconnect = () => {
    dcRef.current?.close();
    pcRef.current?.close();
    pcRef.current = null;
    dcRef.current = null;
    setStatus("disconnected");
  };

  return (
    <div style={{ padding: 24, fontFamily: "sans-serif", maxWidth: 700 }}>
      <h1>OpenAI Realtime voice spike</h1>
      <p>
        Confirms: ephemeral token minting, browser WebRTC connection, and a full
        tool-calling round trip (model calls <code>get_spike_status</code>, browser
        answers, model narrates the result).
      </p>
      <p>
        Status: <strong>{status}</strong>
      </p>
      <div style={{ display: "flex", gap: 8, marginBottom: 16 }}>
        <button onClick={connect} disabled={status === "connected"}>
          Connect
        </button>
        <button onClick={disconnect} disabled={status !== "connected"}>
          Disconnect
        </button>
        <button onClick={askForStatus} disabled={status !== "connected"}>
          Ask for status (triggers tool call)
        </button>
      </div>
      <audio ref={audioRef} autoPlay />
      <h3>Event log</h3>
      <div
        style={{
          background: "#111",
          color: "#0f0",
          padding: 12,
          fontFamily: "monospace",
          fontSize: 12,
          height: 400,
          overflowY: "auto",
          whiteSpace: "pre-wrap",
        }}
      >
        {log.map((entry, i) => (
          <div key={i}>
            [{entry.t}] {entry.msg}
          </div>
        ))}
      </div>
    </div>
  );
}
