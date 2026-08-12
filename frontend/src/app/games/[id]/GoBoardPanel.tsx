"use client";

import { useEffect, useRef, useState, type ComponentType } from "react";
import { BoundedGoban } from "@sabaki/shudan";
import "@sabaki/shudan/css/goban.css";
import { parseGoBoard, ownershipToPaintMap, vertexToCoord, coordToVertex } from "@/lib/go-coords";
import type { Game } from "@/lib/games-api";
import { buttonSecondary, mutedText } from "@/lib/auth-ui";

// Shudan is a Preact component (aliased to react at the bundler level --
// see next.config.ts); its own .d.ts still types against preact's
// ComponentClass though, so JSX needs a light cast here despite working
// correctly at runtime (confirmed in the Phase 0 spike).
const Goban = BoundedGoban as unknown as ComponentType<Record<string, unknown>>;

// BoundedGoban only resizes itself in response to its maxWidth/maxHeight
// props changing (see its componentDidUpdate) -- it does not observe its
// container's CSS size on its own, unlike react-chessboard's board (which
// is a CSS grid that fills its parent). So a plain responsive wrapper div
// isn't enough here; the container's actual width has to be measured and
// fed back in as maxWidth/maxHeight.
const MAX_BOARD_SIZE = 400;

type Props = {
  game: Game;
  submitting: boolean;
  onMove: (coord: string) => void;
  // Instruction mode's suggested move (e.g. "D5" or "pass"), or null/undefined
  // when instruction mode is off or no hint has loaded yet -- see page.tsx.
  hint?: string | null;
};

export default function GoBoardPanel({ game, submitting, onMove, hint }: Props) {
  const { size, grid, ownership } = parseGoBoard(game.fen);
  const interactive = game.status === "in_progress" && !submitting;
  const [showTerritory, setShowTerritory] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const [boardSize, setBoardSize] = useState(MAX_BOARD_SIZE);

  const hintVertex = hint ? coordToVertex(hint, size) : null;

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const observer = new ResizeObserver((entries) => {
      const width = entries[0]?.contentRect.width;
      if (width) setBoardSize(width);
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const handleVertexClick = (_evt: MouseEvent, vertex: [number, number]) => {
    if (!interactive) return;
    const [x, y] = vertex;
    onMove(vertexToCoord(x, y, size));
  };

  return (
    <div>
      <div ref={containerRef} className="w-full max-w-[400px] mx-auto">
        <Goban
          className="instruction-goban"
          maxWidth={boardSize}
          maxHeight={boardSize}
          signMap={grid}
          paintMap={showTerritory && ownership ? ownershipToPaintMap(ownership, size) : undefined}
          selectedVertices={hintVertex ? [hintVertex] : []}
          showCoordinates={true}
          fuzzyStonePlacement={true}
          animateStonePlacement={true}
          onVertexClick={handleVertexClick}
        />
      </div>
      {hint === "pass" && <p className={`${mutedText} text-center mt-1`}>Suggested: pass</p>}
      <div className="flex gap-2 mt-3">
        <button onClick={() => interactive && onMove("pass")} disabled={!interactive} className={buttonSecondary}>
          Pass
        </button>
        {ownership && (
          <button onClick={() => setShowTerritory((v) => !v)} className={buttonSecondary}>
            {showTerritory ? "Hide" : "Show"} territory estimate
          </button>
        )}
      </div>
    </div>
  );
}
