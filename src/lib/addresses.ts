import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { Address } from "viem";
import type { NetworkKey } from "@/lib/networks";
import { getNetworkDefinition, resolveActiveNetworkKey } from "@/lib/networks";
import { resolveContractVersion, type ContractVersion } from "@/lib/inception";

export type Universe = "sandbox" | "live";

export interface DeployedVault {
  symbol: string;
  name: string;
  vault: Address;
  token: Address;
  universe: Universe;
  depth: number;
}

export interface LiveDeployment {
  usdg: Address;
  usdgDecimals: number;
  stockTokens: Record<string, Address>;
  strategyFactory: Address;
  venue: Address;
  vaults: DeployedVault[];
}

export interface DeploymentAddresses {
  schemaVersion?: number;
  chainId: number;
  rpcUrl: string;
  explorerUrl: string;
  deployedAt?: number;
  usdg: Address;
  usdgDecimals?: number;
  stockTokens: Record<string, Address>;
  priceOracles: Record<string, Address>;
  oracle?: Address;
  venue?: Address;
  vaultDeployer?: Address;
  lens?: Address;
  faucet?: Address;
  guardian?: Address;
  strategyFactory: Address;
  rebalanceEngine: Address;
  marketplaceRegistry: Address;
  socialRegistry?: Address;
  maxPriceStaleness?: number;
  deskSpreadBps?: number;
  defaultMaxSlippageBps?: number;
  checkpointMinInterval?: number;
  vaults?: DeployedVault[];
  live?: LiveDeployment;
}

function deploymentsPath(network: NetworkKey): string {
  return join(process.cwd(), "deployments", network, "addresses.json");
}

function deploymentsPathV2(network: NetworkKey): string {
  return join(process.cwd(), "deployments", `${network}-v2`, "addresses.json");
}

function devFixturePath(): string {
  return join(process.cwd(), "src", "lib", "dev", "anvil-addresses.json");
}

const REQUIRED_V2_KEYS = ["oracle", "venue", "lens", "strategyFactory", "marketplaceRegistry"] as const;

function readJson(path: string): DeploymentAddresses {
  return JSON.parse(readFileSync(path, "utf-8")) as DeploymentAddresses;
}

function assertV2(addresses: DeploymentAddresses, path: string): DeploymentAddresses {
  if (addresses.schemaVersion !== 2) {
    throw new Error(`${path} is not a schemaVersion 2 deployment file.`);
  }
  const missing = REQUIRED_V2_KEYS.filter((key) => !addresses[key]);
  if (missing.length > 0) {
    throw new Error(`${path} is missing V2 keys: ${missing.join(", ")}.`);
  }
  return addresses;
}

function readV2(network: NetworkKey): DeploymentAddresses {
  const primary = deploymentsPathV2(network);
  try {
    return assertV2(readJson(primary), primary);
  } catch (error) {
    const fallback = deploymentsPath(network);
    try {
      return assertV2(readJson(fallback), fallback);
    } catch {
      throw new Error(
        `NEXT_PUBLIC_CONTRACT_VERSION=v2 needs a V2 deployment at deployments/${network}-v2/addresses.json ` +
          `(or a schemaVersion 2 file at deployments/${network}/addresses.json). ` +
          `Original error: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
}

let cache: { network: NetworkKey; version: ContractVersion; addresses: DeploymentAddresses } | null = null;

export function loadAddresses(network: NetworkKey): DeploymentAddresses {
  const version = resolveContractVersion();
  if (cache && cache.network === network && cache.version === version) {
    return cache.addresses;
  }

  if (version === "v2") {
    const addresses = readV2(network);
    cache = { network, version, addresses };
    return addresses;
  }

  const primaryPath = network === "anvil-local" ? devFixturePath() : deploymentsPath(network);

  try {
    const addresses = readJson(primaryPath);
    cache = { network, version, addresses };
    return addresses;
  } catch (error) {
    if (network !== "anvil-local") {
      throw new Error(
        `No deployment addresses found at deployments/${network}/addresses.json. ` +
          `This file is owned by the Contracts/Integration roles and is written after a real deploy — ` +
          `until it lands, set NEXT_PUBLIC_NETWORK=anvil-local to run against your own local anvil fixture. ` +
          `Original error: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
    throw new Error(
      `No local anvil fixture found at src/lib/dev/anvil-addresses.json. ` +
        `Run the anvil fixture deploy script first (see dev/fixture/README.md). ` +
        `Original error: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

export function loadActiveAddresses(): DeploymentAddresses {
  return loadAddresses(resolveActiveNetworkKey());
}

export function loadActiveNetworkConfig(): { network: NetworkKey; addresses: DeploymentAddresses } {
  const network = resolveActiveNetworkKey();
  const addresses = loadAddresses(network);
  const definition = getNetworkDefinition(network);
  return {
    network,
    addresses: {
      ...addresses,
      chainId: definition.chainId,
      rpcUrl: definition.rpcUrl,
      explorerUrl: definition.explorerUrl,
    },
  };
}
