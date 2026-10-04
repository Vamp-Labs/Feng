import { gsap, ScrollTrigger } from "@/lib/gsap";
import { GSAP_EASE } from "@/lib/motion";
import { first, type SceneEnv } from "./env";

const POINTER_DURATION = 0.9;

type HeroTile = {
  id: string;
  parallax: { desktop: number; mobile: number } | null;
  pointer: { x: number; y: number };
};

const TILES: readonly HeroTile[] = [
  { id: "purple", parallax: { desktop: 36, mobile: 14 }, pointer: { x: 5, y: 3 } },
  { id: "squares", parallax: null, pointer: { x: 10, y: 6 } },
  { id: "play", parallax: { desktop: -80, mobile: -28 }, pointer: { x: 16, y: 10 } },
];

export function buildHero({ root, mobile, finePointer, track }: SceneEnv) {
  const hero = first(root, "[data-hero]");
  const parts = TILES.map((spec) => {
    const tile = first(hero, `[data-tile="${spec.id}"]`);
    return {
      spec,
      depth: first(tile, "[data-tile-depth]"),
      pointer: first(tile, "[data-tile-pointer]"),
    };
  });

  const scrub = gsap.timeline({
    defaults: { ease: GSAP_EASE.scrub },
    scrollTrigger: { trigger: hero, start: "top top", end: "bottom top", scrub: true },
  });
  parts.forEach((part) => {
    if (!part.spec.parallax) return;
    const distance = mobile ? part.spec.parallax.mobile : part.spec.parallax.desktop;
    scrub.fromTo(part.depth, { y: 0 }, { y: distance }, 0);
  });

  let inView = false;
  const applyVisibility = () => {
    hero.toggleAttribute("data-paused", !(inView && !document.hidden));
  };
  const view = ScrollTrigger.create({
    trigger: hero,
    start: "top bottom",
    end: "bottom top",
    onToggle: (self) => {
      inView = self.isActive;
      applyVisibility();
    },
  });
  inView = view.isActive;
  applyVisibility();
  document.addEventListener("visibilitychange", applyVisibility);
  track(() => {
    document.removeEventListener("visibilitychange", applyVisibility);
    hero.removeAttribute("data-paused");
  });

  if (finePointer && !mobile) {
    const movers = parts.map((part) => ({
      setX: gsap.quickTo(part.pointer, "x", { duration: POINTER_DURATION, ease: GSAP_EASE.out }),
      setY: gsap.quickTo(part.pointer, "y", { duration: POINTER_DURATION, ease: GSAP_EASE.out }),
      reachX: part.spec.pointer.x,
      reachY: part.spec.pointer.y,
    }));
    let width = window.innerWidth;
    let height = window.innerHeight;
    const onResize = () => {
      width = window.innerWidth;
      height = window.innerHeight;
    };
    const onMove = (event: PointerEvent) => {
      if (!inView || document.hidden) return;
      const nx = (event.clientX / width) * 2 - 1;
      const ny = (event.clientY / height) * 2 - 1;
      for (const mover of movers) {
        mover.setX(nx * mover.reachX);
        mover.setY(ny * mover.reachY);
      }
    };
    const onLeave = () => {
      for (const mover of movers) {
        mover.setX(0);
        mover.setY(0);
      }
    };
    window.addEventListener("pointermove", onMove, { passive: true });
    window.addEventListener("resize", onResize, { passive: true });
    document.documentElement.addEventListener("pointerleave", onLeave);
    track(() => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("resize", onResize);
      document.documentElement.removeEventListener("pointerleave", onLeave);
    });
  }
}
