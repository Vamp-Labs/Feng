"use client";

import { StrategyDetailBanner } from "@/components/strategy-detail-banner";
import { StrategyDetailV2 } from "@/components/strategy-detail-v2";
import { Badge } from "@/components/ui/badge";
import { ReturnFigure } from "@/components/return-figure";
import { StatChip } from "@/components/ui/stat-chip";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ButtonLink } from "@/components/ui/button";
import { StateCard } from "@/components/ui/state-card";
import { ErrorCard } from "@/components/ui/error-card";
import { RetryHint } from "@/components/ui/retry-hint";
import { ConstituentList } from "@/components/constituent-list";
import { DepositRedeemPanel } from "@/components/deposit-redeem-panel";
import { FollowButton } from "@/components/follow-button";
import { RebalanceButton } from "@/components/rebalance-button";
import { useFollowerCount } from "@/lib/hooks/use-follower-count";
import { useStrategyDetail } from "@/lib/hooks/use-strategy-detail";
import { isRevertError } from "@/lib/errors";
import { IS_V2 } from "@/lib/protocol";
import { formatUsdg, shortenAddress } from "@/lib/format";

export function StrategyDetail({ vault }: { vault: `0x${string}` }) {
  const detail = useStrategyDetail(vault);
  const followerCount = useFollowerCount(vault);

  if (detail.error && isRevertError(detail.error)) {
    return (
      <div className="mx-auto max-w-2xl">
        <StateCard
          art="empty"
          title="Not a registered strategy"
          actions={<ButtonLink href="/marketplace">Back to marketplace</ButtonLink>}
        >
          <p>This address is not listed in the marketplace registry on the active network.</p>
        </StateCard>
      </div>
    );
  }

  if (detail.error) {
    return (
      <div className="mx-auto max-w-2xl">
        <ErrorCard
          title="Strategy unavailable"
          summary="Could not load this strategy from the active network."
          error={detail.error}
          onRetry={detail.refetch}
        />
      </div>
    );
  }

  if (detail.isLoading || !detail.token) {
    return (
      <div className={IS_V2 ? "flex flex-col gap-6 detail-loading" : "flex flex-col gap-6"}>
        <div className="grid grid-cols-1 gap-8 lg:grid-cols-[1fr_24rem]" role="status">
          <span className="sr-only">Loading strategy</span>
          <Skeleton className="h-96" />
          <Skeleton className="h-72" />
        </div>
        <RetryHint active={detail.isRetrying} />
      </div>
    );
  }

  if (detail.v2) {
    return <StrategyDetailV2 vault={vault} detail={detail} v2={detail.v2} token={detail.token} />;
  }

  const depth = detail.depth ?? 1;

  return (
    <div className="grid grid-cols-1 gap-8 lg:grid-cols-[1fr_24rem]">
      <div className="flex flex-col gap-8">
        <Card variant="glass" className="flex flex-col gap-6">
          <StrategyDetailBanner vault={vault} symbol={detail.symbol} depth={depth} />
          <div className="flex items-start justify-between gap-4">
            <div className="min-w-0">
              <span className="text-overline text-ink-muted">{detail.symbol}</span>
              <h1 className="mt-2 text-heading text-ink">{detail.name}</h1>
              <p className="mt-2 text-caption text-ink-muted">
                Created by {detail.creator ? shortenAddress(detail.creator) : "—"}
              </p>
            </div>
            <div className="flex flex-none items-center gap-3">
              <Badge tone={depth >= 2 ? "orchid" : "violet"}>Depth {depth}</Badge>
              <FollowButton target={vault} label={detail.symbol ?? shortenAddress(vault)} />
            </div>
          </div>

          <div className="flex flex-wrap gap-3">
            <StatChip
              label="Followers"
              value={followerCount.count ?? (followerCount.isAvailable ? "0" : "--")}
              tone="accent"
            />
            <StatChip
              label="NAV"
              value={
                detail.totalAssetsUSDG !== undefined && detail.usdgDecimals !== undefined
                  ? `$${formatUsdg(detail.totalAssetsUSDG, detail.usdgDecimals)}`
                  : "—"
              }
            />
            <StatChip label="Since inception" value={<ReturnFigure value={detail.sinceInception} />} />
            <StatChip label="Constituents" value={detail.constituents.length} />
          </div>
        </Card>

        <Card>
          <h2 className="mb-5 text-title text-ink">Constituents &amp; weights</h2>
          <ConstituentList constituents={detail.constituents} />
        </Card>

        <Card>
          <RebalanceButton
            vault={vault}
            rebalanceNeeded={detail.rebalanceNeeded}
            onRebalanced={detail.refetch}
          />
        </Card>
      </div>

      <div className="lg:sticky lg:top-28 lg:self-start">
        <DepositRedeemPanel
          vault={vault}
          token={detail.token}
          tokenDecimals={detail.decimals ?? 18}
          tokenSymbol={detail.symbol ?? "TOKEN"}
        />
      </div>
    </div>
  );
}
