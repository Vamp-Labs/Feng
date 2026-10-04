"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Notice } from "@/components/ui/notice";
import { StatChip } from "@/components/ui/stat-chip";
import { DepositRedeemPanel } from "@/components/deposit-redeem-panel";
import { FollowButton } from "@/components/follow-button";
import { NestedComposition } from "@/components/nested-composition";
import { ParticipatePanel } from "@/components/participate-panel";
import { PriceFeedStatus } from "@/components/price-feed-status";
import { RealVsSimulated } from "@/components/real-vs-simulated";
import { RebalanceButton } from "@/components/rebalance-button";
import { RebalanceMoment } from "@/components/rebalance-moment";
import { RebalanceSchedule } from "@/components/rebalance-schedule";
import { Sparkline } from "@/components/sparkline";
import { StrategyActivity } from "@/components/strategy-activity";
import { StrategyDetailBanner } from "@/components/strategy-detail-banner";
import { StrategyHoldings } from "@/components/strategy-holdings";
import { StrategyTags } from "@/components/strategy-tags";
import { WeightsBar } from "@/components/weights-bar";
import { useActiveNetwork } from "@/lib/addresses-context";
import { categoryLabel, categorySlugOf } from "@/lib/discovery/categories";
import { formatSharePrice, usdgToNumber } from "@/lib/discovery-format";
import { formatUsdg, shortenAddress } from "@/lib/format";
import { nestedHolding, stockHolding, type Holding } from "@/lib/holding-tones";
import { markRebalanceSeen } from "@/lib/watchlist";
import { useFollowerCount } from "@/lib/hooks/use-follower-count";
import { useNavHistory } from "@/lib/hooks/use-nav-history";
import { useProfile } from "@/lib/hooks/use-profile";
import { useRebalanceEvents, type RebalanceEvent } from "@/lib/hooks/use-rebalance-events";
import type { StrategyDetailData, StrategyDetailV2Fields } from "@/lib/hooks/use-strategy-detail";

const GHOST_SECONDS = 9;

interface WeightSnapshot {
  constituents: (number | undefined)[];
  idle: number | undefined;
}

function holdingsOf(detail: StrategyDetailData): Holding[] {
  return detail.constituents.map((constituent) =>
    constituent.isStrategyToken
      ? nestedHolding(constituent.symbol ?? shortenAddress(constituent.token), constituent.targetWeightBps)
      : stockHolding(constituent.symbol ?? shortenAddress(constituent.token), constituent.targetWeightBps),
  );
}

