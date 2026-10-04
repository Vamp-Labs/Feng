"use client";

import { useMemo } from "react";
import { useReadContract, useReadContracts } from "wagmi";
import type { Address } from "viem";
import { socialRegistryAbi, useSocialRegistryAddress } from "@/lib/social-registry";

export interface UseFollowerCountResult {
  count: number | undefined;
  isAvailable: boolean;
  isLoading: boolean;
  refetch: () => void;
}

const STALE_MS = 15_000;

export function useFollowerCount(target: Address | undefined): UseFollowerCountResult {
  const registry = useSocialRegistryAddress();

  const query = useReadContract({
    address: registry,
    abi: socialRegistryAbi,
    functionName: "followerCount",
    args: target ? [target] : undefined,
    query: { enabled: Boolean(registry && target), staleTime: STALE_MS },
  });

  return {
    count: query.data === undefined ? undefined : Number(query.data),
    isAvailable: Boolean(registry),
    isLoading: query.isLoading,
    refetch: () => void query.refetch(),
  };
}

export interface UseFollowerCountsResult {
  counts: ReadonlyMap<string, number>;
  isAvailable: boolean;
  isLoading: boolean;
}

export function useFollowerCounts(targets: readonly Address[]): UseFollowerCountsResult {
  const registry = useSocialRegistryAddress();

  const contracts = useMemo(() => {
    if (!registry) return [];
    return targets.map((target) => ({
      address: registry,
      abi: socialRegistryAbi,
      functionName: "followerCount" as const,
      args: [target] as const,
    }));
  }, [registry, targets]);

  const query = useReadContracts({ contracts, query: { enabled: contracts.length > 0, staleTime: STALE_MS } });

  const counts = useMemo(() => {
    const map = new Map<string, number>();
    targets.forEach((target, index) => {
      const entry = query.data?.[index];
      if (entry?.status === "success") map.set(target.toLowerCase(), Number(entry.result));
    });
    return map;
  }, [targets, query.data]);

  return { counts, isAvailable: Boolean(registry), isLoading: query.isLoading };
}
