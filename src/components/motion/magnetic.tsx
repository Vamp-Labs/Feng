"use client";

import { m, useMotionValue, useReducedMotion, useSpring } from "framer-motion";
import { useEffect, useRef, type ReactNode } from "react";
import { useFinePointer } from "@/lib/hooks/use-fine-pointer";

const PULL_RADIUS = 40;
const PULL_STRENGTH = 0.25;
const PULL_LIMIT = 8;
const MAGNET_SPRING = { stiffness: 300, damping: 22, mass: 0.6 } as const;
const REMEASURE_MS = 120;

const INLINE_STYLE = { display: "inline-flex" } as const;
const FILL_STYLE = { display: "flex", width: "100%", height: "100%" } as const;

type Anchor = { x: number; y: number; halfWidth: number; halfHeight: number };

type MagneticProps = { children: ReactNode; className?: string; disabled?: boolean; fill?: boolean };

export function Magnetic({ children, className, disabled = false, fill = false }: MagneticProps) {
  const finePointer = useFinePointer();
  const reduced = useReducedMotion();
  const enabled = finePointer && !reduced && !disabled;
  const slot = useRef<HTMLSpanElement>(null);
  const rawX = useMotionValue(0);
  const rawY = useMotionValue(0);
  const x = useSpring(rawX, MAGNET_SPRING);
  const y = useSpring(rawY, MAGNET_SPRING);

  useEffect(() => {
    const element = slot.current;
    if (!enabled || !element) return;

    let anchor: Anchor = { x: 0, y: 0, halfWidth: 0, halfHeight: 0 };
    let pulled = false;
    let measuredAt = 0;

    const measure = () => {
      measuredAt = performance.now();
      const rect = element.getBoundingClientRect();
      anchor = {
        x: rect.left + window.scrollX + rect.width / 2,
        y: rect.top + window.scrollY + rect.height / 2,
        halfWidth: rect.width / 2,
        halfHeight: rect.height / 2,
      };
    };

    const clamp = (value: number) => Math.max(-PULL_LIMIT, Math.min(PULL_LIMIT, value));

    const release = () => {
      if (!pulled) return;
      pulled = false;
      rawX.set(0);
      rawY.set(0);
    };

    const onMove = (event: PointerEvent) => {
      if (event.timeStamp - measuredAt > REMEASURE_MS) measure();
      const dx = event.pageX - anchor.x;
      const dy = event.pageY - anchor.y;
      const outsideX = Math.max(Math.abs(dx) - anchor.halfWidth, 0);
      const outsideY = Math.max(Math.abs(dy) - anchor.halfHeight, 0);
      if (Math.hypot(outsideX, outsideY) > PULL_RADIUS) {
        release();
        return;
      }
      pulled = true;
      rawX.set(clamp(dx * PULL_STRENGTH));
      rawY.set(clamp(dy * PULL_STRENGTH));
    };

    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    window.addEventListener("pointermove", onMove, { passive: true });
    document.documentElement.addEventListener("pointerleave", release);

    return () => {
      observer.disconnect();
      window.removeEventListener("pointermove", onMove);
      document.documentElement.removeEventListener("pointerleave", release);
      rawX.set(0);
      rawY.set(0);
    };
  }, [enabled, rawX, rawY]);

  return (
    <span ref={slot} className={className} style={fill ? FILL_STYLE : INLINE_STYLE}>
      <m.span style={{ ...(fill ? FILL_STYLE : INLINE_STYLE), x, y }}>{children}</m.span>
    </span>
  );
}
