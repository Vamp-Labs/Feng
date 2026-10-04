import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { ReturnFigure } from "@/components/return-figure";
import { formatBpsPoints, formatSharePrice, formatUsdCompact, usdgToNumber } from "@/lib/discovery-format";
import { shortenAddress } from "@/lib/format";
import type { ConstituentDetail } from "@/lib/hooks/use-strategy-detail";

export function NestedComposition({
  constituents,
  usdgDecimals,
}: {
  constituents: readonly ConstituentDetail[];
  usdgDecimals: number | undefined;
}) {
  const nested = constituents.filter((constituent) => constituent.isStrategyToken);
  if (nested.length === 0) return null;

  return (
    <ul className="nested-list">
      {nested.map((constituent) => {
        const label = constituent.symbol ?? shortenAddress(constituent.token);
        const sharePrice =
          constituent.childSharePrice !== undefined && usdgDecimals !== undefined
            ? formatSharePrice(usdgToNumber(constituent.childSharePrice, usdgDecimals))
            : "--";
        return (
          <li key={constituent.token} className="nested-item">
            <div className="nested-item__head">
              <span className="text-label text-ink">{label}</span>
              <Badge tone="orchid">{formatBpsPoints(constituent.targetWeightBps)} of this strategy</Badge>
            </div>
            <dl className="nested-item__stats">
              <div>
                <dt>Child NAV</dt>
                <dd>{constituent.childNavUsd === undefined ? "--" : formatUsdCompact(constituent.childNavUsd)}</dd>
              </div>
              <div>
                <dt>NAV per share</dt>
                <dd>{sharePrice}</dd>
              </div>
              <div>
                <dt>Since inception</dt>
                <dd>
                  <ReturnFigure value={constituent.childSinceInception} />
                </dd>
              </div>
            </dl>
            {constituent.nestedVault ? (
              <Link className="nested-item__link" href={`/strategy/${constituent.nestedVault}`}>
                Open {label}
              </Link>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}
