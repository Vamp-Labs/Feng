"use client";

import { useMemo } from "react";
import { useReadContract, useReadContracts } from "wagmi";
import { useContracts } from "@/lib/use-contracts";
import { erc20Abi, strategyTokenAbi } from "@/lib/abi";
import { sinceInceptionReturn } from "@/lib/inception";
import { useUsdgDecimals } from "@/lib/hooks/use-usdg-decimals";
import { useStrategyDetailV2 } from "@/lib/hooks/use-v2-discovery-detail";
import { IS_V2, type Universe } from "@/lib/protocol";
import type { Constituent } from "@/lib/abi";

export interface ConstituentDetail extends Constituent {
  name?: string;
  symbol?: string;
  nestedVault?: `0x${string}`;
  currentBps?: number;
  effectiveMaxBps?: number;
  childNavUsd?: number;
  childSharePrice?: bigint;
  childSinceInception?: number;
}

export interface StrategyDetailV2Fields {
  description?: string;
  tags: readonly string[];
  universe: Universe;
  usdgDecimals?: number;
  navUsd?: number;
  sharePrice?: bigint;
  inceptionSharePrice?: bigint;
  weights?: number[];
  idleBps?: number;
  maxWeightBps?: number;
  rebalanceInterval?: number;
  lastRebalanceTimestamp?: number;
  maxPriceStaleness?: number;
  paused?: boolean;
  priceFresh?: boolean;
  oldestPriceUpdatedAt?: number;
}

export interface StrategyDetailData {
  token?: `0x${string}`;
  creator?: `0x${string}`;
  createdAt?: bigint;
  depth?: number;
  totalAssetsUSDG?: bigint;
  usdgDecimals?: number;
  sinceInception?: number;
  constituents: ConstituentDetail[];
  rebalanceNeeded?: { timeBased: boolean; thresholdBased: boolean };
  name?: string;
  symbol?: string;
  decimals?: number;
  isLoading: boolean;
  error: Error | null;
  isRetrying: boolean;
  refetch: () => void;
  v2?: StrategyDetailV2Fields;
}

function useStrategyDetailV1(vault: `0x${string}` | undefined): StrategyDetailData {
  const { marketplaceRegistry, vault: vaultContract } = useContracts();
  const usdgDecimals = useUsdgDecimals();
  const enabled = Boolean(vault);
  const vaultConfig = vault ? vaultContract(vault) : undefined;

  const infoQuery = useReadContract({
    ...marketplaceRegistry,
    functionName: "getStrategyInfo",
    args: vault ? [vault] : undefined,
    query: { enabled },
  });

  const coreQuery = useReadContracts({
    contracts: vaultConfig
      ? [
          { ...vaultConfig, functionName: "totalAssetsUSDG" as const },
          { ...vaultConfig, functionName: "getConstituents" as const },
          { ...vaultConfig, functionName: "depth" as const },
          { ...vaultConfig, functionName: "rebalanceNeeded" as const },
        ]
      : [],
    query: { enabled },
  });

  const token = infoQuery.data?.[0];

  const tokenMetaQuery = useReadContracts({
    contracts: token
      ? [
          { address: token, abi: erc20Abi, functionName: "name" as const },
          { address: token, abi: erc20Abi, functionName: "symbol" as const },
          { address: token, abi: erc20Abi, functionName: "decimals" as const },
          { address: token, abi: erc20Abi, functionName: "totalSupply" as const },
        ]
      : [],
    query: { enabled: Boolean(token) },
  });

  const constituents = useMemo<Constituent[]>(() => {
    const raw = coreQuery.data?.[1];
    if (raw?.status !== "success") return [];
    return (raw.result as readonly { token: `0x${string}`; targetWeightBps: number; isStrategyToken: boolean }[]).map(
      (c) => ({ token: c.token, targetWeightBps: Number(c.targetWeightBps), isStrategyToken: c.isStrategyToken }),
    );
  }, [coreQuery.data]);

  const constituentMetaQuery = useReadContracts({
    contracts: constituents.flatMap((c) => [
      { address: c.token, abi: erc20Abi, functionName: "name" as const },
      { address: c.token, abi: erc20Abi, functionName: "symbol" as const },
      { address: c.token, abi: strategyTokenAbi, functionName: "vault" as const },
    ]),
    query: { enabled: constituents.length > 0 },
  });

  const constituentDetails = useMemo<ConstituentDetail[]>(() => {
    return constituents.map((c, index) => {
      const base = index * 3;
      const data = constituentMetaQuery.data;
      const name = data?.[base]?.status === "success" ? (data[base].result as string) : undefined;
      const symbol = data?.[base + 1]?.status === "success" ? (data[base + 1].result as string) : undefined;
      const nestedVault =
        data?.[base + 2]?.status === "success" ? (data[base + 2].result as `0x${string}`) : undefined;
      return { ...c, name, symbol, nestedVault };
    });
  }, [constituents, constituentMetaQuery.data]);

  const totalAssetsUSDG = coreQuery.data?.[0]?.status === "success" ? (coreQuery.data[0].result as bigint) : undefined;
  const depth = coreQuery.data?.[2]?.status === "success" ? Number(coreQuery.data[2].result) : undefined;
  const rebalanceNeeded =
    coreQuery.data?.[3]?.status === "success"
      ? (coreQuery.data[3].result as readonly [boolean, boolean])
      : undefined;

  const shareDecimals =
    tokenMetaQuery.data?.[2]?.status === "success" ? Number(tokenMetaQuery.data[2].result) : undefined;
  const totalSupply =
    tokenMetaQuery.data?.[3]?.status === "success" ? (tokenMetaQuery.data[3].result as bigint) : undefined;
  const sinceInception =
    totalAssetsUSDG !== undefined && totalSupply !== undefined && shareDecimals !== undefined && usdgDecimals !== undefined
      ? sinceInceptionReturn({ navUsdg: totalAssetsUSDG, totalSupply, usdgDecimals, shareDecimals })
      : undefined;

  const creator = infoQuery.data?.[1];
  const createdAt = infoQuery.data?.[3];

  return {
    token,
    creator,
    createdAt,
    depth,
    totalAssetsUSDG,
    usdgDecimals,
    sinceInception,
    constituents: constituentDetails,
    rebalanceNeeded: rebalanceNeeded ? { timeBased: rebalanceNeeded[0], thresholdBased: rebalanceNeeded[1] } : undefined,
    name: tokenMetaQuery.data?.[0]?.status === "success" ? (tokenMetaQuery.data[0].result as string) : undefined,
    symbol: tokenMetaQuery.data?.[1]?.status === "success" ? (tokenMetaQuery.data[1].result as string) : undefined,
    decimals: tokenMetaQuery.data?.[2]?.status === "success" ? (tokenMetaQuery.data[2].result as number) : undefined,
    isLoading: infoQuery.isLoading || coreQuery.isLoading,
    error: infoQuery.error ?? coreQuery.error,
    isRetrying: infoQuery.failureCount > 0 || coreQuery.failureCount > 0,
    refetch: () => {
      infoQuery.refetch();
      coreQuery.refetch();
    },
  };
}

export const useStrategyDetail: (vault: `0x${string}` | undefined) => StrategyDetailData = IS_V2
  ? useStrategyDetailV2
  : useStrategyDetailV1;
