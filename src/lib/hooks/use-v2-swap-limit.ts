"use client";

import { useMemo } from "react";
import { useReadContract, useReadContracts } from "wagmi";
import type { Address } from "viem";
import { strategyTokenV2Abi } from "@/lib/abi/generated";
import { v2Abis, ZERO_ADDRESS } from "@/lib/protocol";
import { largestLegScale, maxTotalUsdg, type WeightedHolding } from "@/lib/protocol/swap-limit";
import { readValue } from "@/lib/hooks/use-v2-discovery-shared";

const STALE_MS = 60_000;

export interface V2SwapLimit {
  capUsdg?: bigint;
  legScale?: bigint;
  maxTotalUsdg?: bigint;
  isUnlimited: boolean;
}

export function useV2SwapLimit(vault: Address, holdings: readonly WeightedHolding[]): V2SwapLimit {
  const desk = useReadContract({
    address: vault,
    abi: v2Abis.vault,
    functionName: "venue",
    query: { staleTime: STALE_MS },
  });

  const nestedTokens = useMemo(() => holdings.filter((holding) => holding.isStrategyToken).map((holding) => holding.token), [holdings]);

  const stage = useReadContracts({
    contracts: [
      ...(desk.data ? [{ address: desk.data, abi: v2Abis.desk, functionName: "maxSwapUsdg" as const }] : []),
      ...nestedTokens.map((token) => ({ address: token, abi: strategyTokenV2Abi, functionName: "vault" as const })),
    ],
    query: { enabled: desk.data !== undefined, staleTime: STALE_MS },
  });

  const capUsdg = readValue<bigint>(stage.data?.[0]);
  const childVaults = useMemo(
    () => nestedTokens.map((_, index) => readValue<Address>(stage.data?.[index + 1]) ?? ZERO_ADDRESS),
    [nestedTokens, stage.data],
  );

  const children = useReadContracts({
    contracts: childVaults.map((childVault) => ({ address: childVault, abi: v2Abis.vault, functionName: "getConstituents" as const })),
    query: { enabled: nestedTokens.length > 0 && stage.data !== undefined && !childVaults.includes(ZERO_ADDRESS), staleTime: STALE_MS },
  });

  return useMemo<V2SwapLimit>(() => {
    if (capUsdg === undefined) return { isUnlimited: false };
    if (capUsdg === 0n) return { capUsdg, isUnlimited: true };
    const byToken = new Map<string, readonly WeightedHolding[]>();
    nestedTokens.forEach((token, index) => {
      const list = readValue<readonly WeightedHolding[]>(children.data?.[index]);
      if (list) byToken.set(token.toLowerCase(), list);
    });
    const legScale = largestLegScale(holdings, byToken);
    return {
      capUsdg,
      legScale,
      maxTotalUsdg: legScale === undefined ? undefined : maxTotalUsdg(capUsdg, legScale),
      isUnlimited: false,
    };
  }, [capUsdg, holdings, nestedTokens, children.data]);
}
