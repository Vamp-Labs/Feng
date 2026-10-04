import type { StrategySummary } from "@/lib/hooks/use-marketplace";

const FOLLOWER_WEIGHT = 3;
const RECENT_DEPOSIT_WEIGHT = 5;

export function trendingScore(
  strategy: Pick<StrategySummary, "vault">,
  followerCounts: ReadonlyMap<string, number>,
  recentDepositCounts: ReadonlyMap<string, number>,
): number {
  const key = strategy.vault.toLowerCase();
  const followers = followerCounts.get(key) ?? 0;
  const deposits = recentDepositCounts.get(key) ?? 0;
  return followers * FOLLOWER_WEIGHT + deposits * RECENT_DEPOSIT_WEIGHT;
}

export function rankTrending(
  strategies: readonly StrategySummary[],
  followerCounts: ReadonlyMap<string, number>,
  recentDepositCounts: ReadonlyMap<string, number>,
): StrategySummary[] {
  return strategies.toSorted(
    (a, b) => trendingScore(b, followerCounts, recentDepositCounts) - trendingScore(a, followerCounts, recentDepositCounts),
  );
}

export function rankNewest(strategies: readonly StrategySummary[]): StrategySummary[] {
  return strategies.toSorted((a, b) => Number(b.createdAt) - Number(a.createdAt));
}
