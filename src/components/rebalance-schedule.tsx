"use client";

import { Badge } from "@/components/ui/badge";
import { explorerLink, formatAgo, formatCountdown, formatInterval } from "@/lib/discovery-format";
import { useNowSeconds } from "@/lib/hooks/use-now";
import type { RebalanceLog } from "@/lib/hooks/use-nav-history";

interface RebalanceScheduleProps {
  intervalSeconds: number | undefined;
  lastTimestamp: number | undefined;
  needed: { timeBased: boolean; thresholdBased: boolean } | undefined;
  paused: boolean | undefined;
  lastLog: RebalanceLog | undefined;
  explorerUrl: string;
}

export function RebalanceSchedule({ intervalSeconds, lastTimestamp, needed, paused, lastLog, explorerUrl }: RebalanceScheduleProps) {
  const now = useNowSeconds(1000);
  const hasSchedule = intervalSeconds !== undefined && lastTimestamp !== undefined && lastTimestamp > 0;
  const remaining = hasSchedule ? lastTimestamp + intervalSeconds - now : undefined;
  const due = remaining !== undefined && remaining <= 0;
  const link = lastLog ? explorerLink(explorerUrl, "tx", lastLog.hash) : undefined;

  const status = paused
    ? { tone: "danger" as const, text: "Paused" }
    : needed?.thresholdBased
      ? { tone: "amber" as const, text: "Threshold breached" }
      : needed?.timeBased
        ? { tone: "amber" as const, text: "Interval elapsed" }
        : needed
          ? { tone: "violet" as const, text: "Up to date" }
          : undefined;

  return (
    <dl className="schedule">
      <div className="schedule__item">
        <dt>Next time-based rebalance</dt>
        <dd>
          {remaining === undefined ? (
            "--"
          ) : due ? (
            <span className="schedule__due">Due now, any keeper can run it</span>
          ) : (
            <time className="schedule__count" role="timer" dateTime={`PT${Math.max(0, remaining)}S`}>
              {formatCountdown(remaining)}
            </time>
          )}
        </dd>
        <dd className="schedule__sub">{intervalSeconds === undefined ? "" : `Every ${formatInterval(intervalSeconds)}`}</dd>
      </div>
      <div className="schedule__item">
        <dt>Last rebalance</dt>
        <dd>{lastTimestamp === undefined ? "--" : lastTimestamp === 0 ? "Never" : formatAgo(now - lastTimestamp)}</dd>
        <dd className="schedule__sub">
          {link ? (
            <a href={link} target="_blank" rel="noreferrer" className="schedule__link">
              View transaction
            </a>
          ) : lastLog ? (
            `Block ${lastLog.blockNumber.toString()}`
          ) : (
            ""
          )}
        </dd>
      </div>
      <div className="schedule__item">
        <dt>Status</dt>
        <dd>{status ? <Badge tone={status.tone}>{status.text}</Badge> : "--"}</dd>
        <dd className="schedule__sub">Also triggers when a weight crosses its limit</dd>
      </div>
    </dl>
  );
}
