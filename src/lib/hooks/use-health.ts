"use client";

import { useQuery } from "@tanstack/react-query";

export interface HealthSummary {
  ok: boolean;
  generatedAt: number;
  oldestFeedAgeSec: number | undefined;
  lastRebalanceAt: number | undefined;
}

const REFRESH_MS = 60_000;
const REQUEST_TIMEOUT_MS = 20_000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function finiteNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

export function parseHealth(value: unknown): HealthSummary | undefined {
  if (!isRecord(value) || typeof value.ok !== "boolean") return undefined;
  const generatedAt = finiteNumber(value.generatedAt);
  if (generatedAt === undefined) return undefined;

  const feeds = Array.isArray(value.feeds) ? value.feeds : [];
  const ages = feeds.flatMap((feed) => {
    const age = isRecord(feed) ? finiteNumber(feed.ageSec) : undefined;
    return age === undefined ? [] : [age];
  });
  const vaults = Array.isArray(value.vaults) ? value.vaults : [];
  const rebalances = vaults.flatMap((vault) => {
    const timestamp = isRecord(vault) ? finiteNumber(vault.lastRebalance) : undefined;
    return timestamp === undefined || timestamp <= 0 ? [] : [timestamp];
  });

  return {
    ok: value.ok,
    generatedAt,
    oldestFeedAgeSec: ages.length > 0 ? Math.max(...ages) : undefined,
    lastRebalanceAt: rebalances.length > 0 ? Math.max(...rebalances) : undefined,
  };
}

export function useHealth() {
  return useQuery({
    queryKey: ["ops-health"],
    retry: false,
    staleTime: REFRESH_MS / 2,
    refetchInterval: REFRESH_MS,
    queryFn: async ({ signal }): Promise<HealthSummary | null> => {
      const timeout = AbortSignal.timeout(REQUEST_TIMEOUT_MS);
      try {
        const response = await fetch("/api/ops/health", {
          cache: "no-store",
          signal: AbortSignal.any([signal, timeout]),
        });
        const body: unknown = await response.json();
        return parseHealth(body) ?? null;
      } catch {
        return null;
      }
    },
  });
}
