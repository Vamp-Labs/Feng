"use client";

// TEMPORARY — this file now only covers the two hooks the canonical `@/lib/social-registry`
// module doesn't have (`useFollowedTargets`, `useSetProfile`). Fold both into
// `src/lib/social-registry.ts` once `src/lib/abi/generated/socialRegistry.ts` lands per
// docs/handoffs/05-social-registry.md.

import { useCallback } from "react";
import { useReadContract } from "wagmi";
import type { Address } from "viem";
import { socialRegistryAbi, useSocialRegistryAddress } from "@/lib/social-registry";
import { useTxFlow } from "@/lib/hooks/use-tx-flow";

export function useFollowedTargets(user?: Address) {
  const registry = useSocialRegistryAddress();
  const query = useReadContract({
    address: registry,
    abi: socialRegistryAbi,
    functionName: "followedBy",
    args: user ? [user] : undefined,
    query: { enabled: Boolean(registry && user) },
  });

  return {
    available: Boolean(registry),
    targets: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  };
}

export function useSetProfile() {
  const registry = useSocialRegistryAddress();
  const flow = useTxFlow();

  const setProfile = useCallback(
    (handle: string, bio: string) => {
      if (!registry) {
        return Promise.reject(new Error("The social registry is not deployed on this network yet."));
      }
      return flow.send({ address: registry, abi: socialRegistryAbi, functionName: "setProfile", args: [handle, bio] });
    },
    [registry, flow],
  );

  return { available: Boolean(registry), setProfile, status: flow.status, error: flow.error, reset: flow.reset };
}
