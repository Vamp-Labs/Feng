import { readFile } from "node:fs/promises";
import path from "node:path";
import { getAddress, isAddress, type Address } from "viem";
import { logOpsError, errorKind } from "./redact";

export type RelayerMode = "hold" | "market";
export type FeedKind = "mock" | "feng";

export type EngineKind = "v1" | "v2";

export type DeploymentDef = {
  id: string;
  label: string;
  addressesPath: string;
  feedKind: FeedKind;
  engine: EngineKind;
  defaultMode: RelayerMode;
  relayer: boolean;
  keeper: boolean;
  optional: boolean;
};

export const DEPLOYMENT_REGISTRY: readonly DeploymentDef[] = [
  {
    id: "v1",
    label: "V1 mock vaults",
    addressesPath: "robinhood-testnet/addresses.json",
    feedKind: "mock",
    engine: "v1",
    defaultMode: "hold",
    relayer: true,
    keeper: true,
    optional: false,
  },
  {
    id: "v2",
    label: "V2 venue vaults",
    addressesPath: "robinhood-testnet-v2/addresses.json",
    feedKind: "feng",
    engine: "v2",
    defaultMode: "market",
    relayer: true,
    keeper: true,
    optional: true,
  },
];

export type DeploymentAddresses = {
  chainId: number;
  rpcUrl: string;
  usdg: Address;
  usdgDecimals: number | null;
  stockTokens: Record<string, Address>;
  priceOracles: Record<string, Address>;
  strategyFactory: Address;
  rebalanceEngine: Address;
  marketplaceRegistry: Address;
  schemaVersion: number;
  faucet: Address | null;
  venue: Address | null;
  maxPriceStaleness: number | null;
  checkpointMinInterval: number | null;
};

export type Deployment = {
  def: DeploymentDef;
  addresses: DeploymentAddresses;
  mode: RelayerMode;
};

export type OpsConfig = {
  budgetMs: number;
  minSendMs: number;
  rpcUrlOverride: string | null;
  rpcUrlById: Record<string, string>;
  deploymentFilter: string[] | null;
  priceApiBase: string;
  rpcTimeoutMs: number;
  rpcAttempts: number;
  rpcOuterAttempts: number;
  rpcRetryBaseMs: number;
  pushBps: number;
  heartbeatSec: number;
  hardMaxAgeSec: number;
  healthMaxAgeSec: number;
  criticalFeedAgeSec: number;
  spreadMaxBps: number;
  sanityMoveBps: number;
  maxStepBps: number;
  maxStepsPerTick: number;
  clockSkewSec: number;
  maxPriceAgeSec: number;
  sendMinWei: bigint;
  keeperMinWei: bigint;
  relayerMinWei: bigint;
  faucetMinWei: bigint;
  faucetOptional: boolean;
  dryRun: boolean;
  relayerPaused: boolean;
  keeperAddress: Address | null;
  relayerAddress: Address | null;
  faucetAddress: Address | null;
  faucetMode: "v1" | "contract";
  faucetModeExplicit: boolean;
  faucetDeploymentId: string | null;
  faucetMinClaims: number;
  deskMinCoverage: number;
  keeperPageSize: number;
  checkpointEverySec: number;
  checkpointMinIntervalSec: number;
  checkpointBatch: number;
  shockHoldSec: number;
};

export const MULTICALL3_ADDRESS: Address = "0xcA11bde05977b3631167028862bE2a173976CA11";
export const ETH_DRIP_WEI = 200_000_000_000_000n;
export const USDG_FILL_WHOLE = 10_000n;

type Env = Record<string, string | undefined>;

