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
};

export type GameSummary = {
  id: string;
  game_type: string;
  status: string;
  result: string | null;
  is_calibration: boolean;
  opponent_engine_config: Record<string, unknown>;
  started_at: string;
  ended_at: string | null;
};

export type Game = GameSummary & {
  fen: string;
  moves: Move[];
};

export type MoveResult = {
  game: GameSummary;
  fen: string;
  human_move: Move;
  engine_move: Move | null;
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

export async function createGame(opts: { opponentElo?: number; isCalibration?: boolean } = {}): Promise<Game> {
  const res = await apiFetch("/api/games", {
    method: "POST",
    body: JSON.stringify({
      opponent_elo: opts.opponentElo,
      is_calibration: opts.isCalibration ?? false,
    }),
  });
  return asJson<Game>(res);
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
