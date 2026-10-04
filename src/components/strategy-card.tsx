import { StrategyLogo, toneFor } from "@/components/art/strategy-logo";
import { StrategyHoldings } from "@/components/strategy-holdings";
import { StrategyTags } from "@/components/strategy-tags";
import { ArrowIcon } from "@/components/ui/icons";
import { CardLink } from "@/components/ui/card";
import { formatUsdCompact } from "@/lib/discovery-format";
import { describeHoldings, type Holding } from "@/lib/holding-tones";
import { navUsdOf, type StrategySummary } from "@/lib/hooks/use-marketplace";
import { useFollowerCount } from "@/lib/hooks/use-follower-count";
import { IS_V2 } from "@/lib/protocol";

type StrategyCardProps = {
  strategy: StrategySummary;
  holdings?: readonly Holding[];
  holdingsLoading?: boolean;
};

export function StrategyCard({ strategy, holdings, holdingsLoading = false }: StrategyCardProps) {
  const depth = strategy.depth || 1;
  const navUsd = navUsdOf(strategy);
  const followerCount = useFollowerCount(strategy.vault);
  const thesis = strategy.description;
  const summary = [strategy.symbol, strategy.name].filter(Boolean).join(", ");
  const held = holdings?.length ? `${summary}, holds ${describeHoldings(holdings)}` : summary;
  const label = thesis ? `${held}. ${thesis}` : held;

  return (
    <CardLink
      href={`/strategy/${strategy.vault}`}
      className="strategy-card h-full"
      data-art={toneFor(strategy.vault)}
      aria-label={label || undefined}
    >
      <StrategyLogo
        className="strategy-card__logo"
        seed={strategy.vault}
        symbol={strategy.symbol}
        depth={depth}
        size="4.25rem"
      />
      <div className="strategy-card__body">
        <div className="strategy-card__head">
          <div className="flex min-w-0 flex-col gap-1">
            <span className="text-title truncate text-ink">{strategy.symbol ?? "…"}</span>
            <span className="text-caption truncate text-ink-muted" title={strategy.name}>{strategy.name}</span>
          </div>
          <div className="strategy-card__nav">
            <span className="strategy-card__nav-value">
              {navUsd !== undefined ? formatUsdCompact(navUsd) : "—"}
            </span>
            <span className="strategy-card__nav-meta">
              <span className="text-overline text-ink-muted">NAV</span>
            </span>
          </div>
        </div>
        {thesis ? <p className="strategy-card__thesis text-caption text-ink-secondary">{thesis}</p> : null}
        <StrategyHoldings holdings={holdings} size="tile" loading={holdingsLoading} />
        {IS_V2 ? <StrategyTags tags={strategy.tags} universe={strategy.universe} className="strategy-card__tags" /> : null}
        <div className="strategy-card__footer">
          <span className="strategy-card__followers text-caption text-ink-muted">
            {followerCount.count ?? (followerCount.isAvailable ? 0 : "—")}{" "}
            {(followerCount.count ?? 0) === 1 ? "follower" : "followers"}
          </span>
          <span className="strategy-card__cta text-label">
            View Strategy
            <ArrowIcon direction="right" className="strategy-card__cta-icon" />
          </span>
        </div>
      </div>
    </CardLink>
  );
}
