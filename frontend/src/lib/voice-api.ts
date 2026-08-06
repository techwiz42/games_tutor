import { apiFetch } from "./api";

export type VoiceSessionStart = {
  session_id: string;
  mode: "calibration_proctor" | "tutoring";
  model: string;
  ephemeral_key: string;
  expires_at: number | null;
  max_session_seconds: number;
};

export type VoiceSessionEnd = {
  session_id: string;
  status: string;
  duration_seconds: number;
  estimated_cost_usd: number;
};

async function asJson<T>(res: Response): Promise<T> {
  const data = await res.json();
  if (!res.ok) {
    const error = new Error(data.detail || "Request failed") as Error & { code?: string };
    error.code = data.code;
    throw error;
  }
  return data as T;
}

export async function startVoiceSession(gameId: string): Promise<VoiceSessionStart> {
  const res = await apiFetch("/api/voice/session", {
    method: "POST",
    body: JSON.stringify({ game_id: gameId }),
  });
  return asJson<VoiceSessionStart>(res);
}

export async function endVoiceSession(sessionId: string): Promise<VoiceSessionEnd> {
  const res = await apiFetch(`/api/voice/session/${sessionId}/end`, { method: "POST" });
  return asJson<VoiceSessionEnd>(res);
}
