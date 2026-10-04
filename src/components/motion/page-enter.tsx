"use client";

import { useLayoutEffect, useRef, type ReactNode } from "react";

let hasEntered = false;

export function PageEnter({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    if (hasEntered) ref.current?.setAttribute("data-enter", "");
    hasEntered = true;
  }, []);

  return (
    <div ref={ref} className="page-enter">
      {children}
    </div>
  );
}
