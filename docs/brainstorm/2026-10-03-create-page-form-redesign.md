# Create page form layout + style redesign

- **Date**: 2026-10-03 · **Project**: Composable Strategy Marketplace (Feng.) · **Mode**: UI / UX
- **Status**: decided

## Context

Read from the repo on 2026-10-03 (paths under `/home/cn/Projects/Competition/Web3/Arbitrum/Feng.`):

- Route: `src/app/create/page.tsx` — `PageHead` + `.page-body` wrapping `CreateStrategyForm`.
- Form: `src/components/create-strategy-form.tsx` (client). Fields: name, symbol, 2–6 constituents, max weight %, rebalance interval, validation, wallet-gated `createStrategy`.
- Layout was a flat glass Card + thin sticky ProgressRing rail.
- Holdings visualization: `src/components/strategy-holdings.tsx` + `lib/holding-tones.ts`.
- Brand direction: Poppins, mint green accent gradients.

## The question

Redesign create page layout, form style, and interaction so composing a strategy feels intentional and matches the product look.

## Decision

**Chosen: Option D — Token-picker composer.**

Locked decisions:
- Replace native constituent `<select>` rows with a **token chip picker** (stocks + nestable strategies) and a **basket** of selected assets with weight sliders.
- Keep **one-page** submit (no wizard steps); sticky **live preview** rail (name/ticker, ProgressRing, StrategyHoldings, Create CTA).
- Keep Identity (name/symbol) and Rules (max weight, interval) on the same page under/ beside the basket.
- Shorten PageHead lead to one line.
- Desktop Create CTA in preview rail + form footer; mobile sticky bottom Create bar.
- No ABI / validation rule changes (≥2 constituents, exactly 100%, max weight, depth rules).
- Auto **even-split** weights when adding/removing a chip; manual slider edits stick until next add/remove or explicit Even split.
- Max 6 constituents; ineligible chips disabled with reason.

## Options considered

| | Impact | Effort | Risk | Fit | Reversibility |
|---|---|---|---|---|---|
| A Studio + preview | High | Medium | Low | High | Easy |
| B Wizard | Medium | High | Friction | Medium | Medium |
| C Single column | Medium | Low | Weaker desktop | OK | Easy |
| **D Composer (chosen)** | High | High | Interaction rewrite | New but product-fit | Medium |

User confirmed D after Indonesian option explanations ("gas option D").

**Pre-mortem:** fails if chips are pretty but weight UX is painful (tiny sliders, no even-split) or mobile lacks a persistent Create — mitigate with range + numeric %, Even split, sticky mobile CTA.

## Spec

### Layout

```
DESKTOP (lg+)
┌─────────────────────────────┬──────────────────┐
│ Available tokens            │ Preview (sticky) │
│ Stocks: [chip][chip]…       │ Name / TICKER    │
│ Strategies: [chip]…         │ ProgressRing     │
│                             │ StrategyHoldings │
│ Basket                      │ Max · Interval   │
│ row: tone · ticker · slider │ [Create]         │
│      % input · remove       │                  │
│ [Even split]                │                  │
│ Identity: name · symbol     │                  │
│ Rules: max weight · interval│                  │
│ Notices + Create (footer)   │                  │
└─────────────────────────────┴──────────────────┘

MOBILE
Picker → basket → identity → rules → sticky Create bar above nav
```

### Files

- `src/app/create/page.tsx` — shorter lead
- `src/components/create-strategy-form.tsx` — composer rewrite
- `src/components/create-strategy-form.module.css` — layout/chips/basket/preview

### Reuse

`StrategyHoldings`, `ProgressRing`, `RankBar`, `Card`, `Button`, `Notice`, `StateCard`, `LayersIcon`, `stockHolding` / `nestedHolding`, `.field` / `.input` / `.select` with mint focus override scoped to composer.

### States

Empty basket, loading options, at-capacity (6), ineligible chips, validation warn, signing/confirming, error+reset, success StateCard, disconnected wallet.

### A11y

- Chip buttons with `aria-pressed` when selected; disabled + `title`/text for ineligible.
- Sliders labelled by ticker; remove buttons named.
- Preview `aria-live="polite"` for allocation %.
- Mobile bar does not cover fields (padding-bottom).

## Out of scope

ABI changes, wizard routes, real stock logos, marketplace/positions redesign, site-wide focus token change.

## Open questions

None — decided.

## Tooling

Nothing needed; installed tooling covers it.

## Evidence

- Form + options hooks as of 2026-10-03.
- User confirmation: "gas option D" (2026-10-03).

## Handoff

- **Agent**: main session / `work:frontend`
- **Prompt**: Implement this decided artifact (Option D composer).
- **Acceptance criteria**:
  - [ ] Chip picker for stocks + strategies; toggle add/remove; max 6
  - [ ] Basket with weight slider + % + remove; even-split on add/remove + button
  - [ ] Live preview with ring + StrategyHoldings + Create
  - [ ] Identity + Rules still present; validation + tx paths unchanged
  - [ ] Mobile sticky Create; keyboard/a11y ok
  - [ ] Mint focus treatment in composer
