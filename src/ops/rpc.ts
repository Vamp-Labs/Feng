import {
  createPublicClient,
  createWalletClient,
  defineChain,
  getAddress,
  http,
  type Address,
  type Chain,
  type Hex,
  type HttpTransport,
  type PublicClient,
  type WalletClient,
  type Account,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { MULTICALL3_ADDRESS, rpcUrlFor, type Deployment, type OpsConfig } from "./config";
import { shortError } from "./redact";

export { shortError };

export class BudgetExceededError extends Error {
  constructor(label: string) {
    super(`time budget exhausted during ${label}`);
    this.name = "BudgetExceededError";
  }
}

export type Budget = {
  readonly startedAt: number;
  readonly signal: AbortSignal;
  left: () => number;
  elapsed: () => number;
  canSend: () => boolean;
  race: <T>(promise: Promise<T>, label: string) => Promise<T>;
  dispose: () => void;
};

export function createBudget(totalMs: number, minSendMs: number, now: () => number = Date.now): Budget {
  const startedAt = now();
  const deadline = startedAt + totalMs;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Math.max(0, totalMs));
  const left = () => deadline - now();
  return {
    startedAt,
    signal: controller.signal,
    left,
    elapsed: () => now() - startedAt,
    canSend: () => left() >= minSendMs,
    race: <T>(promise: Promise<T>, label: string): Promise<T> => {
      const remaining = left();
      if (remaining <= 0) {
        promise.catch(() => undefined);
        return Promise.reject(new BudgetExceededError(label));
      }
      return new Promise<T>((resolve, reject) => {
        const handle = setTimeout(() => reject(new BudgetExceededError(label)), remaining);
        promise.then(
          (value) => {
            clearTimeout(handle);
            resolve(value);
          },
          (error: unknown) => {
            clearTimeout(handle);
            reject(error);
          },
        );
      });
    },
    dispose: () => clearTimeout(timer),
  };
}

const TRANSIENT_PATTERNS = [
  "certificate",
  "econnreset",
  "econnrefused",
  "etimedout",
  "enotfound",
  "eai_again",
  "epipe",
  "socket hang up",
  "fetch failed",
  "network error",
  "timeout",
  "timed out",
  "aborted",
  "und_err",
  "http request failed",
  "too many requests",
  "rate limit",
  "limit exceeded",
  "request failed",
];

const TRANSIENT_WORDS = /\b(tls|ssl)\b/;

function matchesTransient(text: string): boolean {
  const lower = text.toLowerCase();
  return TRANSIENT_PATTERNS.some((pattern) => lower.includes(pattern)) || TRANSIENT_WORDS.test(lower);
}

const RETRYABLE_STATUS = new Set([408, 413, 429, 500, 502, 503, 504]);

export function isTransientError(error: unknown): boolean {
  let current: unknown = error;
  for (let depth = 0; depth < 8 && current !== undefined && current !== null; depth += 1) {
    if (typeof current === "object") {
      const record = current as Record<string, unknown>;
      if (typeof record.status === "number") return RETRYABLE_STATUS.has(record.status);
      const data = record.data;
      if (typeof data === "object" && data !== null && "errorName" in data) return false;
      if (record.name === "ContractFunctionRevertedError" || record.name === "ExecutionRevertedError") return false;
      const text = `${String(record.name ?? "")} ${String(record.code ?? "")} ${String(record.message ?? "")}`.toLowerCase();
      if (text.includes("execution reverted") || text.includes("revert")) return false;
      if (matchesTransient(text)) return true;
      current = record.cause;
    } else {
      return matchesTransient(String(current));
    }
  }
  return false;
}

export type RetryOptions = {
  attempts: number;
  baseMs: number;
  budget?: Budget;
  shouldRetry?: (error: unknown) => boolean;
  sleep?: (ms: number) => Promise<void>;
  onRetry?: (attempt: number, error: unknown) => void;
};

const defaultSleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

export async function withRetry<T>(fn: (attempt: number) => Promise<T>, options: RetryOptions): Promise<T> {
  const shouldRetry = options.shouldRetry ?? isTransientError;
  const sleep = options.sleep ?? defaultSleep;
  let lastError: unknown;
  for (let attempt = 1; attempt <= options.attempts; attempt += 1) {
    try {
      return await fn(attempt);
    } catch (error) {
      lastError = error;
      if (error instanceof BudgetExceededError) throw error;
      if (attempt >= options.attempts || !shouldRetry(error)) throw error;
      const delay = options.baseMs * 2 ** (attempt - 1);
      if (options.budget && options.budget.left() <= delay) throw error;
      options.onRetry?.(attempt, error);
      await sleep(delay);
    }
  }
  throw lastError;
}

