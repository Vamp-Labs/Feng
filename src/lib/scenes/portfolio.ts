import { gsap } from "@/lib/gsap";
import { DURATION, GSAP_EASE, REVEAL_DISTANCE, STAGGER } from "@/lib/motion";
import { all, createGate, first, revealOnce, watchLayout, type SceneEnv } from "./env";

const RANK_SLAB_Y = 90;
const RANK_SLAB_TILT = 28;
const RANK_SLAB_MOBILE_DURATION = 0.9;
const COUNT_DURATION = 1.2;
const RING_DURATION = 1.1;
const COUNT_AT = 0.56;
const KNOB_PULSE_SCALE = 1.6;
const RAYS_FROM = { opacity: 0.15, scaleY: 0.82 };
const RAYS_SWAY = { opacity: 0.38, rotation: 1.4, scale: 1.03, duration: 17 };
const PARALLAX_DISTANCE = 36;
const PARALLAX_DISTANCE_MOBILE = 14;
const CENTER_PERCENT = { xPercent: -50, yPercent: -50 } as const;
const COUNT_SELECTOR = "[data-count]";

type PortfolioTile = { id: string; rotation: number; parallax?: boolean };

const LEAD_TILES: readonly PortfolioTile[] = [
  { id: "clock", rotation: -14, parallax: true },
  { id: "play", rotation: 14, parallax: true },
];

const TRAIL_TILES: readonly PortfolioTile[] = [
  { id: "violet-topleft", rotation: -14 },
  { id: "violet-left", rotation: 14 },
  { id: "dark-topright", rotation: -14 },
  { id: "violet-right", rotation: 14 },
  { id: "dark-small", rotation: -14 },
];

const numberFormat = new Intl.NumberFormat("en-US");

const easedRatio = (tween: gsap.core.Tween) => gsap.parseEase(GSAP_EASE.out)(tween.progress());

function writeCounts(scope: ParentNode, ratio: number) {
  for (const el of all(scope, COUNT_SELECTOR)) {
    if (el.dataset.count === undefined) continue;
    const target = Number(el.dataset.count);
    if (!Number.isFinite(target)) continue;
    const text = numberFormat.format(Math.round(target * ratio));
    if (el.textContent !== text) el.textContent = text;
  }
}

function settleCounts(scope: ParentNode) {
  for (const el of all(scope, COUNT_SELECTOR)) {
    if (el.dataset.count === undefined) continue;
    const target = Number(el.dataset.count);
    if (Number.isFinite(target)) el.textContent = String(target);
  }
}

