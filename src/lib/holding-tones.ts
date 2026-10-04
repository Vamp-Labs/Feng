import type { Address } from "viem";
import type { Constituent } from "@/lib/abi";
import { formatBps, shortenAddress } from "@/lib/format";
import type { StrategySummary } from "@/lib/hooks/use-marketplace";

export type HoldingTone = "orchid" | "periwinkle" | "sky" | "ink" | "slate" | "layered";

export interface Holding {
  key: string;
  label: string;
  weightBps: number;
  nested: boolean;
  tone: HoldingTone;
}

const TICKER_TONES: Record<string, HoldingTone> = {
  TSLA: "orchid",
  AMZN: "periwinkle",
  NFLX: "sky",
  PLTR: "ink",
  AMD: "slate",
};

export function stockHolding(ticker: string, weightBps: number): Holding {
  return { key: ticker, label: ticker, weightBps, nested: false, tone: TICKER_TONES[ticker] ?? "slate" };
}

export function nestedHolding(symbol: string, weightBps: number): Holding {
  return { key: `nested-${symbol}`, label: symbol, weightBps, nested: true, tone: "layered" };
}

export function tickersByAddress(stockTokens: Record<string, Address>): ReadonlyMap<string, string> {
  return new Map(Object.entries(stockTokens).map(([ticker, address]) => [address.toLowerCase(), ticker]));
}

export function resolveHoldings(
  constituents: readonly Constituent[],
  tickers: ReadonlyMap<string, string>,
  strategies: readonly Pick<StrategySummary, "token" | "symbol">[],
): Holding[] {
  return constituents.map((constituent) => {
    const token = constituent.token.toLowerCase();
    const weightBps = Number(constituent.targetWeightBps);

    if (constituent.isStrategyToken) {
      const symbol = strategies.find((strategy) => strategy.token.toLowerCase() === token)?.symbol;
      return nestedHolding(symbol ?? shortenAddress(constituent.token), weightBps);
    }

    const ticker = tickers.get(token);
    return ticker
      ? stockHolding(ticker, weightBps)
      : { key: token, label: shortenAddress(constituent.token), weightBps, nested: false, tone: "slate" };
  });
}

export function describeHoldings(holdings: readonly Holding[]): string {
  return holdings.map((holding) => `${holding.label} ${formatBps(holding.weightBps)}`).join(", ");
}
