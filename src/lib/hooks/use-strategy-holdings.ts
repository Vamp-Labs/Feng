"use client";

import { useMemo } from "react";
import { useReadContracts } from "wagmi";
import { protocolAbis } from "@/lib/protocol";
import { resolveHoldings, tickersByAddress, type Holding } from "@/lib/holding-tones";
import { useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import { useContracts } from "@/lib/use-contracts";

const RETRIES = 3;

export function useStrategyHoldings() {
  const { addresses } = useContracts();
  const { strategies } = useMarketplaceStrategies();

  const vaults = useMemo(() => strategies.map((strategy) => strategy.vault), [strategies]);

  const query = useReadContracts({
    contracts: vaults.map((vault) => ({
      address: vault,
      abi: protocolAbis.vault,
      functionName: "getConstituents" as const,
    })),
    query: {
      enabled: vaults.length > 0,
      staleTime: (cached) => (cached.state.data?.every((entry) => entry.status === "success") ? Infinity : 0),
      gcTime: Infinity,
      retry: RETRIES,
    },
  });

  const tickers = useMemo(() => tickersByAddress(addresses.stockTokens), [addresses.stockTokens]);

  const holdings = useMemo(() => {
    const byVault: Partial<Record<string, Holding[]>> = {};
    vaults.forEach((vault, index) => {
      const entry = query.data?.[index];
      if (entry?.status === "success") {
        byVault[vault] = resolveHoldings(entry.result, tickers, strategies);
      }
    });
    return byVault;
  }, [vaults, query.data, tickers, strategies]);

  return { holdings, isLoading: vaults.length > 0 && query.isPending };
}
