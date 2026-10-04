import { claimFaucet, clientIp } from "@/ops/faucet";

export const dynamic = "force-dynamic";
export const maxDuration = 30;

export async function POST(request: Request): Promise<Response> {
  let address: unknown = null;
  try {
    const body: unknown = await request.json();
    if (typeof body === "object" && body !== null) {
      address = (body as Record<string, unknown>).address;
    }
  } catch {
    address = null;
  }
  const result = await claimFaucet(address, clientIp(request.headers));
  return Response.json(result.body, {
    status: result.httpStatus,
    headers: { "cache-control": "no-store" },
  });
}
