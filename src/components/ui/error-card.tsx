import { Button } from "@/components/ui/button";
import { StateCard } from "@/components/ui/state-card";
import { describeError } from "@/lib/errors";

export function ErrorCard({
  title,
  summary,
  error,
  onRetry,
}: {
  title: string;
  summary: string;
  error: unknown;
  onRetry?: () => void;
}) {
  return (
    <StateCard
      art="error"
      role="alert"
      title={title}
      actions={onRetry ? <Button onClick={onRetry}>Try again</Button> : undefined}
    >
      <p>{summary}</p>
      <p className="text-caption text-ink-muted">{describeError(error)}</p>
    </StateCard>
  );
}
