"use client";

import { useMemo, useState } from "react";
import type { Address } from "viem";
import { useAccount } from "wagmi";
import { StrategyLogo } from "@/components/art/strategy-logo";
import { StrategyCard } from "@/components/strategy-card";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Notice } from "@/components/ui/notice";
import { StateCard } from "@/components/ui/state-card";
import { Skeleton } from "@/components/ui/skeleton";
import { useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import { useFollow } from "@/lib/hooks/use-follow";
import { useFollowerCount } from "@/lib/hooks/use-follower-count";
import { useProfile } from "@/lib/hooks/use-profile";
import { useSetProfile } from "@/lib/hooks/use-social-registry";
import { shortenAddress, utf8Bytes } from "@/lib/format";
import styles from "./creator-profile.module.css";

const MIN_HANDLE_BYTES = 3;
const MAX_HANDLE_BYTES = 20;
const MAX_BIO_BYTES = 160;
const HANDLE_PATTERN = /^[a-z0-9_-]+$/;

function EditProfileForm({ currentHandle, currentBio }: { currentHandle?: string; currentBio?: string }) {
  const { setProfile, status, error, reset, available } = useSetProfile();
  const [handle, setHandle] = useState(currentHandle ?? "");
  const [bio, setBio] = useState(currentBio ?? "");
  const handleBytes = utf8Bytes(handle.trim());
  const bioBytes = utf8Bytes(bio.trim());
  const handleInvalid =
    handle.trim().length > 0 && (!HANDLE_PATTERN.test(handle.trim()) || handleBytes < MIN_HANDLE_BYTES || handleBytes > MAX_HANDLE_BYTES);
  const bioInvalid = bioBytes > MAX_BIO_BYTES;
  const isBusy = status === "signing" || status === "confirming";
  const canSave = available && handle.trim().length > 0 && !handleInvalid && !bioInvalid && !isBusy;

  async function handleSave() {
    if (!canSave) return;
    await setProfile(handle.trim(), bio.trim()).catch(() => {});
  }

  return (
    <Card variant="glass" className={styles.editCard}>
      <h2 className="text-title text-ink">Edit profile</h2>
      {!available ? (
        <Notice tone="warn">The social registry isn&apos;t live on this network yet, so profile edits can&apos;t be saved.</Notice>
      ) : null}
      <label className="field">
        <span className="field__label">Handle</span>
        <input
          value={handle}
          onChange={(event) => setHandle(event.target.value)}
          placeholder="alex"
          className="input"
          aria-invalid={handleInvalid}
        />
        <span className={styles.counter} data-over={handleInvalid ? "" : undefined}>
          {handleBytes}/{MAX_HANDLE_BYTES} bytes · lowercase letters, digits, - and _
        </span>
      </label>
      <label className="field">
        <span className="field__label">Bio</span>
        <textarea
          value={bio}
          onChange={(event) => setBio(event.target.value)}
          rows={3}
          className="input"
          placeholder="AI & Technology Research"
          aria-invalid={bioInvalid}
        />
        <span className={styles.counter} data-over={bioInvalid ? "" : undefined}>
          {bioBytes}/{MAX_BIO_BYTES} bytes
        </span>
      </label>
      {status === "error" && error ? (
        <Notice tone="error" role="alert">
          {error}{" "}
          <button type="button" className="text-button" data-underline="" onClick={reset}>
            Reset
          </button>
        </Notice>
      ) : null}
      {status === "success" ? <Notice tone="success">Profile saved.</Notice> : null}
      <Button onClick={handleSave} disabled={!canSave}>
        {status === "signing" ? "Confirm in wallet…" : status === "confirming" ? "Saving…" : "Save profile"}
      </Button>
    </Card>
  );
}

export function CreatorProfile({ address }: { address: Address }) {
  const { address: account } = useAccount();
  const isOwner = Boolean(account && account.toLowerCase() === address.toLowerCase());
  const profile = useProfile(address);
  const followerCount = useFollowerCount(address);
  const follow = useFollow(address);
  const followBusy = follow.status === "signing" || follow.status === "confirming";
  const { strategies, isLoading: strategiesLoading, error: strategiesError, refetch } = useMarketplaceStrategies();

  const creatorStrategies = useMemo(
    () => strategies.filter((strategy) => strategy.creator.toLowerCase() === address.toLowerCase()),
    [strategies, address],
  );

  const displayName = profile.handle ? `@${profile.handle}` : shortenAddress(address, 6);
  const followDisabled = !follow.isAvailable || follow.isLoading || followBusy || !account;

  return (
    <div className="flex flex-col gap-10">
      <Card variant="glass" tone="violet" className={styles.header}>
        <StrategyLogo seed={address} symbol={profile.handle ?? address} depth={1} size="4.5rem" />
        <div className="flex min-w-0 flex-1 flex-col gap-2">
          <div className="flex flex-wrap items-center gap-3">
            <h1 className="text-heading text-ink">{displayName}</h1>
            {!isOwner ? (
              <Button
                size="sm"
                variant={follow.isFollowing ? "secondary" : "primary"}
                onClick={follow.toggle}
                disabled={followDisabled}
              >
                {follow.isFollowing ? "✓ Following" : "+ Follow"}
              </Button>
            ) : null}
          </div>
          {profile.isLoading ? (
            <Skeleton className="h-5 w-48" />
          ) : (
            <p className="text-body text-ink-soft">{profile.bio ?? "No bio set yet."}</p>
          )}
          <p className="text-caption text-ink-muted">
            {followerCount.count !== undefined
              ? `${followerCount.count.toLocaleString("en-US")} ${followerCount.count === 1 ? "follower" : "followers"}`
              : follow.isAvailable
                ? "— followers"
                : "Social registry not live on this network yet"}
          </p>
          {!isOwner && !account ? <p className="text-caption text-ink-muted">Connect a wallet to follow.</p> : null}
        </div>
      </Card>

      {isOwner ? <EditProfileForm currentHandle={profile.handle} currentBio={profile.bio} /> : null}

      <section className="flex flex-col gap-6">
        <h2 className="text-title text-ink">Strategies</h2>
        {strategiesLoading ? (
          <div className="grid grid-cols-1 gap-6 sm:grid-cols-2" role="status">
            <span className="sr-only">Loading strategies</span>
            {[0, 1].map((index) => (
              <Skeleton key={index} className="h-40" />
            ))}
          </div>
        ) : strategiesError ? (
          <Notice tone="error" role="alert">
            Could not load this creator&apos;s strategies.{" "}
            <button type="button" className="text-button" onClick={refetch}>
              Try again
            </button>
          </Notice>
        ) : creatorStrategies.length === 0 ? (
          <StateCard art="empty" title="No strategies yet">
            <p>{isOwner ? "Publish your first thesis to see it here." : "This creator hasn’t published a strategy yet."}</p>
          </StateCard>
        ) : (
          <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
            {creatorStrategies.map((strategy) => (
              <StrategyCard key={strategy.vault} strategy={strategy} />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
