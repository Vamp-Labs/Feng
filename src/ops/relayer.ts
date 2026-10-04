import { parseAbiItem, type Address, type Hex } from "viem";
import {
  aggregatorAbi,
  fengAggregatorAbi,
  mockAggregatorWriteAbi,
  multicallAbi,
} from "./abi";
import { MULTICALL3_ADDRESS, type Deployment, type FeedKind, type OpsConfig, type RelayerMode } from "./config";
import { fetchQuotes, type FetchLike, type Quote } from "./prices";
import {
  batchRead,
  BudgetExceededError,
  revertName,
  shortError,
  type Budget,
  type OpsClients,
  type Signer,
} from "./rpc";

export const SIMULATION_PLACEHOLDER: Address = "0x000000000000000000000000000000000000dEaD";

export type FeedBand = {
  anchor: bigint;
  maxDeviationBps: number;
  windowSec: number | null;
  marketAgeSec: number | null;
};

export type FeedState = {
  symbol: string;
  feed: Address;
  decimals: number;
  answer: bigint;
  updatedAt: number;
  ageSec: number;
  band: FeedBand | null;
};

export type FeedRead = {
  states: FeedState[];
  errors: string[];
  nowSec: number | null;
};

export async function readFeeds(
  clients: OpsClients,
  deployment: Deployment,
  budget?: Budget,
  only?: readonly string[],
): Promise<FeedRead> {
  const feng = deployment.def.feedKind === "feng";
  const stride = feng ? 6 : 2;
  const entries = Object.entries(deployment.addresses.priceOracles).filter(
    ([symbol]) => only === undefined || only.includes(symbol),
  );
  const calls = [
    { address: MULTICALL3_ADDRESS, abi: multicallAbi, functionName: "getCurrentBlockTimestamp" },
    ...entries.flatMap(([, feed]) => [
      { address: feed, abi: aggregatorAbi, functionName: "latestRoundData" },
      { address: feed, abi: aggregatorAbi, functionName: "decimals" },
      ...(feng
        ? [
            { address: feed, abi: fengAggregatorAbi, functionName: "anchorAnswer" },
            { address: feed, abi: fengAggregatorAbi, functionName: "maxDeviationBps" },
            { address: feed, abi: fengAggregatorAbi, functionName: "ANCHOR_WINDOW" },
            { address: feed, abi: fengAggregatorAbi, functionName: "anchorSetAt" },
          ]
        : []),
    ]),
  ];
  const results = await batchRead(clients, calls, budget);
  const stamp = results[0];
  const nowSec = stamp?.ok && typeof stamp.value === "bigint" ? Number(stamp.value) : null;
  const states: FeedState[] = [];
  const errors: string[] = [];
  entries.forEach(([symbol, feed], index) => {
    const base = 1 + index * stride;
    const round = results[base];
    const decimals = results[base + 1];
    if (!round || !round.ok || !Array.isArray(round.value)) {
      errors.push(`${symbol}: latestRoundData failed${round && !round.ok ? ` (${round.error})` : ""}`);
      return;
    }
    if (!decimals || !decimals.ok || typeof decimals.value !== "number") {
      errors.push(`${symbol}: decimals failed`);
      return;
    }
    const answer = round.value[1];
    const updatedAt = round.value[3];
    if (typeof answer !== "bigint" || typeof updatedAt !== "bigint") {
      errors.push(`${symbol}: unexpected latestRoundData shape`);
      return;
    }
    let band: FeedBand | null = null;
    if (feng) {
      const anchor = results[base + 2];
      const deviation = results[base + 3];
      const window = results[base + 4];
      const setAt = results[base + 5];
      if (anchor?.ok && typeof anchor.value === "bigint" && deviation?.ok && typeof deviation.value === "number") {
        band = {
          anchor: anchor.value,
          maxDeviationBps: deviation.value,
          windowSec: window?.ok && typeof window.value === "bigint" ? Number(window.value) : null,
          marketAgeSec:
            nowSec !== null && setAt?.ok && typeof setAt.value === "bigint"
              ? Math.max(0, nowSec - Number(setAt.value))
              : null,
        };
      } else {
        errors.push(`${symbol}: anchor or deviation bound could not be read`);
      }
    }
    const updated = Number(updatedAt);
    states.push({
      symbol,
      feed,
      decimals: decimals.value,
      answer,
      updatedAt: updated,
      ageSec: nowSec === null ? 0 : Math.max(0, nowSec - updated),
      band,
    });
  });
  return { states, errors, nowSec };
}

