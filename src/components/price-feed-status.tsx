"use client";

import { formatAge } from "@/lib/discovery-format";
import { useNowSeconds } from "@/lib/hooks/use-now";

const AGING_SECONDS = 35 * 60;

interface PriceFeedStatusProps {
  fresh: boolean | undefined;
  oldestUpdatedAt: number | undefined;
}

const STALE_ANNOUNCEMENT = "Price feed is stale. Deposits, redeems and rebalances will revert until prices refresh.";

function Announcement({ state }: { state: "unknown" | "stale" | "aging" | "fresh" }) {
  if (state === "stale") {
    return (
      <span className="sr-only" role="alert">
        {STALE_ANNOUNCEMENT}
      </span>
    );
  }
  return (
    <span className="sr-only" role="status">
      {state === "unknown" ? "Checking the price feed" : state === "aging" ? "Prices are older than usual" : "Prices are fresh"}
    </span>
  );
}

export function PriceFeedStatus({ fresh, oldestUpdatedAt }: PriceFeedStatusProps) {
  const now = useNowSeconds(15_000);

  if (fresh === undefined) {
    return (
      <p className="feed-status text-caption" data-state="unknown">
        <Announcement state="unknown" />
        <span className="feed-status__dot" aria-hidden="true" />
        Checking the price feed
      </p>
    );
  }

  if (!fresh) {
    const known = oldestUpdatedAt !== undefined && oldestUpdatedAt > 0;
    return (
      <p className="feed-status text-caption" data-state="stale">
        <Announcement state="stale" />
        <span className="feed-status__dot" aria-hidden="true" />
        <span>
          {known
            ? `Price feed is stale: the oldest price is ${formatAge(now - oldestUpdatedAt)} old.`
            : "Price feed is unavailable."}{" "}
          Deposits, redeems and rebalances will revert until prices refresh. Redeem in kind still works.
        </span>
      </p>
    );
  }

  const age = oldestUpdatedAt === undefined ? undefined : Math.max(0, now - oldestUpdatedAt);
  const aging = age !== undefined && age > AGING_SECONDS;

  return (
    <p className="feed-status text-caption" data-state={aging ? "aging" : "fresh"}>
      <Announcement state={aging ? "aging" : "fresh"} />
      <span className="feed-status__dot" aria-hidden="true" />
      <span>
        {age === undefined
          ? "Prices are fresh"
          : aging
            ? `Prices last updated ${formatAge(age)} ago, older than the usual relayer cadence`
            : `Prices updated ${formatAge(age)} ago`}
      </span>
    </p>
  );
}
