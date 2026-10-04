import { createConfig } from "@privy-io/wagmi";
import { http } from "wagmi";
import type { Transport } from "viem";
import { buildConfiguredChains } from "@/lib/chains";

const RPC_BATCH_WAIT_MS = 16;
const RPC_RETRY_COUNT = 4;
const RPC_RETRY_DELAY_MS = 250;
const RPC_TIMEOUT_MS = 12_000;

export function createWagmiConfig() {
  const chains = buildConfiguredChains();
  const transports: Record<number, Transport> = {};
  for (const chain of chains) {
    transports[chain.id] = http(chain.rpcUrls.default.http[0], {
      batch: { wait: RPC_BATCH_WAIT_MS },
      retryCount: RPC_RETRY_COUNT,
      retryDelay: RPC_RETRY_DELAY_MS,
      timeout: RPC_TIMEOUT_MS,
    });
  }

  return createConfig({
    chains,
    transports,
    batch: { multicall: { wait: RPC_BATCH_WAIT_MS } },
  });
}
