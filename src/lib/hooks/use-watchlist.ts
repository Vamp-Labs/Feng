"use client";

import { useCallback, useMemo, useSyncExternalStore } from "react";
import { useActiveNetwork } from "@/lib/addresses-context";
import { emptyWatchlist, readWatchlist, subscribeWatchlist, toggleWatch, watchKey } from "@/lib/watchlist";

export function useWatchlist() {
  const { addresses } = useActiveNetwork();
  const chainId = addresses.chainId;
  const entries = useSyncExternalStore(subscribeWatchlist, readWatchlist, emptyWatchlist);

  const followed = useMemo(() => new Set(entries), [entries]);

  const isFollowing = useCallback((vault: string) => followed.has(watchKey(chainId, vault)), [followed, chainId]);
  const toggle = useCallback((vault: string) => toggleWatch(chainId, vault), [chainId]);

  const count = useMemo(() => entries.filter((entry) => entry.startsWith(`${chainId}:`)).length, [entries, chainId]);

  return { isFollowing, toggle, count };
}
