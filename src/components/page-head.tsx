import Image from "next/image";
import type { CSSProperties, ReactNode } from "react";
import { RevealScope } from "@/components/motion/reveal-scope";
import { Words, wordIndex } from "@/components/words";

const TILE_STYLE_LEFT = { "--tile-size": "5.5rem", "--float-seconds": "6.4s" } as CSSProperties;
const TILE_STYLE_RIGHT = { "--tile-size": "4.5rem", "--float-seconds": "7.6s", "--float-phase": "2.4s" } as CSSProperties;

export function PageHead({
  introKey,
  eyebrow,
  title,
  accent,
  children,
}: {
  introKey: string;
  eyebrow: string;
  title: string;
  accent?: string;
  children?: ReactNode;
}) {
  return (
    <header className="page-head">
      <div className="page-head__backdrop" aria-hidden="true" />
      <Image
        className="page-head__tile"
        data-side="left"
        style={TILE_STYLE_LEFT}
        src="/img/hero-tile-purple.png"
        alt=""
        width={94}
        height={69}
        aria-hidden="true"
      />
      <Image
        className="page-head__tile"
        data-side="right"
        style={TILE_STYLE_RIGHT}
        src="/img/hero-tile-play-green.png"
        alt=""
        width={170}
        height={110}
        aria-hidden="true"
      />
      <RevealScope introKey={introKey} className="page-head__inner">
        <span className="tag" data-rise>
          {eyebrow}
        </span>
        <h1 className="page-head__title text-display">
          <Words text={title} accent={accent} />
        </h1>
        {children ? (
          <p className="page-head__lead text-lead" data-rise style={wordIndex(2)}>
            {children}
          </p>
        ) : null}
      </RevealScope>
    </header>
  );
}
