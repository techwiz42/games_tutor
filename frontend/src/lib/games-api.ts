import { apiFetch } from "./api";

export type Move = {
  ply: number;
  player: "human" | "engine";
  notation: string;
  uci: string;
  fen_after: string;
  eval_before: number | null;
  eval_after: number | null;
  loss: number | null;
  engine_best_move: string | null;
  classification: string | null;
  think_time_ms: number | null;
  // Go only -- KataGo's raw policy-network prior (0.0-1.0) for the move as
  // played; null for chess and for Go moves recorded before this existed.
  prior: number | null;
};

export type GameSummary = {
  id: string;
  game_type: "chess" | "go";
  status: string;
  result: string | null;
  // Which board color the human plays -- "white" in chess, "black" in Go
  // (see GamesTutor.Games's moduledoc). Needed to interpret `result`
  // ("white_wins"/"black_wins") as "you won" vs. "engine won".
  human_color: "white" | "black";
  is_calibration: boolean;
  opponent_engine_config: Record<string, unknown>;
  started_at: string;
  ended_at: string | null;
};

export type SkillProfile = {
  game_type: string;
  estimated_rating: number;
  rating_sigma: number;
  display_label: string;
  games_count: number;
};

export type Game = GameSummary & {
  fen: string;
  moves: Move[];
  skill_profile?: SkillProfile | null;
};

export type MoveResult = {
  game: GameSummary;
  fen: string;
  human_move: Move;
  engine_move: Move | null;
  skill_profile: SkillProfile | null;
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

export async function listGames(): Promise<GameSummary[]> {
  const res = await apiFetch("/api/games");
  const data = await asJson<{ games: GameSummary[] }>(res);
  return data.games;
}

export async function createGame(
  opts: {
    gameType?: "chess" | "go";
    opponentElo?: number;
    opponentMaxVisits?: number;
    isCalibration?: boolean;
    selfReportedElo?: number;
    humanColor?: "white" | "black";
  } = {}
): Promise<Game> {
  const res = await apiFetch("/api/games", {
    method: "POST",
    body: JSON.stringify({
      game_type: opts.gameType ?? "chess",
      opponent_elo: opts.opponentElo,
      opponent_max_visits: opts.opponentMaxVisits,
      is_calibration: opts.isCalibration ?? false,
      self_reported_elo: opts.selfReportedElo,
      human_color: opts.humanColor,
    }),
  });
  return asJson<Game>(res);
}

export async function listSkillProfiles(): Promise<SkillProfile[]> {
  const res = await apiFetch("/api/skill-profiles");
  const data = await asJson<{ skill_profiles: SkillProfile[] }>(res);
  return data.skill_profiles;
}

export async function getGame(id: string): Promise<Game> {
  const res = await apiFetch(`/api/games/${id}`);
  return asJson<Game>(res);
}

export async function submitMove(id: string, uci: string): Promise<MoveResult> {
  const res = await apiFetch(`/api/games/${id}/moves`, {
    method: "POST",
    body: JSON.stringify({ move: uci }),
  });
  return asJson<MoveResult>(res);
}

export async function resignGame(id: string): Promise<Game> {
  const res = await apiFetch(`/api/games/${id}/resign`, { method: "POST" });
  return asJson<Game>(res);
}

export async function undoMove(id: string): Promise<Game> {
  const res = await apiFetch(`/api/games/${id}/undo`, { method: "POST" });
  return asJson<Game>(res);
}

export async function deleteGame(id: string): Promise<void> {
  const res = await apiFetch(`/api/games/${id}`, { method: "DELETE" });
  await asJson(res);
}

export type BoardState = {
  fen: string;
  status: string;
  result: string | null;
  to_move: "human" | "engine" | null;
  is_calibration: boolean;
};

export async function getBoardState(id: string): Promise<BoardState> {
  const res = await apiFetch(`/api/games/${id}/board-state`);
  return asJson<BoardState>(res);
}

export async function getMoveAnalysis(id: string, ply?: number): Promise<Move> {
  const query = ply ? `?ply=${ply}` : "";
  const res = await apiFetch(`/api/games/${id}/move-analysis${query}`);
  return asJson<Move>(res);
}

export async function requestHint(id: string): Promise<{ move: string }> {
  const res = await apiFetch(`/api/games/${id}/hint`, { method: "POST" });
  return asJson<{ move: string }>(res);
}

export async function updateExplanationDepth(depth: "brief" | "detailed"): Promise<void> {
  const res = await apiFetch("/api/user-settings", {
    method: "PATCH",
    body: JSON.stringify({ default_explanation_depth: depth }),
  });
  await asJson(res);
}
