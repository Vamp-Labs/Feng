# Feng 5 plans for the Investment Thesis Launchpad PRD (2026-10-04)

**Status**: draft, nothing built from this file. Replaces the earlier version of this file (written for the "Composable Strategy Marketplace" PRD) and `2026-10-03-feng-v2-plan.md`.
**Deadline**: HackQuest submission 2026-10-04 23:59 SGT. Written at about 03:30 SGT, so roughly 20 hours remain.
**Source of truth for features**: `PRD.md` (Investment Thesis Launchpad). Technical choices are mine.

## 0. What the new PRD means for the code

PRD loop: CREATE THESIS -> BUILD STRATEGY -> PUBLISH -> DISCOVER -> FOLLOW / PARTICIPATE -> TRACK. Five pages (Explore, Strategy Detail, Create, Portfolio, Creator Profile), four nav items (Explore, Create, Portfolio, Profile). **Out of scope per PRD**: complex rebalancing, automated trading, composability is not mentioned, comments, copy trading, cross-chain.

Verified state at 03:28 SGT:
- The V2 deploy that was started earlier **finished** (60 of 60 receipts, nothing running). Deployer holds about **0.0039 ETH**. Relayer and faucet hold 0 ETH, nothing is seeded, no keeper runs. The live site still runs V1 (exploitable, price feeds stale).
- The V2 registry already stores what the PRD needs: thesis = `description` (max 160 bytes), category = first of up to 3 `tags`, `creator`, `createdAt` (`contracts/v2/interfaces/IMarketplaceRegistryV2.sol`). **No contract change is needed for thesis, category, creator or date.**
- Missing for the PRD: followers and follow state, creator profile (handle, bio), trending and new rankings, an Explore home with categories, the 5-step create flow with Thesis, participate confirmation with a clear testnet label, a strategy-first portfolio, creator pages, extra stocks (NVDA, TSMC, MSFT and themed names for Robotics, Space, Energy), and seeded content from several creators.

## 1. Decisions I made (change any of them)

| # | Decision | Why |
|---|---|---|
| D1 | Stay on Robinhood Chain testnet, described as an Arbitrum L2 | Everything is deployed there |
| D2 | Use the finished V2 deployment as the execution layer: **Participate = V2 USDG deposit**; labelled TESTNET in the UI | PRD allows a demo/testnet flow and demands a clear label |
| D3 | **Follow and creator profile live on-chain** in one tiny new contract `SocialRegistry` (follow/unfollow a vault or a creator, counts, `setProfile(handle, bio)`) | Shared counters like "1,284 followers" need shared state; no database account or CAPTCHA; fits the web3 story; costs about 0.0003 ETH to deploy. Alternative if rejected: a hosted DB with Privy-verified identity (needs the Privy app secret and a DB account) |
| D4 | Thesis = registry description; category = first tag (AI, Robotics, Space, Energy, Semiconductors, Technology) | No contract change |
| D5 | Trending = followers plus recent deposits from event logs, computed client-side; New = `createdAt` | PRD only needs it to feel right; no indexer |
| D6 | **Explore replaces the home page and `/marketplace`** (one discovery surface, as the PRD says); keep the earlier unified card design and holdings bar | PRD is the latest instruction; supersedes the 2026-10-01 layout split |
| D7 | **Composability and rebalancing leave the main flows** (hidden behind a small "Advanced" area, vault behaviour unchanged); the keeper stays as a quiet background service | PRD puts complex rebalancing out of scope |
| D8 | Extra stocks are mock tokens deployed additively: NVDA, TSMC, MSFT, GOOGL plus themed names (RKLB, ISRG, XOM, ENPH); prices from Robinhood's public price API through the existing relayer | PRD example uses NVDA, AMD, TSMC, MSFT; categories need names |
| D9 | Seed about 12 thesis strategies from 3 to 4 creator wallets (@alex style handles) with profiles and some follows | Explore, Trending and Creator pages must look alive for judges |
| D10 | Keep Privy, framer-motion, lenis, current site tokens | Earlier user decisions |

## 2. The five plans

