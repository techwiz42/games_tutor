"use client";

import { useEffect, useState, useCallback } from "react";
import { useParams } from "next/navigation";
import { Chessboard } from "react-chessboard";
import type { PieceDropHandlerArgs } from "react-chessboard";
import { ProtectedRoute } from "@/lib/protected-route";
import { getGame, submitMove, resignGame, Game, Move, SkillProfile } from "@/lib/games-api";

function resultLabel(game: Game): string {
  if (game.status === "in_progress") return "In progress";
  if (!game.result) return game.status;
  const winner = game.result === "white_wins" ? "You won" : game.result === "black_wins" ? "Engine won" : "Draw";
  return `${game.status} -- ${winner}`;
}

function CalibrationSummary({ profile }: { profile: SkillProfile }) {
  const hedge =
    profile.games_count <= 1
      ? "This is a first, rough estimate -- it'll sharpen as you play more \"rate my play\" games."
      : `Based on ${profile.games_count} calibration games so far -- still improving with each one.`;

  return (
    <div style={{ marginTop: 12, padding: 12, border: "1px solid #ccc", maxWidth: 420 }}>
      <h3 style={{ marginTop: 0 }}>Rate my play: result</h3>
      <p>
        Estimated rating: <strong>{profile.estimated_rating}</strong> ({profile.display_label})
      </p>
      <p style={{ opacity: 0.7, fontSize: 14 }}>{hedge}</p>
    </div>
  );
}

function MoveRow({ move }: { move: Move }) {
  return (
    <tr>
      <td style={{ padding: "2px 8px" }}>{move.ply}</td>
      <td style={{ padding: "2px 8px" }}>{move.player === "human" ? "You" : "Engine"}</td>
      <td style={{ padding: "2px 8px", fontFamily: "monospace" }}>{move.notation}</td>
      <td style={{ padding: "2px 8px" }}>{move.classification ?? "--"}</td>
      <td style={{ padding: "2px 8px" }}>{move.loss ?? "--"}</td>
    </tr>
  );
}

function GameContent() {
  const { id } = useParams<{ id: string }>();
  const [game, setGame] = useState<Game | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    getGame(id)
      .then(setGame)
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load game"));
  }, [id]);

  const handleDrop = useCallback(
    ({ piece, sourceSquare, targetSquare }: PieceDropHandlerArgs) => {
      if (!targetSquare || submitting || !game || game.status !== "in_progress") return false;

      // Auto-queen promotion (v1 simplification -- no promotion picker yet;
      // human is always White, so only a pawn reaching rank 8 can promote).
      const isPromotion = piece.pieceType === "wP" && targetSquare[1] === "8";
      const uci = `${sourceSquare}${targetSquare}${isPromotion ? "q" : ""}`;

      setSubmitting(true);
      setError(null);
      submitMove(id, uci)
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

      // Optimistic accept of the drag gesture -- the actual displayed
      // position stays driven by `game.fen` (a controlled prop), so an
      // illegal move visually snaps back once the request resolves without
      // touching `fen` state.
      return true;
    },
    [id, game, submitting]
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

  if (error && !game) return <div style={{ padding: 24, color: "red" }}>{error}</div>;
  if (!game) return <div style={{ padding: 24 }}>Loading...</div>;

  return (
    <div style={{ maxWidth: 900, margin: "24px auto", padding: 24, display: "flex", gap: 32 }}>
      <div>
        <div style={{ width: 480 }}>
          <Chessboard
            options={{
              position: game.fen,
              boardOrientation: "white",
              allowDragging: game.status === "in_progress" && !submitting,
              canDragPiece: ({ piece }) => piece.pieceType.startsWith("w"),
              onPieceDrop: handleDrop,
            }}
          />
        </div>
        <p style={{ marginTop: 12 }}>
          <strong>{resultLabel(game)}</strong>
          {game.status === "in_progress" && (
            <button onClick={handleResign} disabled={submitting} style={{ marginLeft: 12 }}>
              Resign
            </button>
          )}
        </p>
        {error && <p style={{ color: "red" }}>{error}</p>}

        {game.status !== "in_progress" && game.is_calibration && game.skill_profile && (
          <CalibrationSummary profile={game.skill_profile} />
        )}

        <p>
          <a href="/games">Back to games</a>
        </p>
      </div>

      <div>
        <h3>Moves</h3>
        <table style={{ borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", opacity: 0.6 }}>
              <th style={{ padding: "2px 8px" }}>#</th>
              <th style={{ padding: "2px 8px" }}>By</th>
              <th style={{ padding: "2px 8px" }}>Move</th>
              <th style={{ padding: "2px 8px" }}>Quality</th>
              <th style={{ padding: "2px 8px" }}>Loss</th>
            </tr>
          </thead>
          <tbody>
            {game.moves.map((move) => (
              <MoveRow key={move.ply} move={move} />
            ))}
          </tbody>
        </table>
      </div>
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
