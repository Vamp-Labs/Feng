# 02 — Frontend Engineer

## Context — read first

- `docs/research/05-synthesis.md` §"The stack, fixed" — Next.js App Router, `wagmi`/`viem`, no
  subgraph/indexer, config-driven network switching (Robinhood Chain testnet primary, Arbitrum
  Sepolia fallback).
- `docs/research/01-tech-stack.md` §"Implications per role" (frontend engineer paragraph) — no
  Hardhat dependency, ABIs read from `forge build`'s `out/`, USDG-in/USDG-out as the primary flow,
  composability UI should surface `MAX_DEPTH`/cycle rejection as pre-submission validation not a
  failed-tx surprise.
- `docs/research/02-robinhood-testnet.md` §"Implications per role" (frontend engineer paragraph) —
  exact env var names and values, wallet connection is standard EVM (no custom auth).
- `docs/research/03-domain.md` §"Implications per role" (marketplace/demo narrative paragraph) — do
  not pitch composability as technically unprecedented; the differentiator is tokenized equities on
  Robinhood Chain specifically plus the built-in safety features (depth cap, cycle check, redemption-
  liquidity rule) as an explicit, demonstrable answer to a named real-world failure (Stream Finance,
  Nov 2025). This should inform copy/labels in the UI (e.g. a visible "max depth 2, cycle-checked"
  note on the compose screen), not just a spoken demo narrative.
- `docs/handoffs/contracts.md` — full read. This is the ABI/interface you build against, the
  `addresses.json` schema you import, and the env var names.
- `docs/handoffs/00-overview.md` §"The demo path" — the exact 8-step flow your UI must support end to
  end. **Supersedes its "Design direction" section** — this is no longer from-scratch; see the design
  system section immediately below, which is now the binding visual spec.

## Design system — strict adherence (required, non-negotiable)

The UI must be built strictly to the **"Afterglow"** design system (source:
`https://claude.ai/artifact/E4sDEVfJj8TxXD3w8pPA27`). Do not deviate from these tokens, do not invent
new colors/spacing/radii, do not "improve" on it. This overrides the generic "functionality-first,
minimal visual polish" framing in the Out-of-scope section below — motion and visual fidelity to this
system are now P0, not P2.

**Voice:** dark, game-lit system — deep indigo night, one violet stage light, one mint action that
always means "go". Centered, symmetric layouts; short headlines that turn on a contrast; numbers read
like game HUD stats. Adapt this voice to a DeFi strategy marketplace (e.g. NAV/APY read like HUD
numbers, "Deposit"/"Rebalance"/"Redeem" as the primary mint-colored actions, a strategy card = a
`ChallengeCard`-style glass tile) rather than forcing literal gamified copy.

**Color tokens** (single dark theme, `night`):
| token | hex | usage |
|---|---|---|
| `void` | `#01081c` | page base / deepest ground |
| `night` | `#060c34` | top-of-page wash (gradient `night`→`void`) |
| `surface-card` | `#07123e` | glass card fill, 72–88% opacity |
| `surface-raised` | `#0c1352` | hover/pressed fills, chips |
| `line` | `#363d80` | decorative 1px hairline |
| `line-strong` | `#7986a8` | control borders (ghost/icon buttons, inputs) |
| `ink` | `#ffffff` | headings, button labels on dark |
| `ink-soft` | `#c6d3e4` | body copy, card meta |
| `ink-muted` | `#989fb7` | footer/legal/timestamps |
| `mint` | `#37f9a3` | primary action (CTA fill, badge text/ring, focus ring, "complete" states) |
| `mint-deep` | `#085c3a` | shaded mint glass, progress-ring track (decorative only) |
| `on-mint` | `#01081c` | label/icons on a mint fill |
| `violet` | `#7c25e0` | stage glow (radial light behind hero/featured objects), fill/shadow only |
| `indigo` | `#4322ba` | glass tile faces, floating shapes, avatar rings — decorative only |
| `orchid` | `#d563ec` | active nav link, rank/progress fill, XP-style accents |
| `periwinkle` | `#969aff` | first stop of the accent-word gradient; quiet link color |
| `sky` | `#8aceff` | second stop of the accent-word gradient; info highlights |
| `amber` | `#fdbc00` | streak/alert accents only |
| `focus` | alias of `mint` | keyboard focus ring |
| `link` | alias of `periwinkle` | inline links |

Rule: `violet`/`indigo` are light/material only, never text. Only one gradient exists —
`periwinkle`→`sky` — and it's used on at most one accent word per page/view.

