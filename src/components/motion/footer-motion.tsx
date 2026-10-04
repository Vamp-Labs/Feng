"use client";

import { buildFooter } from "@/lib/scenes/footer";
import { useSceneMotion } from "./use-scene-motion";

export function FooterMotion() {
  const anchor = useSceneMotion(buildFooter);
  return <span ref={anchor} hidden />;
}
