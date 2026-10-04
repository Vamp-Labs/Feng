"use client";

import { formatAge, formatAgo } from "@/lib/discovery-format";
import { useHealth } from "@/lib/hooks/use-health";
import { useNowSeconds } from "@/lib/hooks/use-now";

export function HealthBadge() {
  const { data } = useHealth();
  const now = useNowSeconds(30_000);

  if (!data) return null;

  const elapsed = Math.max(0, now - data.generatedAt);
  const parts = [data.ok ? "Live" : "Degraded"];
  if (data.oldestFeedAgeSec !== undefined) parts.push(`feeds ${formatAge(data.oldestFeedAgeSec + elapsed)} old`);
  if (data.lastRebalanceAt !== undefined) parts.push(`last rebalance ${formatAgo(now - data.lastRebalanceAt)}`);

  return (
    <span className="health-badge" data-state={data.ok ? "ok" : "degraded"}>
      <span className="health-badge__dot" aria-hidden="true" />
      {parts.join(", ")}
    </span>
  );
}