### Plan 1. Foundation live: finish V2 operations (P0, about 2h)
- **Goal**: working, always-on V2 infrastructure.
- **Agent**: `general-purpose` (ops), skill `develop-secure-contracts`.
- **Input**: `.env.ops` (never printed), `deployments/robinhood-testnet-v2/addresses.json`, `docs/handoffs/STATUS.md`, `scripts/deploy-v2.sh`, `script/DeployV2.s.sol`.
- **Tasks**: (1) confirm every V2 address has code; (2) fund relayer and faucet from the deployer, keep at least 0.0015 ETH back for Plan 2; (3) start relayer and keeper, confirm one `Rebalanced` event from a non-deployer address; (4) verify the core contracts on Blockscout (`docs/handoffs/VERIFY-LOG.md`); (5) record `NEXT_PUBLIC_CONTRACT_VERSION=v2` and the V2 addresses for the frontend.
- **Output**: complete `addresses.json` with no zero address, running keeper and relayer, ETH report.
- **Connects to**: unblocks Plan 2. Stop for the user: a testnet ETH claim if the deployer drops under 0.0015.
- **Acceptance**: `strategyCount()` works on V2 and `previewDeposit` returns a quote.
- **Risk**: ISP TLS errors (retry, never rerun a broadcast, use `--resume`).

### Plan 2. Social layer and thesis content on chain (P0, about 5h)
- **Goal**: followers, creator profiles and a seeded, believable launchpad.
- **Agent**: `general-purpose` (contracts), skills `develop-secure-contracts`, `setup-solidity-contracts`, `property-based-testing`.
- **Input**: PRD sections 4 to 10 and 13, `contracts/v2/*`, `script/SeedV2.s.sol`, `script/DeployV2.s.sol`, D3 to D9.
- **Tasks**: (1) `contracts/v2/SocialRegistry.sol`: follow/unfollow a vault or a creator, `followerCount`, `isFollowing`, `followedBy(user)`, `setProfile(handle, bio)` with length limits and unique handles, events; tests including invariants; (2) additive mock stocks and oracle feeds and desk support (`script/AddAssetsV2.s.sol`), relayer price list extended; (3) seed about 12 thesis strategies (names like AI Will Win $AIWIN, Semiconductor Boom, Robotics Future, plus Space and Energy themes) from 3 to 4 creator wallets (fund each with a tiny ETH amount), with a category tag and a 160-byte thesis, a small first deposit each, a few profiles and follows; (4) write the frozen ABI and JSON shape for the frontend in the first hour.
- **Output**: `docs/handoffs/05-social-registry.md` (ABI sketch, addresses.json keys, seed table), contracts and tests green, `deployments/robinhood-testnet-v2/addresses.json` with `socialRegistry`, regenerated ABIs under `src/lib/abi/generated`, seed log with vault addresses.
- **Connects to**: needs Plan 1; its ABI file unblocks Plans 3 and 4 (they can start against the sketch in hour 1).
- **Acceptance**: `forge test` green; on chain: about 12 strategies, handles and bios set, follower counts non-zero on at least 5 strategies.
- **Risk**: ETH budget (about 0.002 to 0.003 needed in total); stop and report if the deployer would drop under 0.0005.

### Plan 3. Explore, Strategy Detail and Participate (P0, about 6h)
- **Goal**: PRD features 1, 2, 4, 5: discover, understand, follow, participate.
- **Agent**: `work:frontend` (skills: `work:reuse-first`, `work:nextjs-app-router`, `work:react-components`, `work:motion-react`); read-only `work:frontend:reviewer` at the end.
- **Input**: `PRD.md` sections 4, 5, 7, 8, ABI sketch from Plan 2, `src/components/strategy-card.tsx`, `src/components/home/*`, `src/components/strategy-detail-v2.tsx`, `src/components/deposit-redeem-panel-v2.tsx`, the 2026-10-01 brainstorm file for card anatomy. Read `AGENTS.md` and the Next docs first.
- **Owns**: home page, strategy card, strategy detail, participate panel, activity, social hooks (`use-follow`, `use-follower-count`). Does not touch create, portfolio, profile, nav.
- **Tasks**: (1) social hooks first (hour 1; Plan 4 reuses them); (2) **Explore** as the home page: Trending Strategies, New Strategies, Categories chips, filtered grid, strategy card with thesis, allocation chips and follower count, CTA "View Strategy"; (3) **Detail**: header with creator link, Follow and Participate, thesis, allocation bars, info block (creator, category, created, followers, description), activity feed from event logs; (4) **Participate**: amount input, clear TESTNET label, simple confirmation ("Strategy participation confirmed, View Portfolio"), wired to the V2 deposit with the transaction explained in plain words; (5) remove composability and rebalance from the main surfaces (keep behind "Advanced").
- **Output**: updated routes and components, `pnpm lint` and `pnpm build` green, a short list of anything untested.
- **Connects to**: needs Plan 2 ABIs; hands finished hooks to Plan 4.
- **Acceptance**: from Explore, open a strategy, follow it (count goes up), participate with 1,000 test USDG, see the confirmation.
- **Risk**: `getLogs` limits (chunk and cache); users need test ETH (the `/start` faucet already exists).

