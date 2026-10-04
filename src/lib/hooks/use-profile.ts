"use client";

import { useReadContract } from "wagmi";
import type { Address } from "viem";
import { socialRegistryAbi, useSocialRegistryAddress } from "@/lib/social-registry";

export interface UseProfileResult {
  handle: string | undefined;
  bio: string | undefined;
  isAvailable: boolean;
  isLoading: boolean;
}

export function useProfile(user: Address | undefined): UseProfileResult {
  const registry = useSocialRegistryAddress();

  const query = useReadContract({
    address: registry,
    abi: socialRegistryAbi,
    functionName: "profileOf",
    args: user ? [user] : undefined,
    query: { enabled: Boolean(registry && user), staleTime: 60_000 },
  });

  const [handle, bio] = query.data ?? [undefined, undefined];

  return {
    handle: handle && handle.length > 0 ? handle : undefined,
    bio: bio && bio.length > 0 ? bio : undefined,
    isAvailable: Boolean(registry),
    isLoading: query.isLoading,
  };
}
