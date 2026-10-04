"use client";

import { useEffect, useRef } from "react";

export function useRestoreFocus(busy: boolean) {
  const target = useRef<HTMLButtonElement>(null);
  const wasBusy = useRef(false);

  useEffect(() => {
    const button = target.current;
    if (wasBusy.current && !busy && button && document.activeElement === document.body) {
      if (button.disabled) button.parentElement?.querySelector<HTMLInputElement>("input")?.focus();
      else button.focus();
    }
    wasBusy.current = busy;
  }, [busy]);

  return target;
}
