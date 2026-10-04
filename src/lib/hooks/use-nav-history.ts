"use client";

import { useCallback, useMemo } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import type { Address } from "viem";
import { SECONDS_PER_DAY } from "@/lib/discovery-format";
import { useNowSeconds } from "@/lib/hooks/use-now";
import type { StrategySummary } from "@/lib/hooks/use-marketplace";
import {
  navCheckpointEvent,
  rebalancedEvent,
  scanRange,
  type NavPoint,
  type RebalanceLog,
} from "@/lib/hooks/use-v2-discovery-logs";
import { useContracts } from "@/lib/use-contracts";
import { IS_V2 } from "@/lib/protocol";

export type { NavPoint, RebalanceLog } from "@/lib/hooks/use-v2-discovery-logs";

interface HistoryData {
  toBlock: bigint;
  points: Record<string, NavPoint[]>;
  rebalances: Record<string, RebalanceLog[]>;
}

const REFRESH_MS = 60_000;
const ONE_E18 = 10n ** 18n;
const MAX_SERIES_POINTS = 48;
const EMPTY_POINTS: readonly NavPoint[] = [];
const EMPTY_REBALANCES: readonly RebalanceLog[] = [];

export const DAY_SECONDS = SECONDS_PER_DAY;
export const WEEK_SECONDS = 7 * SECONDS_PER_DAY;

export function changeOver(
  points: readonly NavPoint[],
  latest: number | undefined,
  windowSeconds: number,
  nowSeconds: number,
): number | undefined {
  if (points.length === 0) return undefined;
  const cutoff = nowSeconds - windowSeconds;
  let reference: NavPoint | undefined;
  for (const point of points) {
    if (point.t <= cutoff) reference = point;
    else break;
  }
  if (!reference || reference.price <= 0) return undefined;
  const end = latest ?? points[points.length - 1].price;
  if (!Number.isFinite(end)) return undefined;
  return end / reference.price - 1;
}

export function seriesWithLatest(
  points: readonly NavPoint[],
  latest: number | undefined,
  nowSeconds: number,
): NavPoint[] {
  if (points.length < 2) return [];
  const merged =
    latest !== undefined && Number.isFinite(latest) && (points.length === 0 || points[points.length - 1].t < nowSeconds)
      ? [...points, { t: nowSeconds, price: latest }]
      : [...points];
  if (merged.length <= MAX_SERIES_POINTS) return merged;
  const stride = (merged.length - 1) / (MAX_SERIES_POINTS - 1);
  const sampled: NavPoint[] = [];
  for (let index = 0; index < MAX_SERIES_POINTS - 1; index += 1) sampled.push(merged[Math.round(index * stride)]);
  sampled.push(merged[merged.length - 1]);
  return sampled;
}

