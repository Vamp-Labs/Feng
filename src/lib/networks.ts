import type { Address } from "viem";

export type NetworkKey = "robinhood-testnet" | "arbitrum-sepolia" | "anvil-local";

export interface NetworkDefinition {
  key: NetworkKey;
  label: string;
  chainId: number;
  rpcUrl: string;
  explorerUrl: string;
  isTestnet: boolean;
  multicall3?: Address;
}

export const MULTICALL3_ADDRESS: Address = "0xcA11bde05977b3631167028862bE2a173976CA11";

const ROBINHOOD_TESTNET: NetworkDefinition = {
  key: "robinhood-testnet",
  label: "Robinhood Chain Testnet",
  chainId: 46630,
  rpcUrl: "https://rpc.testnet.chain.robinhood.com",
  explorerUrl: "https://explorer.testnet.chain.robinhood.com",
  isTestnet: true,
  multicall3: MULTICALL3_ADDRESS,
};

const ARBITRUM_SEPOLIA: NetworkDefinition = {
  key: "arbitrum-sepolia",
  label: "Arbitrum Sepolia",
  chainId: 421614,
  rpcUrl: "https://sepolia-rollup.arbitrum.io/rpc",
  explorerUrl: "https://sepolia.arbiscan.io",
  isTestnet: true,
  multicall3: MULTICALL3_ADDRESS,
};

const ANVIL_LOCAL: NetworkDefinition = {
  key: "anvil-local",
  label: "Anvil (local)",
  chainId: 31337,
  rpcUrl: "http://127.0.0.1:8545",
  explorerUrl: "",
  isTestnet: true,
};

const NETWORKS: Record<NetworkKey, NetworkDefinition> = {
  "robinhood-testnet": ROBINHOOD_TESTNET,
  "arbitrum-sepolia": ARBITRUM_SEPOLIA,
  "anvil-local": ANVIL_LOCAL,
};

function isNetworkKey(value: string): value is NetworkKey {
  return value === "robinhood-testnet" || value === "arbitrum-sepolia" || value === "anvil-local";
}

export function resolveActiveNetworkKey(): NetworkKey {
  const raw = process.env.NEXT_PUBLIC_NETWORK ?? "robinhood-testnet";
  return isNetworkKey(raw) ? raw : "robinhood-testnet";
}

export function getNetworkDefinition(network: NetworkKey): NetworkDefinition {
  const base = NETWORKS[network];
  if (network !== resolveActiveNetworkKey()) {
    return base;
  }
  const chainIdOverride = process.env.NEXT_PUBLIC_CHAIN_ID;
  const rpcUrlOverride = process.env.NEXT_PUBLIC_RPC_URL;
  const explorerUrlOverride = process.env.NEXT_PUBLIC_EXPLORER_URL;
  return {
    ...base,
    chainId: chainIdOverride ? Number(chainIdOverride) : base.chainId,
    rpcUrl: rpcUrlOverride ?? base.rpcUrl,
    explorerUrl: explorerUrlOverride ?? base.explorerUrl,
  };
}

export function getActiveNetworkDefinition(): NetworkDefinition {
  return getNetworkDefinition(resolveActiveNetworkKey());
}

export const FALLBACK_NETWORK_KEY: NetworkKey =
  resolveActiveNetworkKey() === "robinhood-testnet" ? "arbitrum-sepolia" : "robinhood-testnet";
