import { formatEther, formatUnits, parseUnits } from "viem";

export function formatUsdg(amount: bigint, decimals: number, fractionDigits = 2): string {
  const asNumber = Number(formatUnits(amount, decimals));
  return asNumber.toLocaleString("en-US", {
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  });
}

const DECIMAL_PATTERN = /^\d*\.?\d*$/;

export function safeParseAmount(amount: string, decimals: number): bigint {
  if (!amount || !DECIMAL_PATTERN.test(amount) || amount === ".") return 0n;
  const [whole = "0", fraction = ""] = amount.split(".");
  const truncated = fraction.slice(0, decimals);
  return parseUnits(`${whole || "0"}${truncated ? `.${truncated}` : ""}`, decimals);
}

export function utf8Bytes(value: string): number {
  return new TextEncoder().encode(value).length;
}

export function formatBps(bps: number): string {
  return `${(bps / 100).toLocaleString("en-US", { maximumFractionDigits: 2 })}%`;
}

export function bpsToPercent(bps: number): number {
  return bps / 100;
}

export function percentToBps(percent: number): number {
  return Math.round(percent * 100);
}

export function sumBps(values: number[]): number {
  return values.reduce((total, value) => total + value, 0);
}

export function shortenAddress(address: string, chars = 4): string {
  if (address.length <= chars * 2 + 2) return address;
  return `${address.slice(0, chars + 2)}…${address.slice(-chars)}`;
}

export function formatTokenAmount(amount: bigint, decimals: number, fractionDigits = 4): string {
  const asNumber = Number(formatUnits(amount, decimals));
  return asNumber.toLocaleString("en-US", { maximumFractionDigits: fractionDigits });
}

export function formatEthBalance(wei: bigint): string {
  return Number(formatEther(wei)).toLocaleString("en-US", { maximumFractionDigits: 5 });
}

export function truncateToFraction(amount: bigint, decimals: number, fractionDigits: number): bigint {
  const dropped = decimals - fractionDigits;
  if (dropped <= 0) return amount;
  return amount - (amount % 10n ** BigInt(dropped));
}
