import { defineChain, type Chain } from "viem";
import {
  FALLBACK_NETWORK_KEY,
  getActiveNetworkDefinition,
  getNetworkDefinition,
  type NetworkDefinition,
} from "@/lib/networks";

function toViemChain(definition: NetworkDefinition): Chain {
  return defineChain({
    id: definition.chainId,
    name: definition.label,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: {
      default: { http: [definition.rpcUrl] },
    },
    blockExplorers: definition.explorerUrl
      ? { default: { name: "Explorer", url: definition.explorerUrl } }
      : undefined,
    contracts: definition.multicall3 ? { multicall3: { address: definition.multicall3 } } : undefined,
    testnet: definition.isTestnet,
  });
}

export function buildConfiguredChains(): [Chain, ...Chain[]] {
  const active = getActiveNetworkDefinition();
  const primary = toViemChain(active);

  if (active.key === "anvil-local") {
    return [primary];
  }

  const fallback = toViemChain(getNetworkDefinition(FALLBACK_NETWORK_KEY));
  return [primary, fallback];
}
