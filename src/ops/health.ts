import { formatEther, formatUnits, keccak256, parseAbiItem, toHex, type Address } from "viem";
import {
  engineAbi,
  fengAggregatorAbi,
  fengFaucetAbi,
  marketplaceRegistryV2Abi,
  multicallAbi,
  oracleDeskAbi,
  registryAbi,
  strategyVaultV2Abi,
  tokenAbi,
  vaultStateAbi,
} from "./abi";
import {
  MULTICALL3_ADDRESS,
  loadConfig,
  loadDeploymentsDetailed,
  pickFaucetDeployment,
  withResolvedFaucetMode,
  type Deployment,
  type OpsConfig,
} from "./config";
import { formatAnswer, readFeeds } from "./relayer";
import { redactText } from "./redact";
import { listVaultsV2, scanUpkeepV2 } from "./scan";
import {
  batchRead,
  createBudget,
  createClients,
  expectBigint,
  loadSigner,
  shortError,
  type BatchCall,
  type BatchResult,
  type Budget,
  type OpsClients,
} from "./rpc";

export type HealthFeed = {
  deployment: string;
  symbol: string;
  price: string;
  updatedAt: number;
  ageSec: number;
};

export type HealthVault = {
  deployment: string;
  symbol: string;
  vault: Address;
  lastRebalance: number;
  lastCheckpoint: number | null;
  navUsdg: string | null;
  needed: boolean;
};

export type HealthDesk = {
  deployment: string;
  address: Address;
  reserveUsdg: string | null;
  fundedUsdg: string | null;
  withdrawnUsdg: string | null;
  spreadBps: number | null;
  vaultNavUsdg: string | null;
  coverage: number | null;
};

export type HealthFaucetContract = {
  deployment: string;
  address: Address;
  balanceEth: string | null;
  claimsToday: number | null;
  dailyCap: number | null;
  ethPerClaim: string | null;
  usdgPerClaim: string | null;
  claimsAvailable: number | null;
  claimsLeftToday: number | null;
  dispenserAuthorized: boolean | null;
};

export type HealthReport = {
  ok: boolean;
  generatedAt: number;
  alarms: string[];
  feeds: HealthFeed[];
  keeper: { address: Address | null; balanceEth: string | null };
  relayer: { address: Address | null; balanceEth: string | null; mode: string; modes: Record<string, string> };
  vaults: HealthVault[];
  desk: HealthDesk | null;
  faucet: {
    address: Address | null;
    balanceEth: string | null;
    balanceUsdg: string | null;
    claimsToday: number | null;
    mode: "v1" | "contract";
    contract: HealthFaucetContract | null;
  };
  absent: string[];
  deployments: {
    id: string;
    label: string;
    chainId: number;
    feedKind: string;
    mode: string;
    rebalanceEngine: Address;
    marketplaceRegistry: Address;
    feeds: number;
    vaults: number;
  }[];
};

const symbolCache = new Map<string, string>();
const claimsCache: { at: number; key: string; value: number | null } = { at: 0, key: "", value: null };
const transferEvent = parseAbiItem("event Transfer(address indexed from, address indexed to, uint256 value)");
const UPDATER_ROLE = keccak256(toHex("UPDATER_ROLE"));
const DISPENSER_ROLE = keccak256(toHex("DISPENSER_ROLE"));

function eth(wei: bigint | null): string | null {
  if (wei === null) return null;
  return Number(formatEther(wei)).toFixed(8);
}

function plan() {
  const calls: BatchCall[] = [];
  const keys = new Map<string, number>();
  return {
    calls,
    add(key: string, call: BatchCall): void {
      keys.set(key, calls.length);
      calls.push(call);
    },
    get(results: readonly BatchResult[], key: string): BatchResult | undefined {
      const index = keys.get(key);
      return index === undefined ? undefined : results[index];
    },
  };
}

function numberOf(result: BatchResult | undefined): number | null {
  if (!result || !result.ok) return null;
  if (typeof result.value === "bigint") return Number(result.value);
  return typeof result.value === "number" ? result.value : null;
}

