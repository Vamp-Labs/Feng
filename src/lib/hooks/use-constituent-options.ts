"use client";

import { useMemo } from "react";
import { useActiveNetwork } from "@/lib/addresses-context";
import { useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import { getConstituentEligibility, RAW_ASSET_DEPTH } from "@/lib/composability";

export interface ConstituentOption {
  address: `0x${string}`;
  label: string;
  symbol: string;
  isStrategyToken: boolean;
  depth: number;
  eligible: boolean;
  reason?: string;
}

export function useConstituentOptions() {
  const { addresses } = useActiveNetwork();
  const { strategies, isLoading } = useMarketplaceStrategies();

  const options = useMemo<ConstituentOption[]>(() => {
    const stockOptions: ConstituentOption[] = Object.entries(addresses.stockTokens).map(
      ([symbol, address]) => ({
        address,
        label: `${symbol} — mock stock token`,
        symbol,
        isStrategyToken: false,
        depth: RAW_ASSET_DEPTH,
        eligible: true,
      }),
    );

    const strategyOptions: ConstituentOption[] = strategies.map((s) => {
      const eligibility = getConstituentEligibility(s.depth);
      return {
        address: s.token,
        label: `${s.symbol ?? "Strategy"} — depth ${s.depth} Strategy Token`,
        symbol: s.symbol ?? "STRAT",
        isStrategyToken: true,
        depth: s.depth,
        eligible: eligibility.eligible,
        reason: eligibility.reason,
      };
    });

    return [...stockOptions, ...strategyOptions];
  }, [addresses.stockTokens, strategies]);

  return { options, isLoading };
}
