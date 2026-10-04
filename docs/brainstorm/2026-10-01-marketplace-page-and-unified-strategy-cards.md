# Marketplace page split + unified strategy cards (hero slider and marketplace)

- **Date**: 2026-10-01 · **Project**: Composable Strategy Marketplace (Feng.) · **Mode**: UI / UX (with a web3 data note)
- **Status**: draft (decisions unconfirmed)

## Context

Read from the repo on 2026-10-01 (paths under `/home/cn/Projects/Competition/Web3/Arbitrum/Feng.`):

- `src/app/page.tsx` renders `<Hero>`, `<FeaturedStrategies>` (inside `.top`, fixed height `943u`), then a `#marketplace` section with `<MarketplaceList>`, then `<PortfolioSection>` and `<HomeMotion>`.
- **A featured slider already exists.** `components/home/featured-strategies.tsx` -> `featured-carousel.tsx` -> `featured-card.tsx` is a 3-pose coverflow (poses in `lib/carousel-slots.ts`) with arrows, drag, ArrowLeft/Right keys, no autoplay. It currently takes up to 8 strategies by NAV (`lib/featured.ts`, `FEATURED_LIMIT = 8`) and falls back to `DEMO_STRATEGIES` (BLUE, LADR, ARBX) when the registry is empty or errored. So "slider of exactly 3" is mostly a data change plus a card redesign, not a new component.
- Hero card (`featured-card.tsx` + `.module.css`) is absolutely positioned in `--cu` (scaled px) units: logo overflowing the top, symbol, "Depth 1 / Depth 2 · nested" row, NAV, "by 0x..." row, mint "View strategy" button (mint only on the active slot).
- Marketplace card (`components/strategy-card.tsx`, CSS in `styles/site.css` ~L403-430 and L715-731): `StrategyLogo`, symbol, name, `Badge Depth N`, `StatChip NAV`, `StatChip Creator`. Grid class `.strategy-grid`. Wrapped with a whileInView stagger in `components/marketplace-list.tsx`.
- Data: `lib/hooks/use-marketplace.ts` does `getAllStrategies` -> `getStrategyInfo` x N -> (`totalAssetsUSDG`, `name`, `symbol`) x N. No constituents. `lib/hooks/use-strategy-detail.ts` reads `getConstituents` for ONE vault. `deployments/robinhood-testnet/addresses.json` has `stockTokens` keyed by ticker (`TSLA, AMZN, NFLX, PLTR, AMD`), so token address -> ticker is a pure lookup with zero RPC. A nested constituent (`isStrategyToken`) resolves to a strategy via `strategy.token` from the same marketplace list, also zero RPC.
- `contracts/StrategyVault.sol` pushes constituents only in the constructor, so they are immutable: cache forever.
- `lib/chains.ts` uses `defineChain` with no `contracts.multicall3`, so wagmi `useReadContracts` fans out one `eth_call` per entry (the marketplace already issues about 41 for 10 vaults). Holdings add 10 more.
- Seeded constituents (`script/SeedStrategies.s.sol`): AIGR = PLTR 35 / AMD 35 / AMZN 30; STRM = NFLX 60 / AMZN 40; EVMO = TSLA 40 / AMD 30 / PLTR 30; EQ5 = five at 20; DEFC = AMZN 40 / NFLX 30 / AMD 30; CHIP = AMD 60 / TSLA 40; BLTZ = PLTR 50 / TSLA 50; CLCM = AMZN 50 / PLTR 25 / NFLX 25; CORE = AIGR 40 / EQ5 40 / TSLA 20 (nested); CONV = STRM 40 / CHIP 30 / PLTR 30 (nested).
- Nav: `components/nav-links.tsx` has Marketplace -> `/` (also active on `/strategy*`). Other hard links to `/` labelled marketplace: `site-footer.tsx:12`, `not-found.tsx:11`, `positions-list.tsx:71`.
- Next.js 16.3.6: standard App Router; a new `src/app/marketplace/page.tsx` needs nothing special (docs checked: `node_modules/next/dist/docs/01-app/01-getting-started/04-linking-and-navigating.md`). Builder must still read the relevant docs before any API-specific code.
- Motion: `MotionConfig reducedMotion="user"` + `LazyMotion` (`components/motion-provider.tsx`); `lib/motion.ts` has the easings/springs; `RankBar` and `PageHead` are reusable.

