"use client";

import { m } from "framer-motion";
import type { ReactNode } from "react";
import { EASE_OUT, LIST_ITEM_SECONDS, REVEAL_DISTANCE } from "@/lib/motion";

const IN_VIEW = { once: true, margin: "0px 0px -8% 0px" } as const;

export function Reveal({
  children,
  className,
  delay = 0,
}: {
  children: ReactNode;
  className?: string;
  delay?: number;
}) {
  return (
    <m.div
      className={className}
      initial={{ opacity: 0, y: REVEAL_DISTANCE }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={IN_VIEW}
      transition={{ duration: LIST_ITEM_SECONDS, ease: EASE_OUT, delay }}
    >
      {children}
    </m.div>
  );
}
