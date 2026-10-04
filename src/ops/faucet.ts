import { getAddress, isAddress, zeroAddress, type Address, type Hex } from "viem";
import { fengFaucetAbi, multicallAbi, tokenAbi } from "./abi";
import {
  ETH_DRIP_WEI,
  MULTICALL3_ADDRESS,
  USDG_FILL_WHOLE,
  loadConfig,
  loadDeployments,
  pickFaucetDeployment,
  withResolvedFaucetMode,
  type Deployment,
  type OpsConfig,
} from "./config";
import {
  batchRead,
  createBudget,
  createClients,
  expectBigint,
  loadSigner,
  revertName,
  shortError,
  type Budget,
  type OpsClients,
  type Signer,
} from "./rpc";

export type FaucetStatus = "funded" | "already-claimed" | "faucet-empty" | "invalid-address" | "rate-limited";

export type FaucetBody = { status: FaucetStatus; txHash?: Hex };

export type FaucetResponse = { httpStatus: number; body: FaucetBody };

const HTTP: Record<FaucetStatus, number> = {
  funded: 200,
  "already-claimed": 200,
  "faucet-empty": 503,
  "invalid-address": 400,
  "rate-limited": 429,
};

function respond(status: FaucetStatus, txHash?: Hex): FaucetResponse {
  return { httpStatus: HTTP[status], body: txHash ? { status, txHash } : { status } };
}

export type Limiter = {
  hit: (key: string, now?: number) => boolean;
  size: () => number;
};

export function createLimiter(maxHits: number, windowMs: number, maxKeys = 5_000): Limiter {
  const hits = new Map<string, number[]>();
  return {
    hit: (key, now = Date.now()) => {
      if (hits.size > maxKeys) {
        for (const [entryKey, stamps] of hits) {
          if (stamps.every((stamp) => now - stamp > windowMs)) hits.delete(entryKey);
        }
      }
      const recent = (hits.get(key) ?? []).filter((stamp) => now - stamp <= windowMs);
      if (recent.length >= maxHits) {
        hits.set(key, recent);
        return false;
      }
      recent.push(now);
      hits.set(key, recent);
      return true;
    },
    size: () => hits.size,
  };
}

const ipLimiter = createLimiter(6, 10 * 60_000);
const addressLimiter = createLimiter(1, 60_000);
const inFlight = new Set<string>();
let sendQueue: Promise<unknown> = Promise.resolve();

function serialized<T>(task: () => Promise<T>): Promise<T> {
  const run = sendQueue.then(task, task);
  sendQueue = run.catch(() => undefined);
  return run;
}

export function clientIp(headers: Headers): string {
  const forwarded = headers.get("x-vercel-forwarded-for") ?? headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();
  return headers.get("x-real-ip")?.trim() || "unknown";
}

const CONTRACT_REVERTS: Record<string, FaucetStatus> = {
  AlreadyClaimed: "already-claimed",
  FaucetEmpty: "faucet-empty",
  DailyCapReached: "faucet-empty",
  TransferFailed: "faucet-empty",
  RecipientIsContract: "invalid-address",
  ZeroAddress: "invalid-address",
};

export async function claimViaContract(
  deployment: Deployment,
  clients: OpsClients,
  budget: Budget,
  signer: Signer,
  target: Address,
  config: Pick<OpsConfig, "sendMinWei">,
): Promise<FaucetResponse> {
  const faucet = deployment.addresses.faucet;
  const dispenser = signer.account;
  if (!faucet || !dispenser || !signer.address) {
    console.error("faucet: contract mode needs a faucet address in addresses.json and FAUCET_PRIVATE_KEY");
    return respond("faucet-empty");
  }
  const dispenserAddress = signer.address;
  try {
    await clients.call(budget, "simulate claimFor", () =>
      clients.client.simulateContract({
        address: faucet,
        abi: fengFaucetAbi,
        functionName: "claimFor",
        args: [target],
        account: dispenser,
      }),
    );
  } catch (error) {
    const name = revertName(error);
    const mapped = name === null ? undefined : CONTRACT_REVERTS[name];
    if (mapped) return respond(mapped);
    console.error(`faucet: claimFor simulation failed: ${name ?? shortError(error)}`);
    return respond("faucet-empty");
  }
  const balance = await clients.call(budget, "dispenser balance", () =>
    clients.client.getBalance({ address: dispenserAddress }),
  );
  if (balance < config.sendMinWei) {
    console.error("faucet: dispenser wallet is below the send floor");
    return respond("faucet-empty");
  }
  const hash = await serialized(async () => {
    const nonce = await budget.race(
      clients.client.getTransactionCount({ address: dispenserAddress, blockTag: "pending" }),
      "faucet nonce",
    );
    const gas = await clients.client
      .estimateContractGas({ address: faucet, abi: fengFaucetAbi, functionName: "claimFor", args: [target], account: dispenser })
      .then(
        (value) => (value * 13n) / 10n,
        () => undefined,
      );
    return budget.race(
      clients.wallet(dispenser).writeContract({
        address: faucet,
        abi: fengFaucetAbi,
        functionName: "claimFor",
        args: [target],
        nonce,
        gas,
      }),
      "faucet claimFor",
    );
  });
  const receipt = await budget
    .race(
      clients.client.waitForTransactionReceipt({
        hash,
        timeout: Math.max(1_000, Math.min(budget.left() - 1_000, 10_000)),
        pollingInterval: 500,
      }),
      "faucet receipt",
    )
    .catch(() => null);
  if (receipt === null || receipt.status === "success") return respond("funded", hash);
  const claimed = await clients.client
    .readContract({ address: faucet, abi: fengFaucetAbi, functionName: "hasClaimed", args: [target] })
    .catch(() => false);
  return respond(claimed ? "already-claimed" : "faucet-empty");
}

