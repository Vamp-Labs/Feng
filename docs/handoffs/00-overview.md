# 00 — Overview

## What this is

Composable Strategy Marketplace: rule-based ERC-20 "Strategy Tokens" over tokenized stocks, deposited
into/redeemed from an ERC-4626-shaped `StrategyVault` using USDG, auto-rebalanced by a permissionless
keeper, composable (a Strategy Token can be a constituent of another Strategy Token, capped at depth
2), discoverable through an on-chain `MarketplaceRegistry`. Target: **Robinhood Chain testnet**
(chain ID `46630`), for the Arbitrum Open House Singapore Buildathon. **Deadline: 2026‑10‑04 — 6 days
from today (2026‑09‑28).** Every requirement below is scoped to that, not the PRD's own 10-day plan.

## Read this first, every role

1. `docs/research/05-synthesis.md` — every technology decision, with its reasoning and what was
   rejected. Do not re-derive or second-guess a decision already made here; if it's wrong, report it
   to the PM instead of silently doing something else.
2. `docs/handoffs/contracts.md` — the interfaces, address schema, and env vars every role builds
   against. This is the contract between roles; do not read another role's source code to figure out
   an interface.
3. Your own numbered role file below.

## Roles

| # | Role | Scope in one line | Depends on |
|---|---|---|---|
| 01 | Contracts Engineer | `StrategyToken`, `StrategyVault`, `StrategyFactory`, `RebalanceEngine`, `MarketplaceRegistry`, mocks, Foundry tests, deploy scripts | none — starts first |
| 02 | Frontend Engineer | Next.js marketplace UI: create/mint, deposit/redeem, marketplace list, compose flow | `contracts.md` interfaces (frozen up front); real addresses from 01/03 for final wiring |
| 03 | Integration & Deploy Engineer | Real testnet verification, mock deployment execution, `addresses.json` for both networks, end-to-end demo rehearsal, buildathon submission logistics | 01's contracts passing local Foundry tests |

Three roles, not four: `05-synthesis.md` decision 8 removes the need for a separate
indexer/backend role (Marketplace Registry is read directly via RPC, no subgraph) — three
well-scoped roles fit this 6-day build better than four padded ones.

## Dependency graph and dispatch order

```
Contracts (01) ──┬──> Integration & Deploy (03) ──> [updates addresses.json] ──> Frontend (02) final wiring
                 │
                 └──> Frontend (02) starts immediately against contracts.md's frozen interfaces
                      + a local anvil instance the Frontend engineer runs itself for dev/demo of UI
                      flows before real testnet addresses exist
```

Dispatch 01 and 02 concurrently (02 works against the frozen `contracts.md` interface and its own
local `anvil` fixture for early UI work — it does not wait idle). Dispatch 03 once 01 reports its
contracts pass local Foundry tests (`forge test` green) — 03's job is largely deployment and
real-network verification, which needs working, tested contracts first. 03 then updates
`deployments/<network>/addresses.json`, which 02 re-points to for final, real-testnet-backed demo
wiring. Every role finishes every P0 item before starting any P1.

## The demo path (defines P0)

This is what the judges see, click by click, inside the 3-minute target from PRD §4. Everything on
it is P0; nothing else is, until every step here works end to end.

1. **Connect wallet** to Robinhood Chain testnet (network auto-detected/prompted by the frontend).
2. **Create Strategy A** ("$AI-GROWTH"-style, PRD §3's own example shape): pick 2–3 mock stock
   tokens, set weights (must sum to 100%), set a max-weight-per-asset constraint and a rebalance
   interval. Submit → `StrategyFactory.createStrategy()` deploys a depth-1 `StrategyVault` +
   `StrategyToken`, auto-registers in `MarketplaceRegistry`.
3. **Deposit USDG into Strategy A** → receive Strategy-A tokens. Vault mints itself the underlying
   mock stock-token basket per `contracts.md`'s MVP acquisition simplification.
4. **Trigger a rebalance** (manually callable for the demo, via the same permissionless
   `performRebalance()` a keeper bot would call) → show the vault's holdings/weights update on-screen,
   `Rebalanced` event fired.
5. **Create Strategy B**, nesting Strategy A as one of its constituents (depth 2) — demonstrates true
   composability, PRD §12's explicit success criterion ("Strategy inside Strategy").
6. **Deposit USDG into Strategy B** → receive Strategy-B tokens; show Strategy B's NAV correctly
   recursing into Strategy A's live NAV.
7. **Browse the Marketplace** → both strategies listed, basic price/performance display (PRD §6.1).
8. **Redeem** Strategy-A tokens back to USDG, pro-rata.

Every P1/P2 item in each role file is explicitly *not* on this path — do not let it compete for the
6-day budget until all 8 steps above are demoable end to end on Robinhood Chain testnet (or, if that
testnet is genuinely blocked, on the Arbitrum Sepolia fallback per `05-synthesis.md` decision 1).

## Priority tags

- **P0** — on the demo path above, must work end to end on the target testnet.
- **P1** — makes the product credible beyond the bare demo (e.g. redeem from the composed Strategy B,
  a second nested example, basic error states in the UI).
- **P2** — only if time remains after every P0 and P1 is done (PRD §6.1 "Nice to Have" row — creator
  leaderboard, reputation score, tags — is entirely P2 or cut; see `05-synthesis.md`'s timeline
  finding). No role starts P1 while any P0 on the demo path is still red.

## Ownership — every path belongs to exactly one role

- **Contracts Engineer owns:** `contracts/` (all `.sol` sources, Foundry tests, deploy scripts),
  `foundry.toml`, `remappings.txt`, `deployments/<network>/addresses.json` (writes the values after
  each deploy — Integration executes the deploy script but Contracts owns the file's schema/location
  as defined in `contracts.md`).
- **Frontend Engineer owns:** `src/app/`, `src/components/`, `src/lib/` (frontend-side only), and the
  root `package.json`. **Correction, recorded 2026-09-28 after implementation started:** the Contracts
  role's own root-level `lib/` (Foundry's own `libs = ["lib"]` convention, holding `forge-std` and
  `openzeppelin-contracts`) collides with a root-level frontend `lib/` this file originally specified.
  The Frontend role caught this unprompted and resolved it correctly by nesting all frontend source
  under `src/` (`src/app`, `src/components`, `src/lib`), a standard Next.js layout, with `tsconfig.json`
  scoped to `src/**` and explicitly excluding `contracts/`, `lib/`, `out/`, `script/`, `deployments/`.
  This is now the binding path layout — read `src/*`, not root `app/`/`components/`/`lib/`.
  Frontend also owns `dev/fixture/`, a throwaway local Foundry project it created to deploy
  `contracts.md`'s frozen interface to its own local `anvil` for UI development (reuses the root
  `lib/` read-only via relative remappings) — Contracts and Integration should not need to touch it.