export type PushReason = "force" | "move" | "heartbeat" | "hard-floor" | "fresh" | "stale";

export type PushAction = { fn: "updateAnswer"; answer: bigint } | { fn: "refresh" };

export type PushDecision = {
  symbol: string;
  action: "push" | "none";
  reason: PushReason;
  target: bigint | null;
  steps: PushAction[];
  answers: bigint[];
  chase: boolean;
  note: string | null;
};

export type DecideInput = {
  mode: RelayerMode;
  kind: FeedKind;
  state: FeedState;
  quote: Quote | null;
  force: boolean;
  shockHeld?: boolean;
  config: Pick<
    OpsConfig,
    "pushBps" | "heartbeatSec" | "hardMaxAgeSec" | "sanityMoveBps" | "maxStepBps" | "maxStepsPerTick" | "maxPriceAgeSec"
  >;
};

export function moveBps(current: bigint, target: bigint): number {
  if (current <= 0n) return Number.POSITIVE_INFINITY;
  const diff = target > current ? target - current : current - target;
  return Number((diff * 10_000n * 100n) / current) / 100;
}

export function bandLimits(band: FeedBand, maxStepBps: number): { low: bigint; high: bigint } {
  const effective = BigInt(Math.max(1, Math.min(Math.floor(maxStepBps), band.maxDeviationBps)));
  const move = (band.anchor * effective) / 10_000n;
  const low = band.anchor - move;
  return { low: low < 1n ? 1n : low, high: band.anchor + move };
}

export function nextInBand(
  target: bigint,
  band: FeedBand,
  maxStepBps: number,
): { value: bigint; clamped: boolean } {
  const { low, high } = bandLimits(band, maxStepBps);
  const value = target < low ? low : target > high ? high : target;
  return { value, clamped: value !== target };
}

function pushReason(force: boolean, moved: boolean, ageSec: number, hardMaxAgeSec: number): PushReason {
  if (force) return "force";
  if (moved) return "move";
  return ageSec >= hardMaxAgeSec ? "hard-floor" : "heartbeat";
}

export function decidePush(input: DecideInput): PushDecision {
  const { mode, kind, state, quote, force, config } = input;
  const dueAge = Math.min(config.heartbeatSec, config.hardMaxAgeSec);
  const hold = mode === "hold" || input.shockHeld === true;
  let target: bigint | null = null;
  let note: string | null = input.shockHeld === true ? "shock displayed, market pushes held" : null;
  if (hold) {
    target = state.answer;
  } else if (state.symbol === "USDG") {
    target = 10n ** BigInt(state.decimals);
  } else if (quote && quote.status === "ok" && quote.answer !== null) {
    target = quote.answer;
  } else {
    note = quote ? `quote ${quote.status}: ${quote.reason ?? ""}` : "quote unavailable";
  }
  if (target !== null && !hold && moveBps(state.answer, target) > config.sanityMoveBps) {
    note = `move of ${moveBps(state.answer, target).toFixed(0)} bps exceeds sanity limit, price held`;
    target = null;
  }
  const effective = target ?? state.answer;
  const moved = !hold && target !== null && moveBps(state.answer, effective) >= config.pushBps;
  const aged = state.ageSec >= dueAge;
  const none = (): PushDecision => ({
    symbol: state.symbol,
    action: "none",
    reason: "fresh",
    target,
    steps: [],
    answers: [],
    chase: false,
    note,
  });
  if (!force && !moved && !aged) return none();
  const reason = pushReason(force, moved, state.ageSec, config.hardMaxAgeSec);

  if (kind === "mock") {
    return {
      symbol: state.symbol,
      action: "push",
      reason,
      target,
      steps: [{ fn: "updateAnswer", answer: effective }],
      answers: [effective],
      chase: false,
      note,
    };
  }

  if (!moved || target === null) {
    if (!hold && target === null) {
      const age = state.band?.marketAgeSec ?? null;
      if (age === null || age > config.maxPriceAgeSec) {
        const hours = age === null ? "an unknown time" : `${Math.round(age / 360) / 10} h`;
        return {
          symbol: state.symbol,
          action: "none",
          reason: "stale",
          target,
          steps: [],
          answers: [],
          chase: false,
          note: `no market-validated price for ${hours}, heartbeat refresh stopped`,
        };
      }
    }
    const band = state.band;
    if (!hold && target !== null && band && band.windowSec !== null && band.marketAgeSec !== null && band.marketAgeSec >= band.windowSec) {
      const validated = nextInBand(target, band, config.maxStepBps).value;
      return {
        symbol: state.symbol,
        action: "push",
        reason,
        target,
        steps: [{ fn: "updateAnswer", answer: validated }],
        answers: [validated],
        chase: false,
        note,
      };
    }
    return { symbol: state.symbol, action: "push", reason, target, steps: [{ fn: "refresh" }], answers: [], chase: false, note };
  }
  if (!state.band) {
    note = "deviation bound could not be read, price held";
    if (!force && !aged) return { ...none(), note };
    return { symbol: state.symbol, action: "push", reason, target, steps: [{ fn: "refresh" }], answers: [], chase: false, note };
  }
  const first = nextInBand(target, state.band, config.maxStepBps);
  const gap = `${moveBps(state.band.anchor, target).toFixed(0)} bps from the anchor`;
  if (first.value === state.answer) {
    note = `held at the deviation bound, target is ${gap}${state.band.windowSec !== null ? ", anchor window open" : ""}`;
    if (!force && !aged) return { ...none(), note };
    return {
      symbol: state.symbol,
      action: "push",
      reason,
      target,
      steps: [{ fn: "updateAnswer", answer: first.value }],
      answers: [first.value],
      chase: true,
      note,
    };
  }
  if (first.clamped) note = `clamped to the deviation bound, target is ${gap}`;
  return {
    symbol: state.symbol,
    action: "push",
    reason,
    target,
    steps: [{ fn: "updateAnswer", answer: first.value }],
    answers: [first.value],
    chase: first.clamped,
    note,
  };
}