async function countClaimsToday(
  clients: OpsClients,
  budget: Budget,
  usdg: Address,
  faucet: Address,
): Promise<number | null> {
  const key = `${usdg}:${faucet}`;
  if (claimsCache.key === key && Date.now() - claimsCache.at < 60_000) return claimsCache.value;
  try {
    const head = await clients.call(budget, "head block", () => clients.client.getBlock());
    const span = 100_000n;
    const sample = await clients.call(budget, "sample block", () =>
      clients.client.getBlock({ blockNumber: head.number > span ? head.number - span : 0n }),
    );
    const seconds = Number(head.timestamp - sample.timestamp);
    const sampled = Number(head.number > span ? span : head.number);
    const blocksPerSec = seconds > 0 && sampled > 0 ? sampled / seconds : 7;
    const lookback = BigInt(Math.ceil(86_400 * blocksPerSec * 1.02));
    const fromBlock = head.number > lookback ? head.number - lookback : 0n;
    const logs = await clients.call(budget, "claims logs", () =>
      clients.client.getLogs({ address: usdg, event: transferEvent, args: { from: faucet }, fromBlock, toBlock: head.number }),
    );
    claimsCache.value = logs.length;
  } catch {
    claimsCache.value = null;
  }
  claimsCache.key = key;
  claimsCache.at = Date.now();
  return claimsCache.value;
}

export type HealthOptions = {
  config?: OpsConfig;
  deployments?: Deployment[];
};

function primaryMode(deployments: readonly Deployment[]): string {
  const maintained = deployments.filter((item) => item.def.relayer);
  const pool = maintained.length > 0 ? maintained : deployments;
  return pool[pool.length - 1]?.mode ?? "hold";
}

