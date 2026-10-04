import { formatUnits } from "viem";

const FULL = new Intl.NumberFormat("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const COMPACT = new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 });

export const SECONDS_PER_DAY = 86_400;

export function usdgToNumber(amount: bigint, decimals: number): number {
  return Number(formatUnits(amount, decimals));
}

export function formatUsd(value: number): string {
  return `$${FULL.format(value)}`;
}

export function formatUsdCompact(value: number): string {
  return `$${COMPACT.format(value)}`;
}

export function formatSharePrice(value: number): string {
  if (!Number.isFinite(value)) return "--";
  if (value === 0) return "$0.0000";
  if (Math.abs(value) >= 0.01) return `$${value.toLocaleString("en-US", { minimumFractionDigits: 4, maximumFractionDigits: 4 })}`;
  return `$${value.toPrecision(4)}`;
}

export function formatAgo(seconds: number): string {
  const value = Math.max(0, Math.floor(seconds));
  if (value < 45) return "just now";
  if (value < 90) return "1 min ago";
  if (value < 3_600) return `${Math.round(value / 60)} min ago`;
  if (value < 86_400) return `${Math.round(value / 3_600)} h ago`;
  return `${Math.round(value / 86_400)} d ago`;
}

export function formatAge(seconds: number): string {
  const value = Math.max(0, Math.floor(seconds));
  if (value < 60) return "under 1 min";
  if (value < 3_600) return `${Math.round(value / 60)} min`;
  if (value < 86_400) return `${Math.round(value / 3_600)} h`;
  return `${Math.round(value / 86_400)} d`;
}

const pad = (value: number) => String(value).padStart(2, "0");

export function formatCountdown(seconds: number): string {
  const value = Math.max(0, Math.floor(seconds));
  const hours = Math.floor(value / 3_600);
  const minutes = Math.floor((value % 3_600) / 60);
  const secs = value % 60;
  return hours > 0 ? `${hours}:${pad(minutes)}:${pad(secs)}` : `${pad(minutes)}:${pad(secs)}`;
}

export function formatInterval(seconds: number): string {
  if (seconds % SECONDS_PER_DAY === 0) return `${seconds / SECONDS_PER_DAY} d`;
  if (seconds % 3_600 === 0) return `${seconds / 3_600} h`;
  if (seconds % 60 === 0) return `${seconds / 60} min`;
  return `${seconds} s`;
}

export function formatBpsPoints(bps: number): string {
  return `${(bps / 100).toLocaleString("en-US", { minimumFractionDigits: 1, maximumFractionDigits: 2 })}%`;
}

export type ExplorerKind = "tx" | "address";

export function explorerLink(base: string, kind: ExplorerKind, value: string): string | undefined {
  if (!base) return undefined;
  return `${base.replace(/\/$/, "")}/${kind}/${value}`;
}
