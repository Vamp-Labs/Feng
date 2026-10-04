"use client";

import { useQuery } from "@tanstack/react-query";
import { usePublicClient } from "wagmi";
import { getAbiItem, type Address, type Hex } from "viem";
import { scanRange } from "@/lib/hooks/use-v2-discovery-logs";
import { IS_V2, v2Abis } from "@/lib/protocol";

const depositEvent = getAbiItem({ abi: v2Abis.vault, name: "Deposit" });
const redeemEvent = getAbiItem({ abi: v2Abis.vault, name: "Redeem" });
const rebalancedEvent = getAbiItem({ abi: v2Abis.vault, name: "Rebalanced" });

const ACTIVITY_BLOCK_WINDOW = 500_000n;
const MAX_ENTRIES = 25;
const STALE_MS = 30_000;

export type ActivityKind = "deposit" | "redeem" | "rebalance";

export interface ActivityEntry {
  kind: ActivityKind;
  hash: Hex;
  blockNumber: bigint;
  account?: Address;
  usdgAmount?: bigint;
  shares?: bigint;
}

export interface StrategyActivity {
  entries: ActivityEntry[];
  isLoading: boolean;
  error: Error | null;
}

export function useStrategyActivity(vault: Address | undefined): StrategyActivity {
  const client = usePublicClient();

  const query = useQuery({
    queryKey: ["strategy-activity", vault],
    queryFn: async (): Promise<ActivityEntry[]> => {
      if (!client || !vault) return [];
      const head = await client.getBlockNumber();
      const from = head > ACTIVITY_BLOCK_WINDOW ? head - ACTIVITY_BLOCK_WINDOW : 0n;

      const [deposits, redeems, rebalances] = await Promise.all([
        scanRange(from, head, (fromBlock, toBlock) =>
          client.getLogs({ address: vault, event: depositEvent, strict: true, fromBlock, toBlock }),
        ),
        scanRange(from, head, (fromBlock, toBlock) =>
          client.getLogs({ address: vault, event: redeemEvent, strict: true, fromBlock, toBlock }),
        ),
        scanRange(from, head, (fromBlock, toBlock) =>
          client.getLogs({ address: vault, event: rebalancedEvent, strict: true, fromBlock, toBlock }),
        ),
      ]);

      const entries: ActivityEntry[] = [
        ...deposits.map((log) => ({
          kind: "deposit" as const,
          hash: log.transactionHash,
          blockNumber: log.blockNumber,
          account: log.args.receiver,
          usdgAmount: log.args.usdgAmount,
          shares: log.args.shares,
        })),
        ...redeems.map((log) => ({
          kind: "redeem" as const,
          hash: log.transactionHash,
          blockNumber: log.blockNumber,
          account: log.args.receiver,
          usdgAmount: log.args.usdgAmount,
          shares: log.args.shares,
        })),
        ...rebalances.map((log) => ({
          kind: "rebalance" as const,
          hash: log.transactionHash,
          blockNumber: log.blockNumber,
        })),
      ];

      return entries.toSorted((a, b) => (b.blockNumber > a.blockNumber ? 1 : b.blockNumber < a.blockNumber ? -1 : 0)).slice(0, MAX_ENTRIES);
    },
    enabled: IS_V2 && Boolean(client) && Boolean(vault),
    staleTime: STALE_MS,
    retry: 1,
  });

  return { entries: query.data ?? [], isLoading: query.isPending, error: query.error };
}
