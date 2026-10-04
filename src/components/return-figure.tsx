import { formatReturn, returnSign } from "@/lib/inception";
import { cn } from "@/lib/cn";
import styles from "./return-figure.module.css";

export function ReturnFigure({ value, className, title }: { value: number | undefined; className?: string; title?: string }) {
  return (
    <span className={cn(styles.figure, className)} data-sign={returnSign(value)} title={title}>
      {formatReturn(value)}
    </span>
  );
}
