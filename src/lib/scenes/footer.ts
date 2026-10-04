import { gsap } from "@/lib/gsap";
import { DURATION, GSAP_EASE, REVEAL_DISTANCE } from "@/lib/motion";
import { all, first, revealOnce, watchLayout, type SceneEnv } from "./env";

const LINE_DURATION = 0.9;
const LINE_DURATION_MOBILE = 0.7;
const SOCIAL_STAGGER = 0.08;
const LEGAL_STAGGER = 0.06;
const FOOTER_VIEWPORT_RATIO = 0.95;

export function buildFooter(env: SceneEnv) {
  const { root: footer, mobile, track } = env;

  const tl = gsap.timeline({ paused: true, defaults: { ease: GSAP_EASE.out } });
  tl.fromTo(first(footer, "[data-footer-notch]"), { opacity: 0 }, { opacity: 1, duration: 0.24 }, 0)
    .fromTo(
      first(footer, "[data-footer-line]"),
      { scaleX: 0, transformOrigin: "0% 50%" },
      {
        scaleX: 1,
        transformOrigin: "0% 50%",
        duration: mobile ? LINE_DURATION_MOBILE : LINE_DURATION,
        ease: GSAP_EASE.inOut,
      },
      0,
    )
    .fromTo(
      all(footer, '[data-footer-item="logo"], [data-footer-item="copy"]'),
      { opacity: 0, y: REVEAL_DISTANCE },
      { opacity: 1, y: 0, duration: DURATION.md },
      0.2,
    )
    .fromTo(
      all(footer, '[data-footer-item="social"]'),
      { opacity: 0, scale: 0.6 },
      { opacity: 1, scale: 1, duration: 0.4, ease: GSAP_EASE.pop, stagger: SOCIAL_STAGGER },
      0.32,
    )
    .fromTo(
      all(footer, '[data-footer-item="legal"]'),
      { opacity: 0, y: REVEAL_DISTANCE },
      { opacity: 1, y: 0, duration: DURATION.md, stagger: LEGAL_STAGGER },
      0.52,
    );

  revealOnce(env, tl, footer, FOOTER_VIEWPORT_RATIO);
  watchLayout(document.body, track);
}
