import type { ReactNode } from "react";
import { StateArt, type StateArtKind } from "@/components/art/state-art";
import { Card } from "./card";
import { cn } from "@/lib/cn";

export function StateCard({
  art,
  title,
  children,
  actions,
  role,
  className,
}: {
  art: StateArtKind;
  title: string;
  children?: ReactNode;
  actions?: ReactNode;
  role?: "alert" | "status";
  className?: string;
}) {
  return (
    <Card variant="glass" className={cn("state", className)} role={role}>
      <StateArt kind={art} />
      <p className="text-title text-ink">{title}</p>
      {children ? <div className="flex max-w-md flex-col gap-2 text-body text-ink-secondary">{children}</div> : null}
      {actions ? <div className="mt-2 flex flex-wrap justify-center gap-3">{actions}</div> : null}
    </Card>
  );
}