**Type:** single family **Plus Jakarta Sans** (Google Fonts, weights 400–800 + 700/800 italic).
| style | size/line-height | weight | usage |
|---|---|---|---|
| `display` | 64/64px | 700, `-0.03em` | one per page, hero headline, 2 lines max |
| `heading` | 44/48px | 700, `-0.025em` | section headlines |
| `title` | 32/36px | 700, `-0.02em` | card titles / panel headers |
| `lead` | 20/30px | 400 | paragraph under a display/heading, `ink-soft`, max 36em |
| `body` | 16/26px | 400 | default copy, `ink-soft` |
| `label` | 15/20px | 600 | buttons, nav links |
| `caption` | 13/18px | 500 | card meta, helper text |
| `overline` | 13/16px | 700, `0.04em`, uppercase | section badge text, in `mint` |
| `micro` | 11/16px | 400 | footer legal, store-button kickers, `ink-muted` |
| `hud` | 28/32px | 800 italic, `-0.01em` | game-style read-outs (numerals + short word) — use for NAV/APY/rank-style stats |
| `hud-sm` | 16/20px | 800 italic | small stat-chip values |

**Spacing scale:** `space-1`=4px, `space-2`=8px, `space-3`=12px, `space-4`=16px, `space-6`=24px
(card padding), `space-8`=32px (headline→lead gap), `space-12`=48px (between blocks), `space-16`=64px
(desktop page side margin), `space-24`=96px (between sections).

**Radius:** `radius-sm`=6px (small chips), `radius-md`=10px (buttons), `radius-lg`=16px
(cards/panels), `radius-xl`=24px (glass/feature tiles), `radius-pill`=999px (badges, stat chips,
progress bars, icon buttons).

**Shadow/glow** (pair at most one dark shadow + one colored glow, never two glows):
- `shadow-card`: `0 24px 64px rgba(1,8,28,0.6), inset 0 1px 0 rgba(255,255,255,0.06)` — resting glass
  cards.
- `glow-mint`: `0 0 24px rgba(55,249,163,0.45)` — primary button hover, "complete"/success states.
- `glow-violet`: `0 0 64px rgba(124,37,224,0.55)` — the one featured/hero element.
- `glow-orchid`: `0 0 16px rgba(213,99,236,0.7)` — progress/rank-bar fill.
- `focus-ring`: `0 0 0 2px #01081c, 0 0 0 4px #37f9a3` — every control's keyboard focus, no exceptions.

**Surfaces:** cards are glass (`surface-card` at `glass` opacity token `0.8`, 1px `line` edge,
`radius-lg`, `shadow-card`). Depth comes from light, not borders or stacked shadows — a featured
element gets exactly one glow. Hover lightens to `surface-raised` (ghost controls) or adds the primary
element's glow. Pressed nudges 1px down. Disabled = 45% opacity, no glow.

**Accessibility floor (do not regress):** body text ≥4.5:1 contrast on every ground it's used on per
the table above (already satisfied by the token pairings listed — don't invent new foreground/
background combinations without checking contrast). Focus ring on every interactive control, no
exceptions. No AI-cliché visuals: no blue-purple gradient backgrounds beyond the one named accent-word
gradient, no emoji, no left-border cards.

**Reference components** in the source system (build your own React/Tailwind equivalents matching
these, not literal copies — no bundle/asset import from the artifact): `Button`, `IconButton`,
`Badge`, `StatChip`, `AvatarStack`, `GlassTile`, `NavBar`, `ProgressRing`, `RankBar`, `ChallengeCard`
(closest analogue to a Strategy card), `StoreButton` (not applicable here, ignore), `Icon` (24px grid,
2px round-cap stroke set — build an equivalent minimal icon set or use an existing icon library at
this same visual weight, PM approves either).

## Motion — Framer Motion + Lenis (required)

- **Framer Motion** (`framer-motion` package) is the approved animation library for all
  micro-interactions, transitions, and state changes: button/card hover and press states, page/section
  enter transitions, the compose-flow's nested-strategy reveal, tx-pending/success/error state
  transitions. Match the design system's own motion notes: controls transition in ~160ms ease;
  decorative tiles (if you build any `GlassTile`-style decoration) drift a few px on a slow 6–10s loop.
- **Lenis** (`lenis` package, formerly `@studio-freight/lenis`) drives smooth scroll site-wide —
  initialize once at the app root, sync it with Framer Motion's scroll-linked animations if you add
  any (`useScroll` should read from Lenis's scroll position, not the native scroll event, to avoid
  desync).
- **`prefers-reduced-motion` is mandatory, not optional:** disable Lenis smooth-scroll (fall back to
  native scroll) and stop/skip all Framer Motion drift/decorative animation when the media query
  matches; keep only essential state-change transitions, shortened.
