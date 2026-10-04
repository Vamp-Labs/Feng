import type { ReactNode } from "react";

export type NoticeTone = "warn" | "error" | "success";

export function Notice({
  tone = "warn",
  role,
  children,
}: {
  tone?: NoticeTone;
  role?: "alert" | "status";
  children: ReactNode;
}) {
  return (
    <div className="notice" data-tone={tone} role={role}>
      {children}
    </div>
  );
}
