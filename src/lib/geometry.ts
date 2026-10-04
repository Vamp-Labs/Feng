import type { CSSProperties } from "react";

export const REF_TO_CSS = 1.3187;

export type RefBox = readonly [x: number, y: number, w: number, h: number];

const round = (value: number) => Math.round(value * 100) / 100;

export const unit = (cssPx: number) => `calc(var(--u) * ${round(cssPx)})`;

export function cssVars(vars: Record<string, string | number>): CSSProperties {
  return vars as CSSProperties;
}

export function canvasBox(box: RefBox, originRefY = 0): CSSProperties {
  const [x, y, w, h] = box;
  return cssVars({
    "--x": `calc(50% + var(--u) * ${round((x - 546) * REF_TO_CSS)})`,
    "--y": unit((y - originRefY) * REF_TO_CSS),
    "--w": unit(w * REF_TO_CSS),
    "--h": unit(h * REF_TO_CSS),
  });
}