- These two packages are pre-approved additions — do not ask the PM before adding `framer-motion` and
  `lenis` specifically (every other new dependency still needs sign-off per Constraints below).

## Tools — skills and MCP

From `docs/research/06-tooling.md`, all pre-existing global skills, reused (not reinstalled) because
they already fit this exact stack:
- `work:nextjs-app-router` — Server/Client component boundary rules; use for every screen (wallet
  connect and tx-signing components need `'use client'`, RPC-read views can stay server-rendered).
- `work:react-components` — props-API/composition discipline for the deposit/redeem forms and the
  strategy-composition (nested Strategy Token) builder UI.
- `work:typescript-types` — deriving TypeScript types from `forge build`'s ABI JSON instead of
  hand-writing contract-call types.
- `work:reuse-first` — inventory existing components/deps before adding new ones; relevant given the
  6-day budget.
- `me:stack-detect` (via `me:frontend`) — detects the stack at task start and routes to the above
  automatically; invoke this first if you're dispatched through `me:frontend`.

No MCP server is installed for this role. No Figma/design file exists for this project — do not look
for one.

## Owned paths

`app/`, `components/`, `lib/` (frontend-side helpers only — contract ABI imports, `wagmi` config,
`addresses.json` readers), and the frontend's `package.json`/lockfile **only if this becomes a
monorepo with a dedicated frontend workspace** — if instead the frontend is the only Node project at
the repo root, you own the root `package.json` for frontend dependencies, but if Contracts/Integration
ever need a root-level Node dependency too, that's a PM decision, not yours to resolve unilaterally.
Do not touch `contracts/`, `deployments/`, or `scripts/`.

## Responsibilities

Build the Next.js marketplace UI end to end: wallet connect, create/mint a strategy, deposit/redeem,
browse the marketplace, compose a strategy from existing Strategy Tokens, trigger a rebalance for the
demo. You cannot ask the user questions (per the standing rule for this role) — everything you need
is in this file, `contracts.md`, and the research files above; if something is genuinely missing,
report it back rather than guessing silently.

## Scope

### In scope

- **P0:** Wallet connect via Privy (`@privy-io/react-auth` + `@privy-io/wagmi`, email/Google login
  with embedded wallets plus external wallets; app id from `NEXT_PUBLIC_PRIVY_APP_ID`) targeting Robinhood Chain testnet (chain ID `46630`) as
  primary, with a visible network indicator and a config-driven switch to the Arbitrum Sepolia
  fallback (`421614`) per `NEXT_PUBLIC_NETWORK`.
