"use client";

import { buildHero } from "@/lib/scenes/hero";
import type { SceneEnv } from "@/lib/scenes/env";
import { buildPortfolio } from "@/lib/scenes/portfolio";
import { useSceneMotion } from "./use-scene-motion";

function buildHome(env: SceneEnv) {
  buildHero(env);
  buildPortfolio(env);
}

export function HomeMotion() {
  const anchor = useSceneMotion(buildHome);
  return <span ref={anchor} hidden />;
}
