import type { Address } from "viem";
import { loadConfig, loadDeploymentsDetailed, type OpsConfig } from "./config";
import { runKeeper, type KeeperOutcome } from "./keeper";
import type { FetchLike } from "./prices";
import { runRelayer, type RelayerOutcome } from "./relayer";
import { createBudget, createClients, loadSigner, shortError } from "./rpc";

export type TickDeployment = {
  id: string;
  mode: string;
  relayer: RelayerOutcome | null;
  keeper: KeeperOutcome | null;
};

export type TickSummary = {
  ok: boolean;
  dryRun: boolean;
  generatedAt: number;
  elapsedMs: number;
  pushed: string[];
  rebalanced: Address[];
  checkpointed: number;
  wouldCheckpoint: Address[];
  errors: string[];
  wouldPush: string[];
  wouldRebalance: Address[];
  skipped: string[];
  critical: string[];
  absent: string[];
  deployments: TickDeployment[];
};

export type TickOptions = {
  config?: OpsConfig;
  dryRun?: boolean;
  fetchImpl?: FetchLike;
};

export async function runTick(options: TickOptions = {}): Promise<TickSummary> {
  const config = options.config ?? loadConfig();
  const dryRun = options.dryRun ?? config.dryRun;
  const budget = createBudget(config.budgetMs, config.minSendMs);
  const summary: TickSummary = {
    ok: true,
    dryRun,
    generatedAt: Math.floor(Date.now() / 1000),
    elapsedMs: 0,
    pushed: [],
    rebalanced: [],
    checkpointed: 0,
    wouldCheckpoint: [],
    errors: [],
    wouldPush: [],
    wouldRebalance: [],
    skipped: [],
    critical: [],
    absent: [],
    deployments: [],
  };
  const critical = new Set<string>();
  try {
    const keeperSigner = loadSigner("keeper", config);
    const relayerSigner = loadSigner("relayer", config);
    if (!dryRun && keeperSigner.account === null) critical.add("KEEPER_PRIVATE_KEY is not configured");
    if (!dryRun && relayerSigner.account === null) critical.add("RELAYER_PRIVATE_KEY is not configured");

    const load = await loadDeploymentsDetailed();
    summary.absent = load.absent;
    for (const problem of load.problems) {
      summary.errors.push(problem);
      critical.add(problem);
    }
    if (load.deployments.length === 0) critical.add("no deployment could be loaded");
    for (const deployment of [...load.deployments].reverse()) {
      const id = deployment.def.id;
      const entry: TickDeployment = { id, mode: deployment.mode, relayer: null, keeper: null };
      summary.deployments.push(entry);
      const clients = createClients(deployment, config, budget);
      const relayerContext = {
        deployment,
        clients,
        config,
        budget,
        signer: relayerSigner,
        dryRun,
        fetchImpl: options.fetchImpl,
      };
      try {
        entry.relayer = await runRelayer(relayerContext);
        summary.pushed.push(...entry.relayer.pushed);
        summary.wouldPush.push(...entry.relayer.wouldPush);
        summary.errors.push(...entry.relayer.errors.map((message) => `${id} relayer: ${message}`));
        summary.skipped.push(...entry.relayer.skipped.map((item) => `${id} ${item.symbol}: ${item.reason}`));
        entry.relayer.critical.forEach((message) => critical.add(`${id} relayer: ${message}`));
      } catch (error) {
        summary.errors.push(`${id} relayer: ${shortError(error)}`);
      }
      try {
        entry.keeper = await runKeeper({
          deployment,
          clients,
          config,
          budget,
          signer: keeperSigner,
          dryRun,
          refreshFeeds: async () => {
            const forced = await runRelayer(relayerContext, { force: true });
            summary.pushed.push(...forced.pushed);
            summary.wouldPush.push(...forced.wouldPush.filter((symbol) => !summary.wouldPush.includes(symbol)));
            summary.errors.push(...forced.errors.map((message) => `${id} relayer(forced): ${message}`));
            const staleLabel = `${id} relayer: feed older`;
            for (const message of [...critical]) {
              if (message.startsWith(staleLabel)) critical.delete(message);
            }
            forced.critical.forEach((message) => critical.add(`${id} relayer: ${message}`));
            return { projection: forced.projection, nowSec: forced.nowSec };
          },
        });
        summary.rebalanced.push(...entry.keeper.rebalanced);
        summary.wouldRebalance.push(...entry.keeper.wouldRebalance);
        summary.checkpointed += entry.keeper.checkpointed;
        summary.wouldCheckpoint.push(...entry.keeper.wouldCheckpoint);
        summary.errors.push(...entry.keeper.errors.map((message) => `${id} keeper: ${message}`));
        summary.skipped.push(...entry.keeper.skipped.map((item) => `${id} ${item.vault}: ${item.reason}`));
        entry.keeper.critical.forEach((message) => critical.add(`${id} keeper: ${message}`));
      } catch (error) {
        summary.errors.push(`${id} keeper: ${shortError(error)}`);
      }
    }
  } catch (error) {
    summary.errors.push(`tick failed: ${shortError(error)}`);
    critical.add("tick could not run");
  } finally {
    budget.dispose();
  }
  summary.critical = [...critical];
  summary.ok = summary.critical.length === 0;
  summary.elapsedMs = budget.elapsed();
  return summary;
}
