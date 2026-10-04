import type { ComponentPropsWithoutRef, ReactNode } from "react";
import { cn } from "@/lib/cn";

interface IconButtonProps extends Omit<ComponentPropsWithoutRef<"button">, "children"> {
  children: ReactNode;
  label: string;
}

export function IconButton({ children, label, className, type = "button", ...props }: IconButtonProps) {
  return (
    <button
      type={type}
      aria-label={label}
      className={cn("button", className)}
      data-variant="secondary"
      data-size="sm"
      data-shape="round"
      {...props}
    >
      {children}
    </button>
  );
}
