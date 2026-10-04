"use client";

import { cn } from "@/lib/cn";
import { useWatchlist } from "@/lib/hooks/use-watchlist";

export function WatchButton({ vault, label, className }: { vault: string; label: string; className?: string }) {
  const { isFollowing, toggle } = useWatchlist();
  const following = isFollowing(vault);

  return (
    <button
      type="button"
      className={cn("watch-button", className)}
      aria-pressed={following}
      aria-label={`Follow ${label}`}
      title={following ? "Following" : "Follow"}
      onClick={() => toggle(vault)}
    >
      <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false">
        <path
          d="m12 3.2 2.7 5.6 6.1.8-4.5 4.2 1.1 6-5.4-2.9-5.4 2.9 1.1-6L3.2 9.6l6.1-.8Z"
          fill={following ? "currentColor" : "none"}
          stroke="currentColor"
          strokeWidth="1.8"
          strokeLinejoin="round"
        />
      </svg>
    </button>
  );
}
