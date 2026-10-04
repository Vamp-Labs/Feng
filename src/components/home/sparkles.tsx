import type { CSSProperties } from "react";
import { REF_TO_CSS } from "@/lib/geometry";
import { SPARKLES, MOBILE_SPARKLE_COUNT } from "@/lib/sparkles";
import styles from "./sparkles.module.css";

const DOWNLOAD_ORIGIN_REF_Y = 715;
const REF_LEFT = 160;
const REF_SPAN = 720;

export function Sparkles() {
  return (
    <div className={styles.field} aria-hidden data-sparkles>
      {SPARKLES.map((sparkle, index) => {
        const style = {
          "--x": `calc(50% + var(--u) * ${Math.round((sparkle.x - 546) * REF_TO_CSS)})`,
          "--y": `calc(var(--u) * ${Math.round((sparkle.y - DOWNLOAD_ORIGIN_REF_Y) * REF_TO_CSS)})`,
          "--mx": `${Math.round(((sparkle.x - REF_LEFT) / REF_SPAN) * 100)}%`,
          "--my": `calc(var(--v) * ${Math.round((sparkle.y - DOWNLOAD_ORIGIN_REF_Y) * 0.62)})`,
          "--size": sparkle.size,
          "--c": sparkle.color,
          "--o": sparkle.opacity,
          "--dur": `${sparkle.duration}s`,
          "--delay": `${sparkle.delay}s`,
          "--rise": `${sparkle.rise}px`,
          "--drift": `${sparkle.drift}px`,
        } as CSSProperties;
        return (
          <span
            key={index}
            className={`${styles.dot} ${sparkle.kind === "rise" ? styles.rise : styles.twinkle}`}
            data-extra={index >= MOBILE_SPARKLE_COUNT ? "" : undefined}
            style={style}
          />
        );
      })}
    </div>
  );
}
