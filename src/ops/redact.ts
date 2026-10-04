export type ErrorKind =
  | "rpc unreachable"
  | "rpc timeout"
  | "rpc rate limited"
  | "rpc error"
  | "call reverted"
  | "time budget exhausted"
  | "price api error"
  | "internal error";

const URL_PATTERN = /[a-z][a-z0-9+.-]*:\/\/\S+/gi;
const IPV4_PATTERN = /\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b/g;
const HOST_PATTERN = /\b(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?/gi;
const PRIVATE_KEY_PATTERN = /\b(?:0x)?[0-9a-fA-F]{64}\b/g;
const TOKEN_PATTERN = /[A-Za-z0-9_-]{20,}/g;
const LOG_DEDUPE_MS = 60_000;
const LOG_DEDUPE_MAX = 200;

const recentLogs = new Map<string, number>();

export function redactText(text: string): string {
  return text
    .replace(URL_PATTERN, "<redacted>")
    .replace(IPV4_PATTERN, "<redacted>")
    .replace(HOST_PATTERN, "<redacted>")
    .replace(PRIVATE_KEY_PATTERN, "<redacted>")
    .replace(TOKEN_PATTERN, "<redacted>");
}

type ErrorFacts = { text: string; status: number | null };

function collectFacts(error: unknown): ErrorFacts {
  const parts: string[] = [];
  let status: number | null = null;
  let current: unknown = error;
  for (let depth = 0; depth < 8 && current !== undefined && current !== null; depth += 1) {
    if (typeof current !== "object") {
      parts.push(String(current));
      break;
    }
    const record = current as Record<string, unknown>;
    if (status === null && typeof record.status === "number") status = record.status;
    for (const field of ["name", "code", "message", "shortMessage", "details"]) {
      const value = record[field];
      if (typeof value === "string" || typeof value === "number") parts.push(String(value));
    }
    const data = record.data;
    if (typeof data === "object" && data !== null && "errorName" in data) parts.push("execution reverted");
    current = record.cause;
  }
  return { text: parts.join(" ").toLowerCase(), status };
}

export function errorKind(error: unknown): ErrorKind {
  const { text, status } = collectFacts(error);
  if (text.includes("budgetexceedederror") || text.includes("time budget exhausted")) return "time budget exhausted";
  if (text.includes("revert")) return "call reverted";
  if (status === 429 || /rate limit|too many requests|limit exceeded/.test(text)) return "rpc rate limited";
  if (/timeout|timed out|aborted/.test(text)) return "rpc timeout";
  if (status !== null && status >= 400) return "rpc error";
  if (
    /econnrefused|econnreset|enotfound|eai_again|epipe|etimedout|fetch failed|socket hang up|network error|certificate|http request failed|und_err|\b(tls|ssl)\b/.test(
      text,
    )
  ) {
    return "rpc unreachable";
  }
  return "internal error";
}

function firstLine(error: unknown): string {
  if (error instanceof Error) {
    const viemError = error as Error & { shortMessage?: string; details?: string };
    const base = viemError.shortMessage ?? error.message;
    const details = viemError.details && !base.includes(viemError.details) ? `: ${viemError.details}` : "";
    return `${base}${details}`.split("\n")[0].slice(0, 200);
  }
  return String(error).split("\n")[0].slice(0, 200);
}

export function logOpsError(label: string, kind: ErrorKind, error: unknown, now: number = Date.now()): void {
  const detail = redactText(firstLine(error));
  const key = `${label}|${kind}|${detail}`;
  const last = recentLogs.get(key);
  if (last !== undefined && now - last < LOG_DEDUPE_MS) return;
  if (recentLogs.size >= LOG_DEDUPE_MAX) {
    for (const [entry, stamp] of recentLogs) {
      if (now - stamp >= LOG_DEDUPE_MS) recentLogs.delete(entry);
    }
    if (recentLogs.size >= LOG_DEDUPE_MAX) recentLogs.clear();
  }
  recentLogs.set(key, now);
  console.error(`ops error [${label}] ${kind}: ${detail}`);
}

export function shortError(error: unknown, label: string = "ops"): ErrorKind {
  const kind = errorKind(error);
  logOpsError(label, kind, error);
  return kind;
}
