"use client";

import { useMemo } from "react";
import { formatUsdCompact } from "@/lib/discovery-format";
import { sumNavUsd, useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import { usePositions } from "@/lib/hooks/use-positions";

export interface PortfolioStats {
  ready: boolean;
  isConnected: boolean;
  held: number;
  total: number;
  nested: number;
  nestedPercent: number;
  tvl: string;
}

export function usePortfolioStats(): PortfolioStats {
  const { strategies, isLoading, error } = useMarketplaceStrategies();
  const { positions, isConnected, isLoading: positionsLoading } = usePositions();

  return useMemo(() => {
    const total = strategies.length;
    const nested = strategies.filter((strategy) => strategy.depth >= 2).length;
    const tvlUsd = sumNavUsd(strategies);
    return {
      ready: !isLoading && !error && (!isConnected || !positionsLoading),
      isConnected,
      held: positions.length,
      total,
      nested,
      nestedPercent: total === 0 ? 0 : Math.round((nested / total) * 100),
      tvl: tvlUsd === undefined ? "—" : formatUsdCompact(tvlUsd),
    };
  }, [strategies, positions, isLoading, error, isConnected, positionsLoading]);
}
