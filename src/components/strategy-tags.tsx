import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/cn";
import type { Universe } from "@/lib/protocol";

export function StrategyTags({
  tags,
  universe,
  className,
}: {
  tags?: readonly string[];
  universe?: Universe;
  className?: string;
}) {
  const hasTags = tags !== undefined && tags.length > 0;
  if (!hasTags && universe !== "live") return null;

  return (
    <ul className={cn("strategy-tags", className)} aria-label="Strategy labels">
      {universe === "live" ? (
        <li>
          <Badge tone="mint">Live assets</Badge>
        </li>
      ) : null}
      {tags?.map((tag) => (
        <li key={tag}>
          <span className="strategy-tag">#{tag}</span>
        </li>
      ))}
    </ul>
  );
}
