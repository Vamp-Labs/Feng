import Image from "next/image";
import { ButtonLink } from "@/components/ui/button";
import { Bolt } from "@/components/ui/icons";
import { cssVars } from "@/lib/geometry";
import { FloatingTile, type TileMotion } from "./floating-tile";
import { RankScene } from "./rank-scene";
import { Sparkles } from "./sparkles";
import styles from "./portfolio-section.module.css";

const ORIGIN_REF_Y = 715;
const HEADING_WORDS = ["Compose.", "Deposit.", "Rebalance."] as const;

type TileSpec = {
  id: string;
  src: string;
  box: readonly [number, number, number, number];
  glow: string;
  motion: TileMotion;
  floatOnMobile?: boolean;
  className?: string;
  mobile: Record<string, string | number>;
};

const motion = (rotate: number, y: number, tilt: number, seconds: number, phase: number): TileMotion => ({
  rotate,
  delay: 0,
  float: { y, rotate: tilt, seconds },
  phase,
});

const TILES: readonly TileSpec[] = [
  {
    id: "violet-topleft",
    src: "/img/dl-tile-violet-topleft.png",
    box: [232, 766, 98, 78],
    glow: "rgb(90 50 220 / 0.4)",
    motion: motion(-14, -5, 1.2, 5.5, 2.6),
    floatOnMobile: false,
    mobile: { "--m-left": "calc(var(--v) * -16)", "--m-top": "calc(var(--v) * 6)", "--m-width": 54 },
  },
  {
    id: "violet-left",
    src: "/img/dl-tile-violet-left.png",
    box: [93, 839, 81, 60],
    glow: "rgb(90 70 255 / 0.4)",
    motion: motion(14, 4, -1.2, 6.6, 3.9),
    floatOnMobile: false,
    mobile: { "--m-left": "calc(var(--v) * -12)", "--m-top": "calc(var(--v) * 210)", "--m-width": 48 },
  },
  {
    id: "dark-topright",
    src: "/img/dl-tile-dark-topright.png",
    box: [847, 753, 77, 71],
    glow: "rgb(70 40 190 / 0.35)",
    motion: motion(-14, -6, 1, 7.5, 5.2),
    floatOnMobile: false,
    mobile: { "--m-right": "calc(var(--v) * 6)", "--m-top": "calc(var(--v) * 4)", "--m-width": 42 },
  },
  {
    id: "violet-right",
    src: "/img/dl-tile-violet-right.png",
    box: [992, 945, 100, 88],
    glow: "rgb(100 70 255 / 0.4)",
    className: "edgeFade",
    motion: motion(14, 5, -1, 6.2, 6.5),
    floatOnMobile: false,
    mobile: { "--m-right": "calc(var(--v) * -26)", "--m-top": "calc(var(--v) * 236)", "--m-width": 66 },
  },
  {
    id: "dark-small",
    src: "/img/dl-tile-dark-small.png",
    box: [168, 1132, 73, 68],
    glow: "rgb(60 40 170 / 0.35)",
    motion: motion(-14, -4, 1.2, 7, 7.8),
    floatOnMobile: false,
    mobile: { "--m-left": "calc(var(--v) * 36)", "--m-top": "calc(var(--v) * 560)", "--m-width": 40 },
  },
  {
    id: "clock",
    src: "/img/dl-tile-clock-green.png",
    box: [35, 1000, 211, 135],
    glow: "rgb(40 255 150 / 0.4)",
    motion: motion(-14, -5, 1.5, 7.8, 0),
    mobile: { "--m-left": "calc(var(--v) * -34)", "--m-top": "calc(var(--v) * 306)", "--m-width": 126 },
  },
  {
    id: "play",
    src: "/img/dl-tile-play-green.png",
    box: [797, 1035, 185, 121],
    glow: "rgb(40 255 150 / 0.4)",
    motion: motion(14, 5, -1.5, 8.6, 1.3),
    mobile: { "--m-right": "calc(var(--v) * -30)", "--m-top": "calc(var(--v) * 500)", "--m-width": 118 },
  },
];

export function PortfolioSection() {
  return (
    <section id="portfolio" className={styles.section} aria-labelledby="portfolio-title" data-portfolio>
      <div className={styles.rays} aria-hidden="true" data-rays>
        <div className={styles.raysBase}>
          <Image src="/img/dl-bg-rays-clean.png" alt="" fill sizes="100vw" data-rays-base />
        </div>
        <div className={styles.raysSway} data-rays-sway>
          <Image src="/img/dl-bg-rays-clean.png" alt="" fill sizes="100vw" />
        </div>
      </div>
      <Sparkles />

      <div className={styles.copy}>
        <h2 className={styles.title} id="portfolio-title">
          {HEADING_WORDS.map((word) => (
            <span className={styles.mask} key={word}>
              <span className={styles.word} data-word-scene>
                {word}
              </span>
            </span>
          ))}
        </h2>
        <p className={styles.sub} data-reveal data-portfolio-sub>
          Hold Strategy Tokens, watch NAV move with the market, and rebalance on-chain when the rules say so.
        </p>
        <div className={styles.actions}>
          <span data-reveal data-action>
            <ButtonLink href="/create" className={styles.cta}>
              Create a strategy
              <Bolt />
            </ButtonLink>
          </span>
          <span data-reveal data-action>
            <ButtonLink href="/positions" variant="secondary" className={styles.cta}>
              Your positions
            </ButtonLink>
          </span>
        </div>
      </div>

      <div className={styles.scene} data-scene>
        {TILES.map((tile) => (
          <FloatingTile
            key={tile.id}
            id={tile.id}
            src={tile.src}
            box={tile.box}
            nativeSize={[tile.box[2], tile.box[3]]}
            originRefY={ORIGIN_REF_Y}
            glow={tile.glow}
            enter={tile.motion}
            sceneReveal
            floatOnMobile={tile.floatOnMobile ?? true}
            className={tile.className ? styles[tile.className] : undefined}
            mobile={cssVars({
              ...tile.mobile,
              "--aspect": `${tile.box[2]} / ${tile.box[3]}`,
            })}
          />
        ))}
        <RankScene />
      </div>
    </section>
  );
}
