"use client";

import { useCallback } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useAccount, useReadContract } from "wagmi";
import type { Address } from "viem";
import type { DescribedError } from "@/lib/errors";
import { socialRegistryAbi, useSocialRegistryAddress } from "@/lib/social-registry";
import { useTxFlow, type TxStatus } from "@/lib/hooks/use-tx-flow";

export interface UseFollowResult {
  isFollowing: boolean;
  isAvailable: boolean;
  isConnected: boolean;
  isLoading: boolean;
  status: TxStatus;
  error: DescribedError | undefined;
  toggle: () => Promise<void>;
}

export function useFollow(target: Address | undefined): UseFollowResult {
  const { address: account, isConnected } = useAccount();
  const registry = useSocialRegistryAddress();
  const queryClient = useQueryClient();
  const flow = useTxFlow();

  const query = useReadContract({
    address: registry,
    abi: socialRegistryAbi,
    functionName: "isFollowing",
    args: account && target ? [account, target] : undefined,
    query: { enabled: Boolean(registry && account && target) },
  });

  const toggle = useCallback(async () => {
    if (!registry || !target || !account) return;
    const nextFunction = query.data === true ? "unfollow" : "follow";
    try {
      await flow.send({ address: registry, abi: socialRegistryAbi, functionName: nextFunction, args: [target] });
      await queryClient.invalidateQueries();
    } catch {
      return;
    }
  }, [registry, target, account, query.data, flow, queryClient]);

  return {
    isFollowing: query.data === true,
    isAvailable: Boolean(registry),
    isConnected,
    isLoading: query.isLoading,
    status: flow.status,
    error: flow.failure,
    toggle,
  };
}
