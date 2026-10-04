import { useCallback, useRef } from "react";
import { gsap, ScrollTrigger, useGSAP } from "@/lib/gsap";
import { REVEAL_FAILSAFE_MS } from "@/lib/motion";
import type { SceneEnv } from "@/lib/scenes/env";

const FONT_WAIT_MS = 1200;

const QUERIES = {
  motion: "(prefers-reduced-motion: no-preference)",
  reduce: "(prefers-reduced-motion: reduce)",
  desktop: "(min-width: 1000px)",
  mobile: "(max-width: 999px)",
  fine: "(hover: hover) and (pointer: fine)",
};

function fontsSettled(): Promise<unknown> {
  if (typeof document === "undefined" || !document.fonts) return Promise.resolve();
  let timer = 0;
  const timeout = new Promise((resolve) => {
    timer = window.setTimeout(resolve, FONT_WAIT_MS);
  });
  return Promise.race([document.fonts.ready, timeout]).finally(() => window.clearTimeout(timer));
}

export function useSceneMotion(build: (env: SceneEnv) => void) {
  const rootRef = useRef<HTMLElement | null>(null);
  const anchor = useCallback((node: HTMLElement | null) => {
    rootRef.current = node?.closest<HTMLElement>("[data-anim]") ?? null;
  }, []);

  useGSAP(
    () => {
      const root = rootRef.current;
      if (!root) return;

      const mm = gsap.matchMedia();
      mm.add(QUERIES, (context, contextSafe) => {
        const { motion, mobile, fine } = context.conditions ?? {};
        if (!motion || !contextSafe) {
          root.dataset.anim = "ready";
          return;
        }

        let cancelled = false;
        const cleanups: Array<() => void> = [];
        const starts: Array<() => void> = [];
        const env: SceneEnv = {
          root,
          mobile: Boolean(mobile),
          finePointer: Boolean(fine),
          late: false,
          track: (cleanup) => cleanups.push(cleanup),
          start: (play) => starts.push(play),
        };

        const run = contextSafe(() => {
          if (cancelled) return;
          env.late = performance.now() > REVEAL_FAILSAFE_MS;
          try {
            build(env);
            ScrollTrigger.refresh();
          } catch (error) {
            console.error(error);
            mm.revert();
            root.dataset.anim = "ready";
            return;
          }
          starts.forEach((play) => play());
          root.dataset.anim = "ready";
        });

        fontsSettled().then(() => run(), () => run());

        return () => {
          cancelled = true;
          cleanups.forEach((cleanup) => cleanup());
        };
      });
    },
    { scope: rootRef },
  );

  return anchor;
}
