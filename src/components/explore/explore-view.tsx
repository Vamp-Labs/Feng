"use client";

import { useMemo, useState } from "react";
import { CategoryChips } from "@/components/explore/category-chips";
import { StrategySection } from "@/components/explore/strategy-section";
import { StrategyCard } from "@/components/strategy-card";
import { ButtonLink } from "@/components/ui/button";
import { ErrorCard } from "@/components/ui/error-card";
import { RetryHint } from "@/components/ui/retry-hint";
import { Skeleton } from "@/components/ui/skeleton";
import { StateCard } from "@/components/ui/state-card";
import { categorySlugOf } from "@/lib/discovery/categories";
import { rankNewest, rankTrending } from "@/lib/discovery/ranking";
import { useFollowerCounts } from "@/lib/hooks/use-follower-count";
import { useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import { useRecentDepositActivity } from "@/lib/hooks/use-recent-deposit-activity";
import { useStrategyHoldings } from "@/lib/hooks/use-strategy-holdings";

const TRENDING_LIMIT = 6;
const NEW_LIMIT = 6;
const GRID_SKELETONS = [0, 1, 2, 3, 4, 5] as const;

export function ExploreView() {
  const { strategies, isLoading, isEmpty, error, isRetrying, refetch } = useMarketplaceStrategies();
  const { holdings, isLoading: holdingsLoading } = useStrategyHoldings();
  const vaults = useMemo(() => strategies.map((strategy) => strategy.vault), [strategies]);
  const followerCounts = useFollowerCounts(vaults);
  const recentActivity = useRecentDepositActivity(vaults);
  const [category, setCategory] = useState<string | undefined>(undefined);

  const trending = useMemo(
    () => rankTrending(strategies, followerCounts.counts, recentActivity.countByVault).slice(0, TRENDING_LIMIT),
    [strategies, followerCounts.counts, recentActivity.countByVault],
  );
  const freshest = useMemo(() => rankNewest(strategies).slice(0, NEW_LIMIT), [strategies]);

  const filtered = useMemo(() => {
    if (!category) return strategies;
    return strategies.filter((strategy) => categorySlugOf(strategy) === category);
  }, [strategies, category]);

  if (error) {
    return (
      <ErrorCard
        title="Explore unavailable"
        summary="Could not read the registry from the active network."
        error={error}
        onRetry={refetch}
      />
    );
  }

  if (isLoading) {
    return (
      <div className="flex flex-col gap-6">
        <div className="strategy-grid" role="status">
          <span className="sr-only">Loading strategies</span>
          {GRID_SKELETONS.map((slot) => (
            <Skeleton key={slot} className="strategy-skeleton" />
          ))}
        </div>
        <RetryHint active={isRetrying} />
      </div>
    );
  }

  if (isEmpty) {
    return (
      <StateCard art="empty" title="No strategies yet" actions={<ButtonLink href="/create">Create a strategy</ButtonLink>}>
        <p>Be the first to turn an investment thesis into a strategy.</p>
      </StateCard>
    );
  }

  return (
    <div className="flex flex-col gap-16">
      <StrategySection
        title="Trending Strategies"
        lead="Ranked by followers and recent participation."
        strategies={trending}
        holdings={holdings}
        holdingsLoading={holdingsLoading}
        isLoading={followerCounts.isLoading || recentActivity.isLoading}
      />
      <StrategySection
        title="New Strategies"
        lead="Recently published theses."
        strategies={freshest}
        holdings={holdings}
        holdingsLoading={holdingsLoading}
        isLoading={false}
      />

      <section className="explore-section" aria-labelledby="explore-all">
        <div className="explore-section__head">
          <h2 className="text-heading text-ink" id="explore-all">
            Explore by category
          </h2>
          <CategoryChips selected={category} onChange={setCategory} />
        </div>
        {filtered.length === 0 ? (
          <StateCard art="empty" title="No strategies match">
            <p>Nothing in this category yet. Try another one, or create the first.</p>
          </StateCard>
        ) : (
          <div className="strategy-grid">
            {filtered.map((strategy) => (
              <StrategyCard
                key={strategy.vault}
                strategy={strategy}
                holdings={holdings[strategy.vault]}
                holdingsLoading={holdingsLoading}
              />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
