"use client";

import { useMemo, useState } from "react";
import { m, useReducedMotion } from "framer-motion";
import { useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import { StrategyCard } from "@/components/strategy-card";
import {
  filterStrategies,
  hasActiveFilters,
  INITIAL_FILTERS,
  MarketplaceFilters,
  sortStrategies,
  tickersOf,
  type FilterState,
} from "@/components/marketplace-filters";
import { Button, ButtonLink } from "@/components/ui/button";
import { ErrorCard } from "@/components/ui/error-card";
import { RetryHint } from "@/components/ui/retry-hint";
import { Skeleton } from "@/components/ui/skeleton";
import { StateCard } from "@/components/ui/state-card";
import { byNavDesc } from "@/lib/featured";
import { useStrategyHoldings } from "@/lib/hooks/use-strategy-holdings";
import type { StrategyMetrics } from "@/lib/hooks/use-nav-history";
import { useWatchlist } from "@/lib/hooks/use-watchlist";
import { EASE_OUT, LIST_ITEM_SECONDS, LIST_STAGGER_SECONDS } from "@/lib/motion";
import { IS_V2 } from "@/lib/protocol";

const MAX_STAGGER_STEPS = 5;
const IN_VIEW = { once: true, margin: "0px 0px -8% 0px" } as const;
const SKELETONS_V1 = [0, 1, 2] as const;
const SKELETONS_V2 = [0, 1, 2, 3, 4, 5] as const;
const NO_METRICS: ReadonlyMap<string, StrategyMetrics> = new Map();

export function MarketplaceList() {
  const { strategies, isLoading, isEmpty, error, isRetrying, refetch } = useMarketplaceStrategies();
  const { holdings, isLoading: holdingsLoading } = useStrategyHoldings();
  const { isFollowing, count: followingCount } = useWatchlist();
  const [filters, setFilters] = useState<FilterState>(INITIAL_FILTERS);
  const reduceMotion = useReducedMotion();

  const availableTickers = useMemo(
    () => [...new Set(strategies.flatMap((strategy) => tickersOf(holdings[strategy.vault])))].toSorted(),
    [strategies, holdings],
  );
  const availableTags = useMemo(
    () => [...new Set(strategies.flatMap((strategy) => strategy.tags ?? []))].toSorted(),
    [strategies],
  );

  const visible = useMemo(() => {
    if (!IS_V2) return strategies.toSorted(byNavDesc);
    return sortStrategies(filterStrategies(strategies, filters, holdings, isFollowing), NO_METRICS, filters.sort);
  }, [strategies, filters, holdings, isFollowing]);

  if (error) {
    return (
      <ErrorCard
        title="Marketplace unavailable"
        summary="Could not read the registry from the active network."
        error={error}
        onRetry={refetch}
      />
    );
  }

  if (isLoading || (IS_V2 && holdingsLoading)) {
    return (
      <div className="flex flex-col gap-6">
        <div className="strategy-grid" role="status">
          <span className="sr-only">Loading strategies</span>
          {(IS_V2 ? SKELETONS_V2 : SKELETONS_V1).map((i) => (
            <Skeleton key={i} className={IS_V2 ? "strategy-skeleton" : "h-36"} />
          ))}
        </div>
        <RetryHint active={isRetrying} />
      </div>
    );
  }

  if (isEmpty) {
    return (
      <StateCard
        art="empty"
        title="No strategies yet"
        actions={<ButtonLink href="/create">Create a strategy</ButtonLink>}
      >
        <p>Be the first to compose a Strategy Token from tokenized stocks.</p>
      </StateCard>
    );
  }

  return (
    <div className="flex flex-col gap-8">
      {IS_V2 ? (
        <MarketplaceFilters
          filters={filters}
          onChange={setFilters}
          availableTickers={availableTickers}
          availableTags={availableTags}
          hasLive={strategies.some((strategy) => strategy.universe === "live")}
          followingCount={followingCount}
          shown={visible.length}
          total={strategies.length}
        />
      ) : null}
      {visible.length === 0 ? (
        <StateCard
          art="empty"
          title="No strategies match"
          actions={<Button onClick={() => setFilters({ ...INITIAL_FILTERS, sort: filters.sort })}>Clear filters</Button>}
        >
          <p>{hasActiveFilters(filters) ? "Nothing in the registry fits these filters." : "Nothing to show."}</p>
        </StateCard>
      ) : (
        <div className="strategy-grid">
          {visible.map((strategy, index) => (
            <m.div
              key={strategy.vault}
              initial={reduceMotion ? false : { opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={IN_VIEW}
              transition={{
                duration: LIST_ITEM_SECONDS,
                ease: EASE_OUT,
                delay: Math.min(index, MAX_STAGGER_STEPS) * LIST_STAGGER_SECONDS,
              }}
            >
              <StrategyCard
                strategy={strategy}
                holdings={holdings[strategy.vault]}
                holdingsLoading={holdingsLoading}
              />
            </m.div>
          ))}
        </div>
      )}
    </div>
  );
}