export async function claimFaucet(
  rawAddress: unknown,
  ip: string,
  baseConfig: OpsConfig = loadConfig(),
): Promise<FaucetResponse> {
  let config = baseConfig;
  if (!ipLimiter.hit(ip)) return respond("rate-limited");
  if (typeof rawAddress !== "string" || !isAddress(rawAddress, { strict: false }) || rawAddress.toLowerCase() === zeroAddress) {
    return respond("invalid-address");
  }
  const target: Address = getAddress(rawAddress);
  const key = target.toLowerCase();
  if (inFlight.has(key) || !addressLimiter.hit(key)) return respond("rate-limited");
  inFlight.add(key);
  const budget = createBudget(config.budgetMs, config.minSendMs);
  try {
    const deployments = await loadDeployments();
    config = withResolvedFaucetMode(baseConfig, deployments);
    const deployment = pickFaucetDeployment(deployments, config);
    if (!deployment) {
      console.error("faucet: no deployment is available");
      return respond("faucet-empty");
    }
    const clients = createClients(deployment, config, budget);

    const code = await clients.call(budget, "getCode", () => clients.client.getCode({ address: target }));
    if (code !== undefined && code !== "0x") return respond("invalid-address");

    const signer = loadSigner("faucet", config);
    if (!signer.account || !signer.address) {
      console.error("faucet: FAUCET_PRIVATE_KEY is not configured");
      return respond("faucet-empty");
    }

    if (config.faucetMode === "contract") return await claimViaContract(deployment, clients, budget, signer, target, config);

    const usdg = deployment.addresses.usdg;
    const reads = await batchRead(
      clients,
      [
        { address: MULTICALL3_ADDRESS, abi: multicallAbi, functionName: "getEthBalance", args: [target] },
        { address: usdg, abi: tokenAbi, functionName: "balanceOf", args: [target] },
        { address: usdg, abi: tokenAbi, functionName: "decimals" },
        { address: MULTICALL3_ADDRESS, abi: multicallAbi, functionName: "getEthBalance", args: [signer.address] },
        { address: usdg, abi: tokenAbi, functionName: "balanceOf", args: [signer.address] },
      ],
      budget,
    );
    const targetEth = expectBigint(reads[0]);
    const targetUsdg = expectBigint(reads[1]);
    const decimalsRead = reads[2];
    const faucetEth = expectBigint(reads[3]);
    const faucetUsdg = expectBigint(reads[4]);
    if (
      targetEth === null ||
      targetUsdg === null ||
      faucetEth === null ||
      faucetUsdg === null ||
      !decimalsRead?.ok ||
      typeof decimalsRead.value !== "number"
    ) {
      console.error("faucet: balance reads failed");
      return respond("faucet-empty");
    }
    const usdgFill = USDG_FILL_WHOLE * 10n ** BigInt(decimalsRead.value);
    const needsEth = targetEth < ETH_DRIP_WEI / 2n;
    const needsUsdg = targetUsdg < usdgFill / 2n;
    if (!needsEth && !needsUsdg) return respond("already-claimed");

    const sendEth = needsEth && faucetEth >= ETH_DRIP_WEI + config.sendMinWei;
    const sendUsdg = needsUsdg && faucetUsdg >= usdgFill && faucetEth >= config.sendMinWei;
    if (!sendEth && !sendUsdg) return respond("faucet-empty");

    const hashes = await serialized(async () => {
      if (!signer.account || !signer.address) throw new Error("faucet has no signing account");
      const wallet = clients.wallet(signer.account);
      let nonce = await budget.race(
        clients.client.getTransactionCount({ address: signer.address, blockTag: "pending" }),
        "faucet nonce",
      );
      const sent: Hex[] = [];
      if (sendUsdg) {
        sent.push(
          await budget.race(
            wallet.writeContract({
              address: usdg,
              abi: tokenAbi,
              functionName: "transfer",
              args: [target, usdgFill],
              nonce,
            }),
            "faucet usdg transfer",
          ),
        );
        nonce += 1;
      }
      if (sendEth) {
        sent.push(
          await budget.race(wallet.sendTransaction({ to: target, value: ETH_DRIP_WEI, nonce }), "faucet eth transfer"),
        );
      }
      return sent;
    });

    await Promise.all(
      hashes.map((hash) =>
        budget
          .race(
            clients.client.waitForTransactionReceipt({ hash, timeout: Math.max(1_000, Math.min(budget.left() - 1_000, 10_000)), pollingInterval: 500 }),
            "faucet receipt",
          )
          .catch(() => undefined),
      ),
    );
    return respond("funded", hashes[0]);
  } catch (error) {
    console.error(`faucet: ${shortError(error, "faucet")}`);
    return respond("faucet-empty");
  } finally {
    inFlight.delete(key);
    budget.dispose();
  }
}
