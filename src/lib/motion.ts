export type Bezier = [number, number, number, number];

export const EASE_OUT: Bezier = [0.215, 0.61, 0.355, 1];
export const EASE_EXPO: Bezier = [0.16, 1, 0.3, 1];
export const EASE_SPRING: Bezier = [0.34, 1.56, 0.64, 1];
export const EASE_IN_OUT: Bezier = [0.45, 0, 0.55, 1];
export const EASE_LINEAR: Bezier = [0, 0, 1, 1];

export const LIST_STAGGER_SECONDS = 0.07;
export const LIST_ITEM_SECONDS = 0.5;
export const VALUE_TWEEN_SECONDS = 0.4;

export const SEGMENT_SPRING = { type: "spring", stiffness: 520, damping: 38 } as const;

export const DURATION = {
  xs: 0.12,
  sm: 0.24,
  md: 0.48,
  lg: 0.72,
  xl: 1.1,
} as const;

export const STAGGER = {
  word: 0.07,
  line: 0.06,
  item: 0.08,
} as const;

export const REVEAL_DISTANCE = 16;
export const REVEAL_FAILSAFE_MS = 1800;

export const GSAP_EASE = {
  out: "power3.out",
  inOut: "power2.inOut",
  pop: "back.out(1.5)",
  float: "sine.inOut",
  scrub: "none",
} as const;

export const SPRING = {
  pop: { type: "spring", stiffness: 500, damping: 20 },
  snap: { type: "spring", stiffness: 400, damping: 30 },
  orbit: { type: "spring", stiffness: 240, damping: 28, mass: 1 },
} as const;
