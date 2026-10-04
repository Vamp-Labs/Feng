"use client";

import { m, useReducedMotion } from "framer-motion";
import { EASE_OUT, VALUE_TWEEN_SECONDS } from "@/lib/motion";

const OUTLINE_EXTRA = 2;

export function ProgressRing({
  percent,
  size = 112,
  strokeWidth = 12,
  complete = false,
  label,
}: {
  percent: number;
  size?: number;
  strokeWidth?: number;
  complete?: boolean;
  label?: string;
}) {
  const clamped = Math.max(0, Math.min(100, percent));
  const radius = (size - strokeWidth - OUTLINE_EXTRA) / 2;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (clamped / 100) * circumference;
  const reduceMotion = useReducedMotion();
  const tween = { duration: reduceMotion ? 0 : VALUE_TWEEN_SECONDS, ease: EASE_OUT };

  return (
    <div className="relative inline-flex items-center justify-center" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90" aria-hidden="true">
        <circle
          className="ring__track"
          cx={size / 2}
          cy={size / 2}
          r={radius}
          strokeWidth={strokeWidth}
        />
        <m.circle
          className="ring__outline"
          cx={size / 2}
          cy={size / 2}
          r={radius}
          strokeWidth={clamped > 0 ? strokeWidth + OUTLINE_EXTRA : 0}
          strokeDasharray={circumference}
          initial={false}
          animate={{ strokeDashoffset: offset }}
          transition={tween}
        />
        <m.circle
          className="ring__value"
          data-complete={complete ? "" : undefined}
          cx={size / 2}
          cy={size / 2}
          r={radius}
          strokeWidth={clamped > 0 ? strokeWidth - OUTLINE_EXTRA : 0}
          strokeDasharray={circumference}
          initial={false}
          animate={{ strokeDashoffset: offset }}
          transition={tween}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-hud text-ink">{Math.round(clamped)}%</span>
        {label ? <span className="text-micro text-ink-muted">{label}</span> : null}
      </div>
    </div>
  );
}
