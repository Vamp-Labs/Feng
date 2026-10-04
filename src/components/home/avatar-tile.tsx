import type { CSSProperties } from "react";
import styles from "./avatar-tile.module.css";

const HUE_STEP = 7;

export function AvatarTile({ address }: { address?: string }) {
  const digits = address ? address.replace(/^0x/i, "").slice(0, 6) : "";
  const hue = digits ? (Number.parseInt(digits, 16) % 360) : 262;
  const initials = digits ? digits.slice(0, 2).toUpperCase() : "?";
  const style = { "--hue": hue, "--hue-b": (hue + HUE_STEP * 6) % 360 } as CSSProperties;

  return (
    <div className={styles.tile} style={style} aria-hidden="true">
      <span className={styles.face}>
        <span className={styles.seal}>{initials}</span>
      </span>
    </div>
  );
}
