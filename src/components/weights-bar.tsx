"use client";

import Link from "next/link";
import { AnimatePresence, m } from "framer-motion";
import { Badge } from "@/components/ui/badge";
import { formatBpsPoints } from "@/lib/discovery-format";
import { shortenAddress } from "@/lib/format";
import type { ConstituentDetail } from "@/lib/hooks/use-strategy-detail";
import { EASE_OUT, VALUE_TWEEN_SECONDS } from "@/lib/motion";

const DOT_TONES = ["violet", "orchid", "mint", "sky"] as const;
const BPS = 10_000;
const GHOST_MIN_DELTA_BPS = 1;

interface WeightsBarProps {
  constituents: readonly ConstituentDetail[];
  idleBps?: number;
  ghostBps?: readonly (number | undefined)[];
  ghostIdleBps?: number;
}

function Row({
  label,
  nested,
  nestedVault,
  tone,
  currentBps,
  targetBps,
  triggerBps,
  ghostBps,
}: {
  label: string;
  nested: boolean;
  nestedVault?: string;
  tone: string;
  currentBps: number | undefined;
  targetBps: number;
  triggerBps: number | undefined;
  ghostBps: number | undefined;
}) {
  const current = currentBps ?? 0;
  const over = triggerBps !== undefined && currentBps !== undefined && currentBps > triggerBps;
  const drift = currentBps === undefined ? undefined : currentBps - targetBps;
  const showGhost = ghostBps !== undefined && currentBps !== undefined && Math.abs(ghostBps - currentBps) >= GHOST_MIN_DELTA_BPS;
  const summary = [
    `${label} ${currentBps === undefined ? "weight loading" : `at ${formatBpsPoints(currentBps)}`}`,
    `target ${formatBpsPoints(targetBps)}`,
    triggerBps === undefined ? undefined : `rebalances above ${formatBpsPoints(triggerBps)}`,
  ]
    .filter(Boolean)
    .join(", ");

  return (
    <li className="wbar" data-over={over ? "" : undefined}>
      <div className="wbar__head">
        <span className="wbar__name">
          <span className="coin-dot" data-tone={tone} aria-hidden="true">
            {label.charAt(0).toUpperCase()}
          </span>
          <span className="text-label whitespace-nowrap text-ink">{label}</span>
          {nested ? (
            nestedVault ? (
              <Link href={`/strategy/${nestedVault}`} className="rounded-full" aria-label={`Open nested strategy ${label}`}>
                <Badge tone="orchid">Nested Strategy</Badge>
              </Link>
            ) : (
              <Badge tone="orchid">Nested Strategy</Badge>
            )
          ) : null}
        </span>
        <span className="wbar__value text-stat-sm" data-over={over ? "" : undefined}>
          {currentBps === undefined ? "--" : formatBpsPoints(currentBps)}
        </span>
      </div>
      <div className="wbar__track" role="img" aria-label={summary}>
        <div className="wbar__clip">
          <m.span
            className="wbar__fill"
            data-over={over ? "" : undefined}
            initial={false}
            animate={{ scaleX: current / BPS }}
            transition={{ duration: VALUE_TWEEN_SECONDS * 1.6, ease: EASE_OUT }}
          />
        </div>
        {targetBps > 0 ? <span className="wbar__tick" data-kind="target" style={{ insetInlineStart: `${targetBps / 100}%` }} aria-hidden="true" /> : null}
        {triggerBps !== undefined ? (
          <span className="wbar__tick" data-kind="trigger" style={{ insetInlineStart: `${triggerBps / 100}%` }} aria-hidden="true" />
        ) : null}
        <AnimatePresence>
          {showGhost ? (
            <m.span
              key="ghost"
              className="wbar__ghost"
              style={{ insetInlineStart: `${(ghostBps ?? 0) / 100}%` }}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.3 }}
              aria-hidden="true"
            />
          ) : null}
        </AnimatePresence>
      </div>
      <p className="wbar__meta text-micro">
        <span>Target {formatBpsPoints(targetBps)}</span>
        {triggerBps !== undefined ? <span>Rebalances above {formatBpsPoints(triggerBps)}</span> : null}
        {drift !== undefined && targetBps > 0 ? (
          <span data-over={over ? "" : undefined}>
            {drift >= 0 ? "+" : "-"}
            {formatBpsPoints(Math.abs(drift))} vs target
          </span>
        ) : null}
        {showGhost && ghostBps !== undefined ? (
          <span className="wbar__was">Was {formatBpsPoints(ghostBps)}</span>
        ) : null}
      </p>
    </li>
  );
}

export function WeightsBar({ constituents, idleBps, ghostBps, ghostIdleBps }: WeightsBarProps) {
  if (constituents.length === 0) {
    return <p className="text-caption text-ink-muted">No constituents to show yet.</p>;
  }

  return (
    <div className="flex flex-col gap-4">
      <ul className="wbar-list">
        {constituents.map((constituent, index) => (
          <Row
            key={constituent.token}
            label={constituent.symbol ?? shortenAddress(constituent.token)}
            nested={constituent.isStrategyToken}
            nestedVault={constituent.nestedVault}
            tone={DOT_TONES[index % DOT_TONES.length]}
            currentBps={constituent.currentBps}
            targetBps={constituent.targetWeightBps}
            triggerBps={constituent.effectiveMaxBps}
            ghostBps={ghostBps?.[index]}
          />
        ))}
        {idleBps !== undefined && idleBps >= 1 ? (
          <Row
            label="Idle USDG"
            nested={false}
            tone="sky"
            currentBps={idleBps}
            targetBps={0}
            triggerBps={undefined}
            ghostBps={ghostIdleBps}
          />
        ) : null}
      </ul>
      <ul className="wbar-legend text-micro" aria-label="How to read the bars">
        <li data-kind="current">Current weight</li>
        <li data-kind="target">Target</li>
        <li data-kind="trigger">Rebalance trigger</li>
      </ul>
    </div>
  );
}