### Plan 4. Create, Portfolio, Creator Profile and navigation (P0, about 6h, parallel with Plan 3)
- **Goal**: PRD features 3, 6 and the creator profile, plus the 4-item navigation.
- **Agent**: `work:frontend` (same skills).
- **Input**: `PRD.md` sections 6, 9, 10, 11, ABI sketch from Plan 2, `src/components/create-strategy-form.tsx`, `positions-list.tsx`, `wallet-menu.tsx`, `nav-links.tsx`, `docs/brainstorm/2026-10-03-create-page-form-redesign.md`.
- **Owns**: create, portfolio (`/positions` becomes Portfolio), creator profile route, navigation, profile editing. Does not touch home, card or detail.
- **Tasks**: (1) **Create**: 5 steps (Name and Ticker, Thesis, Select stocks and allocation to 100%, Preview, Publish), writes thesis into the registry description and category into the first tag, ends on the new strategy page; (2) **Portfolio**: strategy-first list of participated strategies (amount, allocation chips, View Strategy) plus a Following tab from `SocialRegistry`; (3) **Creator Profile** `/creator/[address]`: handle, bio, followers, follow button, list of their strategies; a small edit-profile form for the signed-in user; (4) nav with exactly Explore, Create, Portfolio, Profile; (5) empty and loading states with plain copy.
- **Output**: new routes `/create` (stepper), `/positions` (Portfolio), `/creator/[address]`, nav update; lint and build green.
- **Connects to**: consumes Plan 2 and Plan 3's social hooks (build the create flow first, portfolio last).
- **Acceptance**: a brand-new email wallet creates AI Will Win with a thesis, sets a handle, and sees the strategy on its profile and in Explore.
- **Risk**: first real Privy login with the new flows; budget rehearsal time.

### Plan 5. Verify, ship, submit (P0, about 5h, starts after Plans 3 and 4 are green)
- **Goal**: a judge completes the PRD scenario (section 13) on the live URL without explanation.
- **Agent**: `hackathon-pm` (docs and coordination) with `general-purpose` (deploy), `work:frontend:reviewer` and a read-only security pass.
- **Input**: all plans, `PRD.md` sections 12 to 14, `docs/submission/`, `README.md`, `docs/security/*`.
- **Tasks**: (1) Vercel preview with production env vars set through the CLI from `.env.ops` without echoing; user adds the preview origin to Privy; (2) rehearse as a new user: create AI Will Win, explore it as another user, read the thesis, follow, participate with 1,000 test USDG, track it in Portfolio, open the creator profile; (3) reviewer and security findings fixed; (4) promote the preview to production only after the rehearsal passes; (5) README and PRD wording (Investment Thesis Launchpad, Robinhood Chain testnet as an Arbitrum L2, real-versus-mock table, known limitations, V1 retired); (6) HackQuest answers, demo script, 3-minute video outline; (7) GitHub repo public with MIT after the secret scan (push needs the user's yes).
- **Output**: production URL, rehearsal report, `docs/submission/*`, final STATUS.
- **Connects to**: needs Plans 1 to 4. Stops for the user at: Privy origin edit, CAPTCHA tasks, GitHub push, final submission.
- **Acceptance**: PRD success criteria (creator: idea to publish; explorer: discover to follow; participant: participate to track) work for a new wallet on the production URL; `pnpm build` and `forge test` green; no secret in the repo.
- **Risk**: video recording from a network the ISP does not filter.

## 3. Order and dependencies

```
Plan 1 (foundation) -> Plan 2 (social + seed) -+-> Plan 3 (Explore, detail, participate) -+
                                               +-> Plan 4 (create, portfolio, profile)  -+-> Plan 5 (ship)
```

- Hour 0: Plan 1 starts; Plans 3 and 4 may start at once against the ABI sketch Plan 2 writes in its first hour (use the existing V2 ABIs until then).
- About hour 2: Plan 1 done; Plan 2 deploys and seeds. About hour 7: addresses and seed data frozen.
- Hour 12: feature freeze. Hours 12 to 20: Plan 5.
- File ownership is split so Plans 3 and 4 never edit the same files; shared social hooks are built by Plan 3 first.

## 4. Open questions (default in brackets)

1. Follow and profile on-chain (D3) or a hosted database? [on-chain]
2. Explore replaces both the home hero and `/marketplace` (D6)? [yes]
3. Drop composability and rebalancing from the main UI (D7), or keep a visible Compose entry? [drop, hide under Advanced]
4. Are you registered on HackQuest? Notes conflict: closing 2026-10-03 01:01 SGT versus 2026-10-04 23:58 SGT. [check now]
5. Can you claim testnet ETH in a browser if the deployer runs low? [yes]