export function StrategyDetailV2({
  vault,
  detail,
  v2,
  token,
}: {
  vault: `0x${string}`;
  detail: StrategyDetailData;
  v2: StrategyDetailV2Fields;
  token: `0x${string}`;
}) {
  const { addresses } = useActiveNetwork();
  const explorerUrl = addresses.explorerUrl;
  const history = useNavHistory(vault, v2.sharePrice);
  const depth = detail.depth ?? 1;
  const label = detail.symbol ?? shortenAddress(vault);
  const followerCount = useFollowerCount(vault);
  const creatorProfile = useProfile(detail.creator);
  const category = categorySlugOf({ tags: v2.tags });

  const [toast, setToast] = useState<RebalanceEvent | null>(null);
  const [ghost, setGhost] = useState<WeightSnapshot | null>(null);
  const snapshot = useRef<WeightSnapshot>({ constituents: [], idle: undefined });
  const refetchDetail = useRef(detail.refetch);
  const refetchHistory = useRef(history.refetch);

  useEffect(() => {
    snapshot.current = { constituents: detail.constituents.map((constituent) => constituent.currentBps), idle: v2.idleBps };
    refetchDetail.current = detail.refetch;
    refetchHistory.current = history.refetch;
  });

  const handleRebalanced = useCallback((event: RebalanceEvent) => {
    markRebalanceSeen();
    setGhost({ constituents: [...snapshot.current.constituents], idle: snapshot.current.idle });
    setToast(event);
    refetchDetail.current();
    refetchHistory.current();
  }, []);

  useRebalanceEvents(vault, handleRebalanced);

  useEffect(() => {
    if (!ghost) return;
    const timer = window.setTimeout(() => setGhost(null), GHOST_SECONDS * 1000);
    return () => window.clearTimeout(timer);
  }, [ghost]);

  const dismissToast = useCallback(() => setToast(null), []);

  const navPerShare =
    v2.sharePrice !== undefined && v2.usdgDecimals !== undefined ? usdgToNumber(v2.sharePrice, v2.usdgDecimals) : undefined;
  const lastLog = history.rebalances[history.rebalances.length - 1];
  const createdDate = detail.createdAt && detail.createdAt > 0n ? new Date(Number(detail.createdAt) * 1000) : undefined;

  return (
    <>
      <div className="grid grid-cols-1 gap-8 lg:grid-cols-[1fr_24rem]">
        <div className="flex min-w-0 flex-col gap-8">
          <Card variant="glass" className="flex flex-col gap-6">
            <StrategyDetailBanner vault={vault} symbol={detail.symbol} depth={depth} />
            <div className="flex items-start justify-between gap-4">
              <div className="min-w-0">
                <span className="text-overline text-ink-muted">{detail.symbol}</span>
                <h1 className="mt-2 text-heading text-ink">{detail.name}</h1>
                <p className="mt-2 text-caption text-ink-muted">
                  Created by{" "}
                  {detail.creator ? (
                    <Link href={`/creator/${detail.creator}`} className="detail-creator-link">
                      {creatorProfile.handle ? `@${creatorProfile.handle}` : shortenAddress(detail.creator)}
                    </Link>
                  ) : (
                    "--"
                  )}
                </p>
              </div>
              <div className="flex flex-none flex-wrap items-center gap-3">
                {category ? <Badge tone="violet">{categoryLabel(category)}</Badge> : null}
                <FollowButton target={vault} label={label} />
                <a href="#participate" className="button" data-variant="primary" data-size="md">
                  Participate
                </a>
              </div>
            </div>
            <StrategyTags tags={v2.tags} universe={v2.universe} />
            {v2.universe === "live" ? (
              <Notice tone="warn">
                Live assets: these are the real Robinhood faucet stock tokens and Paxos USDG. Their issuers can pause, freeze or
                upgrade them, and the vault cannot override that. If they do, deposits and redeems can stop until the issuer
                acts.
              </Notice>
            ) : null}
            {v2.paused ? <Notice tone="error">Deposits and rebalances are paused. You can still redeem.</Notice> : null}
            <div className="flex flex-wrap gap-3">
              <StatChip
                label="Followers"
                value={followerCount.count ?? (followerCount.isAvailable ? "0" : "--")}
                tone="accent"
              />
              <StatChip
                label="NAV"
                value={
                  detail.totalAssetsUSDG !== undefined && v2.usdgDecimals !== undefined
                    ? `$${formatUsdg(detail.totalAssetsUSDG, v2.usdgDecimals)}`
                    : "--"
                }
              />
              <StatChip label="Created" value={createdDate ? createdDate.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" }) : "--"} />
            </div>
          </Card>

          <Card>
            <h2 className="mb-4 text-title text-ink">Thesis</h2>
            <p className="text-body text-ink-secondary detail-description">
              {v2.description && v2.description.length > 0 ? v2.description : "This creator has not written a thesis yet."}
            </p>
          </Card>

          <Card>
            <h2 className="mb-5 text-title text-ink">Allocation</h2>
            <StrategyHoldings holdings={holdingsOf(detail)} size="stage" loading={detail.isLoading} />
          </Card>

          <Card>
            <h2 className="mb-5 text-title text-ink">Strategy information</h2>
            <dl className="info-grid">
              <div>
                <dt className="text-caption text-ink-muted">Creator</dt>
                <dd className="text-label text-ink">
                  {detail.creator ? (
                    <Link href={`/creator/${detail.creator}`}>
                      {creatorProfile.handle ? `@${creatorProfile.handle}` : shortenAddress(detail.creator)}
                    </Link>
                  ) : (
                    "--"
                  )}
                </dd>
              </div>
              <div>
                <dt className="text-caption text-ink-muted">Category</dt>
                <dd className="text-label text-ink">{category ? categoryLabel(category) : "Uncategorized"}</dd>
              </div>
              <div>
                <dt className="text-caption text-ink-muted">Created</dt>
                <dd className="text-label text-ink">
                  {createdDate ? createdDate.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" }) : "--"}
                </dd>
              </div>
              <div>
                <dt className="text-caption text-ink-muted">Followers</dt>
                <dd className="text-label text-ink">{followerCount.count ?? (followerCount.isAvailable ? 0 : "--")}</dd>
              </div>
              <div className="info-grid__wide">
                <dt className="text-caption text-ink-muted">Description</dt>
                <dd className="text-label text-ink">{v2.description && v2.description.length > 0 ? v2.description : "--"}</dd>
              </div>
            </dl>
            <RealVsSimulated />
          </Card>

          <Card>
            <h2 className="mb-5 text-title text-ink">Activity</h2>
            <StrategyActivity
              vault={vault}
              usdgSymbol="USDG"
              usdgDecimals={v2.usdgDecimals}
              shareSymbol={detail.symbol ?? "shares"}
              shareDecimals={detail.decimals ?? 18}
              explorerUrl={explorerUrl}
            />
          </Card>

          <details className="advanced-disclosure">
            <summary className="advanced-disclosure__summary">
              <span className="text-label text-ink">Advanced: rebalancing, composability &amp; full swap</span>
            </summary>
            <div className="advanced-disclosure__body">
              <Card>
                <div className="mb-4 flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                  <h3 className="text-title text-ink">NAV per share</h3>
                  <span className="text-stat text-ink" data-testid="nav-per-share">
                    {navPerShare === undefined ? "--" : formatSharePrice(navPerShare)}
                  </span>
                </div>
                <Sparkline
                  className="spark--fluid"
                  points={history.series}
                  width={640}
                  height={128}
                  label={`NAV per share history for ${label}`}
                  loading={history.isLoading}
                />
              </Card>

              <Card>
                <h3 className="mb-5 text-title text-ink">Live weights vs target</h3>
                <WeightsBar
                  constituents={detail.constituents}
                  idleBps={v2.idleBps}
                  ghostBps={ghost?.constituents}
                  ghostIdleBps={ghost?.idle}
                />
                <div className="mt-5">
                  <PriceFeedStatus fresh={v2.priceFresh} oldestUpdatedAt={v2.oldestPriceUpdatedAt} />
                </div>
              </Card>

              {depth >= 2 ? (
                <Card>
                  <h3 className="mb-5 text-title text-ink">Nested composition</h3>
                  <NestedComposition constituents={detail.constituents} usdgDecimals={v2.usdgDecimals} />
                </Card>
              ) : null}

              <Card className="flex flex-col gap-6">
                <h3 className="text-title text-ink">Rebalancing</h3>
                <RebalanceSchedule
                  intervalSeconds={v2.rebalanceInterval}
                  lastTimestamp={v2.lastRebalanceTimestamp}
                  needed={detail.rebalanceNeeded}
                  paused={v2.paused}
                  lastLog={lastLog}
                  explorerUrl={explorerUrl}
                />
                <RebalanceButton vault={vault} rebalanceNeeded={detail.rebalanceNeeded} onRebalanced={detail.refetch} />
              </Card>

              <DepositRedeemPanel
                vault={vault}
                token={token}
                tokenDecimals={detail.decimals ?? 18}
                tokenSymbol={detail.symbol ?? "TOKEN"}
              />
            </div>
          </details>
        </div>

        <div className="lg:sticky lg:top-28 lg:self-start">
          <ParticipatePanel
            vault={vault}
            token={token}
            tokenDecimals={detail.decimals ?? 18}
            tokenSymbol={detail.symbol ?? "TOKEN"}
            strategyName={detail.name ?? label}
          />
        </div>
      </div>
      <RebalanceMoment event={toast} explorerUrl={explorerUrl} usdgDecimals={v2.usdgDecimals} onDismiss={dismissToast} />
    </>
  );
}
