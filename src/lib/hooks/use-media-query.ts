"use client";

import { useSyncExternalStore } from "react";

type Store = {
  subscribe: (notify: () => void) => () => void;
  getSnapshot: () => boolean;
};

const stores = new Map<string, Store>();

function storeFor(query: string): Store {
  const cached = stores.get(query);
  if (cached) return cached;
  let list: MediaQueryList | undefined;
  const read = () => (list ??= window.matchMedia(query));
  const store: Store = {
    subscribe(notify) {
      const current = read();
      current.addEventListener("change", notify);
      return () => current.removeEventListener("change", notify);
    },
    getSnapshot: () => read().matches,
  };
  stores.set(query, store);
  return store;
}

export function useMediaQuery(query: string, serverValue = false): boolean {
  const store = storeFor(query);
  return useSyncExternalStore(store.subscribe, store.getSnapshot, () => serverValue);
}
