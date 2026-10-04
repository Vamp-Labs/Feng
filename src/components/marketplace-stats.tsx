"use client";

import { useMemo } from "react";
import { formatUsdCompact } from "@/lib/discovery-format";
import { sumNavUsd, useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";

export function MarketplaceStats() {
  const { strategies, isLoading, error } = useMarketplaceStrategies();
  const unavailable = isLoading || Boolean(error);

  const stats = useMemo(() => {
    const tvl = sumNavUsd(strategies);
    return [
      { label: "Strategies", value: unavailable ? "—" : String(strategies.length) },
      { label: "TVL", value: tvl !== undefined && !unavailable ? formatUsdCompact(tvl) : "—" },
      { label: "Nested", value: unavailable ? "—" : String(strategies.filter((strategy) => strategy.depth >= 2).length) },
    ];
  }, [strategies, unavailable]);

  return (
    <dl className="market-stats">
      {stats.map((stat) => (
        <div key={stat.label}>
          <dd className="text-hud text-ink">{stat.value}</dd>
          <dt className="text-overline text-ink-muted">{stat.label}</dt>
        </div>
      ))}
    </dl>
  );
}
