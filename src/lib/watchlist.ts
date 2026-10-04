const STORAGE_KEY = "feng:watchlist:v1";
const CHANGE_EVENT = "feng:watchlist-change";
const EMPTY: readonly string[] = [];

export function watchKey(chainId: number, vault: string): string {
  return `${chainId}:${vault.toLowerCase()}`;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((entry) => typeof entry === "string");
}

let cachedRaw: string | null = null;
let cachedEntries: readonly string[] = EMPTY;

function readRaw(): string | null {
  try {
    return window.localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

export function readWatchlist(): readonly string[] {
  const raw = readRaw();
  if (raw === cachedRaw) return cachedEntries;
  cachedRaw = raw;
  if (raw === null) {
    cachedEntries = EMPTY;
    return cachedEntries;
  }
  try {
    const parsed: unknown = JSON.parse(raw);
    cachedEntries = isStringArray(parsed) ? parsed : EMPTY;
  } catch {
    cachedEntries = EMPTY;
  }
  return cachedEntries;
}

export function emptyWatchlist(): readonly string[] {
  return EMPTY;
}

export function toggleWatch(chainId: number, vault: string): void {
  const key = watchKey(chainId, vault);
  const current = readWatchlist();
  const next = current.includes(key) ? current.filter((entry) => entry !== key) : [...current, key];
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    return;
  }
  window.dispatchEvent(new Event(CHANGE_EVENT));
}

export function subscribeWatchlist(onChange: () => void): () => void {
  const onStorage = (event: StorageEvent) => {
    if (event.key === STORAGE_KEY || event.key === null) onChange();
  };
  window.addEventListener(CHANGE_EVENT, onChange);
  window.addEventListener("storage", onStorage);
  return () => {
    window.removeEventListener(CHANGE_EVENT, onChange);
    window.removeEventListener("storage", onStorage);
  };
}

const START_KEY = "feng:start:v1";
const START_EVENT = "feng:start-change";

export function readRebalanceSeen(): boolean {
  try {
    return window.localStorage.getItem(START_KEY) === "seen";
  } catch {
    return false;
  }
}

export function markRebalanceSeen(): void {
  try {
    window.localStorage.setItem(START_KEY, "seen");
  } catch {
    return;
  }
  window.dispatchEvent(new Event(START_EVENT));
}

export function subscribeRebalanceSeen(onChange: () => void): () => void {
  const onStorage = (event: StorageEvent) => {
    if (event.key === START_KEY || event.key === null) onChange();
  };
  window.addEventListener(START_EVENT, onChange);
  window.addEventListener("storage", onStorage);
  return () => {
    window.removeEventListener(START_EVENT, onChange);
    window.removeEventListener("storage", onStorage);
  };
}
