import { useId, type CSSProperties } from "react";
import { cn } from "@/lib/cn";

export interface SparklinePoint {
  t: number;
  price: number;
}

interface SparklineProps {
  points: readonly SparklinePoint[];
  width: number;
  height: number;
  label: string;
  className?: string;
  loading?: boolean;
}

const PAD = 3;

function build(points: readonly SparklinePoint[], width: number, height: number) {
  const first = points[0];
  const last = points[points.length - 1];
  const prices = points.map((point) => point.price);
  const min = Math.min(...prices);
  const max = Math.max(...prices);
  const span = max - min;
  const timeSpan = last.t - first.t;
  const innerWidth = width - PAD * 2;
  const innerHeight = height - PAD * 2;

  const coords = points.map((point, index) => {
    const x = PAD + (timeSpan > 0 ? (point.t - first.t) / timeSpan : index / (points.length - 1)) * innerWidth;
    const y = span > 0 ? PAD + (1 - (point.price - min) / span) * innerHeight : height / 2;
    return [Number(x.toFixed(2)), Number(y.toFixed(2))] as const;
  });

  const line = coords.map(([x, y], index) => `${index === 0 ? "M" : "L"}${x} ${y}`).join(" ");
  const bottom = height - PAD;
  const area = `${line} L${coords[coords.length - 1][0]} ${bottom} L${coords[0][0]} ${bottom} Z`;
  const direction: "up" | "down" | "flat" = last.price > first.price ? "up" : last.price < first.price ? "down" : "flat";
  return { line, area, end: coords[coords.length - 1], direction };
}

export function Sparkline({ points, width, height, label, className, loading = false }: SparklineProps) {
  const gradientId = useId();
  const size = { "--spark-w": `${width}px`, "--spark-h": `${height}px` } as CSSProperties;

  if (points.length < 2) {
    return (
      <span
        className={cn("spark", className)}
        data-state={loading ? "loading" : "empty"}
        style={size}
        role="img"
        aria-label={loading ? "Loading price history" : "Not enough price history yet"}
      >
        <span aria-hidden="true">--</span>
      </span>
    );
  }

  const { line, area, end, direction } = build(points, width, height);

  return (
    <svg
      className={cn("spark", className)}
      data-direction={direction}
      style={size}
      viewBox={`0 0 ${width} ${height}`}
      role="img"
      aria-label={label}
    >
      <defs>
        <linearGradient id={gradientId} x1="0" x2="0" y1="0" y2="1">
          <stop offset="0%" stopColor="currentColor" stopOpacity="0.32" />
          <stop offset="100%" stopColor="currentColor" stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill={`url(#${gradientId})`} />
      <path d={line} className="spark__line" fill="none" strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={end[0]} cy={end[1]} r="2.25" className="spark__dot" />
    </svg>
  );
}
