"use client";

import { m, useMotionValue, useReducedMotion, useSpring, useTransform } from "framer-motion";
import Link from "next/link";
import type { CSSProperties, PointerEvent as ReactPointerEvent } from "react";
import { StrategyLogo } from "@/components/art/strategy-logo";
import { Magnetic } from "@/components/motion/magnetic";
import { ReturnFigure } from "@/components/return-figure";
import { StrategyHoldings } from "@/components/strategy-holdings";
import { useFinePointer } from "@/lib/hooks/use-fine-pointer";
import type { CarouselPhase, SlotPose } from "@/lib/carousel-slots";
import { isDemoStrategy } from "@/lib/demo-strategies";
import { formatUsd } from "@/lib/discovery-format";
import { describeHoldings, type Holding } from "@/lib/holding-tones";
import { navUsdOf, type StrategySummary } from "@/lib/hooks/use-marketplace";
import { SPRING } from "@/lib/motion";
import styles from "./featured-card.module.css";

const TILT_X_DEGREES = 3;
const TILT_Y_DEGREES = 4;
const LOGO_SIZE = "calc(var(--cu) * 104)";

type FeaturedCardProps = {
  strategy: StrategySummary;
  holdings?: readonly Holding[];
  holdingsLoading: boolean;
  index: number;
  total: number;
  slot: number;
  pose: SlotPose;
  wrapped: boolean;
  phase: CarouselPhase;
  entryPose: SlotPose;
  entryDelay: number;
  onSelect: (index: number) => void;
  dragMoved: { current: boolean };
};

export function FeaturedCard({
  strategy,
  holdings,
  holdingsLoading,
  index,
  total,
  slot,
  pose,
  wrapped,
  phase,
  entryPose,
  entryDelay,
  onSelect,
  dragMoved,
}: FeaturedCardProps) {
  const finePointer = useFinePointer();
  const reduced = useReducedMotion();
  const isActive = slot === 0;
  const isVisible = Math.abs(slot) <= 1;
  const tiltEnabled = finePointer && !reduced && isActive;

  const tiltX = useSpring(useMotionValue(0), SPRING.snap);
  const tiltY = useSpring(useMotionValue(0), SPRING.snap);
  const sheen = useSpring(useMotionValue(50), SPRING.snap);
  const sheenShift = useTransform(sheen, (value) => `${((value - 50) / 38) * 100}%`);

  const onPointerMove = (event: ReactPointerEvent<HTMLElement>) => {
    if (!tiltEnabled) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const px = (event.clientX - rect.left) / rect.width - 0.5;
    const py = (event.clientY - rect.top) / rect.height - 0.5;
    tiltY.set(px * 2 * TILT_Y_DEGREES);
    tiltX.set(-py * 2 * TILT_X_DEGREES);
    sheen.set(50 + px * 30);
  };

  const resetTilt = () => {
    tiltX.set(0);
    tiltY.set(0);
    sheen.set(50);
  };

  const { zIndex, ...transformPose } = pose;
  const target = phase === "stacked" ? entryPose : transformPose;
  const animate = wrapped && phase === "in" ? { ...target, opacity: [0, target.opacity] } : target;
  const transition =
    phase !== "in"
      ? { duration: 0 }
      : wrapped
        ? { default: { duration: 0 }, opacity: { duration: 0.35, ease: "easeOut" as const } }
        : {
            ...SPRING.orbit,
            delay: entryDelay,
            opacity: { duration: 0.24, ease: "easeOut" as const, delay: entryDelay },
          };

  const handleClick = () => {
    if (dragMoved.current || isActive) return;
    onSelect(index);
  };

  const demo = isDemoStrategy(strategy);
  const label = strategy.symbol ?? "Strategy";
  const depth = strategy.depth || 1;
  const navUsd = navUsdOf(strategy);
  const nameFit = { "--len": label.length } as CSSProperties;

  return (
    <m.article
      className={styles.card}
      data-slot={slot}
      data-carousel-card
      style={{ zIndex }}
      initial={false}
      animate={animate}
      transition={transition}
      role="group"
      aria-roledescription="slide"
      aria-label={`${label}, ${index + 1} of ${total}`}
      aria-hidden={isVisible ? undefined : true}
      inert={!isVisible || phase === "stacked"}
      onClick={handleClick}
      onPointerMove={onPointerMove}
      onPointerLeave={resetTilt}
    >
      <m.div className={styles.face} style={{ transformPerspective: 900, rotateX: tiltX, rotateY: tiltY }}>
        <span className={styles.glass} aria-hidden="true" />
        <span className={styles.veil} aria-hidden="true" />
        <m.span className={styles.sheen} aria-hidden="true" style={{ x: sheenShift }} />
        <span className={styles.underglow} aria-hidden="true" />

        <div className={styles.logo}>
          <StrategyLogo seed={strategy.vault} symbol={strategy.symbol} depth={depth} size={LOGO_SIZE} />
        </div>
        <h3 className={styles.name} style={nameFit}>
          {label}
        </h3>
        <p className={styles.nav}>
          <span className={styles.navLabel}>NAV</span>
          <span className={styles.navValue}>
            {navUsd !== undefined ? formatUsd(navUsd) : "—"}
          </span>
          <ReturnFigure value={strategy.sinceInception} className={styles.navReturn} />
        </p>
        <div className={styles.holdings}>
          <StrategyHoldings holdings={holdings} size="stage" loading={holdingsLoading} />
        </div>
        <span className={styles.buttonSlot}>
          <Magnetic disabled={!isActive} fill>
            <Link
              className={styles.button}
              href={demo ? "/create" : `/strategy/${strategy.vault}`}
              tabIndex={isActive ? 0 : -1}
              aria-label={
                demo
                  ? `Create a strategy like ${label}`
                  : `View ${label}${holdings?.length ? `, holds ${describeHoldings(holdings)}` : ""}`
              }
            >
              <span className={styles.buttonFill} aria-hidden="true" />
              <span className={styles.buttonLabel}>{demo ? "Create yours" : "View"}</span>
            </Link>
          </Magnetic>
        </span>
      </m.div>
    </m.article>
  );
}
