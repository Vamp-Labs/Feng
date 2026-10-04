const GLYPHS: Record<string, readonly string[]> = {
  F: ["XXX", "X..", "XX.", "X..", "X.."],
  E: ["XXX", "X..", "XX.", "X..", "XXX"],
  N: ["X..X", "XX.X", "XXXX", "X.XX", "X..X"],
  G: ["XXX", "X..", "X.X", "X.X", "XXX"],
};

const ROWS = 5;
const CELL_FILL = 0.9;
const CELL_RADIUS = 0.14;
const LETTER_GAP = 1;

type Cell = { x: number; y: number };

function layout(text: string): { cells: Cell[]; width: number } {
  const cells: Cell[] = [];
  let cursor = 0;
  for (const char of text) {
    const glyph = GLYPHS[char];
    if (!glyph) continue;
    glyph.forEach((row, y) => {
      Array.from(row).forEach((mark, x) => {
        if (mark === "X") cells.push({ x: cursor + x, y });
      });
    });
    cursor += glyph[0].length + LETTER_GAP;
  }
  return { cells, width: cursor - LETTER_GAP };
}

const WORDMARK = layout("FENG");

export function PixelWordmark({ className }: { className?: string }) {
  const offset = (1 - CELL_FILL) / 2;
  return (
    <svg
      className={className}
      viewBox={`0 0 ${WORDMARK.width} ${ROWS}`}
      fill="currentColor"
      role="img"
      aria-label="Feng"
    >
      {WORDMARK.cells.map(({ x, y }) => (
        <rect
          key={`${x}-${y}`}
          x={x + offset}
          y={y + offset}
          width={CELL_FILL}
          height={CELL_FILL}
          rx={CELL_RADIUS}
        />
      ))}
    </svg>
  );
}
