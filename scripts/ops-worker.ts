import { registerHooks } from "node:module";

registerHooks({
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

const { runTick } = await import("../src/ops/tick");

type Args = { once: boolean; dryRun: boolean; full: boolean; intervalSec: number };

function parseArgs(argv: string[]): Args {
  const args: Args = { once: false, dryRun: false, full: false, intervalSec: Number(process.env.OPS_WORKER_INTERVAL_SEC ?? 300) };
  for (const arg of argv) {
    if (arg === "--once") args.once = true;
    else if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--full") args.full = true;
    else if (arg.startsWith("--interval=")) args.intervalSec = Number(arg.slice("--interval=".length));
  }
  if (!Number.isFinite(args.intervalSec) || args.intervalSec < 10) args.intervalSec = 300;
  return args;
}

const args = parseArgs(process.argv.slice(2));
let stopping = false;
let wake: (() => void) | null = null;

function stop(): void {
  stopping = true;
  wake?.();
}

process.on("SIGINT", stop);
process.on("SIGTERM", stop);

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    wake = () => {
      clearTimeout(timer);
      resolve();
    };
  });
}

let iteration = 0;
let exitCode = 0;

while (!stopping) {
  iteration += 1;
  const startedAt = Date.now();
  try {
    const summary = await runTick({ dryRun: args.dryRun || undefined });
    const line = args.full
      ? { iteration, ...summary }
      : {
          iteration,
          ok: summary.ok,
          dryRun: summary.dryRun,
          pushed: summary.pushed,
          wouldPush: summary.wouldPush,
          rebalanced: summary.rebalanced,
          wouldRebalance: summary.wouldRebalance,
          checkpointed: summary.checkpointed,
          wouldCheckpoint: summary.wouldCheckpoint,
          errors: summary.errors,
          critical: summary.critical,
          elapsedMs: summary.elapsedMs,
        };
    console.log(JSON.stringify(line));
    if (!summary.ok) exitCode = 1;
  } catch (error) {
    console.error(JSON.stringify({ iteration, fatal: error instanceof Error ? error.message : String(error) }));
    exitCode = 1;
  }
  if (args.once) break;
  const wait = Math.max(1_000, args.intervalSec * 1000 - (Date.now() - startedAt));
  await sleep(wait);
}

process.exit(args.once ? exitCode : 0);
