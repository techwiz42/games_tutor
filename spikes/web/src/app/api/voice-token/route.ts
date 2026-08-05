// Phase 0 spike only: mints an OpenAI Realtime ephemeral client secret.
// In Phase 4 this becomes a real, JWT-authenticated FastAPI endpoint
// (POST /api/voice/session) -- this Next.js route exists purely so the
// spike doesn't need a whole backend stood up first.
import { NextResponse } from "next/server";

const TOOLS = [
  {
    type: "function",
    name: "get_spike_status",
    description:
      "Returns a fixed status string from the games_tutor Phase 0 spike backend. " +
      "Call this when the user asks you to check the spike status.",
    parameters: {
      type: "object",
      properties: {},
      required: [],
    },
  },
];

export async function GET() {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return NextResponse.json(
      { error: "OPENAI_API_KEY not set on server" },
      { status: 500 }
    );
  }

  const response = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      session: {
        type: "realtime",
        model: "gpt-realtime-2.1-mini",
        instructions:
          "You are a spike/smoke-test voice agent for a project called games_tutor. " +
          "Greet the user briefly, confirm you can hear them, and mention you have one " +
          "tool available called get_spike_status. If asked to check status, call it.",
        audio: { output: { voice: "marin" } },
        tools: TOOLS,
        tool_choice: "auto",
      },
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    return NextResponse.json(
      { error: `OpenAI client_secrets request failed: ${response.status} ${text}` },
      { status: 500 }
    );
  }

  const data = await response.json();
  return NextResponse.json(data);
}
