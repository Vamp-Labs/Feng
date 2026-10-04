import type { Address } from "viem";

const WEIGHT_UNIT = 10_000n;
const LEG_SCALE = WEIGHT_UNIT * WEIGHT_UNIT;
const SHARE_PRICE_UNIT = 10n ** 18n;

export interface WeightedHolding {
  token: Address;
  targetWeightBps: number;
  isStrategyToken: boolean;
}

export function largestLegScale(
  holdings: readonly WeightedHolding[],
  childHoldings: ReadonlyMap<string, readonly WeightedHolding[]>,
): bigint | undefined {
  let largest = 0n;
  for (const holding of holdings) {
    const weight = BigInt(holding.targetWeightBps);
    if (!holding.isStrategyToken) {
      const scale = weight * WEIGHT_UNIT;
      if (scale > largest) largest = scale;
      continue;
    }
    const children = childHoldings.get(holding.token.toLowerCase());
    if (!children) return undefined;
    for (const child of children) {
      if (child.isStrategyToken) continue;
      const scale = weight * BigInt(child.targetWeightBps);
      if (scale > largest) largest = scale;
    }
  }
  return largest;
}

export function maxTotalUsdg(capUsdg: bigint, scale: bigint): bigint | undefined {
  if (capUsdg === 0n || scale === 0n) return undefined;
  return (capUsdg * LEG_SCALE) / scale;
}

export function largestLegPercent(scale: bigint): number {
  return Number((scale * 10_000n) / LEG_SCALE) / 100;
}

export function sharesWorthUsdg(usdgAmount: bigint, sharePrice: bigint): bigint | undefined {
  if (sharePrice === 0n) return undefined;
  return (usdgAmount * SHARE_PRICE_UNIT) / sharePrice;
}

export function usdgValueOfShares(shares: bigint, sharePrice: bigint): bigint {
  return (shares * sharePrice) / SHARE_PRICE_UNIT;
}
