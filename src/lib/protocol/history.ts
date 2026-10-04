import { getAbiItem, type Address, type PublicClient } from "viem";
import { v2Abis } from "@/lib/protocol";

const MAX_CHUNK_BLOCKS = 200_000n;
const RANGE_ERROR_PATTERN = /range|limit|too many|exceed|response size|query returned/i;
const BLOCK_SEARCH_MARGIN_SECONDS = 3_600;

export type PositionEventKind = "deposit" | "depositInKind" | "redeem" | "redeemInKind";

export interface PositionEvent {
  kind: PositionEventKind;
  vault: Address;
  blockNumber: bigint;
  logIndex: number;
  shares: bigint;
  usdgValue: bigint;
}

export interface CostBasis {
  trackedShares: bigint;
  basis: bigint;
}

const depositEvent = getAbiItem({ abi: v2Abis.vault, name: "Deposit" });
const depositInKindEvent = getAbiItem({ abi: v2Abis.vault, name: "DepositInKind" });
const redeemEvent = getAbiItem({ abi: v2Abis.vault, name: "Redeem" });
const redeemInKindEvent = getAbiItem({ abi: v2Abis.vault, name: "RedeemInKind" });

export async function findFirstBlockAtOrAfter(client: PublicClient, timestamp: number): Promise<bigint> {
  const target = BigInt(Math.max(0, timestamp - BLOCK_SEARCH_MARGIN_SECONDS));
  let low = 0n;
  let high = await client.getBlockNumber();
  while (low < high) {
    const mid = (low + high) / 2n;
    const block = await client.getBlock({ blockNumber: mid });
    if (block.timestamp < target) low = mid + 1n;
    else high = mid;
  }
  return low;
}

async function withRangeSplit<T>(from: bigint, to: bigint, read: (from: bigint, to: bigint) => Promise<T[]>): Promise<T[]> {
  try {
    return await read(from, to);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (from >= to || !RANGE_ERROR_PATTERN.test(message)) throw error;
    const mid = (from + to) / 2n;
    const left = await withRangeSplit(from, mid, read);
    const right = await withRangeSplit(mid + 1n, to, read);
    return [...left, ...right];
  }
}

async function chunked<T>(from: bigint, to: bigint, read: (from: bigint, to: bigint) => Promise<T[]>): Promise<T[]> {
  const results: T[] = [];
  for (let start = from; start <= to; start += MAX_CHUNK_BLOCKS) {
    const end = start + MAX_CHUNK_BLOCKS - 1n < to ? start + MAX_CHUNK_BLOCKS - 1n : to;
    results.push(...(await withRangeSplit(start, end, read)));
  }
  return results;
}

export async function fetchPositionEvents(
  client: PublicClient,
  vaults: readonly Address[],
  account: Address,
  fromBlock: bigint,
): Promise<PositionEvent[]> {
  if (vaults.length === 0) return [];
  const latest = await client.getBlockNumber();
  const address = [...vaults];

  const [deposits, inKindDeposits, redeems, inKindRedeems] = await Promise.all([
    chunked(fromBlock, latest, (from, to) =>
      client.getLogs({ address, event: depositEvent, args: { receiver: account }, fromBlock: from, toBlock: to }),
    ),
    chunked(fromBlock, latest, (from, to) =>
      client.getLogs({ address, event: depositInKindEvent, args: { receiver: account }, fromBlock: from, toBlock: to }),
    ),
    chunked(fromBlock, latest, (from, to) =>
      client.getLogs({ address, event: redeemEvent, args: { owner: account }, fromBlock: from, toBlock: to }),
    ),
    chunked(fromBlock, latest, (from, to) =>
      client.getLogs({ address, event: redeemInKindEvent, args: { owner: account }, fromBlock: from, toBlock: to }),
    ),
  ]);

  const events: PositionEvent[] = [
    ...deposits.map((log) => ({
      kind: "deposit" as const,
      vault: log.address,
      blockNumber: log.blockNumber,
      logIndex: log.logIndex,
      shares: log.args.shares ?? 0n,
      usdgValue: log.args.usdgAmount ?? 0n,
    })),
    ...inKindDeposits.map((log) => ({
      kind: "depositInKind" as const,
      vault: log.address,
      blockNumber: log.blockNumber,
      logIndex: log.logIndex,
      shares: log.args.shares ?? 0n,
      usdgValue: log.args.valueUsdg ?? 0n,
    })),
    ...redeems.map((log) => ({
      kind: "redeem" as const,
      vault: log.address,
      blockNumber: log.blockNumber,
      logIndex: log.logIndex,
      shares: log.args.shares ?? 0n,
      usdgValue: log.args.usdgAmount ?? 0n,
    })),
    ...inKindRedeems.map((log) => ({
      kind: "redeemInKind" as const,
      vault: log.address,
      blockNumber: log.blockNumber,
      logIndex: log.logIndex,
      shares: log.args.shares ?? 0n,
      usdgValue: 0n,
    })),
  ];

  return events.sort((a, b) =>
    a.blockNumber === b.blockNumber ? a.logIndex - b.logIndex : a.blockNumber < b.blockNumber ? -1 : 1,
  );
}

export function averageCostBasis(events: readonly PositionEvent[]): CostBasis {
  let trackedShares = 0n;
  let basis = 0n;
  for (const event of events) {
    if (event.kind === "deposit" || event.kind === "depositInKind") {
      trackedShares += event.shares;
      basis += event.usdgValue;
      continue;
    }
    if (trackedShares === 0n) continue;
    if (event.shares >= trackedShares) {
      trackedShares = 0n;
      basis = 0n;
      continue;
    }
    basis = (basis * (trackedShares - event.shares)) / trackedShares;
    trackedShares -= event.shares;
  }
  return { trackedShares, basis };
}

export interface PositionPnl {
  costBasis: bigint;
  pnl: bigint;
  pnlRatio: number | undefined;
}

export function positionPnl(costBasis: CostBasis, balance: bigint, valueUsdg: bigint): PositionPnl | undefined {
  if (balance === 0n || costBasis.trackedShares === 0n) return undefined;
  if (balance > costBasis.trackedShares) return undefined;
  const basis = (costBasis.basis * balance) / costBasis.trackedShares;
  const pnl = valueUsdg - basis;
  const ratio = basis === 0n ? undefined : Number(pnl) / Number(basis);
  return { costBasis: basis, pnl, pnlRatio: ratio };
}
