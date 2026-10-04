export const FAUCET_ENDPOINT = "/api/faucet";

export const PAXOS_FAUCET_URL = "https://faucet.paxos.com";
export const ROBINHOOD_FAUCET_URL = "https://faucet.testnet.chain.robinhood.com";

export const FAUCET_STATUSES = ["funded", "already-claimed", "faucet-empty", "invalid-address", "rate-limited"] as const;

export type FaucetStatus = (typeof FAUCET_STATUSES)[number];

export type FaucetOutcome =
  | { status: FaucetStatus; txHash?: `0x${string}` }
  | { status: "error"; message: string };

const TX_HASH_PATTERN = /^0x[0-9a-fA-F]{64}$/;

const UNAVAILABLE_MESSAGE = "The faucet is not available on this deployment yet.";
const SERVER_ERROR_MESSAGE = "The faucet hit an error. Try again in a moment.";
const UNREACHABLE_MESSAGE = "Could not reach the faucet. Check your connection and try again.";

export const FAUCET_MESSAGES: Record<FaucetStatus | "error", string> = {
  funded: "Test funds sent. Your balances update in a few seconds.",
  "already-claimed": "This wallet already has enough test funds.",
  "faucet-empty": "The faucet is out of funds right now. Try again later.",
  "invalid-address": "The faucet could not use this wallet address. Test funds go to regular wallet addresses only.",
  "rate-limited": "Too many requests. Wait a minute and try again.",
  error: SERVER_ERROR_MESSAGE,
};

function isFaucetStatus(value: unknown): value is FaucetStatus {
  return typeof value === "string" && (FAUCET_STATUSES as readonly string[]).includes(value);
}

function failureFor(httpStatus: number): FaucetOutcome {
  if (httpStatus === 404) return { status: "error", message: UNAVAILABLE_MESSAGE };
  return { status: "error", message: SERVER_ERROR_MESSAGE };
}

export function parseFaucetResponse(httpStatus: number, body: unknown): FaucetOutcome {
  if (typeof body !== "object" || body === null) return failureFor(httpStatus);
  const record = body as Record<string, unknown>;
  if (!isFaucetStatus(record.status)) return failureFor(httpStatus);
  const txHash = typeof record.txHash === "string" && TX_HASH_PATTERN.test(record.txHash)
    ? (record.txHash as `0x${string}`)
    : undefined;
  return txHash ? { status: record.status, txHash } : { status: record.status };
}

export async function claimTestFunds(address: string, signal?: AbortSignal): Promise<FaucetOutcome> {
  let response: Response;
  try {
    response = await fetch(FAUCET_ENDPOINT, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ address }),
      signal,
    });
  } catch {
    return { status: "error", message: UNREACHABLE_MESSAGE };
  }

  let body: unknown = null;
  try {
    body = await response.json();
  } catch {
    body = null;
  }
  return parseFaucetResponse(response.status, body);
}
