import type { ReactNode } from "react";

export type BadgeTone = "violet" | "orchid" | "mint" | "amber" | "danger" | "neutral";

export function Badge({ tone = "neutral", children }: { tone?: BadgeTone; children: ReactNode }) {
  return (
    <span className="badge" data-tone={tone}>
      {children}
    </span>
  );
}