export async function computeHealth(options: HealthOptions = {}): Promise<HealthReport> {
  const config = options.config ?? loadConfig();
  const budget = createBudget(Math.min(config.budgetMs, 15_000), 0);
  const alarms: string[] = [];
  const report: HealthReport = {
    ok: true,
    generatedAt: Math.floor(Date.now() / 1000),
    alarms,
    feeds: [],
    keeper: { address: null, balanceEth: null },
    relayer: { address: null, balanceEth: null, mode: "hold", modes: {} },
    vaults: [],
    desk: null,
    faucet: {
      address: null,
      balanceEth: null,
      balanceUsdg: null,
      claimsToday: null,
      mode: config.faucetMode,
      contract: null,
    },
    absent: [],
    deployments: [],
  };
  try {
    let deployments: Deployment[];
    if (options.deployments) {
      deployments = options.deployments;
    } else {
      const load = await loadDeploymentsDetailed();
      deployments = load.deployments;
      report.absent = load.absent;
      load.problems.forEach((problem) => alarms.push(problem));
    }
    const keeper = loadSigner("keeper", config);
    const relayer = loadSigner("relayer", config);
    const faucet = loadSigner("faucet", config);
    report.keeper.address = keeper.address;
    report.relayer.address = relayer.address;
    report.faucet.address = faucet.address;
    report.relayer.mode = primaryMode(deployments);
    deployments.forEach((item) => {
      report.relayer.modes[item.def.id] = item.mode;
    });
    const faucetConfig = withResolvedFaucetMode(config, deployments);
    const faucetDeployment = pickFaucetDeployment(deployments, faucetConfig);
    const contractFaucet = faucetConfig.faucetMode === "contract";
    report.faucet.mode = faucetConfig.faucetMode;

    const wallets: { role: "keeper" | "relayer" | "faucet"; address: Address }[] = [];
    if (keeper.address) wallets.push({ role: "keeper", address: keeper.address });
    if (relayer.address) wallets.push({ role: "relayer", address: relayer.address });
    if (faucet.address) wallets.push({ role: "faucet", address: faucet.address });

    const perDeployment = await Promise.all(
      deployments.map(async (deployment) => {
        const clients = createClients(deployment, config, budget);
        const isPrimary = deployment === deployments[0];
        const v2 = deployment.def.engine === "v2";
        const calls = plan();
        if (v2) {
          calls.add("count", {
            address: deployment.addresses.marketplaceRegistry,
            abi: marketplaceRegistryV2Abi,
            functionName: "strategyCount",
          });
        } else {
          calls.add("upkeep", { address: deployment.addresses.rebalanceEngine, abi: engineAbi, functionName: "checkUpkeep" });
          calls.add("all", { address: deployment.addresses.marketplaceRegistry, abi: registryAbi, functionName: "getAllStrategies" });
        }
        if (isPrimary) {
          wallets.forEach((wallet) =>
            calls.add(`eth:${wallet.role}`, {
              address: MULTICALL3_ADDRESS,
              abi: multicallAbi,
              functionName: "getEthBalance",
              args: [wallet.address],
            }),
          );
        }
        const isFaucetDeployment = deployment === faucetDeployment;
        if (isFaucetDeployment && faucet.address && !contractFaucet) {
          calls.add("faucet:usdg", { address: deployment.addresses.usdg, abi: tokenAbi, functionName: "balanceOf", args: [faucet.address] });
          calls.add("faucet:decimals", { address: deployment.addresses.usdg, abi: tokenAbi, functionName: "decimals" });
        }
        if (v2) {
          calls.add("usdg:decimals", { address: deployment.addresses.usdg, abi: tokenAbi, functionName: "decimals" });
          const venue = deployment.addresses.venue;
          if (venue) {
            calls.add("desk:reserve", { address: venue, abi: oracleDeskAbi, functionName: "reserveUsdg" });
            calls.add("desk:accounting", { address: venue, abi: oracleDeskAbi, functionName: "accounting" });
            calls.add("desk:spread", { address: venue, abi: oracleDeskAbi, functionName: "spreadBps" });
          }
          const faucetAddress = deployment.addresses.faucet;
          if (faucetAddress && isFaucetDeployment) {
            calls.add("fc:eth", { address: MULTICALL3_ADDRESS, abi: multicallAbi, functionName: "getEthBalance", args: [faucetAddress] });
            calls.add("fc:today", { address: faucetAddress, abi: fengFaucetAbi, functionName: "claimsToday" });
            calls.add("fc:cap", { address: faucetAddress, abi: fengFaucetAbi, functionName: "dailyCap" });
            calls.add("fc:ethPer", { address: faucetAddress, abi: fengFaucetAbi, functionName: "ethPerClaim" });
            calls.add("fc:usdgPer", { address: faucetAddress, abi: fengFaucetAbi, functionName: "usdgPerClaim" });
            if (faucet.address) {
              calls.add("fc:role", {
                address: faucetAddress,
                abi: fengFaucetAbi,
                functionName: "hasRole",
                args: [DISPENSER_ROLE, faucet.address],
              });
            }
          }
          if (relayer.address && deployment.def.relayer) {
            Object.entries(deployment.addresses.priceOracles).forEach(([symbol, feed]) =>
              calls.add(`role:${symbol}`, {
                address: feed,
                abi: fengAggregatorAbi,
                functionName: "hasRole",
                args: [UPDATER_ROLE, relayer.address],
              }),
            );
          }
        }
        const [feedRead, state] = await Promise.all([
          readFeeds(clients, deployment, budget),
          batchRead(clients, calls.calls, budget),
        ]);
        let vaults: Address[] | null = null;
        let needing: Address[] | null = null;
        let scanErrors: string[] = [];
        if (v2) {
          const count = numberOf(calls.get(state, "count"));
          if (count !== null) {
            try {
              vaults = await listVaultsV2(clients, budget, deployment, config.keeperPageSize, count);
            } catch {
              vaults = null;
            }
            const scan = await scanUpkeepV2(clients, budget, deployment, config.keeperPageSize, count);
            needing = scan.needing;
            scanErrors = scan.errors;
          }
        } else {
          const upkeepResult = calls.get(state, "upkeep");
          const registryResult = calls.get(state, "all");
          needing = upkeepResult?.ok && Array.isArray(upkeepResult.value) ? (upkeepResult.value as Address[]) : null;
          vaults = registryResult?.ok && Array.isArray(registryResult.value) ? (registryResult.value as Address[]) : null;
        }
        return { deployment, clients, feedRead, state, calls, isPrimary, v2, vaults, needing, scanErrors, isFaucetDeployment };
      }),
    );

    for (const item of perDeployment) {
      const { deployment, clients, feedRead, state, calls, v2 } = item;
      const id = deployment.def.id;
      feedRead.errors.forEach((message) => alarms.push(`${id} feed read: ${message}`));
      for (const feed of feedRead.states) {
        report.feeds.push({
          deployment: id,
          symbol: feed.symbol,
          price: formatAnswer(feed.answer, feed.decimals),
          updatedAt: feed.updatedAt,
          ageSec: feed.ageSec,
        });
        if (deployment.def.relayer && feed.ageSec > config.healthMaxAgeSec) {
          alarms.push(`${id} ${feed.symbol} feed is ${Math.round(feed.ageSec / 60)} min old`);
        }
        const marketAge = feed.band?.marketAgeSec ?? null;
        if (deployment.def.relayer && deployment.mode === "market" && marketAge !== null && marketAge > config.maxPriceAgeSec) {
          alarms.push(`${id} ${feed.symbol} price stale`);
        }
      }

      if (item.needing === null) alarms.push(`${id} checkUpkeep could not be read`);
      item.scanErrors.forEach((message) => alarms.push(`${id} ${message}`));
      const upkeep = new Set<string>((item.needing ?? []).map((vault) => vault.toLowerCase()));
      if (item.vaults === null) alarms.push(`${id} registry could not be read`);
      const vaults: Address[] = item.vaults ?? [];

      if (item.isPrimary) {
        for (const wallet of wallets) {
          const wei = expectBigint(calls.get(state, `eth:${wallet.role}`));
          const text = eth(wei);
          if (wallet.role === "keeper") report.keeper.balanceEth = text;
          else if (wallet.role === "relayer") report.relayer.balanceEth = text;
          else report.faucet.balanceEth = text;
          const floor =
            wallet.role === "keeper" ? config.keeperMinWei : wallet.role === "relayer" ? config.relayerMinWei : config.faucetMinWei;
          if (wei === null) alarms.push(`${wallet.role} balance could not be read`);
          else if (wei < floor) alarms.push(`${wallet.role} balance ${text} ETH is below the floor ${eth(floor)} ETH`);
        }
      }
      if (item.isFaucetDeployment && faucet.address && !contractFaucet) {
        const usdgBalance = expectBigint(calls.get(state, "faucet:usdg"));
        const decimalsResult = calls.get(state, "faucet:decimals");
        const decimals = decimalsResult?.ok && typeof decimalsResult.value === "number" ? decimalsResult.value : null;
        if (usdgBalance !== null && decimals !== null) report.faucet.balanceUsdg = formatUnits(usdgBalance, decimals);
        report.faucet.claimsToday = await countClaimsToday(clients, budget, deployment.addresses.usdg, faucet.address);
      }

      const usdgDecimalsResult = calls.get(state, "usdg:decimals");
      const usdgDecimals =
        usdgDecimalsResult?.ok && typeof usdgDecimalsResult.value === "number"
          ? usdgDecimalsResult.value
          : deployment.addresses.usdgDecimals;

      if (v2 && relayer.address && deployment.def.relayer) {
        const missing = Object.keys(deployment.addresses.priceOracles).filter((symbol) => {
          const result = calls.get(state, `role:${symbol}`);
          return result?.ok && result.value === false;
        });
        if (missing.length > 0) alarms.push(`${id} relayer lacks UPDATER_ROLE on ${missing.join(",")}`);
      }

      const detailCalls: BatchCall[] = vaults.flatMap((vault) => [
        { address: vault, abi: vaultStateAbi, functionName: "lastRebalanceTimestamp" },
        { address: deployment.addresses.marketplaceRegistry, abi: registryAbi, functionName: "getStrategyInfo", args: [vault] },
        ...(v2
          ? [
              { address: vault, abi: strategyVaultV2Abi, functionName: "lastCheckpointTimestamp" },
              { address: vault, abi: strategyVaultV2Abi, functionName: "totalAssetsUSDG" },
            ]
          : []),
      ]);
      const stride = v2 ? 4 : 2;
      const details = await batchRead(clients, detailCalls, budget);
      const tokens: (Address | null)[] = vaults.map((_, index) => {
        const info = details[index * stride + 1];
        return info?.ok && Array.isArray(info.value) ? (info.value[0] as Address) : null;
      });
      const unknown = [...new Set(tokens.filter((token): token is Address => token !== null && !symbolCache.has(token)))];
      const symbolResults = await batchRead(
        clients,
        unknown.map((token) => ({ address: token, abi: tokenAbi, functionName: "symbol" })),
        budget,
      );
      symbolResults.forEach((result, index) => {
        if (result.ok && typeof result.value === "string") symbolCache.set(unknown[index], result.value);
      });
      let navTotal = 0n;
      let navKnown = 0;
      vaults.forEach((vault, index) => {
        const token = tokens[index];
        const nav = v2 ? expectBigint(details[index * stride + 3]) : null;
        if (nav !== null) {
          navTotal += nav;
          navKnown += 1;
        }
        report.vaults.push({
          deployment: id,
          symbol: (token ? symbolCache.get(token) : undefined) ?? vault.slice(0, 8),
          vault,
          lastRebalance: Number(expectBigint(details[index * stride]) ?? 0n),
          lastCheckpoint: v2 ? numberOf(details[index * stride + 2]) : null,
          navUsdg: nav !== null && usdgDecimals !== null ? formatUnits(nav, usdgDecimals) : null,
          needed: upkeep.has(vault.toLowerCase()),
        });
      });

      const venue = deployment.addresses.venue;
      if (v2 && venue) {
        const reserve = expectBigint(calls.get(state, "desk:reserve"));
        const accounting = calls.get(state, "desk:accounting");
        const funded = accounting?.ok && Array.isArray(accounting.value) ? (accounting.value[0] as bigint) : null;
        const withdrawn = accounting?.ok && Array.isArray(accounting.value) ? (accounting.value[1] as bigint) : null;
        const spread = numberOf(calls.get(state, "desk:spread"));
        const fmt = (value: bigint | null): string | null =>
          value === null || usdgDecimals === null ? null : formatUnits(value, usdgDecimals);
        const complete = navKnown === vaults.length && vaults.length > 0;
        const coverage =
          reserve !== null && complete && navTotal > 0n
            ? Math.round(Number((reserve * 10_000n) / navTotal)) / 10_000
            : null;
        report.desk = {
          deployment: id,
          address: venue,
          reserveUsdg: fmt(reserve),
          fundedUsdg: fmt(funded),
          withdrawnUsdg: fmt(withdrawn),
          spreadBps: spread,
          vaultNavUsdg: complete ? fmt(navTotal) : null,
          coverage,
        };
        if (reserve === null) alarms.push(`${id} desk reserve could not be read`);
        else if (coverage !== null && coverage < config.deskMinCoverage) {
          alarms.push(`${id} desk reserve covers only ${coverage}x of vault NAV, floor ${config.deskMinCoverage}x`);
        }
      }

      const faucetAddress = deployment.addresses.faucet;
      if (v2 && faucetAddress && item.isFaucetDeployment) {
        const balance = expectBigint(calls.get(state, "fc:eth"));
        const today = numberOf(calls.get(state, "fc:today"));
        const cap = numberOf(calls.get(state, "fc:cap"));
        const ethPer = expectBigint(calls.get(state, "fc:ethPer"));
        const usdgPer = expectBigint(calls.get(state, "fc:usdgPer"));
        const role = calls.get(state, "fc:role");
        const authorized = role?.ok && typeof role.value === "boolean" ? role.value : null;
        const byBalance = balance !== null && ethPer !== null && ethPer > 0n ? Number(balance / ethPer) : null;
        const leftToday = cap !== null && today !== null ? Math.max(0, cap - today) : null;
        report.faucet.contract = {
          deployment: id,
          address: faucetAddress,
          balanceEth: eth(balance),
          claimsToday: today,
          dailyCap: cap,
          ethPerClaim: eth(ethPer),
          usdgPerClaim: usdgPer !== null && usdgDecimals !== null ? formatUnits(usdgPer, usdgDecimals) : null,
          claimsAvailable: byBalance,
          claimsLeftToday: leftToday,
          dispenserAuthorized: authorized,
        };
        if (contractFaucet) {
          report.faucet.claimsToday = today;
          if (!config.faucetOptional) {
            if (balance === null) alarms.push(`${id} faucet contract balance could not be read`);
            else if (byBalance !== null && byBalance < config.faucetMinClaims) {
              alarms.push(`${id} faucet contract can pay only ${byBalance} more claims, top it up`);
            }
            if (authorized === false) alarms.push(`${id} faucet wallet lacks DISPENSER_ROLE on the faucet contract`);
          }
        }
      } else if (contractFaucet && item.isFaucetDeployment && !config.faucetOptional) {
        alarms.push("faucet mode is contract but the deployment has no faucet address");
      }

      report.deployments.push({
        id,
        label: deployment.def.label,
        chainId: deployment.addresses.chainId,
        feedKind: deployment.def.feedKind,
        mode: deployment.mode,
        rebalanceEngine: deployment.addresses.rebalanceEngine,
        marketplaceRegistry: deployment.addresses.marketplaceRegistry,
        feeds: feedRead.states.length,
        vaults: vaults.length,
      });
    }

    if (!keeper.address) alarms.push("keeper address is not configured");
    if (!relayer.address) alarms.push("relayer address is not configured");
    if (!faucet.address && !config.faucetOptional) alarms.push("faucet address is not configured");
  } catch (error) {
    alarms.push(`health could not be computed: ${shortError(error, "health")}`);
  } finally {
    budget.dispose();
  }
  report.alarms = alarms.map(redactText);
  report.ok = alarms.length === 0;
  return report;
}
