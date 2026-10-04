import { toHex, type Address, type Hex } from "viem";
import { engineV2Abi, multicallAbi, strategyVaultV2Abi } from "./abi";
import { MULTICALL3_ADDRESS, type Deployment, type OpsConfig } from "./config";
import { awaitReceipt, SIMULATION_PLACEHOLDER } from "./relayer";
import { listVaultsV2, scanUpkeepV2, strategyCount } from "./scan";
import {
  batchRead,
  BudgetExceededError,
  revertName,
  shortError,
  type Budget,
  type OpsClients,
  type Signer,
} from "./rpc";

export type KeeperOutcome = {
  deployment: string;
  dryRun: boolean;
  upkeep: Address[];
  rebalanced: Address[];
  wouldRebalance: Address[];
  txHashes: Hex[];
  pendingHashes: Hex[];
  skipped: { vault: Address; reason: string }[];
  errors: string[];
  critical: string[];
  notes: { vault: Address; steps: string[] }[];
  balanceWei: string | null;
  staleRelayerRuns: number;
  scanned: number;
  checkpointed: number;
  wouldCheckpoint: Address[];
  checkpointHashes: Hex[];
  checkpointNotes: string[];
};

export type KeeperContext = {
  deployment: Deployment;
  clients: OpsClients;
  config: OpsConfig;
  budget: Budget;
  signer: Signer;
  dryRun: boolean;
  refreshFeeds: () => Promise<{ projection: { feed: Address; answer: string }[]; nowSec: number | null }>;
};

type StateOverride = { address: Address; stateDiff: { slot: Hex; value: Hex }[] }[];

function projectedOverride(projection: readonly { feed: Address; answer: string }[], nowSec: number): StateOverride {
  return projection.map((entry) => ({
    address: entry.feed,
    stateDiff: [
      { slot: toHex(0n, { size: 32 }), value: toHex(BigInt(entry.answer), { size: 32 }) },
      { slot: toHex(1n, { size: 32 }), value: toHex(BigInt(nowSec), { size: 32 }) },
    ],
  }));
}

async function simulateRebalance(
  clients: OpsClients,
  engine: Address,
  vault: Address,
  account: Address,
  stateOverride?: StateOverride,
): Promise<void> {
  await clients.client.simulateContract({
    address: engine,
    abi: engineV2Abi,
    functionName: "performRebalance",
    args: [vault],
    account,
    stateOverride,
  });
}

async function scanUpkeep(ctx: KeeperContext, outcome: KeeperOutcome): Promise<Address[] | null> {
  const { deployment, clients, budget, config } = ctx;
  if (deployment.def.engine === "v1") {
    try {
      const list = await clients.call(budget, "checkUpkeep", () =>
        clients.client.readContract({
          address: deployment.addresses.rebalanceEngine,
          abi: engineV2Abi,
          functionName: "checkUpkeep",
        }),
      );
      return [...list];
    } catch (error) {
      outcome.errors.push(`checkUpkeep failed: ${shortError(error)}`);
      return null;
    }
  }
  try {
    const count = await strategyCount(clients, budget, deployment);
    outcome.scanned = count;
    const result = await scanUpkeepV2(clients, budget, deployment, config.keeperPageSize, count);
    outcome.errors.push(...result.errors);
    return result.needing;
  } catch (error) {
    outcome.errors.push(`strategyCount failed: ${shortError(error)}`);
    return null;
  }
}

