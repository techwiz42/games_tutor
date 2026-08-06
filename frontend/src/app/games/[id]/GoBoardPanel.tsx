"use client";

import type { ComponentType } from "react";
import { BoundedGoban } from "@sabaki/shudan";
import "@sabaki/shudan/css/goban.css";
import { parseGoBoard, vertexToCoord } from "@/lib/go-coords";
import type { Game } from "@/lib/games-api";
import { buttonSecondary } from "@/lib/auth-ui";

// Shudan is a Preact component (aliased to react at the bundler level --
// see next.config.ts); its own .d.ts still types against preact's
// ComponentClass though, so JSX needs a light cast here despite working
// correctly at runtime (confirmed in the Phase 0 spike).
const Goban = BoundedGoban as unknown as ComponentType<Record<string, unknown>>;

type Props = {
  game: Game;
  submitting: boolean;
  onMove: (coord: string) => void;
};

export default function GoBoardPanel({ game, submitting, onMove }: Props) {
  const { size, grid } = parseGoBoard(game.fen);
  const interactive = game.status === "in_progress" && !submitting;

  const handleVertexClick = (_evt: MouseEvent, vertex: [number, number]) => {
    if (!interactive) return;
    const [x, y] = vertex;
    onMove(vertexToCoord(x, y, size));
  };

  return (
    <div>
      <div style={{ width: 400 }}>
        <Goban
          maxWidth={400}
          maxHeight={400}
          signMap={grid}
          showCoordinates={true}
          fuzzyStonePlacement={true}
          animateStonePlacement={true}
          onVertexClick={handleVertexClick}
        />
      </div>
      <button onClick={() => interactive && onMove("pass")} disabled={!interactive} className={`${buttonSecondary} mt-3`}>
        Pass
      </button>
    </div>
  );
}
