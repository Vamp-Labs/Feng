"use client";

import { useMemo } from "react";
import { useReadContract, useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import { useContracts } from "@/lib/use-contracts";
import { erc20Abi, strategyVaultAbi } from "@/lib/abi";
import { sinceInceptionReturn } from "@/lib/inception";
import { useUsdgDecimals } from "@/lib/hooks/use-usdg-decimals";
import { useMarketplaceStrategiesV2 } from "@/lib/hooks/use-v2-discovery-marketplace";
import { IS_V2, type Universe } from "@/lib/protocol";

export interface StrategySummary {
  vault: `0x${string}`;
  token: `0x${string}`;
  creator: `0x${string}`;
  depth: number;
  createdAt: bigint;
  name?: string;
  symbol?: string;
  totalAssetsUSDG?: bigint;
  sinceInception?: number;
  description?: string;
  tags?: readonly string[];
  universe?: Universe;
  sharePrice?: bigint;
  inceptionSharePrice?: bigint;
  usdgDecimals?: number;
  navUsd?: number;
}

export interface MarketplaceData {
  strategies: StrategySummary[];
  isLoading: boolean;
  isEmpty: boolean;
  error: Error | null;
  isRetrying: boolean;
  refetch: () => void;
}

export function navUsdOf(strategy: Pick<StrategySummary, "navUsd" | "totalAssetsUSDG" | "usdgDecimals">): number | undefined {
  if (strategy.navUsd !== undefined) return strategy.navUsd;
  if (strategy.totalAssetsUSDG === undefined || strategy.usdgDecimals === undefined) return undefined;
  return Number(formatUnits(strategy.totalAssetsUSDG, strategy.usdgDecimals));
}

export function sumNavUsd(strategies: readonly StrategySummary[]): number | undefined {
  const navs = strategies.map(navUsdOf).filter((nav): nav is number => nav !== undefined);
  return navs.length === 0 ? undefined : navs.reduce((sum, nav) => sum + nav, 0);
}

const READS_PER_STRATEGY = 5;

function useMarketplaceStrategiesV1(): MarketplaceData {
  const { marketplaceRegistry } = useContracts();
  const usdgDecimals = useUsdgDecimals();

  const vaultsQuery = useReadContract({
    ...marketplaceRegistry,
    functionName: "getAllStrategies",
  });

  const vaults = useMemo(() => (vaultsQuery.data ?? []) as `0x${string}`[], [vaultsQuery.data]);

  const infoQuery = useReadContracts({
    contracts: vaults.map((vault) => ({
      ...marketplaceRegistry,
      functionName: "getStrategyInfo" as const,
      args: [vault] as const,
    })),
    query: { enabled: vaults.length > 0 },
  });

  const tokens = useMemo(
    () =>
      (infoQuery.data ?? []).map((entry) =>
        entry.status === "success" ? (entry.result[0] as `0x${string}`) : undefined,
      ),
    [infoQuery.data],
  );

  const detailQuery = useReadContracts({
    contracts: vaults.flatMap((vault, index) => {
      const token = tokens[index];
      if (!token) return [];
      return [
        { address: vault, abi: strategyVaultAbi, functionName: "totalAssetsUSDG" as const },
        { address: token, abi: erc20Abi, functionName: "name" as const },
        { address: token, abi: erc20Abi, functionName: "symbol" as const },
        { address: token, abi: erc20Abi, functionName: "totalSupply" as const },
        { address: token, abi: erc20Abi, functionName: "decimals" as const },
      ];
    }),
    query: { enabled: vaults.length > 0 && tokens.every((t) => t !== undefined) },
  });

  const strategies = useMemo<StrategySummary[]>(() => {
    if (!infoQuery.data) return [];

    return vaults.map((vault, index) => {
      const info = infoQuery.data[index];
      const [token, creator, depth, createdAt] =
        info?.status === "success" ? info.result : [vault, vault, 0, 0n];

      const detailBase = index * READS_PER_STRATEGY;
      const detail = detailQuery.data;
      const totalAssetsUSDG = detail?.[detailBase]?.status === "success" ? (detail[detailBase].result as bigint) : undefined;
      const name = detail?.[detailBase + 1]?.status === "success" ? (detail[detailBase + 1].result as string) : undefined;
      const symbol = detail?.[detailBase + 2]?.status === "success" ? (detail[detailBase + 2].result as string) : undefined;
      const totalSupply = detail?.[detailBase + 3]?.status === "success" ? (detail[detailBase + 3].result as bigint) : undefined;
      const shareDecimals = detail?.[detailBase + 4]?.status === "success" ? Number(detail[detailBase + 4].result) : undefined;
      const sinceInception =
        totalAssetsUSDG !== undefined && totalSupply !== undefined && shareDecimals !== undefined && usdgDecimals !== undefined
          ? sinceInceptionReturn({ navUsdg: totalAssetsUSDG, totalSupply, usdgDecimals, shareDecimals })
          : undefined;

      return {
        vault,
        token,
        creator,
        depth: Number(depth),
        createdAt: BigInt(createdAt),
        totalAssetsUSDG,
        usdgDecimals,
        sinceInception,
        name,
        symbol,
      };
    });
  }, [vaults, infoQuery.data, detailQuery.data, usdgDecimals]);

  return {
    strategies,
    isLoading: vaultsQuery.isLoading || infoQuery.isLoading,
    isEmpty: vaultsQuery.isSuccess && vaults.length === 0,
    error: vaultsQuery.error ?? infoQuery.error,
    isRetrying: vaultsQuery.failureCount > 0 || infoQuery.failureCount > 0,
    refetch: () => {
      vaultsQuery.refetch();
      infoQuery.refetch();
      detailQuery.refetch();
    },
  };
}

export const useMarketplaceStrategies: () => MarketplaceData = IS_V2 ? useMarketplaceStrategiesV2 : useMarketplaceStrategiesV1;