export function buildChain(chainId: number, rpcUrl: string): Chain {
  return defineChain({
    id: chainId,
    name: "Robinhood Chain Testnet",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [rpcUrl] } },
    contracts: { multicall3: { address: MULTICALL3_ADDRESS } },
    testnet: true,
  });
}

export type OpsPublicClient = PublicClient<HttpTransport, Chain>;

export type Signer = {
  role: "keeper" | "relayer" | "faucet";
  address: Address | null;
  account: Account | null;
};

export type SignerEnvName = "KEEPER_PRIVATE_KEY" | "RELAYER_PRIVATE_KEY" | "FAUCET_PRIVATE_KEY";

export function accountFromEnv(name: SignerEnvName, env: Record<string, string | undefined> = process.env): Account | null {
  const raw = env[name]?.trim();
  if (!raw) return null;
  const hex = raw.startsWith("0x") ? raw : `0x${raw}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(hex)) {
    throw new Error(`${name} is set but is not a 32-byte hex private key`);
  }
  return privateKeyToAccount(hex as Hex);
}

export function loadSigner(
  role: Signer["role"],
  config: OpsConfig,
  env: Record<string, string | undefined> = process.env,
): Signer {
  const envName: SignerEnvName =
    role === "keeper" ? "KEEPER_PRIVATE_KEY" : role === "relayer" ? "RELAYER_PRIVATE_KEY" : "FAUCET_PRIVATE_KEY";
  const configured =
    role === "keeper" ? config.keeperAddress : role === "relayer" ? config.relayerAddress : config.faucetAddress;
  let account: Account | null = null;
  try {
    account = accountFromEnv(envName, env);
  } catch {
    account = null;
  }
  return { role, account, address: account ? getAddress(account.address) : configured };
}

export type OpsClients = {
  chain: Chain;
  client: OpsPublicClient;
  wallet: (account: Account) => WalletClient<HttpTransport, Chain, Account>;
  call: <T>(budget: Budget | undefined, label: string, fn: () => Promise<T>) => Promise<T>;
};

export function createClients(deployment: Deployment, config: OpsConfig, budget?: Budget): OpsClients {
  const url = rpcUrlFor(deployment, config);
  const chain = buildChain(deployment.addresses.chainId, url);
  const transport = http(url, {
    timeout: config.rpcTimeoutMs,
    retryCount: Math.max(0, config.rpcAttempts - 1),
    retryDelay: config.rpcRetryBaseMs,
    fetchOptions: budget ? { signal: budget.signal } : undefined,
  });
  const client = createPublicClient({
    chain,
    transport,
    pollingInterval: 500,
    batch: { multicall: true },
  }) as OpsPublicClient;
  const call = <T>(callBudget: Budget | undefined, label: string, fn: () => Promise<T>): Promise<T> => {
    const attempt = withRetry(fn, {
      attempts: config.rpcOuterAttempts,
      baseMs: config.rpcRetryBaseMs * 2,
      budget: callBudget,
    });
    return callBudget ? callBudget.race(attempt, label) : attempt;
  };
  return {
    chain,
    client,
    wallet: (account) => createWalletClient({ account, chain, transport }),
    call,
  };
}

export type BatchCall = {
  address: Address;
  abi: readonly unknown[];
  functionName: string;
  args?: readonly unknown[];
};

export type BatchResult =
  | { ok: true; value: unknown }
  | { ok: false; error: string };

export async function batchRead(
  clients: OpsClients,
  calls: readonly BatchCall[],
  budget?: Budget,
): Promise<BatchResult[]> {
  if (calls.length === 0) return [];
  const results = await clients.call(budget, "multicall", async () => {
    const batch = (await clients.client.multicall({
      contracts: calls as unknown as Parameters<OpsPublicClient["multicall"]>[0]["contracts"],
      allowFailure: true,
      batchSize: 16_384,
    })) as readonly { status: "success" | "failure"; result?: unknown; error?: Error }[];
    const first = batch[0];
    if (first && first.status === "failure" && batch.every((entry) => entry.status === "failure") && isTransientError(first.error)) {
      throw first.error;
    }
    return batch;
  });
  return results.map((entry) =>
    entry.status === "success"
      ? { ok: true as const, value: entry.result }
      : { ok: false as const, error: shortError(entry.error) },
  );
}

export function revertName(error: unknown): string | null {
  let current: unknown = error;
  for (let depth = 0; depth < 8 && typeof current === "object" && current !== null; depth += 1) {
    const record = current as Record<string, unknown>;
    const data = record.data;
    if (typeof data === "object" && data !== null) {
      const name = (data as Record<string, unknown>).errorName;
      if (typeof name === "string") return name;
    }
    current = record.cause;
  }
  return null;
}

export function expectBigint(result: BatchResult | undefined): bigint | null {
  if (!result || !result.ok || typeof result.value !== "bigint") return null;
  return result.value;
}
