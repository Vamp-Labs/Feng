import Link from "next/link";
import type { ComponentPropsWithoutRef, ComponentPropsWithRef } from "react";
import { cn } from "@/lib/cn";

type ButtonVariant = "primary" | "secondary" | "ghost" | "light" | "danger";
type ButtonSize = "md" | "sm";

interface ButtonStyleProps {
  variant?: ButtonVariant;
  size?: ButtonSize;
}

export function Button({
  variant = "primary",
  size = "md",
  className,
  type = "button",
  ...props
}: ButtonStyleProps & ComponentPropsWithRef<"button">) {
  return (
    <button
      type={type}
      className={cn("button", className)}
      data-variant={variant}
      data-size={size}
      {...props}
    />
  );
}

export function ButtonLink({
  variant = "primary",
  size = "md",
  className,
  ...props
}: ButtonStyleProps & ComponentPropsWithoutRef<typeof Link>) {
  return (
    <Link className={cn("button", className)} data-variant={variant} data-size={size} {...props} />
  );
}
