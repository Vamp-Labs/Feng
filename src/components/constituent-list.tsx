import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { RankBar } from "@/components/ui/rank-bar";
import { formatBps, shortenAddress } from "@/lib/format";
import type { ConstituentDetail } from "@/lib/hooks/use-strategy-detail";

const DOT_TONES = ["violet", "orchid", "mint", "sky"] as const;

export function ConstituentList({ constituents }: { constituents: ConstituentDetail[] }) {
  if (constituents.length === 0) {
    return <p className="text-caption text-ink-muted">No constituents to show yet.</p>;
  }

  return (
    <div className="flex flex-col gap-5">
      {constituents.map((c, index) => (
        <div key={c.token} className="flex flex-col gap-2">
          <div className="flex items-center justify-between gap-3">
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
              <span className="coin-dot" data-tone={DOT_TONES[index % DOT_TONES.length]} aria-hidden="true">
                {(c.symbol ?? "?").charAt(0).toUpperCase()}
              </span>
              <span className="text-label whitespace-nowrap text-ink">{c.symbol ?? shortenAddress(c.token)}</span>
              {c.isStrategyToken && c.nestedVault ? (
                <Link href={`/strategy/${c.nestedVault}`} className="rounded-full">
                  <Badge tone="orchid">Nested Strategy</Badge>
                </Link>
              ) : c.isStrategyToken ? (
                <Badge tone="orchid">Nested Strategy</Badge>
              ) : null}
            </div>
            <span className="text-stat-sm text-ink">{formatBps(c.targetWeightBps)}</span>
          </div>
          <RankBar percent={c.targetWeightBps / 100} />
        </div>
      ))}
    </div>
  );
}
