"use client";

import { useMemo } from "react";
import { useAccount, useReadContracts } from "wagmi";
import { useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import { erc20Abi } from "@/lib/abi";
import { IS_V2, universeOfVault, v2Abis, type Universe } from "@/lib/protocol";
import { useContracts } from "@/lib/use-contracts";

export interface Position {
  vault: `0x${string}`;
  token: `0x${string}`;
  name?: string;
  symbol?: string;
  balance: bigint;
  decimals: number;
  universe: Universe;
  usdgDecimals?: number;
  sharePrice?: bigint;
  valueUsdg?: bigint;
}

const READS_PER_STRATEGY = IS_V2 ? 4 : 2;
const DEFAULT_TOKEN_DECIMALS = 18;

export function usePositions() {
  const { address } = useAccount();
  const { addresses } = useContracts();
  const {
    strategies,
    isLoading: strategiesLoading,
    error: strategiesError,
    isRetrying,
    refetch: refetchStrategies,
  } = useMarketplaceStrategies();

  const balanceQuery = useReadContracts({
    contracts: strategies.flatMap((s) => [
      { address: s.token, abi: erc20Abi, functionName: "balanceOf" as const, args: address ? ([address] as const) : undefined },
      { address: s.token, abi: erc20Abi, functionName: "decimals" as const },
      ...(IS_V2
        ? [
            { address: s.vault, abi: v2Abis.vault, functionName: "sharePrice" as const },
            { address: s.vault, abi: v2Abis.vault, functionName: "usdgDecimals" as const },
          ]
        : []),
    ]),
    query: { enabled: Boolean(address) && strategies.length > 0 },
  });

  const positions = useMemo<Position[]>(() => {
    if (!address || !balanceQuery.data) return [];
    const data = balanceQuery.data;
    return strategies
      .map((s, index) => {
        const base = index * READS_PER_STRATEGY;
        const balanceResult = data[base];
        const decimalsResult = data[base + 1];
        const balance = balanceResult?.status === "success" ? (balanceResult.result as bigint) : 0n;
        const decimals = decimalsResult?.status === "success" ? Number(decimalsResult.result) : DEFAULT_TOKEN_DECIMALS;
        const sharePriceResult = IS_V2 ? data[base + 2] : undefined;
        const usdgDecimalsResult = IS_V2 ? data[base + 3] : undefined;
        const sharePrice = sharePriceResult?.status === "success" ? (sharePriceResult.result as bigint) : undefined;
        const usdgDecimals =
          usdgDecimalsResult?.status === "success" ? Number(usdgDecimalsResult.result) : undefined;
        return {
          vault: s.vault,
          token: s.token,
          name: s.name,
          symbol: s.symbol,
          balance,
          decimals,
          universe: universeOfVault(addresses, s.vault),
          usdgDecimals,
          sharePrice,
          valueUsdg: sharePrice === undefined ? undefined : (balance * sharePrice) / 10n ** BigInt(decimals),
        };
      })
      .filter((p) => p.balance > 0n);
  }, [address, strategies, balanceQuery.data, addresses]);

  return {
    positions,
    isLoading: strategiesLoading || balanceQuery.isLoading,
    isConnected: Boolean(address),
    error: strategiesError ?? balanceQuery.error ?? undefined,
    isRetrying: isRetrying || balanceQuery.failureCount > 0,
    refetch: () => {
      refetchStrategies();
      balanceQuery.refetch();
    },
  };
}
