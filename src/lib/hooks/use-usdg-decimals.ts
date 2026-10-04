"use client";

import { useReadContract } from "wagmi";
import { useContracts } from "@/lib/use-contracts";

export function useUsdgDecimals(): number | undefined {
  const { usdg } = useContracts();
  const { data } = useReadContract({
    ...usdg,
    functionName: "decimals",
    query: { staleTime: Infinity, gcTime: Infinity },
  });
  return data === undefined ? undefined : Number(data);
}
