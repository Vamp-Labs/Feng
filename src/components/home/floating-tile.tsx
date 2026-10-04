import Image from "next/image";
import type { CSSProperties } from "react";
import { canvasBox, cssVars, type RefBox } from "@/lib/geometry";
import styles from "./floating-tile.module.css";

export type TileMotion = {
  rotate: number;
  delay: number;
  float: { y: number; rotate: number; seconds: number };
  phase?: number;
};

type FloatingTileProps = {
  id: string;
  src: string;
  box: RefBox;
  nativeSize: readonly [width: number, height: number];
  originRefY?: number;
  glow: string;
  priority?: boolean;
  mobile?: CSSProperties;
  hiddenOnMobile?: boolean;
  className?: string;
  enter: TileMotion;
  sceneReveal?: boolean;
  floatOnMobile?: boolean;
};

export function FloatingTile({
  id,
  src,
  box,
  nativeSize,
  originRefY = 0,
  glow,
  priority = false,
  mobile,
  hiddenOnMobile = false,
  className,
  enter,
  sceneReveal = false,
  floatOnMobile = true,
}: FloatingTileProps) {
  const style: CSSProperties = {
    ...canvasBox(box, originRefY),
    ...cssVars({
      "--glow": glow,
      "--aspect": `${box[2]} / ${box[3]}`,
      "--enter-rotate": `${enter.rotate}deg`,
      "--enter-delay": `${enter.delay}s`,
      "--float-y": enter.float.y,
      "--float-rotate": enter.float.rotate,
      "--float-seconds": `${enter.float.seconds}s`,
      "--float-phase": `${enter.phase ?? 0}s`,
    }),
    ...(mobile ?? {}),
  };
  const revealAttr = sceneReveal ? "" : undefined;

  return (
    <div
      className={`${styles.tile} ${className ?? ""}`}
      style={style}
      data-tile={id}
      data-mobile={hiddenOnMobile ? "hidden" : undefined}
      data-float-mobile={floatOnMobile ? undefined : "off"}
      aria-hidden="true"
    >
      <div className={styles.depth} data-tile-depth>
        <div className={styles.pointer} data-tile-pointer>
          <div className={styles.float} data-tile-float>
            <span className={styles.halo} data-tile-halo data-reveal={revealAttr} />
            <Image
              className={styles.art}
              src={src}
              alt=""
              width={nativeSize[0]}
              height={nativeSize[1]}
              priority={priority}
              data-tile-art
              data-reveal={revealAttr}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
