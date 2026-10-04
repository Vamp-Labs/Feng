import { gsap, ScrollTrigger } from "@/lib/gsap";

export type SceneEnv = {
  root: HTMLElement;
  mobile: boolean;
  finePointer: boolean;
  late: boolean;
  track: (cleanup: () => void) => void;
  start: (play: () => void) => void;
};

const LAYOUT_REFRESH_DEBOUNCE_MS = 200;

const played = new WeakSet<Element>();
let refreshTimer = 0;

export function all<T extends HTMLElement | SVGElement = HTMLElement>(scope: ParentNode, selector: string): T[] {
  return Array.from(scope.querySelectorAll<T>(selector));
}

export function first<T extends HTMLElement | SVGElement = HTMLElement>(scope: ParentNode, selector: string): T {
  const node = scope.querySelector<T>(selector);
  if (!node) throw new Error(`motion: missing ${selector}`);
  return node;
}

export function createGate(loop: gsap.core.Timeline, armed = false, visible = true) {
  const sync = () => {
    loop.paused(!(armed && visible));
  };
  sync();
  return {
    arm() {
      armed = true;
      sync();
    },
    setVisible(next: boolean) {
      visible = next;
      sync();
    },
  };
}

export function revealOnce(
  env: Pick<SceneEnv, "late">,
  timeline: gsap.core.Timeline,
  trigger: Element,
  viewportRatio: number,
) {
  if (played.has(trigger)) {
    timeline.progress(1);
    return;
  }
  const start = revealStart(trigger, viewportRatio);
  const passedAtBuild = window.scrollY >= start();
  ScrollTrigger.create({
    trigger,
    start,
    once: true,
    onEnter: () => {
      played.add(trigger);
      if (env.late && passedAtBuild) timeline.progress(1);
      else timeline.play();
    },
  });
}

export function revealStart(trigger: Element, viewportRatio: number) {
  return () =>
    Math.min(
      trigger.getBoundingClientRect().top + window.scrollY - window.innerHeight * viewportRatio,
      ScrollTrigger.maxScroll(window) - 1,
    );
}

export function watchLayout(target: Element, track: SceneEnv["track"]) {
  if (typeof ResizeObserver === "undefined") return;
  let height = -1;
  const observer = new ResizeObserver(([entry]) => {
    const next = Math.round(entry.contentRect.height);
    const changed = height >= 0 && next !== height;
    height = next;
    if (!changed) return;
    window.clearTimeout(refreshTimer);
    refreshTimer = window.setTimeout(() => ScrollTrigger.refresh(), LAYOUT_REFRESH_DEBOUNCE_MS);
  });
  observer.observe(target);
  track(() => {
    observer.disconnect();
    window.clearTimeout(refreshTimer);
  });
}
