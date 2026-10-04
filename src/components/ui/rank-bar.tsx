"use client";

import { m } from "framer-motion";
import { EASE_OUT, VALUE_TWEEN_SECONDS } from "@/lib/motion";
import { cn } from "@/lib/cn";

export function RankBar({
  percent,
  warn = false,
  className,
}: {
  percent: number;
  warn?: boolean;
  className?: string;
}) {
  const clamped = Math.max(0, Math.min(100, percent));
  const tween = { duration: VALUE_TWEEN_SECONDS, ease: EASE_OUT };
  return (
    <div className={cn("bar", className)}>
      <div className="bar__clip">
        <m.span
          className="bar__fill"
          data-warn={warn ? "" : undefined}
          initial={false}
          animate={{ scaleX: clamped / 100 }}
          transition={tween}
        />
      </div>
      {clamped > 0 && !warn ? (
        <m.span className="bar__knob" initial={false} animate={{ x: `${clamped - 100}%` }} transition={tween}>
          <span className="bar__dot" />
        </m.span>
      ) : null}
    </div>
  );
}
