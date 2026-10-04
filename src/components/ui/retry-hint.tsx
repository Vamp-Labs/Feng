export function RetryHint({ active }: { active: boolean }) {
  return (
    <p className="text-caption text-ink-muted text-center" role="status" aria-live="polite">
      {active ? "The network is slow right now. Still trying…" : ""}
    </p>
  );
}