async function runCheckpoints(
  ctx: KeeperContext,
  outcome: KeeperOutcome,
  send: { allowed: boolean },
): Promise<void> {
  const { deployment, clients, config, budget, signer, dryRun } = ctx;
  const engine = deployment.addresses.rebalanceEngine;
  let vaults: Address[];
  try {
    const count = await strategyCount(clients, budget, deployment);
    vaults = await listVaultsV2(clients, budget, deployment, config.keeperPageSize, count);
  } catch (error) {
    outcome.errors.push(`checkpoint: vault list failed (${shortError(error)})`);
    return;
  }
  if (vaults.length === 0) return;
  const reads = await batchRead(
    clients,
    [
      { address: MULTICALL3_ADDRESS, abi: multicallAbi, functionName: "getCurrentBlockTimestamp" },
      ...vaults.map((vault) => ({ address: vault, abi: strategyVaultV2Abi, functionName: "lastCheckpointTimestamp" })),
    ],
    budget,
  );
  const stamp = reads[0];
  if (!stamp?.ok || typeof stamp.value !== "bigint") {
    outcome.errors.push("checkpoint: block timestamp could not be read");
    return;
  }
  const nowSec = Number(stamp.value);
  const minGap = Math.max(config.checkpointEverySec, deployment.addresses.checkpointMinInterval ?? config.checkpointMinIntervalSec);
  const due = vaults.filter((_, index) => {
    const read = reads[index + 1];
    if (!read?.ok || typeof read.value !== "bigint") return false;
    return nowSec - Number(read.value) >= minGap;
  });
  if (due.length === 0) {
    outcome.checkpointNotes.push(`none due (${vaults.length} vaults, gap ${minGap}s)`);
    return;
  }
  const canSign = !dryRun && signer.account !== null && signer.address !== null;
  const account = signer.address ?? SIMULATION_PLACEHOLDER;
  let nonce: number | null = null;
  const sent: { hash: Hex; recorded: number }[] = [];
  for (let from = 0; from < due.length; from += config.checkpointBatch) {
    const chunk = due.slice(from, from + config.checkpointBatch);
    if (!dryRun && !budget.canSend()) {
      outcome.checkpointNotes.push(`${chunk.length} vaults deferred: time budget`);
      break;
    }
    let recorded = 0n;
    try {
      const simulation = await clients.call(budget, "simulate checkpoint", () =>
        clients.client.simulateContract({
          address: engine,
          abi: engineV2Abi,
          functionName: "checkpoint",
          args: [chunk],
          account,
        }),
      );
      recorded = simulation.result;
    } catch (error) {
      outcome.errors.push(`checkpoint simulation failed: ${revertName(error) ?? shortError(error)}`);
      continue;
    }
    if (recorded === 0n) {
      outcome.checkpointNotes.push(`engine would record 0 of ${chunk.length}: too early or prices stale, skipped`);
      continue;
    }
    if (dryRun || !canSign) {
      outcome.wouldCheckpoint.push(...chunk);
      outcome.checkpointNotes.push(`dry run: would record ${recorded} of ${chunk.length}`);
      continue;
    }
    if (!send.allowed || !signer.account || !signer.address) {
      outcome.checkpointNotes.push("not sent: keeper balance floor");
      break;
    }
    try {
      if (nonce === null) {
        const owner = signer.address;
        nonce = await clients.call(budget, "keeper nonce", () =>
          clients.client.getTransactionCount({ address: owner, blockTag: "pending" }),
        );
      }
      const gas = await clients.client
        .estimateContractGas({ address: engine, abi: engineV2Abi, functionName: "checkpoint", args: [chunk], account: signer.account })
        .then(
          (value) => (value * 13n) / 10n,
          () => undefined,
        );
      const hash = await budget.race(
        clients.wallet(signer.account).writeContract({
          address: engine,
          abi: engineV2Abi,
          functionName: "checkpoint",
          args: [chunk],
          nonce,
          gas,
        }),
        "send checkpoint",
      );
      nonce += 1;
      sent.push({ hash, recorded: Number(recorded) });
      outcome.checkpointHashes.push(hash);
    } catch (error) {
      outcome.errors.push(`checkpoint send failed: ${shortError(error)}`);
      nonce = null;
    }
  }
  const statuses = await Promise.all(sent.map((item) => awaitReceipt(clients, budget, item.hash)));
  statuses.forEach((status, index) => {
    const item = sent[index];
    if (status === "success") outcome.checkpointed += item.recorded;
    else if (status === "reverted") outcome.errors.push("checkpoint transaction reverted");
    else outcome.pendingHashes.push(item.hash);
  });
}

