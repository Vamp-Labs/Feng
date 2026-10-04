import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { HttpRequestError } from "viem";

type ResolveResult = { url: string; format?: string | null; shortCircuit?: boolean };
type NextResolve = (specifier: string, context: object) => ResolveResult;
type HookHost = {
  registerHooks: (hooks: { resolve: (specifier: string, context: object, nextResolve: NextResolve) => ResolveResult }) => void;
};

const hookHost = (await import("node:module")) as unknown as HookHost;
hookHost.registerHooks({
  resolve(specifier, context, nextResolve) {
    try {
      return nextResolve(specifier, context);
    } catch (error) {
      const code = (error as { code?: string } | null)?.code;
      if (specifier.startsWith(".") && code === "ERR_MODULE_NOT_FOUND") {
        return nextResolve(`${specifier}.ts`, context);
      }
      throw error;
    }
  },
});

const redact = await import("./redact");
const configModule = await import("./config");
const pricesModule = await import("./prices");
const relayerModule = await import("./relayer");
const healthModule = await import("./health");

const SECRET = "SECRETAPIKEY1234567890abcdef";
const FAKE_URL = `https://rpc.provider-example.net/v2/${SECRET}`;
const VOCABULARY = new Set<string>([
  "rpc unreachable",
  "rpc timeout",
  "rpc rate limited",
  "rpc error",
  "call reverted",
  "time budget exhausted",
  "price api error",
  "internal error",
]);

function captureErrors<T>(run: () => T): { value: T; logs: string[] } {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  try {
    return { value: run(), logs };
  } finally {
    console.error = original;
  }
}

test("shortError returns a fixed phrase and the log carries no URL or key", () => {
  const error = new HttpRequestError({
    url: FAKE_URL,
    status: 401,
    details: `invalid key ${SECRET} for /v2/${SECRET} at https://rpc.provider-example.net`,
  });
  const { value, logs } = captureErrors(() => redact.shortError(error, "check"));
  assert.ok(VOCABULARY.has(value), value);
  assert.equal(value, "rpc error");
  assert.ok(!value.includes(SECRET));
  assert.ok(!value.includes("provider-example"));
  assert.ok(logs.length === 1);
  for (const line of logs) {
    assert.ok(!line.includes(SECRET), line);
    assert.ok(!line.includes("provider-example"), line);
    assert.ok(!line.includes("https://"), line);
  }
});

test("shortError classifies timeouts, refusals and rate limits", () => {
  const timeout = captureErrors(() => redact.shortError(new Error(`The request took too long to respond ${FAKE_URL} timed out`))).value;
  const refused = captureErrors(() => redact.shortError(new Error("fetch failed", { cause: new Error("connect ECONNREFUSED 127.0.0.1:8545") }))).value;
  const limited = captureErrors(() => redact.shortError(new HttpRequestError({ url: FAKE_URL, status: 429 }))).value;
  assert.equal(timeout, "rpc timeout");
  assert.equal(refused, "rpc unreachable");
  assert.equal(limited, "rpc rate limited");
  assert.equal(captureErrors(() => redact.shortError("plain text with " + FAKE_URL)).value, "internal error");
});

test("redactText strips URLs, hosts, addresses of hosts, keys and long tokens", () => {
  const text = redact.redactText(`${FAKE_URL} host rpc.provider-example.net:8545 ip 10.1.2.3:9 key 0x${"ab".repeat(32)} token ${SECRET}`);
  for (const bad of [SECRET, "provider-example", "10.1.2.3", "abababab"]) assert.ok(!text.includes(bad), text);
});

