import Image from "next/image";
import { canvasBox, cssVars } from "@/lib/geometry";
import styles from "./complete-badge.module.css";

const RING_PATH =
  "M 53.81 84.25 A 32.58 53.57 114.14 1 1 80.46 24.79 A 32.58 53.57 114.14 1 1 53.81 84.25";

export function CompleteBadge({ percent, ready }: { percent: number; ready: boolean }) {
  return (
    <div
      className={styles.badge}
      style={{
        ...canvasBox([884, 856, 141, 105], 715),
        ...cssVars({
          "--m-right": "calc(var(--v) * 14)",
          "--m-top": "calc(var(--v) * 330)",
          "--nested": percent,
        }),
      }}
      role="img"
      aria-label={ready ? `${percent}% of listed strategies are nested` : "Loading nested share"}
      data-complete
    >
      <div className={styles.depth} data-tile-depth>
        <div className={styles.float} data-tile-float>
          <Image
            className={styles.art}
            src="/img/dl-badge-ring-base.png"
            alt=""
            width={141}
            height={105}
            data-tile-art
            data-reveal
          />
          <svg className={styles.ring} viewBox="0 0 141 105" aria-hidden="true" focusable="false" data-complete-ring data-reveal>
            <defs>
              <linearGradient id="nested-ring-fill" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0" stopColor="#5dffb5" />
                <stop offset="1" stopColor="#1fe28c" />
              </linearGradient>
            </defs>
            <path d={RING_PATH} className={styles.track} />
            <path d={RING_PATH} className={styles.glow} pathLength={100} />
            <path d={RING_PATH} className={styles.arc} pathLength={100} />
          </svg>
          <span className={styles.text} aria-hidden="true" data-complete-text data-reveal>
            <span className={styles.value}>
              <span key={percent} data-count={ready ? percent : undefined}>
                {ready ? percent : "–"}
              </span>
              %
            </span>
            <span className={styles.caption}>NESTED</span>
          </span>
        </div>
      </div>
    </div>
  );
}
