import Image from "next/image";
import { StrategyLogo } from "@/components/art/strategy-logo";

export function StrategyDetailBanner({ vault, symbol, depth }: { vault: string; symbol?: string; depth: number }) {
  return (
    <div className="detail-banner">
      <Image className="detail-banner__tile" data-side="left" src="/img/dl-tile-violet-left.png" alt="" width={81} height={60} aria-hidden="true" />
      <Image className="detail-banner__tile" data-side="right" src="/img/dl-tile-dark-small.png" alt="" width={73} height={68} aria-hidden="true" />
      <StrategyLogo seed={vault} symbol={symbol} depth={depth} size="6.5rem" />
    </div>
  );
}
