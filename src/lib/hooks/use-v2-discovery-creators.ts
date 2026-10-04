import { SECONDS_PER_DAY } from "@/lib/discovery-format";
import { navUsdOf, type StrategySummary } from "@/lib/hooks/use-marketplace";

export interface CreatorRow {
  creator: string;
  strategies: number;
  aumUsd: number;
  bestReturn: number | undefined;
  bestSymbol: string | undefined;
  bestVault: string | undefined;
  oldestCreatedAt: number | undefined;
  score: number;
}

export const SCORE_WEIGHTS = { aum: 0.5, returns: 0.3, age: 0.2 } as const;
export const SCORE_RETURN_FLOOR = -0.5;
export const SCORE_RETURN_CAP = 1;
export const SCORE_AGE_CAP_DAYS = 30;

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

export function buildCreatorRows(strategies: readonly StrategySummary[], nowSeconds: number): CreatorRow[] {
  const groups = new Map<string, StrategySummary[]>();
  for (const strategy of strategies) {
    const key = strategy.creator.toLowerCase();
    groups.set(key, [...(groups.get(key) ?? []), strategy]);
  }

  const partial = [...groups.entries()].map(([creator, list]) => {
    const aumUsd = list.reduce((sum, strategy) => sum + (navUsdOf(strategy) ?? 0), 0);
    let best: StrategySummary | undefined;
    for (const strategy of list) {
      if (strategy.sinceInception === undefined) continue;
      if (!best || strategy.sinceInception > (best.sinceInception ?? Number.NEGATIVE_INFINITY)) best = strategy;
    }
    const created = list.map((strategy) => Number(strategy.createdAt)).filter((value) => value > 0);
    return {
      creator,
      strategies: list.length,
      aumUsd,
      bestReturn: best?.sinceInception,
      bestSymbol: best?.symbol,
      bestVault: best?.vault,
      oldestCreatedAt: created.length > 0 ? Math.min(...created) : undefined,
    };
  });

  const maxAum = Math.max(0, ...partial.map((row) => row.aumUsd));

  return partial.map((row) => {
    const aumScore = maxAum > 0 ? Math.log10(1 + row.aumUsd) / Math.log10(1 + maxAum) : 0;
    const returnScore =
      row.bestReturn === undefined
        ? 0
        : clamp01((row.bestReturn - SCORE_RETURN_FLOOR) / (SCORE_RETURN_CAP - SCORE_RETURN_FLOOR));
    const ageScore =
      row.oldestCreatedAt === undefined ? 0 : clamp01((nowSeconds - row.oldestCreatedAt) / SECONDS_PER_DAY / SCORE_AGE_CAP_DAYS);
    const score = 100 * (SCORE_WEIGHTS.aum * aumScore + SCORE_WEIGHTS.returns * returnScore + SCORE_WEIGHTS.age * ageScore);
    return { ...row, score };
  });
}
