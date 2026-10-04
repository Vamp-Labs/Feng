# Status (Feng v2 run)

## 2026-10-04 PRD2 rebuild (Investment Thesis Launchpad) — dispatch log
Plan source: `docs/brainstorm/2026-10-04-feng-prd2-five-plans.md`. User approved execution directly (no new gate), code-only from here.
Dispatched ~04:00 SGT, all four in parallel:
- Plan 1 (foundation ops: verify V2 addresses, fund relayer/faucet, start keeper, verify on Blockscout) — general-purpose — dispatched
- Plan 2 (SocialRegistry contract, additive mock stocks, seed ~12 strategies, writes `docs/handoffs/05-social-registry.md`) — general-purpose — dispatched
- Plan 3 (Explore/Detail/Participate + social hooks, owns home/card/detail/participate/activity) — me:frontend — dispatched
- Plan 4 (Create/Portfolio/Creator Profile/nav, owns create/positions/creator/nav) — me:frontend — dispatched
Plan 5 (ship/submit) waits until 1-4 report green. See below for results as they return.

Verified before dispatch: V2 deploy confirmed 60/60 receipts at `broadcast/DeployV2.s.sol/46630/run-latest.json`, matches `deployments/robinhood-testnet-v2/addresses.json` (deployedAt 1791054186). Deployer ETH not yet re-checked by me; Plan 1 will report exact balance.

### Plan 1 — interim (02:49 SGT)
Reported a pause, waiting on its own background "verification monitor" before compiling a final report. No balances/tx hashes relayed yet. Will re-check when it resumes.

