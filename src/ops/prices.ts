import { logOpsError } from "./redact";
import { withRetry, type Budget } from "./rpc";
import type { OpsConfig } from "./config";

export const PRICE_API_BASE = "https://api.robinhood.com/rhj/prices";

export type QuoteStatus = "ok" | "halt" | "spread" | "clock" | "error";

export type Quote = {
  symbol: string;
  status: QuoteStatus;
  reason: string | null;
  bid: string | null;
  ask: string | null;
  spreadBps: number | null;
  answer: bigint | null;
};

export type FetchLike = (url: string, init: { signal: AbortSignal; headers: Record<string, string> }) => Promise<{
  ok: boolean;
  status: number;
  json: () => Promise<unknown>;
}>;

const DECIMAL = /^\d+(\.\d+)?$/;

export function parseDecimalToScaled(text: string, decimals: number): bigint | null {
  const trimmed = text.trim();
  if (!DECIMAL.test(trimmed)) return null;
  const [whole, fraction = ""] = trimmed.split(".");
  const padded = (fraction + "0".repeat(decimals)).slice(0, decimals);
  return BigInt(whole) * 10n ** BigInt(decimals) + (padded === "" ? 0n : BigInt(padded));
}

export function scaleMid(bid18: bigint, ask18: bigint, feedDecimals: number): bigint {
  const mid18 = (bid18 + ask18 + 1n) / 2n;
  if (feedDecimals === 18) return mid18;
  if (feedDecimals > 18) return mid18 * 10n ** BigInt(feedDecimals - 18);
  const divisor = 10n ** BigInt(18 - feedDecimals);
  return (mid18 + divisor / 2n) / divisor;
}

export function spreadBps(bid18: bigint, ask18: bigint): number {
  const mid18 = (bid18 + ask18) / 2n;
  if (mid18 <= 0n) return Number.POSITIVE_INFINITY;
  return Number(((ask18 - bid18) * 10_000n * 100n) / mid18) / 100;
}

function asDecimalString(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

function failed(symbol: string, status: QuoteStatus, reason: string, extra: Partial<Quote> = {}): Quote {
  return { symbol, status, reason, bid: null, ask: null, spreadBps: null, answer: null, ...extra };
}

export function parseQuote(
  symbol: string,
  body: unknown,
  feedDecimals: number,
  config: Pick<OpsConfig, "spreadMaxBps" | "clockSkewSec">,
  nowMs: number,
): Quote {
  if (typeof body !== "object" || body === null) return failed(symbol, "error", "response is not an object");
  const quotes = (body as Record<string, unknown>).quotes;
  if (!Array.isArray(quotes) || quotes.length === 0) return failed(symbol, "error", "no quotes in response");
  const first: unknown = quotes[0];
  if (typeof first !== "object" || first === null) return failed(symbol, "error", "quote is not an object");
  const quote = first as Record<string, unknown>;
  if (quote.tokenSymbol !== symbol) return failed(symbol, "error", "tokenSymbol mismatch");
  const bidText = asDecimalString(quote.tokenBid);
  const askText = asDecimalString(quote.tokenAsk);
  if (bidText === null || askText === null) return failed(symbol, "error", "tokenBid or tokenAsk missing");
  if (typeof quote.isTradingHalt !== "boolean") return failed(symbol, "error", "isTradingHalt missing");
  const bid18 = parseDecimalToScaled(bidText, 18);
  const ask18 = parseDecimalToScaled(askText, 18);
  if (bid18 === null || ask18 === null) return failed(symbol, "error", "tokenBid or tokenAsk not a decimal");
  const base = { bid: bidText, ask: askText };
  if (bid18 <= 0n || ask18 < bid18) return failed(symbol, "error", "bid or ask out of order", base);
  if (quote.isTradingHalt) return failed(symbol, "halt", "isTradingHalt is true", base);
  const spread = spreadBps(bid18, ask18);
  if (spread > config.spreadMaxBps) {
    return failed(symbol, "spread", `spread ${spread.toFixed(0)} bps above ${config.spreadMaxBps}`, {
      ...base,
      spreadBps: spread,
    });
  }
  const generated = typeof quote.generatedAt === "string" ? Date.parse(quote.generatedAt) : Number.NaN;
  if (!Number.isFinite(generated)) {
    return failed(symbol, "clock", "generatedAt missing or unreadable", { ...base, spreadBps: spread });
  }
  if (Math.abs(nowMs - generated) > config.clockSkewSec * 1000) {
    return failed(symbol, "clock", "generatedAt differs from the local clock", { ...base, spreadBps: spread });
  }
  const answer = scaleMid(bid18, ask18, feedDecimals);
  if (answer <= 0n) return failed(symbol, "error", "scaled answer is not positive", base);
  return { symbol, status: "ok", reason: null, bid: bidText, ask: askText, spreadBps: spread, answer };
}

const defaultFetch: FetchLike = (url, init) => fetch(url, { signal: init.signal, headers: init.headers, cache: "no-store" });

const API_SYMBOL_OVERRIDES: Record<string, string> = {
  TSMC: "TSM",
};

export async function fetchQuote(
  symbol: string,
  feedDecimals: number,
  config: OpsConfig,
  budget: Budget,
  fetchImpl: FetchLike = defaultFetch,
  nowMs: () => number = Date.now,
): Promise<Quote> {
  try {
    const body = await withRetry(
      async () => {
        const signal = AbortSignal.any([budget.signal, AbortSignal.timeout(config.rpcTimeoutMs)]);
        const apiSymbol = API_SYMBOL_OVERRIDES[symbol] ?? symbol;
        const response = await fetchImpl(`${config.priceApiBase}/${encodeURIComponent(apiSymbol)}`, {
          signal,
          headers: { accept: "application/json" },
        });
        if (!response.ok) {
          const error = new Error(`price api http ${response.status}`) as Error & { status: number };
          error.status = response.status;
          throw error;
        }
        return budget.race(response.json(), `price json ${symbol}`);
      },
      { attempts: config.rpcAttempts, baseMs: config.rpcRetryBaseMs, budget },
    );
    return parseQuote(symbol, body, feedDecimals, config, nowMs());
  } catch (error) {
    logOpsError(`price api ${symbol}`, "price api error", error);
    return failed(symbol, "error", "price api error");
  }
}

export async function fetchQuotes(
  symbols: readonly { symbol: string; decimals: number }[],
  config: OpsConfig,
  budget: Budget,
  fetchImpl?: FetchLike,
): Promise<Map<string, Quote>> {
  const settled = await Promise.all(
    symbols.map((entry) => fetchQuote(entry.symbol, entry.decimals, config, budget, fetchImpl)),
  );
  return new Map(settled.map((quote) => [quote.symbol, quote]));
}
