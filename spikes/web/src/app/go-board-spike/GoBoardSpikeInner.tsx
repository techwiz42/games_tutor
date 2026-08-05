"use client";

import { useState } from "react";
import { BoundedGoban } from "@sabaki/shudan";
import "@sabaki/shudan/css/goban.css";

const SIZE = 19;

function emptyBoard(): number[][] {
  return Array.from({ length: SIZE }, () => Array(SIZE).fill(0));
}

export default function GoBoardSpike() {
  const [signMap, setSignMap] = useState<number[][]>(emptyBoard());
  const [toPlay, setToPlay] = useState<1 | -1>(1);
  const [lastClick, setLastClick] = useState<string>("(none yet)");

  const handleVertexClick = (_evt: unknown, vertex: [number, number]) => {
    const [x, y] = vertex;
    setLastClick(`(${x}, ${y})`);
    setSignMap((prev) => {
      const next = prev.map((row) => row.slice());
      if (next[y][x] === 0) {
        next[y][x] = toPlay;
        setToPlay((p) => (p === 1 ? -1 : 1));
      }
      return next;
    });
  };

  return (
    <div style={{ padding: 24, fontFamily: "sans-serif" }}>
      <h1>Shudan Go board spike (19x19)</h1>
      <p>Click a vertex to place a stone (alternating black/white). Confirms:</p>
      <ul>
        <li>Shudan renders in this Next.js 16 / React 19 setup via the preact-&gt;react alias</li>
        <li>onVertexClick returns usable (x, y) coordinates</li>
      </ul>
      <p>Last clicked vertex: <strong>{lastClick}</strong></p>
      <div style={{ maxWidth: 600 }}>
        <BoundedGoban
          maxWidth={600}
          maxHeight={600}
          signMap={signMap}
          showCoordinates={true}
          fuzzyStonePlacement={true}
          animateStonePlacement={true}
          onVertexClick={handleVertexClick}
        />
      </div>
    </div>
  );
}