**Design-token drift found (important, see Open question 1).** The live code does not match the Afterglow spec in `docs/handoffs/02-frontend.md`: fonts are Inter / Inter Tight (spec: Plus Jakarta Sans); `--bg #000718` (spec void `#01081c`); mint `#35f9a5` (spec `#37f9a3`); orchid `#e879f9` (spec `#d563ec`); periwinkle `#9ccaff` (spec `#969aff`); the accent gradient is periwinkle -> lilac `#8f56ff` (spec periwinkle -> sky `#8aceff`); card radius 22-28px (spec 16px); `coin-dot` uses mint as an identity colour (spec: mint is action/complete only). Also the code's hero tag reads "Tokenized stocks", not "ON-CHAIN STRATEGY LAYER" (the live Vercel build may be newer; treat the repo as truth unless told otherwise).

## The question

The user wants the marketplace list out of the home page and into its own page, with the home hero holding only a 3-card slider. They also want the hero cards and marketplace cards redesigned as one visual family that shows which stock tokens each strategy holds, with little text.

## Decision (recommended, awaiting confirmation)

- (a) Slider: keep the existing coverflow, feed it exactly 3 strategies, no autoplay, restyle the card with the shared anatomy.
- (b) Card anatomy: logo tile + symbol + HUD NAV + a **segmented weight bar with ticker chips** (nested constituents drawn as a distinct "layered" segment showing the child strategy's symbol).
- (c) Page: `/marketplace`, header = title + 3 HUD stats (no lead paragraph), grid of the unified card, no filters in v1.

Locked: none yet (see Open questions). Everything below is the recommendation.

## Options considered

### (a) Hero 3-card slider

| | A1 Existing coverflow, top-3 by NAV | A2 Existing coverflow, curated-by-rule 3 (recommended) | A3 Native scroll-snap row of 3 |
|---|---|---|---|
| Which 3 | Top 3 NAV | Slot 1 (centre, initial) = highest-NAV depth-2 strategy; then the 2 highest-NAV remaining; fall back to plain NAV rank if no depth-2 exists; stable tie-break by registry order | Same rule or any |
| Mechanics | Unchanged | Unchanged: arrows, drag, Arrow keys, no autoplay | CSS scroll-snap, no JS |
| Effort | Lowest | Low (`lib/featured.ts` only) | Medium, discards the built coverflow |
| Risk | On a testnet where NAV ties/0, order is arbitrary and may show 3 look-alikes | A nested centre card tells the product's one-line story (composability) | Loses the visual identity the user already approved |

Pick A2. Condition that changes the pick: if the user wants a hand-chosen showcase (`FEATURED_SYMBOLS = [CORE, EQ5, AIGR]`), that is a one-line swap but hard-codes vault symbols.

Slider notes: with `count = 3`, `slotOf` gives -1/0/+1, so all three poses are visible and the "far" poses are unused. Reduced motion: `MotionConfig reducedMotion="user"` turns the transform springs into snaps; the carousel has no autoplay, so there is nothing to disable, but the builder must verify arrows, Arrow keys and the active card's link stay operable and that tilt/sheen stay off (`featured-card.tsx` already gates tilt on `!reduced`). Do NOT add autoplay.

**How hero differs from a marketplace card.** Same content and same `StrategyHoldings` component; different shell. Hero = "stage" size, portrait, logo overflowing the top, bar with percent labels, one mint CTA on the active slot only. Marketplace = compact tile, whole card is the link, no button, hover lift via the existing `.card[data-interactive]`.

### (b) Unified card anatomy

Honest constraint: no logos exist for TSLA/AMZN/NFLX/PLTR/AMD, and the palette bans mint (action only), amber (alerts), violet/indigo as text. Use two channels so colour is never the only signal: ticker text is always visible, colour is a tone.

Tone map (all inside the palette, none mint/amber): TSLA orchid, AMZN periwinkle, NFLX sky, PLTR ink-soft `#c6d3e4`, AMD slate (`line-strong` `#7986a8`, lightened). Nested = indigo material face with a 45-degree hairline hatch and the `LayersIcon`, label = child strategy symbol.

| | B1 Chip row | B2 Weight bar + ticker row (recommended) | B3 Donut around logo |
|---|---|---|---|
| Visual | Pill per holding: dot + ticker + percent | One proportional bar (8px, 2px gaps) + a tiny ticker label per segment, percents only on the hero card and in `aria-label` | Ring segments around `StrategyLogo` |
| Text load | Highest (percent on every chip) | Low | Lowest, but unreadable below ~80px |
| Handles 5 holdings at 280px | Wraps to 2 lines | Fits (about 56px per segment) | Poor |
| Nested indicator | A badge | Intrinsic: hatched layered segment | Hard |
| Effort | Low | Low-medium | High (SVG arcs, a11y) |

Pick B2. Main tradeoff: segment labels shrink when a holding is under about 12% (hide the label below 10%, keep the segment, rely on `aria-label` "AMZN 40%, NFLX 30%, ..." on the bar). Rejected B3 as too costly for the legibility gain.

Wireframes (sketch):

```
HERO CARD (active slot, 342x330 scaled)       MARKETPLACE CARD (~19rem)
        [logo tile, overflows top]            +------------------------------+
+--------------------------------+            | [logo]  AIGR      $12.5K  NAV|
|             AIGR              |            |         AI Growth            |
|        $12,480.00  NAV         |  <- HUD    | [##########][#######][######]|
| [########][######][#####]      |            |  PLTR        AMD     AMZN    |
|  PLTR 35%   AMD 35%  AMZN 30%  |            +------------------------------+
|        [ View  -> ]  (mint)    |            nested example (CORE):
+--------------------------------+            | [//AIGR//][//EQ5//][TSLA]    |
                                              |   (hatched, layers glyph)    |
```

Text cut, hero card: the "Depth N" row, the "by 0x..." row, the button label shortens to "View". Marketplace card: `Badge Depth N` (replaced by the logo's ghost tile and the hatched segment), the Creator `StatChip` (lives on the detail page), keep symbol + name caption (name carries the theme: "Defensive Core"), keep NAV as HUD numeral with a tiny "NAV".

### (c) Marketplace page

| | C1 Lean page | C2 Lean + HUD stat header (recommended) | C3 Full filter/sort bar |
|---|---|---|---|
| Header | `PageHead` with eyebrow, title, lead | Title + 3 HUD stats (strategies, TVL, nested count) instead of a lead; stats from existing `useMarketplaceStrategies`, zero extra RPC | Same + sort + ticker filters |
| Controls | None | None; default sort NAV desc (stable) | Sort segmented, "holds TSLA" chips, nested toggle |
| Worth it at 10 items | Yes | Yes | No. A ticker-holds filter is the one filter that becomes useful once there are about 25+ strategies |

Pick C2. Route `/marketplace` (matches the nav label and the old `#marketplace` anchor; avoids colliding with `/strategy/[vault]`). Nav: Marketplace -> `/marketplace`, active on `/marketplace*` and `/strategy*`; the brand logo remains the way home (no separate "Home" link). Add one quiet "All strategies ->" link under the slider in the hero so the home page has an in-page route to the list.

### Pre-mortem (it's three months later and this failed; why?)

- Holdings RPC reads flake and cards pop/shift: mitigated by reserving the bar height with a neutral track while loading/failed, never blocking the card, and fetching once with `staleTime`/`gcTime: Infinity` (constituents are immutable) plus `retry`.
- 10 extra `eth_call`s hit a rate-limited public RPC: one shared `useReadContracts` query for all vaults (stable key, shared by hero and marketplace), not one per card.
- Five stock tones look like a rainbow or collide with nested: ticker text always shown; nested uses material + hatch, not a tone; builder keeps the tone map in one file so recolouring is one edit.
- New cards look foreign next to Create/Positions cards because of the token drift: see Open question 1.
- The 3-card slider shows three near-identical cards: the nested-centre rule plus NAV rank mitigates; fallback data (`DEMO_STRATEGIES`) needs demo holdings or the bar is blank.

## Spec

### Component inventory

New:
- `src/lib/holding-tones.ts`: `type Holding = { key: string; label: string; weightBps: number; nested: boolean; tone: HoldingTone }`; ticker -> tone map; built from `addresses.stockTokens` (reverse lookup by address, case-insensitive) with an address-short fallback.
- `src/lib/hooks/use-strategy-holdings.ts`: one `useReadContracts` of `getConstituents` for all vaults of `useMarketplaceStrategies()`; returns `Record<vault, Holding[] | undefined>` plus `isLoading`. Resolves nested via `strategies.find(s => s.token === c.token)?.symbol`. Does not modify `use-marketplace.ts`.
- `src/components/strategy-holdings.tsx` + `strategy-holdings.module.css`: presentational `StrategyHoldings({ holdings, size: "stage" | "tile", loading })`. Bar built from CSS grid with `grid-template-columns` in bps `fr`, `role="img"` with an `aria-label` summary; ticker row under it; percent labels only for `stage`. Framer-motion: segments `scaleX` in once on first view using `EASE_OUT` and `VALUE_TWEEN_SECONDS`; static under reduced motion.
- `src/app/marketplace/page.tsx`: server page using `PageHead` (make the lead `children` optional) or a thin variant, a `MarketplaceStats` HUD row (`text-hud`, `StatChip`), and `<MarketplaceList />`.
- `src/components/marketplace-stats.tsx`: three HUD stats from `usePortfolioStats` or a direct reduce of `strategies` (no new reads).

Modify:
- `src/app/page.tsx`: remove the `#marketplace` section, `MarketplaceList`, `Reveal` and `getActiveNetworkDefinition` usage if now unused. Keep Hero + Featured + PortfolioSection + HomeMotion.
- `src/lib/featured.ts`: `FEATURED_LIMIT = 3`; rule from A2.
- `src/components/home/featured-card.tsx` + `featured-card.module.css`: replace the meta and creator rows with `<StrategyHoldings size="stage">`, re-lay vertical offsets (bar around `top: 205cu`), shorten the button label to "View"; keep logo, NAV, mint-only-on-active.
- `src/components/home/featured-carousel.tsx`: pass holdings down (or have the card call the shared hook); keep a11y live region text.
- `src/components/home/featured-strategies.tsx`: nothing structural; confirm the ghost placeholder still reads as 3 slots.
- `src/lib/demo-strategies.ts`: add demo holdings (static, tickers only) for the three fallback strategies.
- `src/components/strategy-card.tsx` + `.strategy-card*` rules in `src/styles/site.css` (~L403-430, L618-623, L715-731): new anatomy, remove Badge/Creator chips, keep hover logo tilt (already reduced-motion gated).
- `src/components/marketplace-list.tsx`: pass holdings; skeleton height to match the new card; trim empty/error copy.
- `src/components/nav-links.tsx`, `src/components/site-footer.tsx`, `src/app/not-found.tsx`, `src/components/positions-list.tsx`: marketplace links -> `/marketplace`.
- `src/components/home/hero.tsx` + `hero.module.css`: add the quiet "All strategies" link under the slider (or inside the hero actions, per Open question 4).

Do not touch: `lib/hooks/use-marketplace.ts`, `use-strategy-detail.ts`, any contract, `lib/abi`, `lib/scenes/*` (HomeMotion keeps working because `[data-hero]` is unchanged).

### States

- Loading: card skeleton at the new card height; holdings bar renders as a neutral track (no tickers) so height never shifts.
- Holdings failed / partial: the card still renders and links; bar shows the neutral track and no ticker row; no error toast (the detail page shows the full list).
- Empty marketplace: existing `StateCard` with "Create a strategy" (keep, shorten body to one sentence).
- Registry error: existing alert `StateCard`.
- Nested: hatched segment with `LayersIcon` and child symbol; if the child strategy is not in the list (should not happen), show its short address.
- Slider with demo fallback: demo cards link to `/create` as today.

### Copy

- Marketplace header: eyebrow = network label is already in the nav, so use "Live" or drop the eyebrow; title "Marketplace" (accent word is the title itself, one accent per view); stats labelled "Strategies", "TVL", "Nested". No lead paragraph.
- Hero link: "All strategies". Hero card button: "View".
- Cut: "Every registered Strategy Token, read straight from the registry", the "Live on <network>" tag, "Depth N" badges/rows, "Creator" and "by 0x..." text, "Loading strategy" placeholder name (use the skeleton).

### Tokens, motion, a11y

- Colours only from the Afterglow set; mint stays on the CTA; one glow per featured element (the active hero card's existing underglow; remove any glow on chips).
- NAV numerals in `text-hud` (italic, heavy). Do not introduce new fonts.
- Focus ring on every control (existing `:focus-visible`); the whole marketplace card is one link with an `aria-label` like "AIGR, AI Growth, holds PLTR 35%, AMD 35%, AMZN 30%".
- Reduced motion: no autoplay (none added), no tilt/sheen, segment reveal and card stagger become instant, coverflow poses snap, arrows/keys/links still work.
- Mobile: marketplace grid already `auto-fill minmax(min(100%, 19rem), 1fr)`; hero card scales via `--cu`; tap targets at least 44px; ticker labels hide below 10% weight.

### Verification the builder must do

- `pnpm lint` and `pnpm build` pass.
- Visual check at about 1440, 1024, 390 widths; home shows no list; `/marketplace` shows 10 cards with bars; CORE and CONV show hatched nested segments.
- Reduced motion on (DevTools emulation): slider operable by keyboard, nothing drifts.
- Throttle/offline the RPC: cards still render without bars, no layout shift.
- Network tab: exactly one `getConstituents` batch of 10 calls (no per-card duplicates).

## Out of scope

- Contracts, ABI, and the behaviour of `use-marketplace.ts` / `use-strategy-detail.ts`.
- Filters, search, pagination, ticker-holds filtering.
- Real stock logos or a logo asset pipeline.
- Reconciling the site-wide token drift (colours, font, radii), unless the user decides so in Open question 1.
- Rewriting the detail page or `ConstituentList` (it uses `coin-dot` with mint; flag it, do not change it here).
- Autoplay for the slider.

## Open questions

1. **Token drift.** The user's constraint says strict Afterglow, but the code uses Inter, `#000718`, `#35f9a5`, orchid `#e879f9`, 22-28px card radius, and a periwinkle -> lilac gradient. Options: (a) honour the spec values on the touched cards only (default recommendation, accepts a small inconsistency with Create/Positions cards), (b) match the site's existing tokens (consistent now, off-spec), (c) a separate pass to realign tokens and load Plus Jakarta Sans first. Who decides: the user.
2. **Orchid as a stock identity tone.** The spec reserves orchid for active/progress. TSLA = orchid is the borderline case; alternative is a 4-tone ramp plus slate with TSLA = ink-soft. User to confirm.
3. **Featured selection.** A2 (rule: top nested + 2 by NAV) versus hand-picked symbols. Also: do the seeded vaults hold deposits? If all NAVs are 0, the rule degrades to registry order. User to confirm or seed some NAV before the demo.
4. **Hero CTAs.** Add an "All strategies" link under the slider (recommended) versus replacing "Your positions". Also whether to cut or shorten the hero lede paragraph and which badge text is right ("Tokenized stocks" in the repo versus "ON-CHAIN STRATEGY LAYER" in the user's description).
5. **Default marketplace order.** NAV desc (recommended) or registry order.
6. **Cache holdings across reloads?** Immutable data could be persisted in localStorage; not recommended now (more code, stale-risk if contracts redeploy).

## Tooling

- **Installed**: nothing added by this session.
- **Recommended, not installed**: nothing required. The builder should load existing skills: `work:reuse-first`, `work:nextjs-app-router`, `work:react-components`, `work:motion-react`, and `work:animation-qa` for the final reduced-motion pass.
- **Rejected**: a Mobbin lookup (needs a one-time login, and the layout is already constrained by the existing coverflow and the user's brief).
- **Needs the user**: nothing.

Nothing needed; installed tooling covers it.

## Evidence

Read on 2026-10-01: `src/app/page.tsx`, `components/home/{hero,featured-strategies,featured-carousel,featured-card}.tsx` and their CSS modules, `lib/{featured,carousel-slots,demo-strategies,motion,chains,addresses}.ts`, `lib/hooks/{use-marketplace,use-strategy-detail,use-portfolio-stats}.ts`, `components/{strategy-card,marketplace-list,constituent-list,nav-links,page-head,motion-provider}.tsx`, `styles/{tokens,components,site,base}.css`, `contracts/StrategyVault.sol`, `script/SeedStrategies.s.sol`, `deployments/robinhood-testnet/addresses.json`, `docs/handoffs/02-frontend.md`, `node_modules/next/dist/docs/01-app/01-getting-started/04-linking-and-navigating.md`.

Assumptions (unverified): the five stock-token constituents are the only non-strategy holdings in the system; `getConstituents` on the live vaults returns the seeded sets listed above; the public RPC tolerates 10 parallel `eth_call`s (the marketplace already sends about 41); seeded NAVs may be zero; the live Vercel build might differ from the repo copy. Riskiest assumption: that the tone map reads well at 8px bar height; check visually first.

## Handoff

- **Agent**: `work:frontend`. This is component, routing and layout work on an existing Next.js codebase; the coverflow and motion already exist, so `work:creative-dev` is not needed. Ask `work:frontend:reviewer` for a read-only pass at the end.
- **Prompt**:

```
@agent-work:frontend implement docs/brainstorm/2026-10-01-marketplace-page-and-unified-strategy-cards.md
Repo: /home/cn/Projects/Competition/Web3/Arbitrum/Feng. (directory name ends with a dot). Read AGENTS.md and the relevant node_modules/next/dist/docs guide first.
Load skills: work:reuse-first, work:nextjs-app-router, work:react-components, work:motion-react, work:animation-qa.
Status of the plan is "draft": before coding, put Open questions 1-5 to the user and wait for answers; if unreachable, use the recommended defaults stated in the file and say so in your report.
Do: (1) add /marketplace and remove the list from the home page; (2) limit the hero slider to exactly 3 featured strategies using the A2 rule in lib/featured.ts, no autoplay; (3) add useStrategyHoldings (one batched getConstituents read for all vaults, staleTime/gcTime Infinity, never blocks rendering) and a shared StrategyHoldings bar+ticker component; (4) redesign featured-card and strategy-card to the shared anatomy, cutting the text listed in the Copy section; (5) update every Marketplace link to /marketplace.
Do not touch contracts, lib/abi, use-marketplace.ts or use-strategy-detail.ts. No new dependencies. No code comments except // TEMPORARY. Afterglow palette only; mint only for the CTA.
Finish with pnpm lint, pnpm build, and the verification list in the Spec.
```

- **Acceptance criteria**:
  - [ ] Home (`/`) renders the hero and a slider of exactly 3 cards; no marketplace list or `#marketplace` section remains.
  - [ ] `/marketplace` lists all registered strategies using the same card as the hero, with a HUD stat header and no lead paragraph.
  - [ ] Every card shows its holdings as a proportional bar plus ticker labels; CORE and CONV show nested segments with the child strategy symbols.
  - [ ] Depth badges, Creator chips and "by 0x..." text are gone from cards.
  - [ ] Nav, footer, 404 and positions links to the marketplace point to `/marketplace`; the nav item is active on `/marketplace` and `/strategy/*`.
  - [ ] With `prefers-reduced-motion: reduce` the slider has no autoplay or tilt and remains operable by keyboard (arrows and Tab to the active link).
  - [ ] With the RPC throttled or offline, cards still render (neutral bar track) with no layout shift; network shows one batch of 10 `getConstituents` calls.
  - [ ] No contract, ABI or existing data-hook behaviour changed; `pnpm lint` and `pnpm build` pass; no mobile overflow at 390px.
- **References**: `docs/handoffs/02-frontend.md` ("Design system" section); `script/SeedStrategies.s.sol` for expected holdings; live app https://composable-strategy-marketplace.vercel.app.
