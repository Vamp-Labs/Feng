"use client";

import { useMediaQuery } from "@/lib/hooks/use-media-query";

export function useFinePointer(): boolean {
  return useMediaQuery("(hover: hover) and (pointer: fine)");
}
