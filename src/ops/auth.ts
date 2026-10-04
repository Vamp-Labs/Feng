import { createHash, timingSafeEqual } from "node:crypto";

function digest(value: string): Buffer {
  return createHash("sha256").update(value, "utf8").digest();
}

export function isAuthorized(header: string | null, secret: string | undefined): boolean {
  if (!secret) return false;
  const provided = digest(header ?? "");
  const expected = digest(`Bearer ${secret}`);
  return timingSafeEqual(provided, expected);
}
