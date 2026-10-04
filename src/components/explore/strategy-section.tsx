import type { ReactNode } from "react";
import { StrategyCard } from "@/components/strategy-card";
import { Skeleton } from "@/components/ui/skeleton";
import type { Holding } from "@/lib/holding-tones";
import type { StrategySummary } from "@/lib/hooks/use-marketplace";

const SKELETON_SLOTS = [0, 1, 2] as const;

export function StrategySection({
  title,
  lead,
  strategies,
  holdings,
  holdingsLoading,
  isLoading,
}: {
  title: string;
  lead?: ReactNode;
  strategies: readonly StrategySummary[];
  holdings: Readonly<Record<string, readonly Holding[] | undefined>>;
  holdingsLoading: boolean;
  isLoading: boolean;
}) {
  if (!isLoading && strategies.length === 0) return null;

  return (
    <section className="explore-section" aria-labelledby={`explore-${title}`}>
      <div className="explore-section__head">
        <h2 className="text-heading text-ink" id={`explore-${title}`}>
          {title}
        </h2>
        {lead ? <p className="text-caption text-ink-muted">{lead}</p> : null}
      </div>
      {isLoading ? (
        <div className="strategy-grid" role="status">
          <span className="sr-only">Loading {title}</span>
          {SKELETON_SLOTS.map((slot) => (
            <Skeleton key={slot} className="strategy-skeleton" />
          ))}
        </div>
      ) : (
        <div className="strategy-grid">
          {strategies.map((strategy) => (
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
  );
}
