"use client";

import type { Address } from "viem";
import { Button } from "@/components/ui/button";
import { useFollow } from "@/lib/hooks/use-follow";

export function FollowButton({ target, label }: { target: Address; label: string }) {
  const follow = useFollow(target);
  const busy = follow.status === "signing" || follow.status === "confirming";

  if (!follow.isAvailable) {
    return (
      <Button variant="secondary" disabled title="Following is launching soon.">
        + Follow
      </Button>
    );
  }

  return (
    <Button
      variant={follow.isFollowing ? "secondary" : "primary"}
      onClick={() => void follow.toggle()}
      disabled={!follow.isConnected || busy || follow.isLoading}
      aria-pressed={follow.isFollowing}
      aria-label={follow.isFollowing ? `Following ${label}` : `Follow ${label}`}
      title={follow.isConnected ? undefined : "Connect a wallet to follow."}
    >
      {busy ? "..." : follow.isFollowing ? "✓ Following" : "+ Follow"}
    </Button>
  );
}