test("health route payload never echoes provider text, RPC URL or host", async () => {
  const server = createServer((request, response) => {
    response.statusCode = 401;
    response.setHeader("content-type", "text/plain");
    response.end(`invalid key ${SECRET} for ${request.url ?? ""} on https://rpc.provider-example.net/v2/${SECRET}`);
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as AddressInfo).port;
  const rpcUrl = `http://127.0.0.1:${port}/v2/${SECRET}`;
  try {
    const config = configModule.loadConfig({
      OPS_RPC_URL: rpcUrl,
      OPS_RPC_ATTEMPTS: "1",
      OPS_RPC_OUTER_ATTEMPTS: "1",
      OPS_RPC_TIMEOUT_MS: "1500",
      OPS_BUDGET_MS: "8000",
      OPS_KEEPER_ADDRESS: "0x000000000000000000000000000000000000dEaD",
    });
    const addresses = configModule.parseAddresses({
      chainId: 31337,
      rpcUrl,
      usdg: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
      stockTokens: { TSLA: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512" },
      priceOracles: { TSLA: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0" },
      strategyFactory: "0xc6e7DF5E7b4f2A278906862b61205850344D4e7d",
      rebalanceEngine: "0x59b670e9fA9D0A427751Af201D676719a970857b",
      marketplaceRegistry: "0x3Aa5ebB10DC797CAC828524e59A333d0A371443c",
    });
    const def = configModule.DEPLOYMENT_REGISTRY[1];
    const { value: report, logs } = await (async () => {
      const logs: string[] = [];
      const original = console.error;
      console.error = (...args: unknown[]) => {
        logs.push(args.map(String).join(" "));
      };
      try {
        const value = await healthModule.computeHealth({ config, deployments: [{ def, addresses, mode: "market" }] });
        return { value, logs };
      } finally {
        console.error = original;
      }
    })();
    const body = JSON.stringify(report);
    assert.ok(report.alarms.length > 0);
    for (const bad of [SECRET, "provider-example", "127.0.0.1", String(port), "/v2/", "http://", "https://"]) {
      assert.ok(!body.includes(bad), `${bad} leaked in ${body.slice(0, 300)}`);
    }
    for (const alarm of report.alarms) {
      assert.ok(!/[a-z]+:\/\//i.test(alarm), alarm);
    }
    for (const line of logs) {
      assert.ok(!line.includes(SECRET), line);
      assert.ok(!line.includes("provider-example"), line);
    }
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

test("price quote needs a readable generatedAt within the clock bound", () => {
  const config = { spreadMaxBps: 500, clockSkewSec: 120 };
  const now = Date.parse("2026-10-04T12:00:00Z");
  const make = (extra: Record<string, unknown>) => ({
    quotes: [{ tokenSymbol: "TSLA", tokenBid: "100.0", tokenAsk: "100.1", isTradingHalt: false, ...extra }],
  });
  const fresh = pricesModule.parseQuote("TSLA", make({ generatedAt: "2026-10-04T11:59:30.123456789Z" }), 8, config, now);
  assert.equal(fresh.status, "ok");
  for (const extra of [{}, { generatedAt: "not a date" }, { generatedAt: 1759579200 }, { generatedAt: "2026-10-04T11:50:00Z" }, { generatedAt: "2026-10-04T12:10:00Z" }]) {
    const quote = pricesModule.parseQuote("TSLA", make(extra), 8, config, now);
    assert.equal(quote.status, "clock", JSON.stringify(extra));
    assert.equal(quote.answer, null);
  }
});

const BASE_CONFIG = {
  pushBps: 10,
  heartbeatSec: 1500,
  hardMaxAgeSec: 43_200,
  sanityMoveBps: 5000,
  maxStepBps: 900,
  maxStepsPerTick: 3,
  maxPriceAgeSec: 21_600,
};

function feedState(marketAgeSec: number | null, ageSec: number) {
  return {
    symbol: "TSLA",
    feed: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0" as const,
    decimals: 8,
    answer: 40_000_000_000n,
    updatedAt: 0,
    ageSec,
    band: { anchor: 40_000_000_000n, maxDeviationBps: 1000, windowSec: 3600, marketAgeSec },
  };
}

const NO_QUOTE = null;
const OK_QUOTE = {
  symbol: "TSLA",
  status: "ok" as const,
  reason: null,
  bid: "400",
  ask: "400.1",
  spreadBps: 2.5,
  answer: 40_005_000_000n,
};

test("heartbeat refresh stops once the last market validation is older than the bound", () => {
  const stale = relayerModule.decidePush({
    mode: "market",
    kind: "feng",
    state: feedState(7 * 3600, 1800),
    quote: NO_QUOTE,
    force: false,
    config: BASE_CONFIG,
  });
  assert.equal(stale.action, "none");
  assert.equal(stale.reason, "stale");
  assert.deepEqual(stale.steps, []);

  const forced = relayerModule.decidePush({
    mode: "market",
    kind: "feng",
    state: feedState(7 * 3600, 10),
    quote: NO_QUOTE,
    force: true,
    config: BASE_CONFIG,
  });
  assert.equal(forced.reason, "stale");

  const unknown = relayerModule.decidePush({
    mode: "market",
    kind: "feng",
    state: feedState(null, 1800),
    quote: NO_QUOTE,
    force: false,
    config: BASE_CONFIG,
  });
  assert.equal(unknown.reason, "stale");

  const young = relayerModule.decidePush({
    mode: "market",
    kind: "feng",
    state: feedState(2 * 3600, 1800),
    quote: NO_QUOTE,
    force: false,
    config: BASE_CONFIG,
  });
  assert.equal(young.action, "push");
  assert.deepEqual(young.steps, [{ fn: "refresh" }]);
});

test("a validated quiet heartbeat renews the anchor instead of a bare refresh", () => {
  const renewed = relayerModule.decidePush({
    mode: "market",
    kind: "feng",
    state: feedState(7 * 3600, 1800),
    quote: { ...OK_QUOTE, answer: 40_001_000_000n },
    force: false,
    config: BASE_CONFIG,
  });
  assert.equal(renewed.action, "push");
  assert.deepEqual(renewed.steps, [{ fn: "updateAnswer", answer: 40_001_000_000n }]);

  const insideWindow = relayerModule.decidePush({
    mode: "market",
    kind: "feng",
    state: feedState(600, 1800),
    quote: { ...OK_QUOTE, answer: 40_001_000_000n },
    force: false,
    config: BASE_CONFIG,
  });
  assert.deepEqual(insideWindow.steps, [{ fn: "refresh" }]);

  const held = relayerModule.decidePush({
    mode: "hold",
    kind: "feng",
    state: feedState(7 * 3600, 1800),
    quote: NO_QUOTE,
    force: false,
    config: BASE_CONFIG,
  });
  assert.deepEqual(held.steps, [{ fn: "refresh" }]);
});

test("faucet mode defaults to contract when a deployment has a faucet, explicit value wins", () => {
  const def = configModule.DEPLOYMENT_REGISTRY[1];
  const base = {
    chainId: 1,
    rpcUrl: "http://127.0.0.1:1",
    usdg: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    stockTokens: {},
    priceOracles: {},
    strategyFactory: "0xc6e7DF5E7b4f2A278906862b61205850344D4e7d",
    rebalanceEngine: "0x59b670e9fA9D0A427751Af201D676719a970857b",
    marketplaceRegistry: "0x3Aa5ebB10DC797CAC828524e59A333d0A371443c",
  };
  const withFaucet = { def, mode: "market" as const, addresses: configModule.parseAddresses({ ...base, faucet: "0x1111111111111111111111111111111111111111" }) };
  const without = { def, mode: "market" as const, addresses: configModule.parseAddresses(base) };
  assert.equal(configModule.resolveFaucetMode(configModule.loadConfig({}), [withFaucet]), "contract");
  assert.equal(configModule.resolveFaucetMode(configModule.loadConfig({}), [without]), "v1");
  assert.equal(configModule.resolveFaucetMode(configModule.loadConfig({ OPS_FAUCET_MODE: "v1" }), [withFaucet]), "v1");
  assert.equal(configModule.resolveFaucetMode(configModule.loadConfig({ OPS_FAUCET_MODE: "contract" }), [without]), "contract");
  assert.equal(configModule.resolveFaucetMode(configModule.loadConfig({ OPS_FAUCET_MODE: "bogus" }), [withFaucet]), "contract");
});