export function buildPortfolio(env: SceneEnv) {
  const { root, mobile, track } = env;
  const section = first(root, "[data-portfolio]");
  const rays = first(section, "[data-rays]");
  const sway = first(section, "[data-rays-sway]");
  const sparkles = first(section, "[data-sparkles]");
  const scene = first(section, "[data-scene]");

  const rank = first(scene, "[data-rank]");
  const slab = first(rank, "[data-rank-slab]");
  const label = first(rank, "[data-rank-label]");
  const knob = first(rank, "[data-rank-knob]");
  const chips = all(rank, "[data-rank-chip]");
  const avatar = first(rank, "[data-rank-avatar]");

  const complete = first(scene, "[data-complete]");
  const completeDisc = first(complete, "[data-tile-art]");
  const completeRing = first(complete, "[data-complete-ring]");
  const completeText = first(complete, "[data-complete-text]");

  const tileParts = (specs: readonly PortfolioTile[]) =>
    specs.map((spec) => {
      const tile = first(scene, `[data-tile="${spec.id}"]`);
      return {
        spec,
        depth: first(tile, "[data-tile-depth]"),
        art: first(tile, "[data-tile-art]"),
        halo: first(tile, "[data-tile-halo]"),
      };
    });
  const lead = tileParts(LEAD_TILES);
  const trail = tileParts(TRAIL_TILES);
  const tiles = [...lead, ...trail];

  knob.style.scale = "var(--knob-pulse, 1)";
  track(() => {
    knob.style.removeProperty("scale");
    settleCounts(rank);
    settleCounts(complete);
  });

  gsap.fromTo(
    rays,
    { ...RAYS_FROM, xPercent: mobile ? -50 : 0, x: 0, transformOrigin: "50% 100%" },
    {
      opacity: 1,
      scaleY: 1,
      xPercent: mobile ? -50 : 0,
      x: 0,
      transformOrigin: "50% 100%",
      ease: GSAP_EASE.scrub,
      scrollTrigger: { trigger: section, start: "top 100%", end: "clamp(top 35%)", scrub: true },
    },
  );

  const ambient = gsap.timeline({ paused: true });
  ambient.fromTo(
    sway,
    { opacity: 0, rotation: -RAYS_SWAY.rotation, scale: 1, transformOrigin: "50% 100%" },
    {
      ...RAYS_SWAY,
      transformOrigin: "50% 100%",
      ease: GSAP_EASE.float,
      repeat: -1,
      yoyo: true,
      immediateRender: false,
    },
  );
  const ambientGate = createGate(ambient, true, false);

  const copy = gsap.timeline({ paused: true, defaults: { ease: GSAP_EASE.out } });
  copy
    .fromTo(
      all(section, "[data-word-scene]"),
      { yPercent: 110, y: 0 },
      { yPercent: 0, y: 0, duration: DURATION.lg, stagger: STAGGER.word },
      0,
    )
    .fromTo(
      first(section, "[data-portfolio-sub]"),
      { opacity: 0, y: REVEAL_DISTANCE },
      { opacity: 1, y: 0, duration: DURATION.md },
      0.12,
    )
    .fromTo(
      all(section, "[data-action]"),
      { opacity: 0, y: REVEAL_DISTANCE },
      { opacity: 1, y: 0, duration: DURATION.md, stagger: STAGGER.item },
      0.24,
    );
  revealOnce(env, copy, section, 0.85);

  const stage = gsap.timeline({
    paused: true,
    defaults: { ease: GSAP_EASE.out },
    onStart: () => {
      writeCounts(rank, 0);
      writeCounts(complete, 0);
    },
  });
  stage
    .fromTo(
      slab,
      { opacity: 0, y: RANK_SLAB_Y, scale: 0.9, rotationX: RANK_SLAB_TILT, transformOrigin: "50% 100%" },
      {
        opacity: 1,
        y: 0,
        scale: 1,
        rotationX: 0,
        transformOrigin: "50% 100%",
        duration: mobile ? RANK_SLAB_MOBILE_DURATION : DURATION.xl,
      },
      0,
    )
    .fromTo(
      avatar,
      { opacity: 0, y: 24, scale: 0.8, rotation: -8 },
      { opacity: 1, y: 0, scale: 1, rotation: 0, duration: 0.64 },
      0.38,
    )
    .fromTo(
      label,
      { opacity: 0, x: -12, y: 0, ...CENTER_PERCENT },
      { opacity: 1, x: 0, y: 0, ...CENTER_PERCENT, duration: DURATION.md, clearProps: "transform" },
      0.42,
    )
    .fromTo(
      rank,
      { "--reveal": 0 },
      {
        "--reveal": 1,
        duration: COUNT_DURATION,
        onUpdate: function (this: gsap.core.Tween) {
          writeCounts(rank, easedRatio(this));
        },
      },
      COUNT_AT,
    )
    .fromTo(
      knob,
      { "--knob-pulse": 1 },
      { "--knob-pulse": KNOB_PULSE_SCALE, duration: 0.18, yoyo: true, repeat: 1, immediateRender: false },
      COUNT_AT + COUNT_DURATION,
    )
    .fromTo(
      chips,
      { opacity: 0, scale: 0.6, x: 0, y: 10, ...CENTER_PERCENT },
      {
        opacity: 1,
        scale: 1,
        x: 0,
        y: 0,
        ...CENTER_PERCENT,
        duration: 0.52,
        ease: GSAP_EASE.pop,
        stagger: 0.12,
        clearProps: "transform",
      },
      1,
    )
    .fromTo(
      [completeDisc, completeRing],
      { opacity: 0, scale: 0.5, rotation: -20 },
      { opacity: 1, scale: 1, rotation: 0, duration: 0.7 },
      0.36,
    )
    .fromTo(completeText, { opacity: 0 }, { opacity: 1, duration: 0.7 }, 0.36)
    .fromTo(
      complete,
      { "--reveal": 0 },
      {
        "--reveal": 1,
        duration: RING_DURATION,
        onUpdate: function (this: gsap.core.Tween) {
          writeCounts(complete, easedRatio(this));
        },
      },
      COUNT_AT,
    )
    .fromTo(
      lead.map((part) => part.art),
      { opacity: 0, scale: 0.7, rotation: (index: number) => lead[index].spec.rotation },
      { opacity: 1, scale: 1, rotation: 0, duration: DURATION.xl, stagger: 0.08 },
      0.12,
    )
    .fromTo(
      trail.map((part) => part.art),
      { opacity: 0, scale: 0.7, rotation: (index: number) => trail[index].spec.rotation },
      { opacity: 1, scale: 1, rotation: 0, duration: DURATION.xl, stagger: 0.07 },
      0.24,
    )
    .fromTo(
      tiles.map((part) => part.halo),
      { opacity: 0 },
      { opacity: 0.3, duration: DURATION.xl, stagger: 0.06 },
      0.12,
    );
  revealOnce(env, stage, section, 0.78);

  let inView = false;
  const applyVisibility = () => {
    const live = inView && !document.hidden;
    ambientGate.setVisible(live);
    section.toggleAttribute("data-paused", !live);
    sparkles.toggleAttribute("data-paused", !live);
  };
  document.addEventListener("visibilitychange", applyVisibility);
  track(() => {
    document.removeEventListener("visibilitychange", applyVisibility);
    section.removeAttribute("data-paused");
    sparkles.removeAttribute("data-paused");
  });

  const parallaxTargets = tiles.filter((part) => part.spec.parallax).map((part) => part.depth);
  const distance = mobile ? PARALLAX_DISTANCE_MOBILE : PARALLAX_DISTANCE;
  const scrub = gsap.timeline({
    defaults: { ease: GSAP_EASE.scrub },
    scrollTrigger: {
      trigger: section,
      start: "top bottom",
      end: "bottom top",
      scrub: true,
      onToggle: (self) => {
        inView = self.isActive;
        applyVisibility();
      },
    },
  });
  scrub.fromTo(parallaxTargets, { y: distance }, { y: -distance }, 0);
  inView = scrub.scrollTrigger?.isActive ?? false;
  applyVisibility();

  watchLayout(root, track);
}
