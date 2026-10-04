import type { Abi, Address } from "viem";

export interface ReadCall {
  address: Address;
  abi: Abi;
  functionName: string;
  args?: readonly unknown[];
}

export function readCall(address: Address, abi: Abi, functionName: string, args?: readonly unknown[]): ReadCall {
  return { address, abi, functionName, args };
}

export interface ReadEntry {
  status: string;
  result?: unknown;
  error?: unknown;
}

export function readError(entry: ReadEntry | undefined): Error | null {
  if (entry?.status !== "failure") return null;
  return entry.error instanceof Error ? entry.error : new Error("A contract read failed.");
}

export function readNumber(entry: ReadEntry | undefined): number | undefined {
  const value = readValue<bigint | number>(entry);
  return value === undefined ? undefined : Number(value);
}

export function readValue<T>(entry: ReadEntry | undefined): T | undefined {
  return entry?.status === "success" ? (entry.result as T) : undefined;
}

export const POLL_MS = 30_000;
export const MAX_STRATEGIES = 200;
export const PAGE_SIZE = 50;