export type FeedReport = {
  symbol: string;
  ageSec: number;
  current: string;
  target: string | null;
  action: "push" | "none";
  reason: PushReason;
  method: "updateAnswer" | "refresh" | null;
  answers: string[];
  anchor: string | null;
  quote: { status: string; bid: string | null; ask: string | null; spreadBps: number | null; reason: string | null } | null;
  note: string | null;
};

export type RelayerOutcome = {
  deployment: string;
  mode: RelayerMode;
  paused: boolean;
  dryRun: boolean;
  nowSec: number | null;
  feeds: FeedReport[];
  pushed: string[];
  wouldPush: string[];
  projection: { feed: Address; answer: string }[];
  txHashes: Hex[];
  pendingHashes: Hex[];
  skipped: { symbol: string; reason: string }[];
  errors: string[];
  critical: string[];
  balanceWei: string | null;
  maxFeedAgeSec: number | null;
};

export type RelayerContext = {
  deployment: Deployment;
  clients: OpsClients;
  config: OpsConfig;
  budget: Budget;
  signer: Signer;
  dryRun: boolean;
  fetchImpl?: FetchLike;
};

function scaled(value: bigint, decimals: number): string {
  const base = 10n ** BigInt(decimals);
  const whole = value / base;
  const frac = (value % base).toString().padStart(decimals, "0").replace(/0+$/, "");
  return frac === "" ? whole.toString() : `${whole}.${frac}`;
}

export function formatAnswer(value: bigint, decimals: number): string {
  return value < 0n ? `-${scaled(-value, decimals)}` : scaled(value, decimals);
}

async function simulatePush(
  clients: OpsClients,
  kind: FeedKind,
  feed: Address,
  step: PushAction,
  account: Address,
): Promise<void> {
  if (kind === "mock") {
    if (step.fn !== "updateAnswer") throw new Error("mock feeds have no refresh");
    await clients.client.simulateContract({
      address: feed,
      abi: mockAggregatorWriteAbi,
      functionName: "updateAnswer",
      args: [step.answer],
      account,
    });
    return;
  }
  if (step.fn === "refresh") {
    await clients.client.simulateContract({ address: feed, abi: fengAggregatorAbi, functionName: "refresh", account });
    return;
  }
  await clients.client.simulateContract({
    address: feed,
    abi: fengAggregatorAbi,
    functionName: "updateAnswer",
    args: [step.answer],
    account,
  });
}

