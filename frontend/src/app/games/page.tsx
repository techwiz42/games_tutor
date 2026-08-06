"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { ProtectedRoute } from "@/lib/protected-route";
import { createGame, listGames, GameSummary } from "@/lib/games-api";

function statusLabel(game: GameSummary): string {
  if (game.status === "in_progress") return "In progress";
  if (!game.result) return game.status;
  const winner = game.result === "white_wins" ? "You won" : game.result === "black_wins" ? "Engine won" : "Draw";
  return `${game.status} -- ${winner}`;
}

function GamesContent() {
  const router = useRouter();
  const [games, setGames] = useState<GameSummary[] | null>(null);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    listGames()
      .then(setGames)
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load games"));
  }, []);

  const handleNewGame = async () => {
    setCreating(true);
    setError(null);
    try {
      const game = await createGame();
      router.push(`/games/${game.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create game");
      setCreating(false);
    }
  };

  return (
    <div style={{ maxWidth: 640, margin: "40px auto", padding: 24 }}>
      <h1>Games</h1>
      <button onClick={handleNewGame} disabled={creating}>
        {creating ? "Starting..." : "New game vs. Stockfish"}
      </button>
      {error && <p style={{ color: "red" }}>{error}</p>}

      {games === null ? (
        <p>Loading...</p>
      ) : games.length === 0 ? (
        <p style={{ opacity: 0.6, marginTop: 16 }}>No games yet.</p>
      ) : (
        <ul style={{ listStyle: "none", padding: 0, marginTop: 16 }}>
          {games.map((game) => (
            <li key={game.id} style={{ borderBottom: "1px solid #ddd", padding: "12px 0" }}>
              <a href={`/games/${game.id}`}>
                {game.game_type} -- {statusLabel(game)}
                {game.is_calibration ? " (rate my play)" : ""}
              </a>
              <div style={{ fontSize: 12, opacity: 0.6 }}>{new Date(game.started_at).toLocaleString()}</div>
            </li>
          ))}
        </ul>
      )}

      <p style={{ marginTop: 24 }}>
        <a href="/dashboard">Back to dashboard</a>
      </p>
    </div>
  );
}

export default function GamesPage() {
  return (
    <ProtectedRoute>
      <GamesContent />
    </ProtectedRoute>
  );
}
