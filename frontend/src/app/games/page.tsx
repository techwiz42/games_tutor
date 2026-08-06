"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { ProtectedRoute } from "@/lib/protected-route";
import { createGame, listGames, listSkillProfiles, GameSummary, SkillProfile } from "@/lib/games-api";

function statusLabel(game: GameSummary): string {
  if (game.status === "in_progress") return "In progress";
  if (!game.result) return game.status;
  const winner = game.result === `${game.human_color}_wins` ? "You won" : game.result === "draw" ? "Draw" : "Engine won";
  return `${game.status} -- ${winner}`;
}

function GamesContent() {
  const router = useRouter();
  const [gameType, setGameType] = useState<"chess" | "go">("chess");
  const [games, setGames] = useState<GameSummary[] | null>(null);
  const [profiles, setProfiles] = useState<SkillProfile[]>([]);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [selfReportedElo, setSelfReportedElo] = useState("");

  useEffect(() => {
    listGames()
      .then(setGames)
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load games"));
    listSkillProfiles()
      .then(setProfiles)
      .catch(() => {
        // Non-critical -- the games list is the primary content of this page.
      });
  }, []);

  const startGame = async (opts: { isCalibration?: boolean; selfReportedElo?: number }) => {
    setCreating(true);
    setError(null);
    try {
      const game = await createGame({ gameType, ...opts });
      router.push(`/games/${game.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create game");
      setCreating(false);
    }
  };

  const handleRateMyPlay = () => {
    const hasProfile = profiles.some((p) => p.game_type === gameType);
    if (hasProfile) {
      startGame({ isCalibration: true });
    } else {
      setShowOnboarding(true);
    }
  };

  const profile = profiles.find((p) => p.game_type === gameType);
  const opponentName = gameType === "chess" ? "Stockfish" : "KataGo";

  return (
    <div style={{ maxWidth: 640, margin: "40px auto", padding: 24 }}>
      <h1>Games</h1>

      <div style={{ display: "flex", gap: 12, marginBottom: 16 }}>
        <label>
          <input type="radio" checked={gameType === "chess"} onChange={() => setGameType("chess")} /> Chess
        </label>
        <label>
          <input type="radio" checked={gameType === "go"} onChange={() => setGameType("go")} /> Go
        </label>
      </div>

      {profile && (
        <p style={{ opacity: 0.75 }}>
          Estimated {gameType} rating: <strong>{profile.estimated_rating}</strong> ({profile.display_label})
          {" -- "}
          based on {profile.games_count} calibration game{profile.games_count === 1 ? "" : "s"}
        </p>
      )}

      <div style={{ display: "flex", gap: 12 }}>
        <button onClick={() => startGame({})} disabled={creating}>
          {creating ? "Starting..." : `New game vs. ${opponentName}`}
        </button>
        <button onClick={handleRateMyPlay} disabled={creating}>
          Rate my play
        </button>
      </div>

      {showOnboarding && (
        <div style={{ marginTop: 12, padding: 12, border: "1px solid #ccc", maxWidth: 420 }}>
          <p>
            Roughly what&apos;s your {gameType} rating, if you know it? This just gives the tutor a better starting
            guess -- skip it if you&apos;re not sure.
          </p>
          <input
            type="number"
            placeholder="e.g. 1200"
            value={selfReportedElo}
            onChange={(e) => setSelfReportedElo(e.target.value)}
            style={{ marginRight: 8 }}
          />
          <button
            onClick={() =>
              startGame({
                isCalibration: true,
                selfReportedElo: selfReportedElo ? parseInt(selfReportedElo, 10) : undefined,
              })
            }
            disabled={creating}
          >
            Start
          </button>
        </div>
      )}

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
