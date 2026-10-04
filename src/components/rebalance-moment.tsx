"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, m } from "framer-motion";
import { explorerLink, formatSharePrice, usdgToNumber } from "@/lib/discovery-format";
import type { RebalanceEvent } from "@/lib/hooks/use-rebalance-events";
import { EASE_OUT } from "@/lib/motion";

const TOAST_SECONDS = 14;

interface RebalanceMomentProps {
  event: RebalanceEvent | null;
  explorerUrl: string;
  usdgDecimals: number | undefined;
  onDismiss: () => void;
}

export function RebalanceMoment({ event, explorerUrl, usdgDecimals, onDismiss }: RebalanceMomentProps) {
  const [paused, setPaused] = useState(false);

  useEffect(() => {
    if (!event || paused) return;
    const timer = window.setTimeout(onDismiss, TOAST_SECONDS * 1000);
    return () => window.clearTimeout(timer);
  }, [event, paused, onDismiss]);

  const link = event ? explorerLink(explorerUrl, "tx", event.hash) : undefined;
  const reason = event ? (event.thresholdBased ? "A weight crossed its limit" : "The interval elapsed") : "";
  const price =
    event && usdgDecimals !== undefined ? formatSharePrice(usdgToNumber(event.sharePrice, usdgDecimals)) : undefined;

  return (
    <div className="moment-region" role="status" aria-live="polite">
      <AnimatePresence>
        {event ? (
          <m.div
            key={event.hash}
            className="moment"
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 8 }}
            transition={{ duration: 0.32, ease: EASE_OUT }}
            onPointerEnter={() => setPaused(true)}
            onPointerLeave={() => setPaused(false)}
            onFocus={() => setPaused(true)}
            onBlur={() => setPaused(false)}
          >
            <div className="moment__body">
              <p className="moment__title">Rebalanced just now</p>
              <p className="moment__text">
                {reason}.{price ? ` NAV per share ${price}.` : ""}
              </p>
              {link ? (
                <a className="moment__link" href={link} target="_blank" rel="noreferrer">
                  View transaction
                </a>
              ) : null}
            </div>
            <button type="button" className="moment__close" onClick={onDismiss} aria-label="Dismiss rebalance notice">
              <span aria-hidden="true">x</span>
            </button>
          </m.div>
        ) : null}
      </AnimatePresence>
    </div>
  );
}
