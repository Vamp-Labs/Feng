export type CarouselPhase = "ssr" | "stacked" | "in";

export type SlotPose = {
  x: string;
  y: string;
  scale: number;
  rotateZ: number;
  rotateY: number;
  opacity: number;
  zIndex: number;
};

const SIDE_POSES: Record<"-1" | "1", SlotPose> = {
  "-1": { x: "-90.8%", y: "15.1%", scale: 0.881, rotateZ: -9.1, rotateY: 0, opacity: 1, zIndex: 2 },
  "1": { x: "90.2%", y: "15.5%", scale: 0.8826, rotateZ: 9.8, rotateY: 0, opacity: 1, zIndex: 2 },
};

const FAR_X_PERCENT = 165;
const FAR_Y_PERCENT = 27;
const FAR_ROTATION = 12;
const FAR_TILT = 14;
const FAR_SCALE = 0.8;

export const ENTRY_POSE: SlotPose = {
  x: "0%",
  y: "7%",
  scale: 0.88,
  rotateZ: 0,
  rotateY: 0,
  opacity: 0,
  zIndex: 1,
};

export function slotOf(index: number, active: number, count: number): number {
  const half = Math.floor(count / 2);
  return ((((index - active + half) % count) + count) % count) - half;
}

export function poseForSlot(slot: number): SlotPose {
  if (slot === 0) {
    return { x: "0%", y: "0%", scale: 1, rotateZ: 0, rotateY: 0, opacity: 1, zIndex: 3 };
  }
  const sign = Math.sign(slot);
  if (slot === -1 || slot === 1) return SIDE_POSES[String(slot) as "-1" | "1"];
  return {
    x: `${sign * FAR_X_PERCENT}%`,
    y: `${FAR_Y_PERCENT}%`,
    scale: FAR_SCALE,
    rotateZ: sign * FAR_ROTATION,
    rotateY: sign * FAR_TILT,
    opacity: 0,
    zIndex: 1,
  };
}
