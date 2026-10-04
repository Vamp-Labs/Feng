import { QueryClient } from "@tanstack/react-query";
import { BaseError, ContractFunctionRevertedError } from "viem";

const STALE_TIME_MS = 15_000;
const GC_TIME_MS = 5 * 60_000;
const MAX_RETRIES = 3;
const BASE_RETRY_DELAY_MS = 1_000;
const MAX_RETRY_DELAY_MS = 8_000;

function isRevert(error: unknown): boolean {
  return error instanceof BaseError && error.walk((cause) => cause instanceof ContractFunctionRevertedError) !== null;
}

export function createQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: STALE_TIME_MS,
        gcTime: GC_TIME_MS,
        retry: (failureCount, error) => failureCount < MAX_RETRIES && !isRevert(error),
        retryDelay: (attempt) => Math.min(BASE_RETRY_DELAY_MS * 2 ** attempt, MAX_RETRY_DELAY_MS),
      },
    },
  });
}
