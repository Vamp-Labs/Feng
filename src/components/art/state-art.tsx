import Image from "next/image";

export type StateArtKind = "empty" | "wallet" | "error" | "done";

const TILE = {
  empty: { src: "/img/hero-tile-squares.png", width: 94, height: 85 },
  wallet: { src: "/img/hero-tile-purple.png", width: 94, height: 69 },
  error: { src: "/img/dl-tile-dark-topright.png", width: 77, height: 71 },
  done: { src: "/img/dl-tile-clock-green.png", width: 211, height: 135 },
} as const;

export function StateArt({ kind }: { kind: StateArtKind }) {
  const tile = TILE[kind];
  return (
    <div className="state__art" data-kind={kind} aria-hidden="true">
      <Image src={tile.src} alt="" width={tile.width} height={tile.height} loading="eager" />
    </div>
  );
}