- **P0:** Create Strategy screen: pick 2–3 constituents from the available mock stock tokens (and, for
  a depth-2 strategy, from already-registered Strategy Tokens read from `MarketplaceRegistry`), set
  weights that must sum to 100% (client-side validation before submit), set a max-weight-per-asset
  constraint and a rebalance interval, submit → calls `StrategyFactory.createStrategy()`. Surface the
  `MAX_DEPTH=2`/cycle-rejection rule as pre-submission validation (e.g. grey out or explain why a
  constituent can't be picked) rather than letting the user discover it via a failed transaction
  (`01-tech-stack.md`'s explicit recommendation).
- **P0:** Deposit/Redeem screen for a given Strategy Token: USDG-in → StrategyToken-out (deposit),
  StrategyToken-in → USDG-out (redeem), using `previewDeposit`/`previewRedeem` for a live quote before
  submit.
- **P0:** Marketplace list: reads `MarketplaceRegistry.getAllStrategies()` +
  `getStrategyInfo()`/`totalAssetsUSDG()` per vault directly via RPC (no subgraph/indexer — `view`
  calls only), shows name, creator, depth, basic price/NAV display (PRD §6.1 "basic performance
  display").
- **P0:** Strategy detail view: current constituents/weights, NAV, a manually-triggerable "Rebalance
  now" button calling `RebalanceEngine.performRebalance(vault)` (stands in for the keeper bot during
  the live demo), and — for a depth-2 strategy — a clear visual showing the nested Strategy Token as a
  constituent (this is the composability "money shot" for the demo).
- **P1:** basic loading/empty/error states across all screens (a genuinely empty marketplace on first
  load, a pending-transaction state, a reverted-transaction error surfaced legibly — not a raw RPC
  error dump).
- **P1:** a "your positions" view (which Strategy Tokens the connected wallet holds, redeemable from
  there directly).
- **P2:** anything from PRD §6.1's "Nice to Have" row (leaderboard, reputation score, tags) — cut per
  `05-synthesis.md`'s timeline finding unless every P0 and P1 above is done with days to spare.

### Out of scope

- Any subgraph/indexer/off-chain database — every read is a direct RPC `view` call or `eth_getLogs`
  filtered on the indexed event fields `contracts.md` defines.
- Direct multi-asset (non-USDG) deposit UI — not built by Contracts, don't build UI for it.
- Any backend/API route beyond what Next.js needs for its own app (e.g. do not build a custom
  indexing service).
- Mobile-specific responsive polish beyond "doesn't break" — desktop-first for a live demo.
- Anything not in the Afterglow token set (see Design system section) — no ad hoc colors, fonts,
  spacing or radii, even to "fix" a layout edge case; if the system's tokens genuinely don't cover a
  case, flag it back to the PM rather than inventing one.

## Objectives

A working Next.js app that supports every step of the 8-step demo path in `00-overview.md` end to
end, pointed at Robinhood Chain testnet by default with a working Arbitrum Sepolia fallback toggle.

## Requirements

See Scope above — every item is already P0/P1/P2 tagged.

## Dependencies

`contracts.md`'s frozen interface (available immediately, does not block starting). Real, deployed
contract addresses and the final ABI (`out/*.json`) come from role 01 (Contracts) passing its tests
and role 03 (Integration) executing the real deploy — until those land, build and test your own flows
against a local `anvil` instance you run yourself with the same interface, so you're not idle. Final
integration/demo rehearsal happens once role 03 delivers real `deployments/robinhood-testnet/addresses.json`.

## Constraints

- Next.js App Router, Server Components by default, `'use client'` only on interactive leaves.
- TypeScript strict — no `any`, no `@ts-ignore`, no non-null assertion to silence a real nullable.
- No new dependency without asking the PM first (check `work:reuse-first` before reaching for
  anything) — **except `framer-motion` and `lenis`, which are pre-approved** (see Motion section
  above).
- No code comments except a `// TEMPORARY —` tag on explicitly-temporary scaffolding.
- Respect `prefers-reduced-motion` on every animation, including Lenis smooth-scroll.
- Strict adherence to the Afterglow design tokens (colors, type scale, spacing, radius, shadow/glow) —
  see the Design system section above. No literal copying of the source artifact's bundle/assets;
  reimplement equivalents against these tokens.

## Deliverables

- **P0:** working Next.js app covering the full 8-step demo path.
- **P0:** `NEXT_PUBLIC_CHAIN_ID`/`NEXT_PUBLIC_RPC_URL`/`NEXT_PUBLIC_EXPLORER_URL`/`NEXT_PUBLIC_NETWORK`
  wired from `.env` (names only — you consume them, you don't invent new secret-bearing vars).
- **P0:** a `lib/addresses.ts` (or similar) that imports `deployments/<network>/addresses.json` and
  exposes typed contract addresses/ABIs to the rest of the app.
- **P0:** a Tailwind theme (or CSS variables, your call) implementing the full Afterglow token set from
  the Design system section — colors, type scale, spacing, radius, shadow/glow — as the single source
  of truth every component pulls from.
- **P0:** Lenis smooth scroll wired at the app root, Framer Motion used for the interaction/transition
  points listed in the Motion section, `prefers-reduced-motion` fallback verified for both.
- **P1:** loading/empty/error states, "your positions" view.

## Acceptance criteria

- A user can connect a wallet, create a depth-1 strategy, deposit USDG, see it minted as a Strategy
  Token, trigger a rebalance, create a depth-2 strategy nesting the first, deposit into it, see its
  NAV correctly reflect the nested vault's live NAV, browse both in the marketplace, and redeem —
  entirely through the UI, no manual `cast` calls needed by a demo presenter.
- Attempting to nest a strategy beyond depth 2, or create a circular composition, is prevented or
  clearly explained in the UI before a transaction is even submitted.
- The network indicator correctly reflects whichever of Robinhood Chain testnet / Arbitrum Sepolia the
  connected wallet is on, and switching `NEXT_PUBLIC_NETWORK` actually repoints every contract call.
- `next build` (or the project's equivalent typecheck/build command) passes with zero TypeScript
  errors and no `any`/`@ts-ignore` introduced.
- No hardcoded contract address appears anywhere in `app/`/`components/` — all sourced from the
  addresses config.
- Every screen visibly matches the Afterglow tokens (dark void/night ground, mint primary actions,
  glass cards with at most one glow, Plus Jakarta Sans type scale) — no default framework styling, no
  off-palette colors.
- Scrolling is Lenis-smooth on every page with content taller than the viewport; disabling
  `prefers-reduced-motion` in devtools falls back to native scroll and stops all decorative motion
  while state-change transitions still work.
