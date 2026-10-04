"use client";

import { Skeleton } from "@/components/ui/skeleton";
import { shortenAddress, formatTokenAmount } from "@/lib/format";
import { explorerLink } from "@/lib/discovery-format";
import { useStrategyActivity, type ActivityEntry } from "@/lib/hooks/use-strategy-activity";

function describeEntry(entry: ActivityEntry, usdgSymbol: string, usdgDecimals: number | undefined, shareSymbol: string, shareDecimals: number): string {
  const who = entry.account ? shortenAddress(entry.account) : "Someone";
  if (entry.kind === "deposit") {
    const usdg = entry.usdgAmount !== undefined && usdgDecimals !== undefined ? formatTokenAmount(entry.usdgAmount, usdgDecimals, 2) : undefined;
    return usdg ? `${who} participated with ${usdg} ${usdgSymbol}` : `${who} participated`;
  }
  if (entry.kind === "redeem") {
    const shares = entry.shares !== undefined ? formatTokenAmount(entry.shares, shareDecimals, 4) : undefined;
    return shares ? `${who} redeemed ${shares} ${shareSymbol}` : `${who} redeemed shares`;
  }
  return "The strategy rebalanced to stay on target";
}

export function StrategyActivity({
  vault,
  usdgSymbol,
  usdgDecimals,
  shareSymbol,
  shareDecimals,
  explorerUrl,
}: {
  vault: `0x${string}` | undefined;
  usdgSymbol: string;
  usdgDecimals: number | undefined;
  shareSymbol: string;
  shareDecimals: number;
  explorerUrl: string;
}) {
  const activity = useStrategyActivity(vault);

  if (activity.isLoading) {
    return (
      <div className="flex flex-col gap-2" role="status">
        <span className="sr-only">Loading activity</span>
        <Skeleton className="h-10" />
        <Skeleton className="h-10" />
        <Skeleton className="h-10" />
      </div>
    );
  }

  if (activity.entries.length === 0) {
    return <p className="text-caption text-ink-muted">No on-chain activity yet.</p>;
  }

  return (
    <ul className="activity-feed">
      {activity.entries.map((entry) => {
        const link = explorerLink(explorerUrl, "tx", entry.hash);
        return (
          <li key={entry.hash} className="activity-feed__item" data-kind={entry.kind}>
            <span className="activity-feed__dot" aria-hidden="true" />
            <span className="activity-feed__body">
              <span className="text-caption text-ink">{describeEntry(entry, usdgSymbol, usdgDecimals, shareSymbol, shareDecimals)}</span>
              <span className="activity-feed__meta text-micro text-ink-muted">
                Block {entry.blockNumber.toString()}
                {link ? (
                  <>
                    {" "}
                    <a href={link} target="_blank" rel="noreferrer">
                      View transaction
                    </a>
                  </>
                ) : null}
              </span>
            </span>
          </li>
        );
      })}
    </ul>
  );
}