function useHistory(vaults: readonly Address[]) {
  const client = usePublicClient();
  const queryClient = useQueryClient();
  const { addresses } = useContracts();
  const chainId = addresses.chainId;
  const key = useMemo(() => vaults.map((vault) => vault.toLowerCase()).toSorted().join(","), [vaults]);
  const queryKey = useMemo(() => ["nav-history", chainId, key] as const, [chainId, key]);

  const query = useQuery<HistoryData | undefined>({
    queryKey,
    enabled: IS_V2 && vaults.length > 0 && client !== undefined,
    staleTime: REFRESH_MS,
    gcTime: 30 * 60_000,
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      if (!client) return undefined;
      const previous = queryClient.getQueryData<HistoryData>(queryKey);
      const head = await client.getBlockNumber();
      const from = previous ? previous.toBlock + 1n : 0n;
      if (previous && from > head) return previous;

      const logs = await scanRange(from, head, (start, end) =>
        client.getLogs({
          address: [...vaults],
          events: [navCheckpointEvent, rebalancedEvent],
          strict: true,
          fromBlock: start,
          toBlock: end,
        }),
      );

      const points: Record<string, NavPoint[]> = {};
      const rebalances: Record<string, RebalanceLog[]> = {};
      if (previous) {
        for (const [vault, list] of Object.entries(previous.points)) points[vault] = [...list];
        for (const [vault, list] of Object.entries(previous.rebalances)) rebalances[vault] = [...list];
      }

      const ordered = logs.toSorted((a, b) =>
        a.blockNumber === b.blockNumber ? a.logIndex - b.logIndex : a.blockNumber < b.blockNumber ? -1 : 1,
      );

      for (const log of ordered) {
        const vault = log.address.toLowerCase();
        if (log.eventName === "NavCheckpoint") {
          const { timestamp, totalAssets, totalSupply } = log.args;
          if (totalSupply === 0n) continue;
          (points[vault] ??= []).push({ t: Number(timestamp), price: Number((totalAssets * ONE_E18) / totalSupply) });
        } else if (log.eventName === "Rebalanced") {
          const { timestamp, timeBased, thresholdBased, sharePrice } = log.args;
          (rebalances[vault] ??= []).push({
            t: Number(timestamp),
            hash: log.transactionHash,
            blockNumber: log.blockNumber,
            timeBased,
            thresholdBased,
            sharePrice,
          });
        }
      }

      return { toBlock: head, points, rebalances };
    },
  });

  const pointsFor = useCallback(
    (vault: Address): readonly NavPoint[] => query.data?.points[vault.toLowerCase()] ?? EMPTY_POINTS,
    [query.data],
  );
  const rebalancesFor = useCallback(
    (vault: Address): readonly RebalanceLog[] => query.data?.rebalances[vault.toLowerCase()] ?? EMPTY_REBALANCES,
    [query.data],
  );

  const isLoading = query.isLoading;
  const isReady = query.data !== undefined;
  const error = query.error;
  const refetch = query.refetch;

  return useMemo(
    () => ({ pointsFor, rebalancesFor, isLoading, isReady, error, refetch }),
    [pointsFor, rebalancesFor, isLoading, isReady, error, refetch],
  );
}

export interface StrategyMetrics {
  series: NavPoint[];
  change24h: number | undefined;
  change7d: number | undefined;
}

export function useStrategyMetrics(strategies: readonly StrategySummary[]) {
  const vaults = useMemo(() => strategies.map((strategy) => strategy.vault), [strategies]);
  const history = useHistory(vaults);
  const now = useNowSeconds(60_000);

  const metrics = useMemo(() => {
    const byVault = new Map<string, StrategyMetrics>();
    for (const strategy of strategies) {
      const points = history.pointsFor(strategy.vault);
      const latest = strategy.sharePrice === undefined ? undefined : Number(strategy.sharePrice);
      byVault.set(strategy.vault, {
        series: seriesWithLatest(points, latest, now),
        change24h: changeOver(points, latest, DAY_SECONDS, now),
        change7d: changeOver(points, latest, WEEK_SECONDS, now),
      });
    }
    return byVault;
  }, [strategies, history, now]);

  return { metrics, isLoading: history.isLoading, isReady: history.isReady };
}

export function useNavHistory(vault: Address | undefined, latestSharePrice: bigint | undefined) {
  const vaults = useMemo<Address[]>(() => (vault ? [vault] : []), [vault]);
  const history = useHistory(vaults);
  const now = useNowSeconds(60_000);

  return useMemo(() => {
    const points = vault ? history.pointsFor(vault) : EMPTY_POINTS;
    const rebalances = vault ? history.rebalancesFor(vault) : EMPTY_REBALANCES;
    const latest = latestSharePrice === undefined ? undefined : Number(latestSharePrice);
    return {
      series: seriesWithLatest(points, latest, now),
      change24h: changeOver(points, latest, DAY_SECONDS, now),
      change7d: changeOver(points, latest, WEEK_SECONDS, now),
      rebalances,
      isLoading: history.isLoading,
      isReady: history.isReady,
      error: history.error,
      refetch: history.refetch,
    };
  }, [vault, latestSharePrice, history, now]);
}
