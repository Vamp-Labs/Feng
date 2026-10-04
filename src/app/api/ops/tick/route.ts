import { isAuthorized } from "@/ops/auth";
import { runTick } from "@/ops/tick";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const NO_STORE = { "cache-control": "no-store" };

async function handle(request: Request): Promise<Response> {
  if (!isAuthorized(request.headers.get("authorization"), process.env.CRON_SECRET)) {
    return new Response("Unauthorized", { status: 401, headers: NO_STORE });
  }
  const summary = await runTick();
  console.log(
    JSON.stringify({
      tick: {
        ok: summary.ok,
        dryRun: summary.dryRun,
        pushed: summary.pushed.length,
        rebalanced: summary.rebalanced.length,
        errors: summary.errors.length,
        critical: summary.critical,
        elapsedMs: summary.elapsedMs,
      },
    }),
  );
  return Response.json(summary, { status: summary.ok ? 200 : 503, headers: NO_STORE });
}

export async function GET(request: Request): Promise<Response> {
  return handle(request);
}

export async function POST(request: Request): Promise<Response> {
  return handle(request);
}
