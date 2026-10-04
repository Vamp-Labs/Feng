"use client";

import { useEffect, type ReactNode } from "react";

const INTRO_SETTLE_MS = 2600;

export function RevealScope({
  introKey,
  className,
  children,
}: {
  introKey: string;
  className?: string;
  children: ReactNode;
}) {
  useEffect(() => {
    const root = document.documentElement;
    const timer = window.setTimeout(() => {
      const played = new Set((root.dataset.played ?? "").split(" ").filter(Boolean));
      played.add(introKey);
      root.dataset.played = Array.from(played).join(" ");
    }, INTRO_SETTLE_MS);
    return () => window.clearTimeout(timer);
  }, [introKey]);

  return (
    <div className={className} data-intro={introKey}>
      {children}
    </div>
  );
}
