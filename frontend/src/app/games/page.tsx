"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { ProtectedRoute } from "@/lib/protected-route";
import { createGame, listGames, listSkillProfiles, GameSummary, SkillProfile } from "@/lib/games-api";
import {
  pageWrap,
  navBar,
  navBrand,
  navBrandAccent,
  card,
  pageTitle,
  mutedText,
  buttonPrimary,
  buttonSecondary,
  linkButton,
  segmentedGroup,
  segmentedOption,
} from "@/lib/auth-ui";

function statusLabel(game: GameSummary): string {
  if (game.status === "in_progress") return "In progress";
  if (!game.result) return game.status;
  const winner = game.result === `${game.human_color}_wins` ? "You won" : game.result === "draw" ? "Draw" : "Engine won";
  return `${game.status} -- ${winner}`;
}

// The traditional "student" role games_tutor gives the human by default in
// each game -- White in chess, Black in Go (mirrors the backend's own
// default_human_color/1) -- used to reset the color picker when switching
// game types.
function defaultColorFor(gameType: "chess" | "go"): "white" | "black" {
  return gameType === "go" ? "black" : "white";
}

function GamesContent() {
  const router = useRouter();
  const [gameType, setGameType] = useState<"chess" | "go">("chess");
  const [humanColor, setHumanColor] = useState<"white" | "black">(defaultColorFor("chess"));
  const [games, setGames] = useState<GameSummary[] | null>(null);
  const [profiles, setProfiles] = useState<SkillProfile[]>([]);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [selfReportedElo, setSelfReportedElo] = useState("");

  const changeGameType = (type: "chess" | "go") => {
    setGameType(type);
    setHumanColor(defaultColorFor(type));
  };

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
      const game = await createGame({ gameType, humanColor, ...opts });
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
    <div className={pageWrap}>
      <header className={navBar}>
        <a href="/dashboard" className={navBrand}>
          games<span className={navBrandAccent}>_tutor</span>
        </a>
        <a href="/dashboard" className={linkButton}>
          Back to dashboard
        </a>
      </header>

      <main className="max-w-5xl mx-auto grid gap-6">
        <section className={card}>
          <h1 className={pageTitle}>New game</h1>

          <div className="flex flex-wrap gap-6 mb-5">
            <div>
              <div className={`${mutedText} mb-2`}>Game</div>
              <div className={segmentedGroup}>
                <button className={segmentedOption(gameType === "chess")} onClick={() => changeGameType("chess")}>
                  Chess
                </button>
                <button className={segmentedOption(gameType === "go")} onClick={() => changeGameType("go")}>
                  Go
                </button>
              </div>
            </div>

            <div>
              <div className={`${mutedText} mb-2`}>Play as</div>
              <div className={segmentedGroup}>
                <button className={segmentedOption(humanColor === "white")} onClick={() => setHumanColor("white")}>
                  White
                </button>
                <button className={segmentedOption(humanColor === "black")} onClick={() => setHumanColor("black")}>
                  Black
                </button>
              </div>
              {gameType === "go" && <div className={`${mutedText} mt-1`}>Black moves first</div>}
            </div>
          </div>

          {profile && (
            <p className={`${mutedText} mb-5`}>
              Estimated {gameType} rating: <strong className="text-zinc-900 dark:text-zinc-50">{profile.estimated_rating}</strong> (
              {profile.display_label}) -- based on {profile.games_count} calibration game{profile.games_count === 1 ? "" : "s"}
            </p>
          )}

          <div className="flex flex-wrap gap-3">
            <button onClick={() => startGame({})} disabled={creating} className={buttonPrimary}>
              {creating ? "Starting..." : `New game vs. ${opponentName}`}
            </button>
            <button onClick={handleRateMyPlay} disabled={creating} className={buttonSecondary}>
              Rate my play
            </button>
          </div>

          {showOnboarding && (
            <div className="mt-4 rounded-lg border border-zinc-200 dark:border-zinc-800 p-4 max-w-md">
              <p className={mutedText}>
                Roughly what&apos;s your {gameType} rating, if you know it? This just gives the tutor a better starting guess --
                skip it if you&apos;re not sure.
              </p>
              <div className="flex gap-2 mt-3">
                <input
                  type="number"
                  placeholder="e.g. 1200"
                  value={selfReportedElo}
                  onChange={(e) => setSelfReportedElo(e.target.value)}
                  className="w-32 rounded-lg border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-800 px-3 py-1.5 text-sm text-zinc-900 dark:text-zinc-100"
                />
                <button
                  onClick={() =>
                    startGame({
                      isCalibration: true,
                      selfReportedElo: selfReportedElo ? parseInt(selfReportedElo, 10) : undefined,
                    })
                  }
                  disabled={creating}
                  className={buttonPrimary}
                >
                  Start
                </button>
              </div>
            </div>
          )}

          {error && <p className="mt-4 text-sm text-red-600 dark:text-red-400">{error}</p>}
        </section>

        <section className={card}>
          <h2 className="text-sm font-semibold text-zinc-900 dark:text-zinc-50 mb-3">Your games</h2>
          {games === null ? (
            <p className={mutedText}>Loading...</p>
          ) : games.length === 0 ? (
            <p className={mutedText}>No games yet.</p>
          ) : (
            <ul className="flex flex-col gap-2">
              {games.map((game) => (
                <li key={game.id}>
                  <a
                    href={`/games/${game.id}`}
                    className="flex items-center justify-between rounded-lg border border-zinc-200 dark:border-zinc-800 px-4 py-3 hover:bg-zinc-50 dark:hover:bg-zinc-800/50 transition-colors"
                  >
                    <span className="text-sm text-zinc-900 dark:text-zinc-50">
                      {game.game_type} -- {statusLabel(game)}
                      {game.is_calibration ? " (rate my play)" : ""}
                    </span>
                    <span className={mutedText}>{new Date(game.started_at).toLocaleString()}</span>
                  </a>
                </li>
              ))}
            </ul>
          )}
        </section>
      </main>
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