- **Integration & Deploy Engineer owns:** `scripts/` (deploy orchestration, keeper cron script),
  `.env.example` templates (names only, no values), CI/README notes on how to run a testnet deploy,
  and is the one who actually *executes* `forge script ... --broadcast` against the real testnet (not
  Contracts — Contracts writes and locally tests the deploy scripts, Integration runs them for real
  and owns the resulting real addresses going into `addresses.json`).
- **Shared/root files** (`.gitignore`, top-level `README.md`, this repo's future `package.json` if a
  monorepo tool is chosen): owned by whichever role the PM designates when the need arises — ask,
  don't assume.

## Design direction (frontend) — no existing HTML to inventory

The repository is greenfield: no existing HTML, frontend code, or design assets exist to inventory
(confirmed by direct filesystem check before research began — see `docs/research/00-brief.md`,
"Tracks skipped"). There is therefore no design-system inventory to embed here. The Frontend role
instead works from this minimal from-scratch direction, chosen for build speed within 6 days and
because the audience is hackathon judges evaluating substance over visual polish:

- **Framework:** Next.js App Router, Server Components by default, `'use client'` only on
  interactive leaves (wallet connect button, deposit/redeem forms, the strategy-composition builder).
- **Component library:** use Tailwind CSS + a minimal, unstyled-primitive component set (e.g. the
  project may pull in shadcn/ui components on request — check with the PM before adding the
  dependency, per the standing "no new dependency without asking" rule) rather than hand-building a
  design system from scratch. Keep it plain: light theme, one accent color, system font stack. Do not
  spend hackathon time on animation/motion polish beyond basic hover/focus/disabled states and
  respecting `prefers-reduced-motion` — this is a functionality-first demo, not a visual showcase.
- **Structure:** a persistent header (wallet connect + network indicator per `05-synthesis.md`'s
  fallback-network recommendation), three primary views — Marketplace (list), Strategy detail
  (deposit/redeem, holdings/weights, rebalance trigger), Create Strategy (constituent picker, weight
  sliders/inputs summing to 100%, constraint inputs) — and no more than that for P0.

## Index of `docs/research/` — which file each role reads

| File | Contracts (01) | Frontend (02) | Integration & Deploy (03) |
|---|---|---|---|
| `00-brief.md` | context only | context only | context only |
| `01-tech-stack.md` | **read in full** — Foundry setup, vault/keeper/oracle/composability reasoning | §"Implications per role" (frontend) | §3 (keeper), §4 (oracle) for what to verify on testnet |
| `02-robinhood-testnet.md` | §1–2, §9 (chain identity, quirks) | §"Implications per role" (frontend env vars) | **read in full** — this is your primary source |
| `03-domain.md` | §"Recommendations" (depth/cycle/NAV/liquidity/staleness rules) — **read in full** | §"Implications per role" (demo narrative framing) | context only |
| `05-synthesis.md` | **read in full** | **read in full** | **read in full** |
| `06-tooling.md` | your installed skills | your reused skills | none installed specifically for you — use `cast`/Foundry directly |

## Standing rules (apply to every role — restated from the PM's own brief)

- English everywhere. No code comments except a `// TEMPORARY —` tag on explicitly-temporary
  scaffolding. TypeScript strict, no `any`/`@ts-ignore`/non-null-assertion-to-silence-real-nullable.
  No new dependency without asking the PM first. Use the installed skills from `06-tooling.md` before
  writing code they cover. Server Components by default in the frontend; `'use client'` only on
  interactive leaves. Every animation respects `prefers-reduced-motion`. Never read/write/echo
  `.env*` files or secrets. Never run destructive git commands; never `git add -A`/`git add .`
  (this repo isn't even a git repo yet — if the user wants it initialized, that's a PM/user decision,
  not something a role does unprompted).
