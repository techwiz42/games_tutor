"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import { useParams } from "next/navigation";
import dynamic from "next/dynamic";
import { Chessboard } from "react-chessboard";
import type { PieceDropHandlerArgs } from "react-chessboard";
import { ProtectedRoute } from "@/lib/protected-route";
import { getGame, submitMove, resignGame, undoMove, Game, Move, SkillProfile } from "@/lib/games-api";
import { useRealtimeVoiceSession, VoiceStatus } from "@/lib/use-realtime-voice-session";
import {
  pageWrap,
  navBar,
  navBrand,
  navBrandAccent,
  card,
  buttonSecondary,
  buttonDanger,
  linkButton,
  mutedText,
  classificationBadgeClass,
} from "@/lib/auth-ui";

// Shudan's render is non-deterministic between server and client passes (an
// internal `random` prop for fuzzy stone placement), which causes a
// hydration mismatch under Next.js's default SSR -- confirmed in the Phase
// 0 spike. A Go board has no SSR/SEO value anyway; render it client-only.
const GoBoardPanel = dynamic(() => import("./GoBoardPanel"), { ssr: false });

function resultLabel(game: Game): string {
  if (game.status === "in_progress") return "In progress";
  if (!game.result) return game.status;
  const winner = game.result === `${game.human_color}_wins` ? "You won" : game.result === "draw" ? "Draw" : "Engine won";
  return `${game.status} -- ${winner}`;
}

function CalibrationSummary({ profile }: { profile: SkillProfile }) {
  const hedge =
    profile.games_count <= 1
      ? "This is a first, rough estimate -- it'll sharpen as you play more \"rate my play\" games."
      : `Based on ${profile.games_count} calibration games so far -- still improving with each one.`;

  return (
    <div className={`${card} mt-4`}>
      <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-50 mb-1">Rate my play: result</h3>
      <p className="text-zinc-900 dark:text-zinc-50">
        Estimated rating: <strong>{profile.estimated_rating}</strong> ({profile.display_label})
      </p>
      <p className={`${mutedText} mt-1`}>{hedge}</p>
    </div>
  );
}

type VoiceHook = {
  status: VoiceStatus;
  error: string | null;
  isAssistantSpeaking: boolean;
  isUserSpeaking: boolean;
  disconnect: () => void;
  stop: () => void;
  audioElRef: React.RefObject<HTMLAudioElement | null>;
};

// Presentational only -- the hook itself is lifted into GameContent so
// MoveRow's "Ask tutor why" links can call askAboutMove, the sole way a
// session starts (no general-purpose "start voice tutor" entry point).
// Voice-only (no on-screen transcript) and transient: renders nothing at
// rest, appears for the duration of one spoken explanation, then
// disappears again once use-realtime-voice-session.ts's auto-stop (or the
// Stop button below) ends the session -- there's no persistent "voice
// tutor" panel sitting on the page.
function VoicePanel({ voice, gameInProgress }: { voice: VoiceHook; gameInProgress: boolean }) {
  const { status, error, isAssistantSpeaking, isUserSpeaking, disconnect, stop, audioElRef } = voice;
  const wasInProgressRef = useRef(gameInProgress);

  // End the voice session if the game ends WHILE a conversation is live,
  // rather than sitting connected (mic still hot) indefinitely just
  // because the player hasn't navigated away yet. Must be an edge check
  // (was in progress, just ended), not "is it in progress right now" --
  // "Ask tutor why" is also offered on already-finished games (reviewing
  // a past mistake after resigning/scoring), where gameInProgress is
  // false from the moment the session starts; a static check fired the
  // instant status reached "connected", disconnecting before the tutor
  // had said anything.
  useEffect(() => {
    const wasInProgress = wasInProgressRef.current;
    wasInProgressRef.current = gameInProgress;

    if (wasInProgress && !gameInProgress && status === "connected") {
      disconnect();
    }
  }, [gameInProgress, status, disconnect]);

  if (status === "idle" || status === "ended") return null;

  const statusLabel = {
    "requesting-permission": "Requesting microphone permission...",
    connecting: "Connecting...",
    connected: isAssistantSpeaking ? "Explaining..." : isUserSpeaking ? "Listening..." : "Connected",
    error: "Error",
  }[status];

  return (
    <div className={`${card} mt-4`}>
      <div className="flex items-center justify-between">
        <p className={mutedText}>{statusLabel}</p>
        <button onClick={stop} className={buttonSecondary}>
          Stop
        </button>
      </div>
      {error && <p className="text-sm text-red-600 dark:text-red-400 mt-1">{error}</p>}

      <audio ref={audioElRef} autoPlay />
    </div>
  );
}

