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

export type Stone = 1 | -1 | 0;

export function parseGoBoard(fen: string): { size: number; grid: Stone[][] } {
  return JSON.parse(fen);
}