export async function runKeeper(ctx: KeeperContext): Promise<KeeperOutcome> {
  const { deployment, clients, config, budget, signer, dryRun } = ctx;
  const engine = deployment.addresses.rebalanceEngine;
  const outcome: KeeperOutcome = {
    deployment: deployment.def.id,
    dryRun,
    upkeep: [],
    rebalanced: [],
    wouldRebalance: [],
    txHashes: [],
    pendingHashes: [],
    skipped: [],
    errors: [],
    critical: [],
    notes: [],
    balanceWei: null,
    staleRelayerRuns: 0,
    scanned: 0,
    checkpointed: 0,
    wouldCheckpoint: [],
    checkpointHashes: [],
    checkpointNotes: [],
  };
  if (!deployment.def.keeper) return outcome;

  const scanned = await scanUpkeep(ctx, outcome);
  if (scanned === null) {
    outcome.critical.push("checkUpkeep could not be read");
    return outcome;
  }
  outcome.upkeep = scanned;
  const v2 = deployment.def.engine === "v2";
  if (outcome.upkeep.length === 0 && !v2) return outcome;

  const canSign = !dryRun && signer.account !== null && signer.address !== null;
  if (!dryRun && !canSign) outcome.critical.push("KEEPER_PRIVATE_KEY is not configured");
  const account = signer.address ?? SIMULATION_PLACEHOLDER;

  let sendAllowed = canSign;
  if (canSign && signer.address) {
    try {
      const keeperAddress = signer.address;
      const balance = await clients.call(budget, "keeper balance", () =>
        clients.client.getBalance({ address: keeperAddress }),
      );
      outcome.balanceWei = balance.toString();
      if (balance < config.keeperMinWei) outcome.critical.push("keeper balance below alarm floor");
      if (balance < config.sendMinWei) {
        outcome.critical.push("keeper balance below send floor, nothing sent");
        sendAllowed = false;
      }
    } catch (error) {
      outcome.errors.push(`keeper balance read failed: ${shortError(error)}`);
      sendAllowed = false;
    }
  }

  let nonce: number | null = null;
  let relayerRan = false;
  let projection: { feed: Address; answer: string }[] = [];
  let projectionNow: number | null = null;
  const sent: { vault: Address; hash: Hex }[] = [];

  for (const vault of outcome.upkeep) {
    const steps: string[] = [];
    outcome.notes.push({ vault, steps });
    if (!budget.canSend() && !dryRun) {
      outcome.skipped.push({ vault, reason: "budget" });
      steps.push("skipped: not enough time budget left to send");
      continue;
    }
    let simulated = false;
    try {
      await clients.call(budget, `simulate ${vault}`, () => simulateRebalance(clients, engine, vault, account));
      steps.push("simulate: ok");
      simulated = true;
    } catch (error) {
      const name = revertName(error);
      steps.push(`simulate: ${name ?? shortError(error)}`);
      if (name === "RebalanceNotNeeded") {
        outcome.skipped.push({ vault, reason: "rebalance no longer needed" });
        continue;
      }
      if (name !== "StalePrice") {
        outcome.errors.push(`${vault}: ${name ?? shortError(error)}`);
        continue;
      }
      if (!relayerRan) {
        relayerRan = true;
        outcome.staleRelayerRuns += 1;
        steps.push("relayer: forced refresh run");
        try {
          const refreshed = await ctx.refreshFeeds();
          projection = refreshed.projection;
          projectionNow = refreshed.nowSec;
        } catch (refreshError) {
          steps.push(`relayer: failed (${shortError(refreshError)})`);
          if (refreshError instanceof BudgetExceededError) {
            outcome.errors.push(`${vault}: StalePrice and no time left to refresh`);
            continue;
          }
        }
      } else {
        steps.push("relayer: already refreshed this tick");
      }
      const projected = dryRun && deployment.def.feedKind === "mock" && projection.length > 0 && projectionNow !== null;
      try {
        const override = projected && projectionNow !== null ? projectedOverride(projection, projectionNow) : undefined;
        await clients.call(budget, `retry ${vault}`, () => simulateRebalance(clients, engine, vault, account, override));
        steps.push(projected ? "retry simulate with projected fresh feeds: ok" : "retry simulate: ok");
        simulated = true;
      } catch (retryError) {
        const retryName = revertName(retryError);
        steps.push(`retry simulate: ${retryName ?? shortError(retryError)}`);
        outcome.errors.push(`${vault}: ${retryName ?? shortError(retryError)} after refresh`);
        continue;
      }
    }
    if (!simulated) continue;

    if (dryRun || !canSign) {
      outcome.wouldRebalance.push(vault);
      steps.push("dry run: would send performRebalance");
      continue;
    }
    if (!sendAllowed || !signer.account || !signer.address) {
      outcome.skipped.push({ vault, reason: "keeper balance below send floor" });
      steps.push("not sent: balance floor");
      continue;
    }
    if (!budget.canSend()) {
      outcome.skipped.push({ vault, reason: "budget" });
      steps.push("not sent: time budget");
      continue;
    }
    try {
      if (nonce === null) {
        const owner = signer.address;
        nonce = await clients.call(budget, "keeper nonce", () =>
          clients.client.getTransactionCount({ address: owner, blockTag: "pending" }),
        );
      }
      const gas = await clients.client
        .estimateContractGas({ address: engine, abi: engineV2Abi, functionName: "performRebalance", args: [vault], account: signer.account })
        .then(
          (value) => (value * 13n) / 10n,
          () => undefined,
        );
      const hash = await budget.race(
        clients.wallet(signer.account).writeContract({
          address: engine,
          abi: engineV2Abi,
          functionName: "performRebalance",
          args: [vault],
          nonce,
          gas,
        }),
        `send ${vault}`,
      );
      nonce += 1;
      sent.push({ vault, hash });
      outcome.txHashes.push(hash);
      steps.push(`sent ${hash}`);
    } catch (error) {
      steps.push(`send failed: ${shortError(error)}`);
      outcome.errors.push(`${vault}: send failed (${shortError(error)})`);
      nonce = null;
    }
  }

  const statuses = await Promise.all(sent.map((item) => awaitReceipt(clients, budget, item.hash)));
  statuses.forEach((status, index) => {
    const item = sent[index];
    if (status === "success") outcome.rebalanced.push(item.vault);
    else if (status === "reverted") outcome.errors.push(`${item.vault}: rebalance transaction reverted`);
    else outcome.pendingHashes.push(item.hash);
  });
  if (v2) await runCheckpoints(ctx, outcome, { allowed: sendAllowed });
  return outcome;
}
