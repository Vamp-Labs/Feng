import type { CSSProperties } from "react";
import styles from "./strategy-logo.module.css";

export type ArtTone = "violet" | "mint" | "orchid" | "sky";

const TONES: ArtTone[] = ["violet", "mint", "orchid", "sky"];
const MONOGRAM_LENGTH = 3;

const hexDigits = (seed: string) =>
  Array.from(seed.replace(/^0x/i, "")).map((char) => Number.parseInt(char, 16) || 0);

export function toneFor(seed: string): ArtTone {
  return TONES[(hexDigits(seed)[0] ?? 0) % TONES.length];
}

const monogram = (symbol: string | undefined) =>
  symbol ? symbol.replace(/[^A-Za-z0-9]/g, "").slice(0, MONOGRAM_LENGTH).toUpperCase() || "?" : "?";

export function StrategyLogo({
  seed,
  symbol,
  depth,
  size,
  className,
}: {
  seed: string;
  symbol?: string;
  depth: number;
  size?: string;
  className?: string;
}) {
  const style = size ? ({ "--s": size } as CSSProperties) : undefined;
  return (
    <span className={`${styles.logo} ${className ?? ""}`} data-tone={toneFor(seed)} data-nested={depth >= 2 ? "" : undefined} style={style} aria-hidden="true">
      {depth >= 2 ? <span className={styles.ghost} /> : null}
      <span className={styles.tile}>
        <span className={styles.bars}>
          <i />
          <i />
          <i />
        </span>
        <span className={styles.mono}>{monogram(symbol)}</span>
      </span>
    </span>
  );
}
