import { navUsdOf, type StrategySummary } from "@/lib/hooks/use-marketplace";

export const FEATURED_LIMIT = 3;

const navOf = (strategy: StrategySummary) => navUsdOf(strategy) ?? -1;

export function byNavDesc(a: StrategySummary, b: StrategySummary): number {
  return navOf(b) - navOf(a);
}

export function pickFeatured(strategies: readonly StrategySummary[]): StrategySummary[] {
  const ranked = strategies.toSorted(byNavDesc);
  const centre = ranked.find((strategy) => strategy.depth >= 2);
  if (!centre) return ranked.slice(0, FEATURED_LIMIT);
  return [centre, ...ranked.filter((strategy) => strategy !== centre).slice(0, FEATURED_LIMIT - 1)];
}