function num(env: Env, name: string, fallback: number): number {
  const raw = env[name];
  if (raw === undefined || raw.trim() === "") return fallback;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function flag(env: Env, name: string): boolean {
  const raw = env[name]?.trim().toLowerCase();
  return raw === "1" || raw === "true" || raw === "yes";
}

function ethToWei(env: Env, name: string, fallbackEth: string): bigint {
  const raw = env[name]?.trim();
  const text = raw && /^\d+(\.\d+)?$/.test(raw) ? raw : fallbackEth;
  const [whole, frac = ""] = text.split(".");
  return BigInt(whole) * 10n ** 18n + BigInt(frac.padEnd(18, "0").slice(0, 18));
}

function optionalAddress(env: Env, name: string): Address | null {
  const raw = env[name]?.trim();
  return raw && isAddress(raw, { strict: false }) ? getAddress(raw) : null;
}

function perDeploymentRpc(env: Env): Record<string, string> {
  const result: Record<string, string> = {};
  for (const def of DEPLOYMENT_REGISTRY) {
    const value = env[`OPS_RPC_URL_${def.id.toUpperCase()}`]?.trim();
    if (value) result[def.id] = value;
  }
  return result;
}

function idList(env: Env, name: string): string[] | null {
  const raw = env[name]?.trim();
  if (!raw) return null;
  const ids = raw
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter((item) => item !== "");
  return ids.length === 0 ? null : ids;
}

function explicitFaucetMode(env: Env): "v1" | "contract" | null {
  const raw = env.OPS_FAUCET_MODE?.trim().toLowerCase();
  return raw === "v1" || raw === "contract" ? raw : null;
}

export function loadConfig(env: Env = process.env): OpsConfig {
  return {
    budgetMs: num(env, "OPS_BUDGET_MS", 22_000),
    minSendMs: num(env, "OPS_MIN_SEND_MS", 6_000),
    rpcUrlOverride: env.OPS_RPC_URL?.trim() || null,
    rpcUrlById: perDeploymentRpc(env),
    deploymentFilter: idList(env, "OPS_DEPLOYMENTS"),
    priceApiBase: (env.OPS_PRICE_API_BASE?.trim() || "https://api.robinhood.com/rhj/prices").replace(/\/+$/, ""),
    rpcTimeoutMs: num(env, "OPS_RPC_TIMEOUT_MS", 3_000),
    rpcAttempts: Math.max(1, Math.floor(num(env, "OPS_RPC_ATTEMPTS", 3))),
    rpcOuterAttempts: Math.max(1, Math.floor(num(env, "OPS_RPC_OUTER_ATTEMPTS", 2))),
    rpcRetryBaseMs: num(env, "OPS_RPC_RETRY_BASE_MS", 200),
    pushBps: num(env, "OPS_PUSH_BPS", 10),
    heartbeatSec: num(env, "OPS_HEARTBEAT_SEC", 25 * 60),
    hardMaxAgeSec: num(env, "OPS_HARD_MAX_AGE_SEC", 12 * 3600),
    healthMaxAgeSec: num(env, "OPS_HEALTH_MAX_AGE_SEC", 35 * 60),
    criticalFeedAgeSec: num(env, "OPS_CRITICAL_FEED_AGE_SEC", 6 * 3600),
    spreadMaxBps: num(env, "OPS_SPREAD_MAX_BPS", 500),
    sanityMoveBps: num(env, "OPS_SANITY_MOVE_BPS", 5000),
    maxStepBps: num(env, "OPS_MAX_STEP_BPS", 900),
    maxStepsPerTick: Math.max(1, Math.floor(num(env, "OPS_MAX_STEPS_PER_TICK", 3))),
    clockSkewSec: num(env, "OPS_CLOCK_SKEW_SEC", 120),
    maxPriceAgeSec: num(env, "OPS_MAX_PRICE_AGE_SEC", 6 * 3600),
    sendMinWei: ethToWei(env, "OPS_SEND_MIN_ETH", "0.00002"),
    keeperMinWei: ethToWei(env, "OPS_KEEPER_MIN_ETH", "0.0003"),
    relayerMinWei: ethToWei(env, "OPS_RELAYER_MIN_ETH", "0.001"),
    faucetMinWei: ethToWei(env, "OPS_FAUCET_MIN_ETH", "0.0005"),
    faucetOptional: flag(env, "OPS_FAUCET_OPTIONAL"),
    dryRun: flag(env, "OPS_DRY_RUN"),
    relayerPaused: flag(env, "RELAYER_PAUSED"),
    keeperAddress: optionalAddress(env, "OPS_KEEPER_ADDRESS"),
    relayerAddress: optionalAddress(env, "OPS_RELAYER_ADDRESS"),
    faucetAddress: optionalAddress(env, "OPS_FAUCET_ADDRESS"),
    faucetMode: explicitFaucetMode(env) ?? "v1",
    faucetModeExplicit: explicitFaucetMode(env) !== null,
    faucetDeploymentId: env.OPS_FAUCET_DEPLOYMENT?.trim().toLowerCase() || null,
    faucetMinClaims: Math.floor(num(env, "OPS_FAUCET_MIN_CLAIMS", 3)),
    deskMinCoverage: num(env, "OPS_DESK_MIN_COVERAGE", 1),
    keeperPageSize: Math.min(50, Math.max(5, Math.floor(num(env, "OPS_KEEPER_PAGE_SIZE", 25)))),
    checkpointEverySec: num(env, "OPS_CHECKPOINT_SEC", 3_600),
    checkpointMinIntervalSec: num(env, "OPS_CHECKPOINT_MIN_SEC", 1_800),
    checkpointBatch: Math.min(25, Math.max(1, Math.floor(num(env, "OPS_CHECKPOINT_BATCH", 10)))),
    shockHoldSec: num(env, "OPS_SHOCK_HOLD_SEC", 600),
  };
}

function switchFor(env: Env, name: string, fallback: boolean): boolean {
  const raw = env[name]?.trim().toLowerCase();
  if (raw === "1" || raw === "true" || raw === "on" || raw === "yes") return true;
  if (raw === "0" || raw === "false" || raw === "off" || raw === "no") return false;
  return fallback;
}

function safeRelativePath(raw: string | undefined): string | null {
  const value = raw?.trim();
  if (!value || path.isAbsolute(value) || value.split(/[\\/]/).includes("..")) return null;
  return value;
}

export function resolveDef(def: DeploymentDef, env: Env): DeploymentDef {
  const key = def.id.toUpperCase();
  return {
    ...def,
    addressesPath: safeRelativePath(env[`OPS_ADDRESSES_${key}`]) ?? def.addressesPath,
    relayer: switchFor(env, `OPS_RELAYER_${key}`, def.relayer),
    keeper: switchFor(env, `OPS_KEEPER_${key}`, def.keeper),
  };
}

function modeFor(def: DeploymentDef, env: Env): RelayerMode {
  const specific = env[`OPS_MODE_${def.id.toUpperCase()}`]?.trim().toLowerCase();
  const global = env.OPS_RELAYER_MODE?.trim().toLowerCase();
  const chosen = specific || global;
  if (chosen === "hold" || chosen === "market") return chosen;
  return def.defaultMode;
}

function asAddress(value: unknown, label: string): Address {
  if (typeof value !== "string" || !isAddress(value, { strict: false })) {
    throw new Error(`addresses.json is missing a valid ${label}`);
  }
  return getAddress(value);
}

function asAddressMap(value: unknown, label: string): Record<string, Address> {
  if (typeof value !== "object" || value === null) {
    throw new Error(`addresses.json is missing ${label}`);
  }
  const result: Record<string, Address> = {};
  for (const [key, entry] of Object.entries(value)) {
    result[key] = asAddress(entry, `${label}.${key}`);
  }
  return result;
}

function optionalAddressField(value: unknown): Address | null {
  return typeof value === "string" && isAddress(value, { strict: false }) ? getAddress(value) : null;
}

function optionalNumberField(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : null;
}

export function parseAddresses(raw: unknown): DeploymentAddresses {
  if (typeof raw !== "object" || raw === null) throw new Error("addresses.json is not an object");
  const record = raw as Record<string, unknown>;
  const chainId = record.chainId;
  const rpcUrl = record.rpcUrl;
  if (typeof chainId !== "number") throw new Error("addresses.json is missing chainId");
  if (typeof rpcUrl !== "string") throw new Error("addresses.json is missing rpcUrl");
  const usdgDecimals = typeof record.usdgDecimals === "number" ? record.usdgDecimals : null;
  const schemaVersion = typeof record.schemaVersion === "number" ? record.schemaVersion : 1;
  return {
    chainId,
    rpcUrl,
    usdg: asAddress(record.usdg, "usdg"),
    usdgDecimals,
    stockTokens: asAddressMap(record.stockTokens, "stockTokens"),
    priceOracles: asAddressMap(record.priceOracles, "priceOracles"),
    strategyFactory: asAddress(record.strategyFactory, "strategyFactory"),
    rebalanceEngine: asAddress(record.rebalanceEngine, "rebalanceEngine"),
    marketplaceRegistry: asAddress(record.marketplaceRegistry, "marketplaceRegistry"),
    schemaVersion,
    faucet: optionalAddressField(record.faucet),
    venue: optionalAddressField(record.venue),
    maxPriceStaleness: optionalNumberField(record.maxPriceStaleness),
    checkpointMinInterval: optionalNumberField(record.checkpointMinInterval),
  };
}

const addressCache = new Map<string, Promise<DeploymentAddresses>>();

function loadAddresses(def: DeploymentDef): Promise<DeploymentAddresses> {
  const cacheKey = `${def.id}:${def.addressesPath}`;
  const cached = addressCache.get(cacheKey);
  if (cached) return cached;
  const pending = readFile(path.join(process.cwd(), "deployments", def.addressesPath), "utf8").then((text) =>
    parseAddresses(JSON.parse(text)),
  );
  addressCache.set(cacheKey, pending);
  pending.catch(() => addressCache.delete(cacheKey));
  return pending;
}

export type DeploymentLoad = {
  deployments: Deployment[];
  absent: string[];
  problems: string[];
};

function isMissingFile(error: unknown): boolean {
  return typeof error === "object" && error !== null && (error as { code?: unknown }).code === "ENOENT";
}

export async function loadDeploymentsDetailed(env: Env = process.env): Promise<DeploymentLoad> {
  const filter = idList(env, "OPS_DEPLOYMENTS");
  const defs = DEPLOYMENT_REGISTRY.filter((def) => filter === null || filter.includes(def.id)).map((def) =>
    resolveDef(def, env),
  );
  const settled = await Promise.all(
    defs.map(async (def) => {
      try {
        return { def, addresses: await loadAddresses(def), error: null };
      } catch (error) {
        return { def, addresses: null, error };
      }
    }),
  );
  const load: DeploymentLoad = { deployments: [], absent: [], problems: [] };
  for (const item of settled) {
    if (item.addresses) {
      load.deployments.push({ def: item.def, addresses: item.addresses, mode: modeFor(item.def, env) });
    } else if (item.def.optional && isMissingFile(item.error)) {
      load.absent.push(item.def.id);
    } else {
      logOpsError(`addresses ${item.def.id}`, errorKind(item.error), item.error);
      load.problems.push(`${item.def.id} addresses could not be loaded`);
    }
  }
  return load;
}

export async function loadDeployments(env: Env = process.env): Promise<Deployment[]> {
  const load = await loadDeploymentsDetailed(env);
  if (load.deployments.length === 0 && load.problems.length > 0) throw new Error(load.problems[0]);
  return load.deployments;
}

export function resolveFaucetMode(config: OpsConfig, deployments: readonly Deployment[]): "v1" | "contract" {
  if (config.faucetModeExplicit) return config.faucetMode;
  const candidates = config.faucetDeploymentId
    ? deployments.filter((item) => item.def.id === config.faucetDeploymentId)
    : deployments;
  return candidates.some((item) => item.addresses.faucet !== null) ? "contract" : "v1";
}

export function withResolvedFaucetMode(config: OpsConfig, deployments: readonly Deployment[]): OpsConfig {
  const faucetMode = resolveFaucetMode(config, deployments);
  return faucetMode === config.faucetMode ? config : { ...config, faucetMode };
}

export function pickFaucetDeployment(deployments: readonly Deployment[], config: OpsConfig): Deployment | undefined {
  if (config.faucetDeploymentId) {
    const named = deployments.find((item) => item.def.id === config.faucetDeploymentId);
    if (named) return named;
  }
  if (config.faucetMode === "contract") {
    const withFaucet = deployments.filter((item) => item.addresses.faucet !== null);
    return withFaucet[withFaucet.length - 1];
  }
  return deployments[0];
}

export function rpcUrlFor(deployment: Deployment, config: OpsConfig): string {
  return config.rpcUrlById[deployment.def.id] ?? config.rpcUrlOverride ?? deployment.addresses.rpcUrl;
}
