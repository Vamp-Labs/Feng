import type { Address } from "viem";
import type { DeploymentAddresses, DeployedVault, LiveDeployment, Universe } from "@/lib/addresses";
import { resolveContractVersion, type ContractVersion } from "@/lib/inception";
import { erc20Abi, marketplaceRegistryAbi, rebalanceEngineAbi, stockTokenAbi, strategyVaultAbi } from "@/lib/abi";
import {
  chainlinkPriceOracleV2Abi,
  marketplaceRegistryV2Abi,
  oracleDeskAbi,
  rebalanceEngineV2Abi,
  strategyFactoryV2Abi,
  strategyLensAbi,
  strategyVaultV2Abi,
} from "@/lib/abi/generated";

export type { Constituent } from "@/lib/abi";
export type { ContractVersion as ProtocolVersion } from "@/lib/inception";
export type { DeployedVault, LiveDeployment, Universe } from "@/lib/addresses";

export const ZERO_ADDRESS: Address = "0x0000000000000000000000000000000000000000";

export const PROTOCOL_VERSION: ContractVersion = resolveContractVersion();
export const IS_V2: boolean = PROTOCOL_VERSION === "v2";

type PickByName<Abi extends readonly unknown[], Name extends string> = Abi extends readonly [
  infer Head,
  ...infer Tail,
]
  ? Head extends { readonly name: Name }
    ? [Head, ...PickByName<Tail, Name>]
    : PickByName<Tail, Name>
  : [];

type SharedVaultFunction =
  | "previewDeposit"
  | "previewRedeem"
  | "totalAssetsUSDG"
  | "getConstituents"
  | "depth"
  | "rebalanceNeeded"
  | "executeRebalance";

type SharedRegistryFunction = "getAllStrategies" | "getStrategyInfo";

type SharedEngineFunction = "checkUpkeep" | "performRebalance";

const SHARED_VAULT_FUNCTIONS: readonly SharedVaultFunction[] = [
  "previewDeposit",
  "previewRedeem",
  "totalAssetsUSDG",
  "getConstituents",
  "depth",
  "rebalanceNeeded",
  "executeRebalance",
];

const SHARED_REGISTRY_FUNCTIONS: readonly SharedRegistryFunction[] = ["getAllStrategies", "getStrategyInfo"];

const SHARED_ENGINE_FUNCTIONS: readonly SharedEngineFunction[] = ["checkUpkeep", "performRebalance"];

type AbiLike = readonly { readonly type: string; readonly name?: string }[];

function pickFunctions<Result>(abi: AbiLike, names: readonly string[]): Result {
  return abi.filter((item) => item.type === "function" && item.name !== undefined && names.includes(item.name)) as Result;
}

export type SharedVaultAbi = PickByName<typeof strategyVaultAbi, SharedVaultFunction>;
export type SharedRegistryAbi = PickByName<typeof marketplaceRegistryAbi, SharedRegistryFunction>;
export type SharedEngineAbi = PickByName<typeof rebalanceEngineAbi, SharedEngineFunction>;

const sharedVaultAbi = pickFunctions<SharedVaultAbi>(IS_V2 ? strategyVaultV2Abi : strategyVaultAbi, SHARED_VAULT_FUNCTIONS);
const sharedRegistryAbi = pickFunctions<SharedRegistryAbi>(
  IS_V2 ? marketplaceRegistryV2Abi : marketplaceRegistryAbi,
  SHARED_REGISTRY_FUNCTIONS,
);
const sharedEngineAbi = pickFunctions<SharedEngineAbi>(
  IS_V2 ? rebalanceEngineV2Abi : rebalanceEngineAbi,
  SHARED_ENGINE_FUNCTIONS,
);

export const protocolAbis = {
  vault: sharedVaultAbi,
  registry: sharedRegistryAbi,
  engine: sharedEngineAbi,
  erc20: erc20Abi,
  stockToken: stockTokenAbi,
} as const;

export const v2Abis = {
  vault: strategyVaultV2Abi,
  factory: strategyFactoryV2Abi,
  registry: marketplaceRegistryV2Abi,
  lens: strategyLensAbi,
  desk: oracleDeskAbi,
  oracle: chainlinkPriceOracleV2Abi,
} as const;

export interface V2Deployment {
  oracle: Address;
  venue: Address;
  lens: Address;
  strategyFactory: Address;
  marketplaceRegistry: Address;
  guardian?: Address;
  faucet?: Address;
  usdgDecimals?: number;
  maxPriceStaleness?: number;
  defaultMaxSlippageBps?: number;
  vaults: DeployedVault[];
  live?: LiveDeployment;
}

export function v2Deployment(addresses: DeploymentAddresses): V2Deployment | undefined {
  if (!IS_V2) return undefined;
  const { oracle, venue, lens } = addresses;
  if (!oracle || !venue || !lens) return undefined;
  return {
    oracle,
    venue,
    lens,
    strategyFactory: addresses.strategyFactory,
    marketplaceRegistry: addresses.marketplaceRegistry,
    guardian: addresses.guardian,
    faucet: addresses.faucet,
    usdgDecimals: addresses.usdgDecimals,
    maxPriceStaleness: addresses.maxPriceStaleness,
    defaultMaxSlippageBps: addresses.defaultMaxSlippageBps,
    vaults: addresses.vaults ?? [],
    live: addresses.live,
  };
}

export interface UniverseAddresses {
  universe: Universe;
  usdg: Address;
  usdgDecimals?: number;
  stockTokens: Record<string, Address>;
  strategyFactory: Address;
  venue?: Address;
}

export function hasLiveUniverse(addresses: DeploymentAddresses): boolean {
  return IS_V2 && addresses.live !== undefined && addresses.live.strategyFactory !== ZERO_ADDRESS;
}

export function universeAddresses(addresses: DeploymentAddresses, universe: Universe): UniverseAddresses {
  if (universe === "live" && hasLiveUniverse(addresses) && addresses.live) {
    return {
      universe,
      usdg: addresses.live.usdg,
      usdgDecimals: addresses.live.usdgDecimals,
      stockTokens: addresses.live.stockTokens,
      strategyFactory: addresses.live.strategyFactory,
      venue: addresses.live.venue,
    };
  }
  return {
    universe: "sandbox",
    usdg: addresses.usdg,
    usdgDecimals: addresses.usdgDecimals,
    stockTokens: addresses.stockTokens,
    strategyFactory: addresses.strategyFactory,
    venue: addresses.venue,
  };
}

export function universeOfVault(addresses: DeploymentAddresses, vault: Address): Universe {
  const lower = vault.toLowerCase();
  const live = addresses.live?.vaults.some((entry) => entry.vault.toLowerCase() === lower);
  return live ? "live" : "sandbox";
}

export function protocolContracts(addresses: DeploymentAddresses) {
  const v2 = v2Deployment(addresses);
  return {
    version: PROTOCOL_VERSION,
    addresses,
    v2,
    marketplaceRegistry: { address: addresses.marketplaceRegistry, abi: protocolAbis.registry } as const,
    rebalanceEngine: { address: addresses.rebalanceEngine, abi: protocolAbis.engine } as const,
    usdg: { address: addresses.usdg, abi: erc20Abi } as const,
    vault: (vaultAddress: Address) => ({ address: vaultAddress, abi: protocolAbis.vault }) as const,
    erc20: (tokenAddress: Address) => ({ address: tokenAddress, abi: erc20Abi }) as const,
    stockToken: (tokenAddress: Address) => ({ address: tokenAddress, abi: stockTokenAbi }) as const,
  };
}

export type ProtocolContracts = ReturnType<typeof protocolContracts>;
