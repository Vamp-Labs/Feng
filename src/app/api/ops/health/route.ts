import { computeHealth, type HealthReport } from "@/ops/health";
import { shortError } from "@/ops/redact";

export const dynamic = "force-dynamic";
export const maxDuration = 30;

const CACHE_MS = 15_000;
let cached: { at: number; pending: Promise<HealthReport> } | null = null;

function report(): Promise<HealthReport> {
  const now = Date.now();
  if (cached && now - cached.at < CACHE_MS) return cached.pending;
  const pending = computeHealth();
  cached = { at: now, pending };
  pending.catch(() => {
    cached = null;
  });
  return pending;
}

export async function GET(): Promise<Response> {
  try {
    const health = await report();
    return Response.json(health, {
      status: health.ok ? 200 : 503,
      headers: { "cache-control": "no-store" },
    });
  } catch (error) {
    shortError(error, "health route");
    return Response.json(
      { ok: false, alarms: ["health unavailable"] },
      { status: 503, headers: { "cache-control": "no-store" } },
    );
  }
}