async function sendPush(
  clients: OpsClients,
  signer: Signer,
  kind: FeedKind,
  feed: Address,
  step: PushAction,
  nonce: number,
): Promise<Hex> {
  if (!signer.account) throw new Error("relayer has no signing account");
  const wallet = clients.wallet(signer.account);
  if (kind === "mock") {
    if (step.fn !== "updateAnswer") throw new Error("mock feeds have no refresh");
    return wallet.writeContract({
      address: feed,
      abi: mockAggregatorWriteAbi,
      functionName: "updateAnswer",
      args: [step.answer],
      nonce,
    });
  }
  if (step.fn === "refresh") {
    return wallet.writeContract({ address: feed, abi: fengAggregatorAbi, functionName: "refresh", nonce });
  }
  return wallet.writeContract({
    address: feed,
    abi: fengAggregatorAbi,
    functionName: "updateAnswer",
    args: [step.answer],
    nonce,
  });
}

const shockedEvent = parseAbiItem(
  "event AnswerShocked(int256 indexed current, int256 indexed anchor, uint256 indexed roundId)",
);

export async function findShockedFeeds(
  clients: OpsClients,
  budget: Budget,
  config: Pick<OpsConfig, "shockHoldSec">,
  states: readonly FeedState[],
  nowSec: number | null,
): Promise<Set<string>> {
  const held = new Set<string>();
  const candidates = states.filter((state) => state.band !== null && state.band.anchor !== state.answer);
  if (config.shockHoldSec <= 0 || nowSec === null || candidates.length === 0) return held;
  try {
    const head = await clients.call(budget, "head block", () => clients.client.getBlockNumber());
    const lookback = BigInt(Math.ceil(config.shockHoldSec * 10) + 1_000);
    const logs = await clients.call(budget, "shock logs", () =>
      clients.client.getLogs({
        address: candidates.map((state) => state.feed),
        event: shockedEvent,
        fromBlock: head > lookback ? head - lookback : 0n,
        toBlock: head,
      }),
    );
    for (const state of candidates) {
      const mine = logs.filter((log) => log.address.toLowerCase() === state.feed.toLowerCase());
      const last = mine[mine.length - 1];
      if (!last || last.args.current !== state.answer || last.blockNumber === null) continue;
      const block = await clients.call(budget, "shock block", () =>
        clients.client.getBlock({ blockNumber: last.blockNumber as bigint }),
      );
      if (nowSec - Number(block.timestamp) <= config.shockHoldSec) held.add(state.symbol);
    }
  } catch {
    return held;
  }
  return held;
}

export async function awaitReceipt(
  clients: OpsClients,
  budget: Budget,
  hash: Hex,
): Promise<"success" | "reverted" | "pending"> {
  const timeout = Math.min(budget.left() - 2_000, 8_000);
  if (timeout <= 500) return "pending";
  try {
    const receipt = await budget.race(
      clients.client.waitForTransactionReceipt({ hash, timeout, pollingInterval: 500 }),
      "receipt",
    );
    return receipt.status === "success" ? "success" : "reverted";
  } catch {
    return "pending";
  }
}

async function nextChaseStep(
  ctx: RelayerContext,
  symbol: string,
  target: bigint | null,
  outcome: RelayerOutcome,
): Promise<PushAction | null> {
  if (target === null) return null;
  const fresh = await readFeeds(ctx.clients, ctx.deployment, ctx.budget, [symbol]);
  const state = fresh.states[0];
  if (!state || !state.band || state.answer === target) return null;
  const next = nextInBand(target, state.band, ctx.config.maxStepBps);
  if (next.value === state.answer) {
    outcome.skipped.push({
      symbol,
      reason: `held at the deviation bound, target is ${moveBps(state.band.anchor, target).toFixed(0)} bps from the anchor${state.band.windowSec !== null ? ", anchor window open" : ""}`,
    });
    return null;
  }
  return { fn: "updateAnswer", answer: next.value };
}

