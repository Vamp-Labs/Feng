"use client";

import { useId, useState } from "react";
import { cn } from "@/lib/cn";
import type { Holding } from "@/lib/holding-tones";
import { navUsdOf, type StrategySummary } from "@/lib/hooks/use-marketplace";
import type { StrategyMetrics } from "@/lib/hooks/use-nav-history";

const VISIBLE_TAGS = 6;

export type SortKey = "nav" | "change24h" | "sinceInception" | "newest";

export const SORT_OPTIONS: readonly { key: SortKey; label: string }[] = [
  { key: "nav", label: "NAV" },
  { key: "change24h", label: "24 h change" },
  { key: "sinceInception", label: "Since inception" },
  { key: "newest", label: "Newest" },
];

export interface FilterState {
  sort: SortKey;
  following: boolean;
  nested: boolean;
  live: boolean;
  tickers: readonly string[];
  tags: readonly string[];
}

export const INITIAL_FILTERS: FilterState = {
  sort: "nav",
  following: false,
  nested: false,
  live: false,
  tickers: [],
  tags: [],
};

export function hasActiveFilters(filters: FilterState): boolean {
  return filters.following || filters.nested || filters.live || filters.tickers.length > 0 || filters.tags.length > 0;
}

function sortValue(strategy: StrategySummary, metrics: ReadonlyMap<string, StrategyMetrics>, key: SortKey): number | undefined {
  switch (key) {
    case "nav":
      return navUsdOf(strategy);
    case "change24h":
      return metrics.get(strategy.vault)?.change24h;
    case "sinceInception":
      return strategy.sinceInception;
    case "newest":
      return Number(strategy.createdAt);
  }
}

export function sortStrategies(
  strategies: readonly StrategySummary[],
  metrics: ReadonlyMap<string, StrategyMetrics>,
  key: SortKey,
): StrategySummary[] {
  return strategies.toSorted((a, b) => {
    const left = sortValue(a, metrics, key);
    const right = sortValue(b, metrics, key);
    if (left === undefined && right === undefined) return 0;
    if (left === undefined) return 1;
    if (right === undefined) return -1;
    return right - left;
  });
}

export function tickersOf(holdings: readonly Holding[] | undefined): string[] {
  return holdings ? holdings.filter((holding) => !holding.nested).map((holding) => holding.label) : [];
}

export function filterStrategies(
  strategies: readonly StrategySummary[],
  filters: FilterState,
  holdings: Readonly<Record<string, readonly Holding[] | undefined>>,
  isFollowing: (vault: string) => boolean,
): StrategySummary[] {
  return strategies.filter((strategy) => {
    if (filters.following && !isFollowing(strategy.vault)) return false;
    if (filters.nested && strategy.depth < 2) return false;
    if (filters.live && strategy.universe !== "live") return false;
    if (filters.tags.some((tag) => !strategy.tags?.includes(tag))) return false;
    if (filters.tickers.length > 0) {
      const held = tickersOf(holdings[strategy.vault]);
      if (filters.tickers.some((ticker) => !held.includes(ticker))) return false;
    }
    return true;
  });
}

function Chip({ pressed, onToggle, children }: { pressed: boolean; onToggle: () => void; children: React.ReactNode }) {
  return (
    <button type="button" className="filter-chip" aria-pressed={pressed} onClick={onToggle}>
      {children}
    </button>
  );
}

function toggleIn(list: readonly string[], value: string): string[] {
  return list.includes(value) ? list.filter((entry) => entry !== value) : [...list, value];
}

interface MarketplaceFiltersProps {
  filters: FilterState;
  onChange: (next: FilterState) => void;
  availableTickers: readonly string[];
  availableTags: readonly string[];
  hasLive: boolean;
  followingCount: number;
  shown: number;
  total: number;
  className?: string;
}

export function MarketplaceFilters({
  filters,
  onChange,
  availableTickers,
  availableTags,
  hasLive,
  followingCount,
  shown,
  total,
  className,
}: MarketplaceFiltersProps) {
  const sortId = useId();
  const active = hasActiveFilters(filters);
  const [showAllTags, setShowAllTags] = useState(false);
  const visibleTags = showAllTags
    ? availableTags
    : availableTags.filter((tag, index) => index < VISIBLE_TAGS || filters.tags.includes(tag));

  return (
    <section className={cn("market-filters", className)} aria-label="Sort and filter strategies">
      <div className="market-filters__row">
        <div className="market-filters__sort">
          <label className="text-overline text-ink-muted" htmlFor={sortId}>
            Sort by
          </label>
          <div className="select">
            <select
              id={sortId}
              className="input"
              data-size="sm"
              value={filters.sort}
              onChange={(event) => onChange({ ...filters, sort: event.target.value as SortKey })}
            >
              {SORT_OPTIONS.map((option) => (
                <option key={option.key} value={option.key}>
                  {option.label}
                </option>
              ))}
            </select>
          </div>
        </div>
        <p className="market-filters__count text-caption text-ink-muted" role="status">
          {active ? `Showing ${shown} of ${total}` : `${total} ${total === 1 ? "strategy" : "strategies"}`}
        </p>
      </div>
      <div className="market-filters__chips" role="group" aria-label="Filters">
        <Chip pressed={filters.following} onToggle={() => onChange({ ...filters, following: !filters.following })}>
          Following{followingCount > 0 ? ` (${followingCount})` : ""}
        </Chip>
        <Chip pressed={filters.nested} onToggle={() => onChange({ ...filters, nested: !filters.nested })}>
          Nested
        </Chip>
        {hasLive ? (
          <Chip pressed={filters.live} onToggle={() => onChange({ ...filters, live: !filters.live })}>
            Live assets
          </Chip>
        ) : null}
        {availableTickers.map((ticker) => (
          <Chip
            key={`ticker-${ticker}`}
            pressed={filters.tickers.includes(ticker)}
            onToggle={() => onChange({ ...filters, tickers: toggleIn(filters.tickers, ticker) })}
          >
            {ticker}
          </Chip>
        ))}
        {visibleTags.map((tag) => (
          <Chip key={`tag-${tag}`} pressed={filters.tags.includes(tag)} onToggle={() => onChange({ ...filters, tags: toggleIn(filters.tags, tag) })}>
            #{tag}
          </Chip>
        ))}
        {availableTags.length > VISIBLE_TAGS ? (
          <button type="button" className="text-button" aria-expanded={showAllTags} onClick={() => setShowAllTags((value) => !value)}>
            {showAllTags ? "Fewer tags" : `More tags (${availableTags.length - VISIBLE_TAGS})`}
          </button>
        ) : null}
        {active ? (
          <button type="button" className="text-button" data-underline onClick={() => onChange({ ...INITIAL_FILTERS, sort: filters.sort })}>
            Clear filters
          </button>
        ) : null}
      </div>
    </section>
  );
}
