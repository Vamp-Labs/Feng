"use client";

import { m, useReducedMotion } from "framer-motion";
import { LayersIcon } from "@/components/ui/icons";
import { formatBps } from "@/lib/format";
import { describeHoldings, type Holding } from "@/lib/holding-tones";
import { EASE_OUT, STAGGER, VALUE_TWEEN_SECONDS } from "@/lib/motion";
import styles from "./strategy-holdings.module.css";

const MIN_LABEL_BPS = 1000;
const IN_VIEW = { once: true, margin: "0px 0px -8% 0px" } as const;

type StrategyHoldingsProps = {
  holdings?: readonly Holding[];
  size: "stage" | "tile";
  loading?: boolean;
};

export function StrategyHoldings({ holdings, size, loading = false }: StrategyHoldingsProps) {
  const reduceMotion = useReducedMotion();
  const ready = holdings !== undefined && holdings.length > 0;
  const columns = ready ? holdings.map((holding) => `minmax(0, ${holding.weightBps}fr)`).join(" ") : "minmax(0, 1fr)";

  return (
    <div className={styles.root} data-size={size} data-state={ready ? "ready" : loading ? "loading" : "idle"}>
      <div
        className={styles.bar}
        style={{ gridTemplateColumns: columns }}
        role={ready ? "img" : undefined}
        aria-label={ready ? `Holds ${describeHoldings(holdings)}` : undefined}
      >
        {ready ? (
          holdings.map((holding, index) => (
            <m.span
              key={holding.key}
              className={styles.segment}
              data-tone={holding.tone}
              initial={reduceMotion ? false : { scaleX: 0 }}
              whileInView={{ scaleX: 1 }}
              viewport={IN_VIEW}
              transition={{ duration: VALUE_TWEEN_SECONDS, ease: EASE_OUT, delay: index * STAGGER.item }}
            />
          ))
        ) : (
          <span className={styles.segment} data-tone="empty" />
        )}
      </div>
      <div className={styles.labels} style={{ gridTemplateColumns: columns }} aria-hidden="true">
        {ready
          ? holdings.map((holding) => (
              <span key={holding.key} className={styles.label} data-hidden={holding.weightBps < MIN_LABEL_BPS ? "" : undefined}>
                <span className={styles.ticker}>
                  {holding.nested ? <LayersIcon className={styles.layers} /> : null}
                  <span className={styles.tickerText}>{holding.label}</span>
                </span>
                {size === "stage" ? <span className={styles.percent}>{formatBps(holding.weightBps)}</span> : null}
              </span>
            ))
          : null}
      </div>
    </div>
  );
}
