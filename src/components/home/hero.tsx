import { cssVars } from "@/lib/geometry";
import { RevealScope } from "@/components/motion/reveal-scope";
import { Bolt } from "@/components/ui/icons";
import { ButtonLink } from "@/components/ui/button";
import { wordIndex } from "@/components/words";
import { FloatingTile } from "./floating-tile";
import styles from "./hero.module.css";

const HEADLINE_LINES = [
  ["Turn", "strategies", "into"],
  ["composable", "tokens"],
] as const;
const ACCENT_WORD = "composable";

export function Hero() {
  let wordNumber = 0;

  return (
    <section className={styles.hero} aria-labelledby="hero-title" data-hero>
      <RevealScope introKey="home-hero" className={styles.scope}>
        <FloatingTile
          id="purple"
          src="/img/hero-tile-purple.png"
          box={[126, 114, 94, 69]}
          nativeSize={[94, 69]}
          glow="rgb(110 70 255 / 0.55)"
          priority
          enter={{ rotate: 16, delay: 0.3, float: { y: -6, rotate: 2.5, seconds: 6.2 } }}
          mobile={cssVars({
            "--m-left": "calc(var(--v) * -18)",
            "--m-top": "calc(var(--v) * 14)",
            "--m-width": 74,
            "--aspect": "94 / 69",
          })}
        />
        <FloatingTile
          id="squares"
          hiddenOnMobile
          src="/img/hero-tile-squares.png"
          box={[126, 307, 94, 85]}
          nativeSize={[94, 85]}
          glow="rgb(70 80 255 / 0.4)"
          priority
          enter={{ rotate: -16, delay: 0.38, float: { y: 5, rotate: -2, seconds: 7.4 } }}
          mobile={cssVars({
            "--m-left": "calc(var(--v) * -20)",
            "--m-top": "calc(var(--v) * 470)",
            "--m-width": 66,
            "--aspect": "94 / 85",
          })}
        />
        <FloatingTile
          id="play"
          src="/img/hero-tile-play-green.png"
          box={[874, 222, 170, 110]}
          nativeSize={[170, 110]}
          glow="rgb(40 255 150 / 0.45)"
          priority
          enter={{ rotate: 16, delay: 0.46, float: { y: -4, rotate: 1.5, seconds: 8.6 } }}
          mobile={cssVars({
            "--m-right": "calc(var(--v) * -34)",
            "--m-top": "calc(var(--v) * 62)",
            "--m-width": 112,
            "--aspect": "170 / 110",
          })}
        />

        <h1 className={styles.title} id="hero-title">
          {HEADLINE_LINES.map((line, lineIndex) => (
            <span className={styles.line} key={lineIndex}>
              {line.map((word) => {
                const index = wordNumber++;
                return (
                  <span className={styles.mask} key={word}>
                    <span
                      className={
                        word === ACCENT_WORD ? `${styles.word} ${styles.accentGreen}` : styles.word
                      }
                      data-word
                      style={wordIndex(index)}
                    >
                      {word}
                    </span>
                  </span>
                );
              })}
            </span>
          ))}
        </h1>
        <p className={styles.lede} data-rise style={wordIndex(4)}>
          Rule-based Strategy Tokens over{" "}
          <span className={styles.accentGreen}>tokenized stocks</span>.
        </p>
        <div className={styles.actions}>
          <span data-rise style={wordIndex(6)}>
            <ButtonLink href="/create" className={styles.cta}>
              Create a strategy
              <Bolt />
            </ButtonLink>
          </span>
          <span data-rise style={wordIndex(7)}>
            <ButtonLink href="/positions" variant="secondary" className={styles.cta}>
              Your positions
            </ButtonLink>
          </span>
        </div>
      </RevealScope>
    </section>
  );
}
