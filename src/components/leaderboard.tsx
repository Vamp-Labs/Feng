"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { ReturnFigure } from "@/components/return-figure";
import { ErrorCard } from "@/components/ui/error-card";
import { Skeleton } from "@/components/ui/skeleton";
import { StateCard } from "@/components/ui/state-card";
import { ButtonLink } from "@/components/ui/button";
import { formatUsdCompact } from "@/lib/discovery-format";
import { shortenAddress } from "@/lib/format";
import { useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import { useNowSeconds } from "@/lib/hooks/use-now";
import {
  buildCreatorRows,
  SCORE_AGE_CAP_DAYS,
  SCORE_RETURN_CAP,
  SCORE_RETURN_FLOOR,
  SCORE_WEIGHTS,
  type CreatorRow,
} from "@/lib/hooks/use-v2-discovery-creators";

type Ranking = "aum" | "return" | "score";

const RANKINGS: readonly { key: Ranking; label: string }[] = [
  { key: "aum", label: "By AUM" },
  { key: "return", label: "By best return" },
  { key: "score", label: "By score" },
];

function ranked(rows: readonly CreatorRow[], ranking: Ranking): CreatorRow[] {
  return rows.toSorted((a, b) => {
    if (ranking === "aum") return b.aumUsd - a.aumUsd;
    if (ranking === "score") return b.score - a.score;
    const left = a.bestReturn ?? Number.NEGATIVE_INFINITY;
    const right = b.bestReturn ?? Number.NEGATIVE_INFINITY;
    return right - left;
  });
}

export function Leaderboard() {
  const { strategies, isLoading, isEmpty, error, refetch } = useMarketplaceStrategies();
  const now = useNowSeconds(60_000);
  const [ranking, setRanking] = useState<Ranking>("aum");

  const rows = useMemo(() => ranked(buildCreatorRows(strategies, now), ranking), [strategies, now, ranking]);

  if (error) {
    return <ErrorCard title="Leaderboard unavailable" summary="Could not read the registry from the active network." error={error} onRetry={refetch} />;
  }

  if (isLoading) {
    return (
      <div role="status" className="leaderboard-loading">
        <span className="sr-only">Loading creators</span>
        <Skeleton className="h-96" />
      </div>
    );
  }

  if (isEmpty) {
    return (
      <StateCard art="empty" title="No creators yet" actions={<ButtonLink href="/create">Create a strategy</ButtonLink>}>
        <p>Strategies appear here once they are registered.</p>
      </StateCard>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="market-filters__chips" role="group" aria-label="Ranking">
        {RANKINGS.map((option) => (
          <button
            key={option.key}
            type="button"
            className="filter-chip"
            aria-pressed={ranking === option.key}
            onClick={() => setRanking(option.key)}
          >
            {option.label}
          </button>
        ))}
      </div>
      <div className="leaderboard-scroll" role="region" aria-label="Creators table" tabIndex={0}>
        <table className="leaderboard">
          <caption className="sr-only">Strategy creators ranked {RANKINGS.find((option) => option.key === ranking)?.label.toLowerCase()}</caption>
          <thead>
            <tr>
              <th scope="col">#</th>
              <th scope="col">Creator</th>
              <th scope="col">Strategies</th>
              <th scope="col">AUM</th>
              <th scope="col">Best return</th>
              <th scope="col">Score</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row, index) => (
              <tr key={row.creator}>
                <td>{index + 1}</td>
                <th scope="row">{shortenAddress(row.creator)}</th>
                <td>{row.strategies}</td>
                <td>{formatUsdCompact(row.aumUsd)}</td>
                <td>
                  <ReturnFigure value={row.bestReturn} />
                  {row.bestVault && row.bestSymbol ? (
                    <Link className="leaderboard__link" href={`/strategy/${row.bestVault}`}>
                      {row.bestSymbol}
                    </Link>
                  ) : null}
                </td>
                <td>{row.score.toFixed(0)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="text-caption text-ink-muted leaderboard__formula">
        Score, 0 to 100: {SCORE_WEIGHTS.aum * 100}% AUM on a log scale against the largest creator, {SCORE_WEIGHTS.returns * 100}% best
        return since inception (clamped from {SCORE_RETURN_FLOOR * 100}% to +{SCORE_RETURN_CAP * 100}%), {SCORE_WEIGHTS.age * 100}% age of
        the oldest strategy (full marks at {SCORE_AGE_CAP_DAYS} days). Computed in your browser from registry data.
      </p>
    </div>
  );
}
