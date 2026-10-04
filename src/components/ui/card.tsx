import Link from "next/link";
import type { ComponentPropsWithoutRef } from "react";
import { cn } from "@/lib/cn";

export type CardTone = "violet" | "mint";
export type CardVariant = "glass" | "flat";

interface CardStyleProps {
  variant?: CardVariant;
  tone?: CardTone;
}

export function Card({
  variant = "flat",
  tone,
  className,
  ...props
}: CardStyleProps & ComponentPropsWithoutRef<"div">) {
  return <div className={cn("card", className)} data-variant={variant} data-tone={tone} {...props} />;
}

export function CardLink({
  variant = "glass",
  tone,
  className,
  ...props
}: CardStyleProps & ComponentPropsWithoutRef<typeof Link>) {
  return (
    <Link
      className={cn("card", className)}
      data-variant={variant}
      data-tone={tone}
      data-interactive=""
      {...props}
    />
  );
}
