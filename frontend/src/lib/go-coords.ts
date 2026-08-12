// Mirrors GamesTutor.Go.Board's coordinate convention exactly (column
// letters skip "I"; rank 1 is the bottom row) so moves sent to the
// backend match what it expects.
const COLUMNS = ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"];

// Shudan's onVertexClick gives [x, y] with y = 0 at the top row, matching
// GamesTutor.Go.Board.to_grid/1's row-major "row 0 = top" convention --
// no row-order conversion needed, just the rank<->row-index relationship.
export function vertexToCoord(x: number, y: number, size: number): string {
  const rank = size - y;
  return `${COLUMNS[x]}${rank}`;
}

// Inverse of vertexToCoord -- turns a backend move coordinate (e.g. "D5",
// from GamesTutor.Go.GameServer's hint/1) back into a Shudan vertex for
// highlighting. Returns null for "pass" (nothing to highlight) or an
// unparseable coordinate.
export function coordToVertex(coord: string, size: number): [number, number] | null {
  const match = coord.match(/^([A-Za-z]+)(\d+)$/);
  if (!match) return null;

  const [, letters, rankStr] = match;
  const x = COLUMNS.indexOf(letters.toUpperCase());
  const rank = parseInt(rankStr, 10);
  if (x === -1) return null;

  return [x, size - rank];
}

export type Stone = 1 | -1 | 0;

// `ownership` is optional -- absent for chess games entirely, and for any
// Go position recorded before this field existed (see
// GamesTutor.Go.GameServer's board_json/2). A flat size*size array, one
// float per point in [-1 (white), 1 (black)], in the exact same row-major
// (row 0 = top) order `grid` is already in -- empirically confirmed
// against the live engine, not assumed (see the finding-2 commit).
export function parseGoBoard(fen: string): { size: number; grid: Stone[][]; ownership: number[] | null } {
  const parsed = JSON.parse(fen);
  return { size: parsed.size, grid: parsed.grid, ownership: parsed.ownership ?? null };
}

// Territory overlay coloring for Shudan's `paintMap` prop: thresholds the
// continuous per-point ownership estimate into discrete black/white/
// contested paint, shaped to match `grid`'s own row-major 2D layout.
// +-0.3 (not 0) as the "contested" cutoff -- KataGo's ownership rarely
// lands exactly on 0 even for genuinely undecided points, so a strict
// sign check would paint almost every point some color; this keeps
// visibly-uncertain points (dame, unresolved life-and-death) neutral
// instead of implying false confidence.
const CONTESTED_THRESHOLD = 0.3;

export function ownershipToPaintMap(ownership: number[], size: number): Stone[][] {
  const rows: Stone[][] = [];
  for (let y = 0; y < size; y++) {
    const row: Stone[] = [];
    for (let x = 0; x < size; x++) {
      const value = ownership[y * size + x];
      row.push(value > CONTESTED_THRESHOLD ? 1 : value < -CONTESTED_THRESHOLD ? -1 : 0);
    }
    rows.push(row);
  }
  return rows;
}
