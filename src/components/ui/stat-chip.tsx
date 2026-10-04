import type { ReactNode } from "react";

export function StatChip({
  label,
  value,
  tone = "default",
}: {
  label: string;
  value: ReactNode;
  tone?: "default" | "accent";
}) {
  return (
    <dl className="stat-chip" data-tone={tone}>
      <dt>{label}</dt>
      <dd className="text-stat-sm">{value}</dd>
    </dl>
  );
}
