"use client";

import "lenis/dist/lenis.css";
import { useEffect, useMemo, useRef, type ReactNode } from "react";
import { ReactLenis, type LenisRef } from "lenis/react";
import { cancelFrame, frame } from "framer-motion";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";

const LENIS_LERP = 0.1;

export function SmoothScroll({ children }: { children: ReactNode }) {
  const lenisRef = useRef<LenisRef>(null);
  const reduceMotion = usePrefersReducedMotion();
  const options = useMemo(
    () => ({ autoRaf: false, lerp: reduceMotion ? 1 : LENIS_LERP, smoothWheel: !reduceMotion, anchors: true }),
    [reduceMotion],
  );

  useEffect(() => {
    const update = ({ timestamp }: { timestamp: number }) => lenisRef.current?.lenis?.raf(timestamp);
    frame.update(update, true);
    return () => cancelFrame(update);
  }, []);

  return (
    <ReactLenis root ref={lenisRef} options={options}>
      {children}
    </ReactLenis>
  );
}
