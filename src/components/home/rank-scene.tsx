"use client";

import Image from "next/image";
import type { CSSProperties } from "react";
import { useAccount } from "wagmi";
import { BoltGlyph, LayersIcon } from "@/components/ui/icons";
import { canvasBox, cssVars } from "@/lib/geometry";
import { usePortfolioStats } from "@/lib/hooks/use-portfolio-stats";
import { AvatarTile } from "./avatar-tile";
import { CompleteBadge } from "./complete-badge";
import styles from "./rank-scene.module.css";

const MOBILE_BOX: CSSProperties = cssVars({
  "--m-top": "calc(var(--v) * 372)",
});

const PLACEHOLDER = "–";

export function RankScene() {
  const { address } = useAccount();
  const stats = usePortfolioStats();
  const progress = stats.total === 0 ? 0 : stats.held / stats.total;
  const label = stats.ready
    ? stats.isConnected
      ? `You hold ${stats.held} of ${stats.total} listed strategies. ${stats.tvl} total value locked. ${stats.nested} nested strategies.`
      : `${stats.total} listed strategies, ${stats.tvl} total value locked. Connect a wallet to see your positions.`
    : "Loading portfolio";

  return (
    <>
      <CompleteBadge percent={stats.nestedPercent} ready={stats.ready} />
      <div
        className={styles.rank}
        style={{ ...canvasBox([312, 1071, 475, 245], 715), ...MOBILE_BOX, ...cssVars({ "--rank-progress": progress }) }}
        role="img"
        aria-label={label}
        data-rank
      >
        <div className={styles.slab} data-rank-slab data-reveal>
          <Image
            className={styles.bar}
            src="/img/rank-bar-notext-no-avatar.png"
            alt=""
            width={475}
            height={180}
            sizes="(min-width: 1000px) 626px, 340px"
          />
          <span className={styles.label} data-rank-label aria-hidden="true">
            Positions
          </span>
          <div className={styles.track} data-rank-track aria-hidden="true">
            <span className={styles.rest} />
            <span className={styles.fill} data-rank-fill />
            <span className={styles.knob} data-rank-knob />
          </div>
          <span className={styles.figure} data-rank-figure aria-hidden="true">
            <span key={`h${stats.held}`} data-count={stats.ready ? stats.held : undefined}>
              {stats.ready ? stats.held : PLACEHOLDER}
            </span>
            <span className={styles.divider}> / </span>
            <span key={`t${stats.total}`} data-count={stats.ready ? stats.total : undefined}>
              {stats.ready ? stats.total : PLACEHOLDER}
            </span>
          </span>
          <span className={`${styles.chip} ${styles.tvl}`} data-rank-chip aria-hidden="true">
            <BoltGlyph className={styles.bolt} />
            <span>{stats.ready ? `${stats.tvl} TVL` : PLACEHOLDER}</span>
          </span>
          <span className={`${styles.chip} ${styles.nested}`} data-rank-chip aria-hidden="true">
            <LayersIcon className={styles.layers} />
            <span>{stats.ready ? `${stats.nested} nested` : PLACEHOLDER}</span>
          </span>
        </div>
        <div className={styles.avatar} data-rank-avatar data-reveal>
          <AvatarTile address={address} />
        </div>
      </div>
    </>
  );
}
