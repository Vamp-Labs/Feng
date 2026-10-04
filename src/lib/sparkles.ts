export type Sparkle = {
  x: number;
  y: number;
  size: number;
  color: string;
  opacity: number;
  kind: "rise" | "twinkle";
  duration: number;
  delay: number;
  rise: number;
  drift: number;
};

export const SPARKLES: readonly Sparkle[] = [
  { x: 245, y: 934, size: 5.0, color: "#4535da", opacity: 0.94, kind: "rise", duration: 5.2, delay: -0.0, rise: 180, drift: -18 },
  { x: 163, y: 926, size: 5.6, color: "#463edf", opacity: 0.97, kind: "rise", duration: 7.4, delay: -1.37, rise: 260, drift: 14 },
  { x: 272, y: 988, size: 6.0, color: "#7856ff", opacity: 1, kind: "twinkle", duration: 2.2, delay: -0.54, rise: 220, drift: -26 },
  { x: 792, y: 994, size: 6.0, color: "#612ab7", opacity: 0.69, kind: "rise", duration: 8.6, delay: -4.11, rise: 340, drift: 22 },
  { x: 226, y: 959, size: 4.0, color: "#6d59f8", opacity: 1, kind: "rise", duration: 5.8, delay: -5.48, rise: 200, drift: 10 },
  { x: 300, y: 1034, size: 4.0, color: "#6334f4", opacity: 1, kind: "twinkle", duration: 2.6, delay: -1.65, rise: 300, drift: -12 },
  { x: 277, y: 1001, size: 5.0, color: "#633be5", opacity: 0.93, kind: "rise", duration: 5.2, delay: -3.02, rise: 180, drift: -18 },
  { x: 303, y: 999, size: 4.4, color: "#4026be", opacity: 0.67, kind: "rise", duration: 7.4, delay: -2.19, rise: 260, drift: 14 },
  { x: 280, y: 990, size: 4.0, color: "#4428c8", opacity: 0.7, kind: "twinkle", duration: 1.8, delay: -0.16, rise: 220, drift: -26 },
  { x: 224, y: 968, size: 4.4, color: "#5c48f5", opacity: 1, kind: "rise", duration: 8.6, delay: -3.73, rise: 340, drift: 22 },
  { x: 279, y: 1019, size: 4.0, color: "#623bed", opacity: 0.96, kind: "rise", duration: 5.8, delay: -2.1, rise: 200, drift: 10 },
  { x: 775, y: 1285, size: 5.0, color: "#4023b0", opacity: 0.54, kind: "twinkle", duration: 3.0, delay: -0.07, rise: 300, drift: -12 },
  { x: 280, y: 1050, size: 4.0, color: "#764afb", opacity: 1, kind: "rise", duration: 5.2, delay: -0.84, rise: 180, drift: -18 },
  { x: 301, y: 1022, size: 4.0, color: "#5128c9", opacity: 0.67, kind: "rise", duration: 7.4, delay: -3.01, rise: 260, drift: 14 },
  { x: 270, y: 915, size: 4.0, color: "#151871", opacity: 0.45, kind: "twinkle", duration: 2.2, delay: -1.58, rise: 220, drift: -26 },
  { x: 675, y: 1112, size: 6.0, color: "#361074", opacity: 0.45, kind: "rise", duration: 8.6, delay: -3.35, rise: 340, drift: 22 },
  { x: 646, y: 1149, size: 5.0, color: "#4c1592", opacity: 0.45, kind: "rise", duration: 5.8, delay: -4.52, rise: 200, drift: 10 },
  { x: 165, y: 1223, size: 5.0, color: "#2a24b5", opacity: 0.5, kind: "twinkle", duration: 2.6, delay: -2.49, rise: 300, drift: -12 },
  { x: 252, y: 1281, size: 5.0, color: "#2626ac", opacity: 0.47, kind: "rise", duration: 5.2, delay: -3.86, rise: 180, drift: -18 },
  { x: 872, y: 1209, size: 5.0, color: "#5527e4", opacity: 0.73, kind: "rise", duration: 7.4, delay: -3.83, rise: 260, drift: 14 },
  { x: 285, y: 1003, size: 3.0, color: "#4b30c5", opacity: 0.65, kind: "twinkle", duration: 1.8, delay: -0.4, rise: 220, drift: -26 },
  { x: 756, y: 1013, size: 4.0, color: "#2f1772", opacity: 0.45, kind: "rise", duration: 8.6, delay: -2.97, rise: 340, drift: 22 },
  { x: 280, y: 1067, size: 5.6, color: "#784bfc", opacity: 1, kind: "rise", duration: 5.8, delay: -1.14, rise: 200, drift: 10 },
  { x: 197, y: 899, size: 4.0, color: "#181c81", opacity: 0.45, kind: "twinkle", duration: 3.0, delay: -1.51, rise: 300, drift: -12 },
];

export const MOBILE_SPARKLE_COUNT = 12;