### Plan 4 — returned (02:49 SGT), PM-verified
Create (5-step wizard, Advanced disclosure for rebalance/max-weight per D7), nav (Explore/Create/Portfolio/Profile), `/creator/[address]` + creator-profile component, Portfolio Strategies+Following tabs — all built. Did not find Plan 3's social hooks yet at build time, so it stubbed its own (`src/lib/hooks/use-social-registry.ts`, `src/lib/social-registry.ts`, `src/lib/abi/social-registry-sketch.ts`) against `05-social-registry.md`'s signatures, gated to show "not live yet" since `addresses.socialRegistry` is unset.
PM verification: `pnpm lint` clean (0 errors, 2 warnings in `strategy-detail.tsx` — Plan 3's file, still mid-edit), `pnpm build` clean (all routes compile, including `/creator/[address]`).
### Plan 3 — returned, PM-verified
Explore (replaces home + `/marketplace`, which now redirects to `/`), Strategy Detail restructured to PRD flow with composability/rebalance demoted to an `<details>` "Advanced" block (nothing deleted), new `ParticipatePanel` (TESTNET-labelled deposit, approve→deposit→confirmation→View Portfolio), real `use-follow`/`use-follower-count`/`use-profile` hooks wired to the live `SocialRegistry` (`0xe0FaeeD02db34f98Da05bab08E01a1473f8dC6F1`, confirmed in `addresses.json`) via a hand-transcribed sketch ABI (`src/lib/abi/social-registry-sketch.ts`, marked TEMPORARY pending Plan 2's generated ABI).
PM verification: `pnpm lint` 0 errors / 0 warnings (clean, including the Plan-4-authored unused-import warnings seen earlier — resolved now that both plans landed). `pnpm build` clean, all 9 routes incl. `/creator/[address]` and `/strategy/[vault]`.
Untested in-browser (deposit/follow against a real wallet) — type-checked and reviewed only, per the agent's own report.

### Reconciliation dispatched (03:xx SGT)
Confirmed duplication: Plan 4's `src/lib/hooks/use-social-registry.ts` redefined its own `useFollow`/`useFollowerCount`/`useCreatorProfile` against a second inline ABI, parallel to Plan 3's canonical `use-follow.ts`/`use-follower-count.ts`/`use-profile.ts` (`@/lib/social-registry.ts`). Dispatched a scoped `me:frontend` follow-up to: retire the duplicated three hooks, keep Plan 4's two non-duplicate ones (`useFollowedTargets`, `useSetProfile`) rewired onto the canonical ABI/address source, and repoint `creator-profile.tsx` + `positions-list.tsx` at the canonical hooks (adjusting `.available`→`.isAvailable` field-name differences). Scope-limited to those 2-3 files. Running now.

**Reconciliation — returned, PM-verified**: `use-social-registry.ts` now only exports `useFollowedTargets`/`useSetProfile`, rewired onto the canonical `@/lib/social-registry.ts` ABI/address; `creator-profile.tsx` and `positions-list.tsx` repointed at canonical `useProfile`/`useFollow`/`useFollowerCount`. `follow-button.tsx` left as-is in creator-profile (size-prop mismatch, out of scope, noted not a blocker). PM re-ran `pnpm lint` (0/0) and `pnpm build` (clean, 9 routes) myself — confirmed green. **Plans 3+4 are now fully reconciled and green.**

### Plan 2 — returned, PM-verified
`forge test`: PM re-ran myself, 609/609 green (matches agent's own count). `SocialRegistry.sol` (hand-rolled swap-and-pop sets, not OZ EnumerableSet — repo's `evm_version=paris` can't use OZ v5.7's Cancun-only `mcopy`). 8 new stock tokens/oracles added additively (NVDA/TSMC/MSFT/GOOGL/RKLB/ISRG/XOM/ENPH — PM confirmed 13 total stockTokens keys in addresses.json, all 5 originals intact). 12 strategies seeded from 4 creators; PM confirmed on-chain `strategyCount()` returns 12 (direct `cast call`, succeeded on 3rd retry — see ISP note below). Deployer ETH: 0.00389 → 0.000689 (PM confirmed this exact balance independently), stayed above the 0.0005 floor throughout. `docs/handoffs/05-social-registry.md` finalized, `src/lib/abi/generated/socialRegistry.ts` generated and confirmed present. One flagged note (not fixed, outside this plan's ownership): ticker key `TSMC` vs Robinhood's real symbol `TSM` — needs Plan 1/ops to reconcile in the price feed list.

### Plan 1 — still in progress (03:21 SGT check)
PM independently confirmed real progress, this is not idle: Blockscout verification done (`VERIFY-LOG.md`, verified_now=20 failed=0, all V2 core contracts incl. the new `live.*` proxies — `guardian` shows unverified but that's an EOA, not a contract, expected). Relayer funded 0.00119 ETH, faucet funded 0.0006 ETH. `NEXT_PUBLIC_CONTRACT_VERSION=v2` confirmed in `.env.local` (only that line touched, other secrets untouched). `strategyCount()=12` confirmed queryable on V2. A keeper/relayer process (`scripts/ops-worker.ts --full`, pid 2933248) has been running 40+ min, 20 iterations: confirmed at least one real on-chain heartbeat push (6 tx hashes, feeds refreshed) — but **no `Rebalanced` event yet**, because the Robinhood price API fetch has failed 20/20 times over 40 min (`fetch failed`, same ISP pattern as the RPC's intermittent TLS — one `cast` call even returned a cert for `internetsehatku.com`, an Indonesian ISP content-filter domain, confirming this is network-level interference, not a contract bug). Without a live price delta, nothing triggers a rebalance. Not blocking Plans 2-4; the agent's own process is still auto-retrying. Likely moot for the real demo since production hosting (Vercel/Railway, not this home connection) would run the keeper from different infra. No user action needed yet — flagging for visibility only.

### Rebalanced-event investigation (03:20-03:40 SGT) — PM, root-caused, not fixed, deprioritized
Confirmed definitively via a DNS-over-HTTPS bypass test (`curl --doh-url https://1.1.1.1/dns-query`) that both `api.robinhood.com` (price API) and `rpc.testnet.chain.robinhood.com` work perfectly when the local poisoned DNS resolver is bypassed — the system resolver redirects `api.robinhood.com` to `aduankonten.id`, Indonesia's government ISP content-block landing page. This is conclusive: the organic no-Rebalanced-event condition is 100% local ISP censorship, not a contract or code bug. RPC itself is only intermittently hit (~30-40% success this session); the price API appears fully blocked (0/20+ attempts over the keeper's run).
Tried to force a `Rebalanced` event via the project's own `scripts/demo-shock.sh` (built for exactly this) on 2 safe, bounded combinations (GREEN vault/TSLA at 18%, CHIPS vault/AMD at 15% — both real on-chain shock+restore txs, confirmed by hash, no funds at risk). Neither crossed the vault's rebalance threshold band (`maxWeightBps` 35-45%, well above seeded target weights) — consistent with the vaults' conservative anti-manipulation design, not a bug. `rebalanceInterval` is 604,800s (7 days), so the time-based trigger won't fire during the hackathon window either.
**Decision**: stopping here rather than continuing to spend RPC-retry time/ETH chasing one event. The rebalance mechanism itself is already proven correct off-chain (609/609 forge tests, including dedicated invariant/fuzz suites). Recording as a known, accepted limitation for Plan 5's submission writeup: "a live on-chain Rebalanced event was not observed this session due to ISP-blocked price feeds + the vaults' conservative safety bands; the mechanism is unit/invariant-tested." Not on the demo path (D7 moves rebalancing to a non-primary Advanced area).

### Fix dispatched: TSMC vs TSM ticker mismatch (03:40 SGT)
Scoped `general-purpose` fix to `src/ops/prices.ts`: add an internal-ticker-to-Robinhood-API-symbol override map (`TSMC` → `TSM`) applied only to the outbound URL, keeping the internal `TSMC` key everywhere else (addresses.json, contracts, seed data, `Quote.symbol`). Running now.

### TSMC/TSM fix — returned, PM-verified (03:41 SGT)
`src/ops/prices.ts`: `API_SYMBOL_OVERRIDES = { TSMC: "TSM" }` applied only to the outbound Robinhood URL; internal `TSMC` key untouched elsewhere. PM re-ran `pnpm lint`/`pnpm build` myself — clean. PM restarted the keeper/relayer process (`scripts/ops-worker.ts --full`, old pid 2933248 killed, new pid 3074573, same env: `OPS_DEPLOYMENTS=v2 OPS_WORKER_INTERVAL_SEC=120`) so it picks up the full 14-symbol list (previously only knew the original 5, since it started before Plan 2 added the other 9). Confirmed iteration 1 now sees all 14 symbols including `TSMC`, and successfully heartbeat-pushed the 8 new tickers on-chain. Price API still ISP-blocked for all symbols (expected, documented above) — the TSM mapping is correctly wired and will resolve once the network path is open (e.g. from production hosting).
PM also directly confirmed Plan 1's two remaining acceptance items myself: `strategyCount()` → 12, `previewDeposit(1000 USDG)` → ~999 shares (sensible 1:1-minus-fee quote). **Plan 1 is now fully closed**, with the Rebalanced-event item downgraded to a documented, accepted limitation (see above).

### All of Plans 1-4 are green. Proceeding to coordinate Plan 5 now (deploy/rehearse/ship), per original dispatch instructions ("you coordinate this yourself").
PM found before dispatching: `docs/handoffs/RUNBOOK-DEPLOY.md`'s step 6 ("archive V1, switch deployments/robinhood-testnet to V2") is superseded — `src/lib/addresses.ts` already reads `deployments/robinhood-testnet-v2/addresses.json` directly when `NEXT_PUBLIC_CONTRACT_VERSION=v2` (which Plan 1 already set locally), so no file-switch step is needed before deploying.
Dispatched general-purpose Plan 5 step 1: Vercel **preview** deploy only (existing linked project `composable-strategy-marketplace`/candra0x6, no new project). Sets preview-scope env vars (NEXT_PUBLIC_CONTRACT_VERSION=v2 + others, CRON_SECRET/RELAYER/FAUCET/KEEPER keys piped not echoed), deploys preview, smoke-tests `/` and `/api/ops/health`, stops before any production action. Will report the preview URL and the exact Privy-origin string the user needs to add. Running now.

### Plan 5 step 1 — returned, PM-verified (04:0x SGT)
Preview: `https://composable-strategy-marketplace-a5xemhqg9-candras-projects.vercel.app`. PM confirmed independently: `vercel env ls preview` shows all 9 vars set, scoped Preview only. Build succeeded (no `--prod`). `/api/ops/health` (via authenticated `vercel curl`) returns 503 with clean body — alarms are v1-feed-staleness only (expected, V1 is retired), all v2 feeds fresh, `faucet.mode: contract` as expected.
**Blocker, stop point reached (named in the original plan — "Privy origin edit")**: Vercel **Deployment Protection** (SSO wall) is on for this project — PM confirmed plain `curl /` → 302, same as the dispatched agent found. This blocks automated smoke testing (by me or any agent) but should NOT block the user themselves, since they're already authenticated to the `candras-projects` Vercel team in their own browser. Needs a user decision: disable protection for Preview, add specific people (e.g. judges) to the team, or generate a "Protection Bypass for Automation" secret — PM did not toggle this, it's a project security setting.
**Action needed from user**: (1) add `https://composable-strategy-marketplace-a5xemhqg9-candras-projects.vercel.app` to Privy's allowed origins; (2) decide on Deployment Protection for Preview (see above). Reported to user, awaiting reply before the full new-user rehearsal (Plan 5 task 2).

## CRITICAL: large real-time gap discovered (14:3x SGT, was ~03:4x SGT last check)
A `date` check mid-rehearsal showed ~10 hours of real wall-clock time had passed since the last explicit check, invisible across the async notification turns. **Deadline 23:59 SGT — roughly 9.5 hours left, not ~20h.** Re-prioritizing accordingly; told the user plainly in this turn's report.

### Coordinator-directed actions taken this turn
1. **Disabled Vercel Deployment Protection (SSO wall)** for the project via `vercel project protection disable composable-strategy-marketplace --sso` — confirmed via `vercel project protection ... --json` (`ssoProtection: null`) and a plain `curl` now returning 200 instead of 302. No production deployment exists yet, so nothing production-facing was exposed; will revisit protection scope at the production-promotion step.
2. **Rehearsed via `browser-cdp`** (the user's own Brave/CDP tooling, available on this machine) against the real preview: Explore, Strategy Detail (AIWIN), Creator Profile (@alex), Create (5-step wizard), Portfolio all render correctly and closely match the PRD's example copy/layout. Nav is exactly Explore/Create/Portfolio/Profile.
3. **Wallet-login blocker confirmed with hard evidence, not inference**: `curl` to Privy's own app-config endpoint (`https://auth.privy.io/api/v1/apps/<app-id>` with the app's privy-app-id header) returns `"allowed_domains":[]` — empty. No domain is whitelisted at all right now, not just this preview. This is the exact blocker the coordinator anticipated; could not proceed past wallet connect for the two-wallet participate/follow/track flow.
4. **New finding, also from that same config response**: `"embedded_wallet_config":{"create_on_login":"off", ..., "mode":"user-controlled-server-wallets-only"}` — a brand-new email-only login may NOT auto-create a usable embedded wallet under this Privy app setting. Flagging for the user to check in the Privy dashboard (Embedded Wallets settings) — this could affect the "brand-new user creates a strategy" acceptance scenario even after the origin is fixed. Not changed by PM (auth/product behavior decision, not an access toggle).
5. **Created a stable preview alias**: `https://feng-thesis-launchpad.vercel.app` → always points at the latest preview deploy (`vercel alias set`). Recommend the user add THIS to Privy instead of the throwaway per-deploy URL, so future `vercel deploy` runs don't require re-adding a new origin each time.
6. **Fixed a real demo-visible bug**: the site-wide health badge was reading both V1 (permanently retired/stale) and V2 feeds, so every page showed "Degraded, feeds 3 d old" even though V2 itself was fine. Added `OPS_DEPLOYMENTS=v2` to Vercel preview env (matches what Plan 1 already used locally) and redeployed — confirmed via `/api/ops/health` the alarm list is now V2-only.
7. **Rebalanced-event open item from earlier — now resolved, unexpectedly**: manually triggered `POST /api/ops/tick` against the Vercel deployment (with `CRON_SECRET`, bearer auth) — since Vercel's servers aren't behind the local ISP, this succeeded where the local keeper couldn't. Result: 4 real on-chain `Rebalanced` events (AIWIN, CLOUD, BARBL, BIGT vaults) with confirmed tx hashes, keeper wallet (non-deployer) as sender. The earlier "accepted limitation" write-up is superseded — it did happen, just needed to run from non-ISP-filtered infrastructure.
8. **New risk found**: 5 tickers (TSMC/TSM, GOOGL, RKLB, ISRG, ENPH) still fail to get a live quote even from Vercel's unfiltered network — likely Robinhood's price API doesn't actually offer these specific symbols (possibly beyond Robinhood's real tokenized universe, a Plan 2 asset-selection issue, not a network issue). Their on-chain price is frozen at seed-time and will start reverting deposits/rebalances with `StalePrice` after `maxPriceStaleness` (12h) if untouched — currently ~10.7h old, so **roughly 1-1.5h of runway** before this bites. Flagged to user rather than spending remaining time on a fix; a cheap mitigation (manual `updateAnswer` refresh) is possible close to demo time if needed.
9. Local keeper process had died silently during the ~10h gap (background processes don't survive that); restarted again (new pid, logs now at `/tmp/feng-ops/` instead of the per-session scratchpad, which appears to get recycled across long gaps). Recommending reliance on the Vercel `/api/ops/tick` route (manually triggered by PM, or ideally a real external cron) rather than the local process going forward, given the demonstrated fragility.

### Manual price refresh for the 5 stale tickers — done (coordinator-directed, "fast path")
Confirmed relayer (`0x0E9053318B9cBE351dc79F3Ba538D7A01f0934fc`) holds `UPDATER_ROLE` on all 5 feeds. Pushed `updateAnswer(<same last price>)` from the relayer key for each, resetting `updatedAt` to now (buys another ~12h `maxPriceStaleness` window):
- TSMC `0xc0ff17b1...` status 1
- GOOGL `0xc9fb6d5c...` status 1
- RKLB `0x75411151...` status 1
- ISRG `0x4cc9a87d...` status 1
- ENPH `0x3f585b04...` status 1
XOM checked separately — already fresh (~3 min old), no action needed (likely from an earlier tick's partial success).
**Verified**: `/api/ops/health` now returns `ok: true`, `alarms: []`. Clean for rehearsal/demo. Will repeat this refresh once more closer to submission time per the coordinator's instruction if the window is closing.

### Waiting on the user's two Privy fixes (add `https://feng-thesis-launchpad.vercel.app` to allowed origins; check `create_on_login`) before continuing the full end-to-end rehearsal (wallet login + participate tx). Everything else (price refresh, health, protection, alias) is ready to go the moment login works. Fast-path order confirmed by coordinator: rehearsal -> production deploy -> stop for user's GitHub-push yes -> lightweight submission materials.

### Plans 3 & 4 — reconfirmed for the record (both already reported done + PM-verified above)
Plan 3 (`me:frontend`, Explore/Detail/Participate + social hooks) and Plan 4 (`me:frontend`, Create/Portfolio/Creator Profile/nav) were dispatched in the very first batch alongside Plans 1-2, finished, were PM-verified (`pnpm lint`/`pnpm build` clean), and a found hook-duplication was reconciled (also PM-verified clean). Nothing further to dispatch for them.


Plan: `docs/brainstorm/2026-10-03-feng-v2-plan.md`. Approval: user said "yes" to the plan and its open questions 1-5; defaults for 1-13 apply (V2 go/no-go at G1, Vercel route + pinger, repo public MIT after secret scan, V2 becomes production key, user claims Paxos USDG/faucet tokens in a browser when asked).
Previous (2026-09-28) status archived at `STATUS-2026-09-28-archive.md`.

## Clock
- T0 = 2026-10-03 22:21 SGT (14:21 UTC), measured with `date`.
- Hard deadline: 2026-10-04 23:59 SGT = T+25h38m. Planned submit by 21:21 SGT (T+23h).
- G0 T+1h = 23:21 SGT Oct 3. G1 T+12h = 10:21 SGT Oct 4. G2 (feature freeze) T+16h = 14:21 SGT Oct 4.

## Current step
All agent work that does not need the user is finished (02:30 SGT). G1 evidence complete at 01:58 SGT (T+3h37m), ahead of the T+12h gate. Waiting on the user for the V2 deploy (keys + funding approval). F4 (frontend integration/audit) and FIX-A (ops/script hardening) running.

## G0 result (T+0:30)
PASS with a user action: HackQuest registrationClose was EXTENDED to 2026-10-04 23:58 SGT (live API, docs/research/14); submissionClose 23:59 SGT unchanged. Registration is a precondition to submit, and only the user can see their status (login). User must open the buildathon page and confirm the button reads "Start Submit".

## Findings that change the run
- All 6 V1 price feeds are ~50 h stale: every deposit, redeem and rebalance on the live testnet deployment reverts StalePrice (BASELINE section 3). Needs a funded tx (user supplies a key).
- Local keeper process is dead (last action 2026-10-02 00:25Z). No keeper.sh running.
- Port 3000 is the Feng next dev server (pid 636015, cwd this repo, 3.7 GB, not answering): not "another project". Left alone, user decides.
- Redesign builds clean: lint 0, tsc 0, build 0 (all 5 routes). Multicall3 set: /marketplace now 3 eth_calls instead of ~51.
- forge test 48/48.

## Done
- Plan, 07-testnet-reality-check, old STATUS and DEMO-NOTES read (22:2x SGT).
- Live-state check: no keeper process running (laptop keeper is dead). Port 3000 is served by `next-server` whose cwd is THIS repo (pid 636015, started 14:34 local), not another project; left untouched. Nothing on 3001/8545/8546.

## Agents
(see table below, updated as agents are dispatched / return)

| Agent | Lane / tasks | State | Result |
|---|---|---|---|
| a64d7dc9601f96215 | GP/baseline: E0-T1 baseline, E0-T2 repo hygiene | returned | BASELINE written; 48/48; feeds 50 h stale; git init local, LICENSE MIT; no secrets staged |
| abdd517b877d10b1c | me:frontend: E0-T3 rebrand, E6-T0 sweep, E6-T2 multicall | returned | Feng rebrand, multicall3, query client; lint/tsc/build pass |
| a014350d9bf54ae74 | research R2 price source -> 09 | returned | Robinhood API usable, no Pyth/Chainlink testnet, 10% bound, 5 min tick |
| a625f249ab462d587 | research R4 Blockscout verification -> 11 | returned | forge verify works w/ retries; ctor args = creation_bytecode suffix; V1 registry + AIGR vault now verified; ISP = DNS poisoning ~50% |
| a604a7c40e485df54 | research R5 always-on hosting -> 12 | returned | Vercel Hobby (cron daily only) -> cron-job.org 5 min + UptimeRobot watchdog; skip Railway |
| a0e8f180627c87207 | research R7 HackQuest -> 14 (G0 input) | returned | registration extended to Oct 4 23:58 SGT; 300-char caps; em dash format |
| a700a5f89b7233a1b | E3-T0 V2 spec -> docs/handoffs/04-contracts-v2.md | returned | frozen spec, 36 decisions C-01..C-36, side-by-side contracts/v2, MVP cut line in 7.3 |
| a7f26e9792c2aac52 | GP/ops: E2-T1..T3,T8, E10-T1 faucet route V1, runbook | returned | relayer/keeper/health/tick/faucet routes built, lint/tsc/build pass, dry-run would push 6 feeds + rebalance EVMO/BLTZ/CONV; send paths exercised on a local fork only; not deployed |
| a58b1b1d2a236b302 | me:frontend F1: E9-T1 visual verify+fixes, E10-T2, E5-T1a | returned | 15 visual findings, 14 fixed (1 accepted, 1 third-party Node25 localStorage warning open); Get test funds UI, wallet menu, network banner, since-inception return; lint/tsc/build pass; connected flows not exercised (Privy placeholder id); REPORT.md could not be written (harness blocks report files) - findings kept here |
| a39d2fbbe45f8fa45 | research R1 real assets+USDG -> 08 | returned | GO Live at demo scale; Paxos faucet 100 USDG/wallet/day no CAPTCHA; stock faucet 5 each + 0.01 ETH; USDG is bottleneck; vault freeze risks documented |
| a8ae8004d96b5ab08 | research R3 venue -> 10 | returned | only TSLA has a USDG v4 pool (~$100 liquidity, 87% impact at 500 USDG): no v4 venue; desk only |
| a9b71499a2d7514be | docs: README skeleton, submission pack, R8 -> 15 | returned | README, submission pack, gen-addresses-md.sh written; [V2-PENDING] markers to resolve after G1; R8: real Chainlink feeds are 19-24 h old on weekends, NFLX has no feed |
| a575dbd0d9482aade | GP/contracts C1: vault, token, factory, registry, engine | returned | built; 460/461 v2 tests pass (1 test defect); VaultDeployerV2 24,007 B < 24,576; StrategyLens added; V1 sha256 unchanged |
| a1c928cd34ade9d2c | GP/contracts C2: oracle, desk, mocks, faucet, deploy/seed scripts, sync-abi | returned | periphery done + local rehearsal OK (redeem = NAV minus 10bps spread); BLOCKER: VaultDeployerV2 26,153 B > 24,576 EIP-170 (needs C1 trim) |
| a4b45c7352cbefeb5 | GP/tests: E8-T2 independent tests from spec | returned | 486/486 v2 tests pass, V1 48/48, deep profile 2000 runs pass; coverage 99.6% lines / 94.8% branches (plain mode; --ir-minimum SIGTERMs); findings: revert strings in Registry/Engine, maxSwapUsdg not in spec |
| acf1ceb288bc3de44 | GP/review: E8-T1 threat model (review pass later) | returned | threat model, checklist, known-limitations; V1 EXPLOITABLE (open feed + NAV mint/pot redeem: 1 USDG in, 20,000 out on local PoC) |
| a6e7240720729dd0c | GP/review: E8-T3 independent V2 code review (gates G1) | returned | PASS WITH CONDITIONS: no Critical/High; 486/486; 5 Medium test gaps (killer tests ready), F-01/F-02/F-03 accepted w/ cheap patches; Live shares sandbox oracle (R-V2-03) |
| aea740f91d430e605 | GP/contracts C1b: vault flag patch R-V2-09/10, revert strings R-V2-12 | returned | applied; deployer 24,135 B (441 margin); V1 48/48 |
| a20c09ebcc9c10149 | GP/contracts C2c: anchor window F-01, sandbox desk cap 5000, faucet defaults 0.0001 ETH/40, distinct relayer/faucet addresses | returned | applied and rehearsed at 6 and 18 decimals; 2 aggregator tests need adapting; NOTE: frontend must read maxSwapUsdg (leg above 5,000 USDG reverts SwapTooLarge) |
| a19d5443cd4a119d4 | me:frontend F2: V2 trading | returned | V2 panel/positions/create + V1 decimals fix done; flows exercised on local anvil V2 (deposit, in-kind, redeem, slippage, stale, nested); Live path only with stand-in data |
| ab63cd717c8234e97 | me:frontend F4: integration (decimals, desk maxSwap), builds v1/v2, audit, states pass | returned | PM verified in real repo: lint 0, tsc 0, pnpm build OK (v1 default, 9 pages + 3 api routes); per-trade-limit notice, 7 major a11y/token findings fixed, 121 screenshots v2-final; keyboard flows OK; Live/real wallet untested |
| ae8e0764f58cf1e54 | GP/tests T2: adapt tests, killer tests, deep rerun, coverage | returned | 533 v2 tests + 48 v1 pass (PM re-ran: 581/581); deep invariants 2000 runs x2 pass; coverage 99.6% lines / 94.8% branches; 13 mutants killed |
| af1b9cd40ebf03c8e | GP/review pass 2: aggregator window, flags, desk cap, Live scripts line-by-line, src/ops | returned | PASS: no open High/Critical; new Medium R-V2-24 (round-trip inside window, accept); cap can brick rebalance of large vaults (demo vaults far below); health leaks provider error text (fix dispatched) |
| afe9e050cd2cc204d | GP/FIX-A: redact health errors, price API trust, faucet mode default, deploy-v2.sh has_code + address-file gating | returned | R-V2-27/28/29/31 fixed and verified (lint/tsc/build, 533 tests, dry deploy, tick); new: addresses.json only written when WRITE_ADDRESSES=true; CRON_SECRET min length (R-V2-30) still open |
| af4682d6992deb6de | GP/ops2: V2 relayer/keeper/health/faucet, demo-shock.sh | returned | V2 market mode + paged keeper + checkpoints + contract faucet + demo-shock.sh verified on local anvil V2; lint/tsc/build pass; real-chain send paths untested; V1 and V2 served by one tick |
| a7253d96a1ec3c1ea | GP/contracts C2b: lens deploy, size-limit rehearsal, faucet cap 40, desk maxSwap, DeployLive/SeedLive | returned | rehearsal passes with default size limits; total deploy+seed+live 125 tx, ~0.0011 ETH; Live scripts need --hardfork osaka; faucet cap 40; desk maxSwapUsdg; 486/486 |
| a19d5443cd4a119d4 | me:frontend F2: V2 trading (panel, positions, create, V1 decimals fix) | dispatched 00:15 SGT | pending |
| a561f9027135482ab | me:frontend F3: V2 discovery, detail, rebalance moment, health badge | returned | all P0/P1 built + /start + /leaderboard; verified on local anvil V2 (3 eth_call/page, CLS ~0, rebalance moment works); V1 path smoke OK; no independent audit yet |
| a4fb2783325c649c0 | GP/deploy: E7-T2 verify.sh (run on V1), E8-T4 CI, deploy runbook | returned | all 36 V1 addresses verified on Blockscout; ci.yml + RUNBOOK-DEPLOY written; nothing run in CI |

## Review
(acceptance per epic, pass / fail)

## Blocked on the user
- E0-T5: confirm HackQuest registration (needs login).
- Funding/keys: KEEPER_PRIVATE_KEY in env (refresh feeds + restart keeper); later DEPLOYER_PRIVATE_KEY for the funding batch and V2 deploy.
- Decide: kill the wedged next dev on port 3000? Confirm `vercel deploy` to the existing project counts as covered. GitHub push commands are ready (BASELINE section 7), waiting for the user's yes.

## Decisions recorded (coordinator, 2026-10-04 00:30 SGT)
- F-01 relayer walk: mitigated by 1 h anchor window (patch). F-02: sandbox desk per-swap cap 5,000 USDG, Live 25 USDG; residual accepted. F-04: faucet 0.0001 ETH per claim, cap 40, funded 0.004 ETH. F-05: maxPriceStaleness stays 12 h (43200). F-09: relayer and faucet addresses must differ from deployer; guardian may be deployer (documented). R-V2-03 Live shares sandbox oracle: documented in README/known-limitations.
- Visual findings (frontend F1): 15 found, 14 fixed, 1 third-party warning (Node 25 localStorage in Privy deps). Connected flows untested until a real Privy app id/wallet.

## G1 evidence (2026-10-04 01:58 SGT)
(a) forge test green: PM re-run 581/581 (533 v2 + 48 v1), V1 sources sha256 unchanged. (b) invariants I1-I11 pass at 256 and 2000 runs (6 and 18 decimals); coverage 99.6% lines / 94.8% branches; 13 mutants killed. (c) independent review pass 1 + pass 2: no open Critical/High; Mediums accepted (docs/security/review-v2.md). (d) deploy dry run: DeployV2 + SeedV2 + DeployLive + SeedLive rehearsed on local anvil with default code-size limits at 6 and 18 decimals; est. 125 tx, ~0.0011 ETH. (e) rehearsal deposit->redeem equals NAV minus the 10 bps desk spread (quoteRedeem == paid, to the unit). RECOMMENDATION: GO.
Env check: no key variables are set in this environment (DEPLOYER/KEEPER/RELAYER/FAUCET/CRON_SECRET all unset).
