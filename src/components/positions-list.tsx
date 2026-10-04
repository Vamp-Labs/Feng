"use client";

import { useMemo, useState } from "react";
import type { Address } from "viem";
import { useAccount } from "wagmi";
import { StrategyLogo } from "@/components/art/strategy-logo";
import { Badge } from "@/components/ui/badge";
import { ButtonLink } from "@/components/ui/button";
import { ErrorCard } from "@/components/ui/error-card";
import { RetryHint } from "@/components/ui/retry-hint";
import { Card, CardLink } from "@/components/ui/card";
import { LayersIcon } from "@/components/ui/icons";
import { RankBar } from "@/components/ui/rank-bar";
import { Skeleton } from "@/components/ui/skeleton";
import { StateCard } from "@/components/ui/state-card";
import { StatChip } from "@/components/ui/stat-chip";
import { TestFundsPrompt } from "@/components/test-funds";
import { StrategyHoldings } from "@/components/strategy-holdings";
import { usePortfolioStats } from "@/lib/hooks/use-portfolio-stats";
import { useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import { usePositions } from "@/lib/hooks/use-positions";
import { useStrategyHoldings } from "@/lib/hooks/use-strategy-holdings";
import { useFollowedTargets } from "@/lib/hooks/use-social-registry";
import { useFollowerCount } from "@/lib/hooks/use-follower-count";
import { useProfile } from "@/lib/hooks/use-profile";
import { ReturnFigure } from "@/components/return-figure";
import { formatTokenAmount, formatUsdg, shortenAddress } from "@/lib/format";
import { useV2PositionPnl } from "@/lib/hooks/use-v2-position-pnl";
import { IS_V2 } from "@/lib/protocol";
import type { PositionPnl } from "@/lib/protocol/history";
import styles from "./positions-list.module.css";

const TOTAL_SCALE_DECIMALS = 18;

function totalValueLabel(positions: ReturnType<typeof usePositions>["positions"]): string | undefined {
  let total = 0n;
  for (const position of positions) {
    if (position.valueUsdg === undefined || position.usdgDecimals === undefined) return undefined;
    total += position.valueUsdg * 10n ** BigInt(TOTAL_SCALE_DECIMALS - position.usdgDecimals);
  }
  return `$${formatUsdg(total, TOTAL_SCALE_DECIMALS)}`;
}

function formatPnlAmount(pnl: PositionPnl, decimals: number): string {
  const sign = pnl.pnl > 0n ? "+" : pnl.pnl < 0n ? "-" : "";
  const magnitude = pnl.pnl < 0n ? -pnl.pnl : pnl.pnl;
  return `${sign}$${formatUsdg(magnitude, decimals)}`;
}

function PortfolioRank({ totalValue }: { totalValue?: string }) {
  const stats = usePortfolioStats();
  const percent = stats.total === 0 ? 0 : (stats.held / stats.total) * 100;

  return (
    <Card variant="glass" tone="violet" className="flex flex-col gap-5">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="flex flex-col gap-1">
          <span className="text-overline text-ink-muted">Strategies held</span>
          <span className="text-hud text-ink">
            {stats.held} <span className="text-ink-muted">/ {stats.total}</span>
          </span>
        </div>
        <div className="flex flex-wrap gap-3">
          {totalValue ? <StatChip label="Your value" value={totalValue} tone="accent" /> : null}
          <StatChip label="TVL" value={stats.tvl} tone={totalValue ? "default" : "accent"} />
          <StatChip label="Nested" value={stats.nested} />
        </div>
      </div>
      <RankBar percent={percent} />
      <p className="text-caption text-ink-muted">
        {stats.held === 1 ? "1 strategy" : `${stats.held} strategies`} out of {stats.total} listed on this network.
      </p>
    </Card>
  );
}

function StrategiesTab() {
  const { positions, isLoading, isConnected, error, isRetrying, refetch } = usePositions();
  const { strategies } = useMarketplaceStrategies();
  const pnl = useV2PositionPnl(positions);
  const { holdings, isLoading: holdingsLoading } = useStrategyHoldings();

  if (!isConnected) {
    return (
      <StateCard art="wallet" title="Connect a wallet">
        <p>Connect to see which strategies you&apos;ve participated in.</p>
      </StateCard>
    );
  }

  if (error) {
    return (
      <ErrorCard
        title="Portfolio unavailable"
        summary="Could not read your balances from the active network."
        error={error}
        onRetry={refetch}
      />
    );
  }

  if (isLoading) {
    return (
      <div className="flex flex-col gap-6">
        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2" role="status">
          <span className="sr-only">Loading strategies</span>
          {[0, 1].map((i) => (
            <Skeleton key={i} className="h-28" />
          ))}
        </div>
        <RetryHint active={isRetrying} />
      </div>
    );
  }

  if (positions.length === 0) {
    return (
      <StateCard
        art="empty"
        title="You haven't participated in any strategies yet"
        actions={<ButtonLink href="/">Explore strategies</ButtonLink>}
      >
        <p>Participate in a strategy to see it appear here.</p>
        <TestFundsPrompt />
      </StateCard>
    );
  }

  const depthOf = new Map(strategies.map((strategy) => [strategy.vault, strategy.depth || 1]));

  return (
    <div className="flex flex-col gap-10">
      <PortfolioRank totalValue={IS_V2 ? totalValueLabel(positions) : undefined} />
      <div className="grid grid-cols-1 gap-x-6 gap-y-12 pt-4 sm:grid-cols-2">
        {positions.map((position) => {
          const depth = depthOf.get(position.vault) ?? 1;
          const positionPnl = pnl.byVault[position.vault];
          return (
            <CardLink
              key={position.vault}
              href={`/strategy/${position.vault}`}
              className={`position-card flex flex-wrap items-center justify-between gap-4 ${styles.card}`}
            >
              <StrategyLogo
                className="position-card__logo"
                seed={position.vault}
                symbol={position.symbol}
                depth={depth}
                size="3.75rem"
              />
              <div className="min-w-0 flex-1 pl-[4.75rem]">
                <p className="text-title truncate text-ink">{position.symbol ?? "Strategy"}</p>
                <p className="text-caption truncate text-ink-muted">{position.name}</p>
                <span className="mt-2 flex flex-wrap gap-2">
                  {depth >= 2 ? (
                    <Badge tone="orchid">
                      <LayersIcon className="size-3.5" />
                      Nested
                    </Badge>
                  ) : null}
                  {IS_V2 && position.universe === "live" ? <Badge tone="amber">Live assets</Badge> : null}
                </span>
                <div className="mt-3 max-w-xs">
                  <StrategyHoldings holdings={holdings[position.vault]} size="tile" loading={holdingsLoading} />
                </div>
              </div>
              <div className={styles.stats}>
                <StatChip
                  label="Amount"
                  value={formatTokenAmount(position.balance, position.decimals)}
                  tone="accent"
                />
                {IS_V2 ? (
                  <>
                    <StatChip
                      label="Value"
                      value={
                        position.valueUsdg !== undefined && position.usdgDecimals !== undefined
                          ? `$${formatUsdg(position.valueUsdg, position.usdgDecimals)}`
                          : "—"
                      }
                    />
                    <StatChip
                      label="P/L"
                      value={
                        positionPnl && position.usdgDecimals !== undefined ? (
                          <span className={styles.pnl}>
                            <ReturnFigure value={positionPnl.pnlRatio} />
                            <span className={styles.pnlAmount}>{formatPnlAmount(positionPnl, position.usdgDecimals)}</span>
                          </span>
                        ) : pnl.isLoading ? (
                          "…"
                        ) : (
                          "—"
                        )
                      }
                    />
                  </>
                ) : null}
              </div>
            </CardLink>
          );
        })}
      </div>
    </div>
  );
}

function FollowedStrategyRow({ vault, symbol, name, depth }: { vault: Address; symbol?: string; name?: string; depth: number }) {
  return (
    <CardLink href={`/strategy/${vault}`} className="flex items-center gap-4">
      <StrategyLogo seed={vault} symbol={symbol} depth={depth} size="3rem" />
      <div className="min-w-0 flex-1">
        <p className="text-title truncate text-ink">{symbol ?? "Strategy"}</p>
        <p className="text-caption truncate text-ink-muted">{name}</p>
      </div>
      <Badge tone="neutral">Strategy</Badge>
    </CardLink>
  );
}

function FollowedCreatorRow({ creator }: { creator: Address }) {
  const profile = useProfile(creator);
  const followerCount = useFollowerCount(creator);
  const displayName = profile.handle ? `@${profile.handle}` : shortenAddress(creator, 6);

  return (
    <CardLink href={`/creator/${creator}`} className="flex items-center gap-4">
      <StrategyLogo seed={creator} symbol={profile.handle ?? creator} depth={1} size="3rem" />
      <div className="min-w-0 flex-1">
        <p className="text-title truncate text-ink">{displayName}</p>
        <p className="text-caption truncate text-ink-muted">
          {followerCount.count !== undefined ? `${followerCount.count.toLocaleString("en-US")} followers` : "Creator"}
        </p>
      </div>
      <Badge tone="violet">Creator</Badge>
    </CardLink>
  );
}

function FollowingTab({ account }: { account: Address }) {
  const { targets, isLoading, available, error, refetch } = useFollowedTargets(account);
  const { strategies } = useMarketplaceStrategies();

  const vaultsByAddress = useMemo(() => new Map(strategies.map((strategy) => [strategy.vault.toLowerCase(), strategy])), [strategies]);

  if (!available) {
    return (
      <StateCard art="empty" title="Following isn't live on this network yet">
        <p>The social registry hasn&apos;t been deployed here. Check back once it is to follow strategies and creators.</p>
      </StateCard>
    );
  }

  if (error) {
    return <ErrorCard title="Following unavailable" summary="Could not read your follows from the active network." error={error} onRetry={refetch} />;
  }

  if (isLoading) {
    return (
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2" role="status">
        <span className="sr-only">Loading follows</span>
        {[0, 1].map((i) => (
          <Skeleton key={i} className="h-20" />
        ))}
      </div>
    );
  }

  if (targets.length === 0) {
    return (
      <StateCard art="empty" title="You're not following anything yet" actions={<ButtonLink href="/">Explore strategies</ButtonLink>}>
        <p>Follow a strategy or a creator from Explore to see it here.</p>
      </StateCard>
    );
  }

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      {targets.map((target) => {
        const strategy = vaultsByAddress.get(target.toLowerCase());
        return strategy ? (
          <FollowedStrategyRow key={target} vault={strategy.vault} symbol={strategy.symbol} name={strategy.name} depth={strategy.depth || 1} />
        ) : (
          <FollowedCreatorRow key={target} creator={target} />
        );
      })}
    </div>
  );
}

export function PositionsList() {
  const { address, isConnected } = useAccount();
  const [tab, setTab] = useState<"strategies" | "following">("strategies");

  if (!isConnected || !address) {
    return (
      <StateCard art="wallet" title="Connect a wallet">
        <p>Connect to see the strategies you&apos;ve participated in or followed.</p>
      </StateCard>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <div className={styles.tabs} role="tablist" aria-label="Portfolio views">
        <button type="button" role="tab" aria-selected={tab === "strategies"} className={styles.tab} onClick={() => setTab("strategies")}>
          Strategies
        </button>
        <button type="button" role="tab" aria-selected={tab === "following"} className={styles.tab} onClick={() => setTab("following")}>
          Following
        </button>
      </div>
      {tab === "strategies" ? <StrategiesTab /> : <FollowingTab account={address} />}
    </div>
  );
}
