"use client";

import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import { getAbiItem, type Address } from "viem";
import { scanRange } from "@/lib/hooks/use-v2-discovery-logs";
import { IS_V2, v2Abis } from "@/lib/protocol";

const depositEvent = getAbiItem({ abi: v2Abis.vault, name: "Deposit" });

const RECENT_BLOCK_WINDOW = 300_000n;
const STALE_MS = 60_000;

export interface RecentDepositActivity {
  countByVault: ReadonlyMap<string, number>;
  isLoading: boolean;
  error: Error | null;
}

export function useRecentDepositActivity(vaults: readonly Address[]): RecentDepositActivity {
  const client = usePublicClient();
  const key = vaults.map((vault) => vault.toLowerCase()).toSorted().join(",");

  const query = useQuery({
    queryKey: ["recent-deposit-activity", key],
    queryFn: async (): Promise<Map<string, number>> => {
      if (!client || vaults.length === 0) return new Map();
      const head = await client.getBlockNumber();
      const from = head > RECENT_BLOCK_WINDOW ? head - RECENT_BLOCK_WINDOW : 0n;
      const logs = await scanRange(from, head, (fromBlock, toBlock) =>
        client.getLogs({ address: [...vaults], event: depositEvent, fromBlock, toBlock }),
      );
      const counts = new Map<string, number>();
      for (const log of logs) {
        const vault = log.address.toLowerCase();
        counts.set(vault, (counts.get(vault) ?? 0) + 1);
      }
      return counts;
    },
    enabled: IS_V2 && Boolean(client) && vaults.length > 0,
    staleTime: STALE_MS,
    gcTime: 5 * STALE_MS,
    retry: 1,
  });

  return {
    countByVault: query.data ?? new Map(),
    isLoading: query.isPending && vaults.length > 0,
    error: query.error,
  };
}
