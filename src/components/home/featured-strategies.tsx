"use client";

import { DEMO_HOLDINGS, DEMO_STRATEGIES } from "@/lib/demo-strategies";
import { pickFeatured } from "@/lib/featured";
import { poseForSlot } from "@/lib/carousel-slots";
import { useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import { useStrategyHoldings } from "@/lib/hooks/use-strategy-holdings";
import { AllStrategiesLink, FeaturedCarousel } from "./featured-carousel";
import frame from "./featured-carousel.module.css";
import styles from "./featured-strategies.module.css";

const PLACEHOLDER_SLOTS = [-1, 0, 1] as const;

function poseStyle(slot: number) {
  const pose = poseForSlot(slot);
  return {
    transform: `translate(${pose.x}, ${pose.y}) rotate(${pose.rotateZ}deg) scale(${pose.scale})`,
    zIndex: pose.zIndex,
  };
}

export function FeaturedStrategies() {
  const { strategies, isLoading } = useMarketplaceStrategies();
  const { holdings, isLoading: holdingsLoading } = useStrategyHoldings();
  const featured = pickFeatured(strategies);

  if (featured.length > 0) {
    return <FeaturedCarousel strategies={featured} holdings={holdings} holdingsLoading={holdingsLoading} />;
  }

  if (isLoading) {
    return (
      <section className={frame.root} aria-label="Featured strategies" aria-busy="true">
        <div className={frame.viewport}>
          {PLACEHOLDER_SLOTS.map((slot) => (
            <div className={styles.ghost} key={slot} style={poseStyle(slot)} data-active={slot === 0 ? "" : undefined} />
          ))}
        </div>
        <p className="sr-only" role="status">
          Loading featured strategies
        </p>
        <AllStrategiesLink />
      </section>
    );
  }

  return <FeaturedCarousel strategies={DEMO_STRATEGIES} holdings={DEMO_HOLDINGS} holdingsLoading={false} />;
}
