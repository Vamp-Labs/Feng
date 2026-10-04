"use client";

import { m, useInView, type PanInfo } from "framer-motion";
import Link from "next/link";
import { useCallback, useEffect, useRef, useState, type KeyboardEvent } from "react";
import { Magnetic } from "@/components/motion/magnetic";
import { ArrowIcon } from "@/components/ui/icons";
import { ENTRY_POSE, poseForSlot, slotOf, type CarouselPhase } from "@/lib/carousel-slots";
import { useHydrated } from "@/lib/hooks/use-hydrated";
import type { Holding } from "@/lib/holding-tones";
import type { StrategySummary } from "@/lib/hooks/use-marketplace";
import { DURATION, EASE_OUT } from "@/lib/motion";
import { FeaturedCard } from "./featured-card";
import styles from "./featured-carousel.module.css";

const SWIPE_DISTANCE = 40;
const SWIPE_VELOCITY = 450;
const PRESS_LOCK_MS = 90;
const SIDE_ENTRY_DELAY = 0.14;
const INTRO_SETTLE_MS = 1000;

type Cursor = { active: number; direction: -1 | 0 | 1 };

export function AllStrategiesLink() {
  return (
    <Link className={styles.more} href="/marketplace">
      All strategies
      <ArrowIcon direction="right" className={styles.moreGlyph} />
    </Link>
  );
}

type FeaturedCarouselProps = {
  strategies: readonly StrategySummary[];
  holdings: Readonly<Record<string, readonly Holding[] | undefined>>;
  holdingsLoading: boolean;
};

export function FeaturedCarousel({ strategies, holdings, holdingsLoading }: FeaturedCarouselProps) {
  const count = strategies.length;
  const root = useRef<HTMLElement>(null);
  const lastPress = useRef(0);
  const dragMoved = useRef(false);
  const [cursor, setCursor] = useState<Cursor>({ active: 0, direction: 0 });
  const inView = useInView(root, { amount: 0.35, once: true, margin: "0px 0px -15% 0px" });
  const mounted = useHydrated();
  const [armed, setArmed] = useState(false);
  const [introDone, setIntroDone] = useState(false);
  const phase: CarouselPhase = !mounted ? "ssr" : inView && armed ? "in" : "stacked";
  const active = Math.min(cursor.active, count - 1);

  useEffect(() => {
    const frame = requestAnimationFrame(() => setArmed(true));
    return () => cancelAnimationFrame(frame);
  }, []);

  useEffect(() => {
    if (phase !== "in") return;
    const timer = window.setTimeout(() => setIntroDone(true), INTRO_SETTLE_MS);
    return () => window.clearTimeout(timer);
  }, [phase]);

  const step = useCallback(
    (direction: -1 | 1) => {
      const now = performance.now();
      if (now - lastPress.current < PRESS_LOCK_MS) return;
      lastPress.current = now;
      setCursor((current) => ({
        active: (Math.min(current.active, count - 1) + direction + count) % count,
        direction,
      }));
    },
    [count],
  );

  const select = useCallback(
    (index: number) => {
      setCursor((current) => {
        const offset = slotOf(index, Math.min(current.active, count - 1), count);
        if (offset === 0) return current;
        return { active: index, direction: offset > 0 ? 1 : -1 };
      });
    },
    [count],
  );

  const onKeyDown = (event: KeyboardEvent<HTMLElement>) => {
    if (event.repeat || count < 2) return;
    if (event.key === "ArrowLeft") {
      event.preventDefault();
      step(-1);
    } else if (event.key === "ArrowRight") {
      event.preventDefault();
      step(1);
    }
  };

  const onDragEnd = (_event: PointerEvent | MouseEvent | TouchEvent, info: PanInfo) => {
    const travelled = info.offset.x;
    const speed = info.velocity.x;
    if (count > 1 && (Math.abs(travelled) > SWIPE_DISTANCE || Math.abs(speed) > SWIPE_VELOCITY)) {
      step(travelled < 0 || (travelled === 0 && speed < 0) ? 1 : -1);
    }
    window.setTimeout(() => {
      dragMoved.current = false;
    }, 0);
  };

  const current = strategies[active];
  const previousActive = (active - cursor.direction + count) % count;
  const showArrows = count > 1;
  const arrowDelay = introDone ? 0 : 0.36;
  const arrowHidden = phase === "stacked" || !showArrows;

  return (
    <section
      ref={root}
      id="featured"
      className={styles.root}
      aria-roledescription="carousel"
      aria-label="Featured strategies"
      onKeyDown={onKeyDown}
      data-carousel
    >
      {showArrows ? (
        <div className={`${styles.arrow} ${styles.arrowLeft}`} inert={arrowHidden}>
          <Magnetic>
            <m.button
              type="button"
              className={styles.arrowButton}
              aria-label="Previous strategy"
              onClick={() => step(-1)}
              initial={false}
              animate={{ opacity: arrowHidden ? 0 : 1, x: arrowHidden ? -12 : 0 }}
              transition={
                phase === "in"
                  ? { duration: DURATION.md, ease: EASE_OUT, delay: arrowDelay }
                  : { duration: 0 }
              }
              whileTap={{ scale: 0.92 }}
            >
              <ArrowIcon direction="left" className={styles.glyph} />
            </m.button>
          </Magnetic>
        </div>
      ) : null}

      <div className={styles.viewport}>
        <m.div
          className={styles.track}
          drag={count > 1 ? "x" : false}
          dragConstraints={{ left: 0, right: 0 }}
          dragElastic={0.55}
          dragSnapToOrigin
          dragDirectionLock
          onDragStart={() => {
            dragMoved.current = true;
          }}
          onDragEnd={onDragEnd}
        >
          {strategies.map((strategy, index) => {
            const slot = slotOf(index, active, count);
            const previousSlot = slotOf(index, previousActive, count);
            return (
              <FeaturedCard
                key={strategy.vault}
                strategy={strategy}
                holdings={holdings[strategy.vault]}
                holdingsLoading={holdingsLoading}
                index={index}
                total={count}
                slot={slot}
                pose={poseForSlot(slot)}
                wrapped={cursor.direction !== 0 && Math.abs(slot - previousSlot) > 1}
                phase={phase}
                entryPose={ENTRY_POSE}
                entryDelay={introDone || slot === 0 ? 0 : SIDE_ENTRY_DELAY}
                onSelect={select}
                dragMoved={dragMoved}
              />
            );
          })}
        </m.div>
      </div>

      {showArrows ? (
        <div className={`${styles.arrow} ${styles.arrowRight}`} inert={arrowHidden}>
          <Magnetic>
            <m.button
              type="button"
              className={styles.arrowButton}
              aria-label="Next strategy"
              onClick={() => step(1)}
              initial={false}
              animate={{ opacity: arrowHidden ? 0 : 1, x: arrowHidden ? 12 : 0 }}
              transition={
                phase === "in"
                  ? { duration: DURATION.md, ease: EASE_OUT, delay: arrowDelay }
                  : { duration: 0 }
              }
              whileTap={{ scale: 0.92 }}
            >
              <ArrowIcon direction="right" className={styles.glyph} />
            </m.button>
          </Magnetic>
        </div>
      ) : null}

      <p className="sr-only" aria-live="polite">
        Showing {current?.symbol ?? "strategy"}, {active + 1} of {count}
      </p>
      <AllStrategiesLink />
    </section>
  );
}
