import type { Address } from "viem";
import { socialRegistrySketchAbi } from "@/lib/abi/social-registry-sketch";
import { useActiveNetwork } from "@/lib/addresses-context";

// TEMPORARY — swap to `import { socialRegistryAbi } from "@/lib/abi/generated";`
// once docs/handoffs/05-social-registry.md's generated module lands.
export const socialRegistryAbi = socialRegistrySketchAbi;

export function useSocialRegistryAddress(): Address | undefined {
  const { addresses } = useActiveNetwork();
  return addresses.socialRegistry;
}