function MoveRow({ move, onAskWhy }: { move: Move; onAskWhy: (move: Move) => void }) {
  const askable = move.player === "human" && !!move.classification && move.classification !== "best";

  return (
    <tr className="border-b border-zinc-100 dark:border-zinc-800/60 last:border-0">
      <td className="px-2 py-1.5 text-zinc-500 dark:text-zinc-400">{move.ply}</td>
      <td className="px-2 py-1.5 text-zinc-700 dark:text-zinc-300">{move.player === "human" ? "You" : "Engine"}</td>
      <td className="px-2 py-1.5 font-mono text-zinc-900 dark:text-zinc-50">{move.notation}</td>
      <td className="px-2 py-1.5">{move.classification && <span className={classificationBadgeClass(move.classification)}>{move.classification}</span>}</td>
      <td className="px-2 py-1.5 text-zinc-500 dark:text-zinc-400">{move.loss ?? "--"}</td>
      <td className="px-2 py-1.5">
        {askable && (
          <button onClick={() => onAskWhy(move)} className={linkButton}>
            Ask tutor why
          </button>
        )}
      </td>
    </tr>
  );
}

function GameContent() {
  const { id } = useParams<{ id: string }>();
  const [game, setGame] = useState<Game | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const voice = useRealtimeVoiceSession(id);
  const movesScrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    getGame(id)
      .then(setGame)
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load game"));
  }, [id]);

  // Keep the most recent move in view as the game grows, rather than
  // requiring a scroll every move -- the moves panel below has a fixed
  // height (see its className) specifically so this scrolls the panel
  // itself, not the whole page.
  useEffect(() => {
    const el = movesScrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [game?.moves.length]);

  const submitMoveAndUpdate = useCallback(
    (moveStr: string) => {
      setSubmitting(true);
      setError(null);
      submitMove(id, moveStr)
        .then((result) => {
          setGame((prev) =>
            prev
              ? {
                  ...prev,
                  ...result.game,
                  fen: result.fen,
                  moves: [...prev.moves, result.human_move, ...(result.engine_move ? [result.engine_move] : [])],
                  skill_profile: result.skill_profile,
                }
              : prev
          );
        })
        .catch((err) => {
          setError(err instanceof Error ? err.message : "Move failed");
        })
        .finally(() => setSubmitting(false));
    },
    [id]
  );

  const handleDrop = useCallback(
    ({ piece, sourceSquare, targetSquare }: PieceDropHandlerArgs) => {
      if (!targetSquare || submitting || !game || game.status !== "in_progress") return false;

      // Auto-queen promotion (v1 simplification -- no promotion picker yet).
      // Which pawn/rank promotes depends on which color the human is
      // playing: White pawns promote on rank 8, Black pawns on rank 1.
      const humanPawn = game.human_color === "black" ? "bP" : "wP";
      const promotionRank = game.human_color === "black" ? "1" : "8";
      const isPromotion = piece.pieceType === humanPawn && targetSquare[1] === promotionRank;
      const uci = `${sourceSquare}${targetSquare}${isPromotion ? "q" : ""}`;
      submitMoveAndUpdate(uci);

      // Optimistic accept of the drag gesture -- the actual displayed
      // position stays driven by `game.fen` (a controlled prop), so an
      // illegal move visually snaps back once the request resolves without
      // touching `fen` state.
      return true;
    },
    [game, submitting, submitMoveAndUpdate]
  );

  const handleResign = async () => {
    if (!game) return;
    setSubmitting(true);
    try {
      const updated = await resignGame(id);
      setGame(updated);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Resign failed");
    } finally {
      setSubmitting(false);
    }
  };

  const handleUndo = async () => {
    if (!game) return;
    setSubmitting(true);
    setError(null);
    try {
      const updated = await undoMove(id);
      setGame(updated);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Takeback failed");
    } finally {
      setSubmitting(false);
    }
  };

  const handleAskWhy = (move: Move) => {
    voice.askAboutMove(
      `Please explain why my move ${move.notation} (move ${move.ply}) wasn't the best, and what would have been better.`
    );
  };

  if (error && !game) return <div className={`${pageWrap} text-red-600 dark:text-red-400`}>{error}</div>;
  if (!game) return <div className={pageWrap}>Loading...</div>;

  const canUndo = game.status !== "resigned" && game.status !== "aborted" && game.moves.length > 0 && !game.is_calibration;

  return (
    <div className={pageWrap}>
      <header className={navBar}>
        <a href="/dashboard" className={navBrand}>
          games<span className={navBrandAccent}>_tutor</span>
        </a>
        <a href="/games" className={linkButton}>
          Back to games
        </a>
      </header>

      <main className="max-w-5xl mx-auto grid gap-6 md:grid-cols-[auto_1fr] items-start">
        <div>
          <div className={card}>
            {game.game_type === "go" ? (
              <GoBoardPanel game={game} submitting={submitting} onMove={submitMoveAndUpdate} />
            ) : (
              <div className="w-full max-w-[400px] mx-auto">
                <Chessboard
                  options={{
                    position: game.fen,
                    boardOrientation: game.human_color === "black" ? "black" : "white",
                    allowDragging: game.status === "in_progress" && !submitting,
                    canDragPiece: ({ piece }) => piece.pieceType.startsWith(game.human_color === "black" ? "b" : "w"),
                    onPieceDrop: handleDrop,
                  }}
                />
              </div>
            )}

            <div className="flex items-center justify-between mt-4">
              <strong className="text-zinc-900 dark:text-zinc-50">{resultLabel(game)}</strong>
              <div className="flex gap-2">
                {canUndo && (
                  <button onClick={handleUndo} disabled={submitting} className={buttonSecondary}>
                    Take back
                  </button>
                )}
                {game.status === "in_progress" && (
                  <button onClick={handleResign} disabled={submitting} className={buttonDanger}>
                    Resign
                  </button>
                )}
              </div>
            </div>
            {error && <p className="text-sm text-red-600 dark:text-red-400 mt-2">{error}</p>}
          </div>

          {game.status !== "in_progress" && game.is_calibration && game.skill_profile && (
            <CalibrationSummary profile={game.skill_profile} />
          )}

          <VoicePanel voice={voice} gameInProgress={game.status === "in_progress"} />
        </div>

        <div className={card}>
          <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-50 mb-3">Moves</h3>
          <div ref={movesScrollRef} className="max-h-96 overflow-y-auto overflow-x-auto">
            <table className="w-full text-sm border-collapse">
              <thead>
                <tr className={`text-left ${mutedText}`}>
                  <th className="sticky top-0 bg-white dark:bg-zinc-900 px-2 py-1 font-medium">#</th>
                  <th className="sticky top-0 bg-white dark:bg-zinc-900 px-2 py-1 font-medium">By</th>
                  <th className="sticky top-0 bg-white dark:bg-zinc-900 px-2 py-1 font-medium">Move</th>
                  <th className="sticky top-0 bg-white dark:bg-zinc-900 px-2 py-1 font-medium">Quality</th>
                  <th className="sticky top-0 bg-white dark:bg-zinc-900 px-2 py-1 font-medium">Loss</th>
                  <th className="sticky top-0 bg-white dark:bg-zinc-900 px-2 py-1 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {game.moves.map((move) => (
                  <MoveRow key={move.ply} move={move} onAskWhy={handleAskWhy} />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </main>
    </div>
  );
}

export default function GamePage() {
  return (
    <ProtectedRoute>
      <GameContent />
    </ProtectedRoute>
  );
}
