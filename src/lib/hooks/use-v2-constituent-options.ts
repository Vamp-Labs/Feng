"use client";

import { useMemo } from "react";
import { useReadContracts } from "wagmi";
import type { Address } from "viem";
import { getConstituentEligibility, RAW_ASSET_DEPTH } from "@/lib/composability";
import { useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import type { ConstituentOption } from "@/lib/hooks/use-constituent-options";
import { IS_V2, universeAddresses, universeOfVault, v2Abis, ZERO_ADDRESS, type Universe } from "@/lib/protocol";
import { useContracts } from "@/lib/use-contracts";

const READS_PER_STOCK = 2;

export function useV2ConstituentOptions(universe: Universe) {
  const { addresses, v2 } = useContracts();
  const { strategies, isLoading: strategiesLoading } = useMarketplaceStrategies();
  const scope = useMemo(() => universeAddresses(addresses, universe), [addresses, universe]);

  const stocks = useMemo(() => Object.entries(scope.stockTokens), [scope.stockTokens]);
  const universeStrategies = useMemo(
    () => strategies.filter((strategy) => universeOfVault(addresses, strategy.vault) === scope.universe),
    [strategies, addresses, scope.universe],
  );

  const oracle = v2?.oracle;
  const venue = scope.venue;

  const support = useReadContracts({
    contracts:
      oracle && venue
        ? stocks.flatMap(([, token]) => [
            { address: oracle, abi: v2Abis.oracle, functionName: "isSupported" as const, args: [token] as const },
            { address: venue, abi: v2Abis.desk, functionName: "isSupported" as const, args: [token] as const },
          ])
        : [],
    query: { enabled: IS_V2 && Boolean(oracle) && Boolean(venue) && stocks.length > 0 },
  });

  const membership = useReadContracts({
    contracts: universeStrategies.map((strategy) => ({
      address: scope.strategyFactory,
      abi: v2Abis.factory,
      functionName: "vaultOf" as const,
      args: [strategy.token] as const,
    })),
    query: { enabled: IS_V2 && universeStrategies.length > 0 },
  });

  const options = useMemo<ConstituentOption[]>(() => {
    const stockOptions = stocks.map(([symbol, address], index): ConstituentOption => {
      const oracleEntry = support.data?.[index * READS_PER_STOCK];
      const venueEntry = support.data?.[index * READS_PER_STOCK + 1];
      const oracleOk = oracleEntry?.status === "success" ? oracleEntry.result === true : undefined;
      const venueOk = venueEntry?.status === "success" ? venueEntry.result === true : undefined;
      const known = oracleOk !== undefined && venueOk !== undefined;
      const eligible = known && oracleOk === true && venueOk === true;
      const reason = !known
        ? "Checking price feed and desk support."
        : oracleOk === false
          ? "No price feed for this token yet."
          : venueOk === false
            ? "The trading desk does not list this token yet."
            : undefined;
      return {
        address: address as Address,
        label: `${symbol} - stock token`,
        symbol,
        isStrategyToken: false,
        depth: RAW_ASSET_DEPTH,
        eligible,
        reason,
      };
    });

    const strategyOptions = universeStrategies.map((strategy, index): ConstituentOption => {
      const entry = membership.data?.[index];
      const registered = entry?.status === "success" ? entry.result !== ZERO_ADDRESS : undefined;
      const depthRule = getConstituentEligibility(strategy.depth);
      const eligible = registered === true && depthRule.eligible;
      return {
        address: strategy.token,
        label: `${strategy.symbol ?? "Strategy"} - depth ${strategy.depth} Strategy Token`,
        symbol: strategy.symbol ?? "STRAT",
        isStrategyToken: true,
        depth: strategy.depth,
        eligible,
        reason: !depthRule.eligible
          ? depthRule.reason
          : registered === false
            ? "This strategy was not created by this universe's factory."
            : registered === undefined
              ? "Checking strategy registration."
              : undefined,
      };
    });

    return [...stockOptions, ...strategyOptions];
  }, [stocks, support.data, universeStrategies, membership.data]);

  const readsFailed = [support.data, membership.data].some((entries) => entries?.some((entry) => entry.status === "failure"));

  return {
    options,
    isLoading: strategiesLoading || support.isLoading || membership.isLoading,
    error: support.error ?? membership.error ?? (readsFailed ? new Error("A support check did not return.") : null),
  };
}