export async function runRelayer(
  ctx: RelayerContext,
  options: { force?: boolean } = {},
): Promise<RelayerOutcome> {
  const { deployment, clients, config, budget, signer, dryRun } = ctx;
  const outcome: RelayerOutcome = {
    deployment: deployment.def.id,
    mode: deployment.mode,
    paused: config.relayerPaused,
    dryRun,
    nowSec: null,
    feeds: [],
    pushed: [],
    wouldPush: [],
    projection: [],
    txHashes: [],
    pendingHashes: [],
    skipped: [],
    errors: [],
    critical: [],
    balanceWei: null,
    maxFeedAgeSec: null,
  };
  if (!deployment.def.relayer) return outcome;

  let read: FeedRead;
  try {
    read = await readFeeds(clients, deployment, budget);
  } catch (error) {
    outcome.errors.push(`feed read failed: ${shortError(error)}`);
    outcome.critical.push("feed state could not be read");
    return outcome;
  }
  outcome.nowSec = read.nowSec;
  outcome.errors.push(...read.errors);
  if (read.states.length === 0) {
    outcome.critical.push("no feed could be read");
    return outcome;
  }
  outcome.maxFeedAgeSec = Math.max(...read.states.map((state) => state.ageSec));

  if (config.relayerPaused) {
    outcome.skipped.push({ symbol: "*", reason: "RELAYER_PAUSED is set" });
    return finish(outcome, config, new Set(), read.states);
  }

  let quotes = new Map<string, Quote>();
  if (deployment.mode === "market") {
    const symbols = read.states
      .filter((state) => state.symbol !== "USDG")
      .map((state) => ({ symbol: state.symbol, decimals: state.decimals }));
    try {
      quotes = await fetchQuotes(symbols, config, budget, ctx.fetchImpl);
    } catch (error) {
      outcome.errors.push(`price fetch aborted: ${shortError(error)}`);
    }
  }

  const shocked =
    deployment.def.feedKind === "feng" && deployment.mode === "market"
      ? await findShockedFeeds(clients, budget, config, read.states, read.nowSec)
      : new Set<string>();

  const decisions = read.states.map((state) => {
    const quote = quotes.get(state.symbol) ?? null;
    const decision = decidePush({
      mode: deployment.mode,
      kind: deployment.def.feedKind,
      state,
      quote,
      force: options.force === true,
      shockHeld: shocked.has(state.symbol),
      config,
    });
    outcome.feeds.push({
      symbol: state.symbol,
      ageSec: state.ageSec,
      current: formatAnswer(state.answer, state.decimals),
      target: decision.target === null ? null : formatAnswer(decision.target, state.decimals),
      action: decision.action,
      reason: decision.reason,
      method: decision.steps[0]?.fn ?? null,
      answers: decision.answers.map((answer) => formatAnswer(answer, state.decimals)),
      anchor: state.band ? formatAnswer(state.band.anchor, state.decimals) : null,
      quote: quote
        ? { status: quote.status, bid: quote.bid, ask: quote.ask, spreadBps: quote.spreadBps, reason: quote.reason }
        : null,
      note: decision.note,
    });
    if (quote && quote.status !== "ok") outcome.skipped.push({ symbol: state.symbol, reason: `price ${quote.status}` });
    if (decision.reason === "stale") {
      outcome.skipped.push({ symbol: state.symbol, reason: "price stale" });
      outcome.critical.push(`${state.symbol} price stale, ${decision.note ?? "heartbeat refresh stopped"}`);
    }
    if (decision.action === "none" && decision.note !== null && decision.note.startsWith("held at the deviation bound")) {
      outcome.skipped.push({ symbol: state.symbol, reason: decision.note });
    }
    return { state, decision };
  });

  const due = decisions.filter((entry) => entry.decision.action === "push");
  if (due.length === 0) return finish(outcome, config, new Set(), read.states);

  const simulationAccount = signer.address ?? SIMULATION_PLACEHOLDER;
  const canSimulate = deployment.def.feedKind === "mock" || signer.address !== null;
  const simulated: ({ entry: (typeof due)[number]; ok: true } | { entry: (typeof due)[number]; ok: false; error: unknown })[] = [];
  for (const entry of due) {
    try {
      if (canSimulate) {
        await clients.call(budget, `simulate ${entry.state.symbol}`, () =>
          simulatePush(clients, deployment.def.feedKind, entry.state.feed, entry.decision.steps[0], simulationAccount),
        );
      }
      simulated.push({ entry, ok: true });
    } catch (error) {
      simulated.push({ entry, ok: false, error });
    }
  }
  const ready = simulated.filter((item) => item.ok).map((item) => item.entry);
  for (const item of simulated) {
    if (!item.ok) {
      const name = revertName(item.error);
      outcome.errors.push(`${item.entry.state.symbol}: simulation failed (${name ?? shortError(item.error)})`);
      if (name === "AccessControlUnauthorizedAccount") outcome.critical.push("relayer address does not hold UPDATER_ROLE");
    }
  }

  if (dryRun || !signer.account || !signer.address) {
    outcome.wouldPush.push(...ready.map((entry) => entry.state.symbol));
    outcome.projection.push(
      ...ready.map((entry) => ({
        feed: entry.state.feed,
        answer: (entry.decision.answers[entry.decision.answers.length - 1] ?? entry.state.answer).toString(),
      })),
    );
    if (!dryRun) outcome.critical.push("RELAYER_PRIVATE_KEY is not configured");
    return finish(outcome, config, new Set(), read.states);
  }

  const relayerAddress = signer.address;
  let balance: bigint;
  try {
    balance = await clients.call(budget, "relayer balance", () => clients.client.getBalance({ address: relayerAddress }));
  } catch (error) {
    outcome.errors.push(`relayer balance read failed: ${shortError(error)}`);
    return finish(outcome, config, new Set(), read.states);
  }
  outcome.balanceWei = balance.toString();
  if (balance < config.relayerMinWei) outcome.critical.push("relayer balance below alarm floor");
  if (balance < config.sendMinWei) {
    outcome.critical.push("relayer balance below send floor, nothing sent");
    outcome.skipped.push(...ready.map((entry) => ({ symbol: entry.state.symbol, reason: "balance below send floor" })));
    return finish(outcome, config, new Set(), read.states);
  }

  let nonce: number;
  try {
    nonce = await clients.call(budget, "relayer nonce", () =>
      clients.client.getTransactionCount({ address: relayerAddress, blockTag: "pending" }),
    );
  } catch (error) {
    outcome.errors.push(`relayer nonce read failed: ${shortError(error)}`);
    return finish(outcome, config, new Set(), read.states);
  }

  const sent: { symbol: string; hash: Hex }[] = [];
  let aborted = false;
  for (const entry of ready) {
    if (aborted) break;
    const maxSteps = entry.decision.chase ? config.maxStepsPerTick : 1;
    let step: PushAction | null = entry.decision.steps[0] ?? null;
    for (let index = 0; index < maxSteps && step !== null; index += 1) {
      if (!budget.canSend()) {
        outcome.skipped.push({ symbol: entry.state.symbol, reason: "budget" });
        break;
      }
      try {
        const hash = await budget.race(
          sendPush(clients, signer, deployment.def.feedKind, entry.state.feed, step, nonce),
          `send ${entry.state.symbol}`,
        );
        nonce += 1;
        outcome.txHashes.push(hash);
        sent.push({ symbol: entry.state.symbol, hash });
        if (!entry.decision.chase) break;
        const status = await awaitReceipt(clients, budget, hash);
        if (status !== "success") {
          outcome.errors.push(`${entry.state.symbol}: step ${index + 1} was not confirmed, remaining steps deferred`);
          break;
        }
        step = index + 1 < maxSteps ? await nextChaseStep(ctx, entry.state.symbol, entry.decision.target, outcome) : null;
      } catch (error) {
        outcome.errors.push(`${entry.state.symbol}: send failed (${shortError(error)})`);
        aborted = !(error instanceof BudgetExceededError) ? true : aborted;
        break;
      }
    }
  }

  const confirmed = new Set<string>();
  const statuses = await Promise.all(sent.map((item) => awaitReceipt(clients, budget, item.hash)));
  statuses.forEach((status, index) => {
    const item = sent[index];
    if (status === "success") confirmed.add(item.symbol);
    else if (status === "reverted") outcome.errors.push(`${item.symbol}: transaction reverted`);
    else outcome.pendingHashes.push(item.hash);
  });
  outcome.pushed.push(...ready.filter((entry) => confirmed.has(entry.state.symbol)).map((entry) => entry.state.symbol));
  return finish(outcome, config, confirmed, read.states);
}

function finish(
  outcome: RelayerOutcome,
  config: OpsConfig,
  confirmed: Set<string>,
  states: readonly FeedState[],
): RelayerOutcome {
  const stale = states.filter((state) => state.ageSec > config.criticalFeedAgeSec && !confirmed.has(state.symbol));
  if (stale.length > 0) {
    outcome.critical.push(`feed older than ${Math.round(config.criticalFeedAgeSec / 3600)} h: ${stale.map((state) => state.symbol).join(",")}`);
  }
  return outcome;
}
