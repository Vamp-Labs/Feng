import { getAbiItem, type Hex } from "viem";
import type { usePublicClient } from "wagmi";
import { isNetworkError } from "@/lib/errors";
import { v2Abis } from "@/lib/protocol";

export type ChainClient = NonNullable<ReturnType<typeof usePublicClient>>;

export const navCheckpointEvent = getAbiItem({ abi: v2Abis.vault, name: "NavCheckpoint" });
export const rebalancedEvent = getAbiItem({ abi: v2Abis.vault, name: "Rebalanced" });

export interface NavPoint {
  t: number;
  price: number;
}

export interface RebalanceLog {
  t: number;
  hash: Hex;
  blockNumber: bigint;
  timeBased: boolean;
  thresholdBased: boolean;
  sharePrice: bigint;
}

const MAX_SPLIT_DEPTH = 6;
const MIN_SPAN = 1_000n;

export async function scanRange<T>(
  from: bigint,
  to: bigint,
  fetchRange: (from: bigint, to: bigint) => Promise<T[]>,
  depth = 0,
): Promise<T[]> {
  try {
    return await fetchRange(from, to);
  } catch (error) {
    if (isNetworkError(error) || depth >= MAX_SPLIT_DEPTH || to - from < MIN_SPAN) throw error;
    const mid = from + (to - from) / 2n;
    const left = await scanRange(from, mid, fetchRange, depth + 1);
    const right = await scanRange(mid + 1n, to, fetchRange, depth + 1);
    return [...left, ...right];
  }
}
