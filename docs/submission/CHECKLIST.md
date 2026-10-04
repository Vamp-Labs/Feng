# Submission checklist (T-6h)

Deadlines (`docs/research/14-hackquest-submission.md` F1, live HackQuest API read 2026-10-03): registration closes **2026-10-04 23:58 SGT**, submission closes **2026-10-04 23:59 SGT** (22:58 and 22:59 WIB, 15:58 and 15:59 UTC). **Target: submitted by 2026-10-04 17:59 SGT (16:59 WIB, 09:59 UTC), six hours early**, because the organiser can change the server value and the form needs a logged-in session.

Gate times for context: G1 (V2 go or no-go) 2026-10-04 10:21 SGT; G2 (feature freeze) 14:21 SGT (`docs/handoffs/STATUS.md`). Addresses must not change after 15:00 SGT (research 14, implications), because the form and the README quote them.

`[V2-PENDING: this file is the skeleton; the coordinator fills the V2-dependent boxes after G1 and removes the markers]`

## Who does what

- **User (human, needs a login or a camera):** section A.
- **Coordinator (verification agent, read-only checks and edits inside the docs lane):** section B.
- **Both, in order:** section C, the final hour sequence.

## A. Human actions (user)

Do the first four today; they cannot wait. Source: the checklist table in research 14.

- [ ] **A1. Registration state.** Log in to HackQuest and open `https://arbitrum-singapore.hackquest.io/buildathons/Arbitrum-Open-House-Singapore-Online-Buildathon`. The main button must read **"Start Submit"**. "Start Register" means register now (form fields F3 in research 14: name, location, idea and project-URL answers, Arbitrum One wallet, T&C and newsletter radios, email, Telegram, GitHub, Twitter). "Registered" alone, "Pending", "Waitlist" or "Confirm Attendance" is a problem: ask `#open-house` on the Arbitrum Discord (`https://discord.com/invite/arbitrum`) and email `swagtimus@arbitrum.foundation` the same hour; keep a screenshot.
- [ ] **A2. Screenshot** the "Registered" state and keep it.
- [ ] **A3. Click "Start Submit" once** to create the draft; read the project-profile labels and which are required (name, logo, one-line intro, description, tracks, tech stack, demo video, pitch video, repo link, wallet, project progress, fundraising). Save the draft. Do not press final submit. Send the exact labels and the required flags to the coordinator, especially whether the demo video blocks submission and the real character limits of the profile fields.
- [ ] **A4. Join** the Discord `#open-house` channel.
- [ ] **A5. Repository.** Create the GitHub repository and push after the coordinator's secret scan passes (commands in `docs/handoffs/BASELINE-2026-10-03.md` section 7). Public is safest for judges; if private, invite `https://github.com/engineering-AF` as a collaborator. `[V2-PENDING: repo URL]`
- [ ] **A6. Video.** Record from a network outside the ISP filter (`docs/submission/demo-script.md`, `docs/submission/video-shotlist.md`), edit, upload unlisted, open the link logged out. `[V2-PENDING: video URL]`
- [ ] **A7. Wallet.** Have the Arbitrum One prize wallet address ready (same as at registration). `[ADDRESS-PENDING]`
- [ ] **A8. Privy.** Confirm the production domain is in the Privy allowed origins (a missing origin breaks sign-in for judges).
- [ ] **A9. Funds for ops.** Confirm the keeper and relayer wallets still hold ETH (see B3).

## B. Verification (coordinator)

Each item names the command or the file to check and the pass condition. Record results in `docs/handoffs/STATUS.md`.

### B1. Explorer links and addresses

- [ ] Run `scripts/gen-addresses-md.sh robinhood-testnet`; exit code 0 and every HackQuest block reads `PASS` (at most 300 characters, em dash U+2014, network `Robinhood Chain`).
- [ ] The three blocks and the single contract address in `docs/submission/hackquest-answers.md` are byte-identical to the script output: regenerate and compare each block.
- [ ] The README address section matches: `scripts/gen-addresses-md.sh robinhood-testnet --inject README.md` produces no further change.
- [ ] Every address returns a contract from the explorer API: `curl -sS https://explorer.testnet.chain.robinhood.com/api/v2/addresses/<addr> | jq '{is_contract, is_verified}'` gives `is_contract: true`. Retry on TLS errors.
- [ ] Verification claim matches reality. If the README or the answers say "verified", every core address returns `is_verified: true` (and `docs/handoffs/VERIFY-LOG.md` agrees); otherwise delete the claim. `[V2-PENDING: verification status after the V2 deploy]`
- [ ] Each address in the form belongs to the final deployment (`deployments/robinhood-testnet/addresses.json`), not to an archived V1 or V2 directory.

### B2. Site and routes

- [ ] The production URL returns 200 for `/`, `/marketplace`, `/create`, `/positions` and `/strategy/<vault>`; `curl -sS -o /dev/null -w '%{http_code}\n' <url>/marketplace`. The 2026-10-03 baseline had `/marketplace` at 404 on the old build.
- [ ] Page titles and the footer say Feng, not "Composable Strategy Marketplace" or "StrategyMarket"; `curl -sS <url>/ | grep -o '<title>[^<]*'`.
- [ ] A fresh email login works end to end on the production domain (Privy origin, network badge, no "Wrong network").

### B3. Health and freshness

- [ ] `curl -sS <url>/api/ops/health | jq '{ok, alarms}'` gives `ok: true` and an empty `alarms`; every feed `ageSec` under 2100. `[V2-PENDING: route deployed and public]`
- [ ] Keeper and relayer ETH balances are above 0.0003 each (`balanceEth` in the same report, or `cast balance`).
- [ ] At least one `Rebalanced` event from a non-deployer address in the last 24 hours (`eth_getLogs` on the vault, or the explorer logs tab).
- [ ] The pinger and the watchdog (cron-job.org tick, UptimeRobot on the health URL) are active and set to alert. `[V2-PENDING: ops hosting chosen in docs/research/12-always-on-hosting.md]`
- [ ] If feeds are older than their limit (V1: 24 hours), refresh them before the demo and before the judges look; V1 deposits, redeems and rebalances revert with `StalePrice` otherwise.

### B4. README accuracy

- [ ] `grep -rnE '\[V2-PENDIN[G]:|\[ADDRESS-PENDIN[G]\]' README.md docs/submission docs/research/15-mainnet-path.md scripts/gen-addresses-md.sh` prints nothing, and the line starting "Skeleton pass" is deleted from each file that has one.
- [ ] The "What is real versus mocked" table matches the deployment that is live: mock or real USDG, mock or real stock tokens, constant or relayer prices, mint/burn or venue custody, keeper host. Nothing says real prices, real swaps, Chainlink on testnet, audited or mainnet unless it is true on chain today.
- [ ] Test counts and commands in the README match a fresh run: `forge test` and the stated total, `pnpm lint`, `pnpm build` (use a dummy `NEXT_PUBLIC_PRIVY_APP_ID`).
- [ ] Links resolve: `docs/research/15-mainnet-path.md`, `docs/submission/hackquest-answers.md`, `docs/security/*` (if cited), `LICENSE`, `docs/handoffs/DEMO-NOTES.md`.
- [ ] A stranger test: clone the repo into an empty directory, follow "Run it locally" and "Deployed addresses" without outside help; every step works.

### B5. Repository, license, secrets

- [ ] Repository is reachable logged out: `curl -sS -o /dev/null -w '%{http_code}\n' https://github.com/<owner>/<repo>` prints 200 (or the collaborator invite to `engineering-AF` exists for a private repo).
- [ ] `LICENSE` is MIT and the README says MIT; `package.json` has no conflicting license field `[V2-PENDING: add "license": "MIT" to package.json; owned by another lane]`.
- [ ] No secret is tracked. Run the gate in `docs/handoffs/BASELINE-2026-10-03.md` section 7: no `.env*`, `*.key`, `*.pem`, keystore, log or `broadcast/` file is eligible, and the grep for `PRIVATE_KEY=0x<64 hex>` finds nothing outside the known public anvil keys (which the docs now reference as `$ANVIL_KEY_0` and `$ANVIL_KEY_1`). Also run a scanner if available (`trufflehog filesystem .` or GitHub secret scanning after the push). Do not open any `.env*` file.
- [ ] The first public commit contains `README.md`, `LICENSE`, `contracts/`, `script/`, `scripts/`, `deployments/`, `src/`, `docs/` and the vendored `lib/` (or submodules); `git status` shows nothing unexpected.
- [ ] Commit history is logical and structured (the form says it helps judges understand progress); the explanation of what was produced in the buildathon is in field 5 of the answers.

### B6. Form content

- [ ] Every field in `docs/submission/hackquest-answers.md` shows a character count and PASS; there is no marker left; the sponsor ticks are Robinhood Chain and OpenZeppelin, plus Paxos/USDG only if the real USDG deployment is live and shown `[V2-PENDING]`.
- [ ] The video link, repository link, frontend link and wallet address in the profile are filled and open correctly.

## C. Final hour sequence

| When (SGT) | Step | Owner |
|---|---|---|
| By 12:00 | A1 to A4 done; draft saved; video recorded or scheduled | user |
| 14:21 | G2 feature freeze; no new features | coordinator |
| 15:00 | Address freeze; regenerate and paste the address blocks, README block and answers once | coordinator |
| 15:00 to 16:00 | Section B in full; fix findings (docs lane only) | coordinator |
| 16:00 to 17:00 | Fill the form from `hackquest-answers.md`; upload video; paste links; do not submit yet | user |
| 17:00 to 17:30 | Coordinator reads the filled form against the answers file field by field | both |
| **17:59** | **Press final submit; screenshot the "Submitted" state ("Submit Another Project" appears)** | user |
| 18:00 to 20:00 | Re-run B2 and B3 once; keep the keeper and the pinger running | coordinator |
| 20:59 | Latest comfortable time to fix anything that blocked submission | both |
| 22:59 | Last chance to retry if the submission failed; contact the organiser (Discord `#open-house`, `swagtimus@arbitrum.foundation`) | user |
| 23:58 and 23:59 | Registration and submission close | n/a |

## D. If something goes wrong

- **Not registered or "Pending" at A1:** register or ask the organiser immediately; there is no submit button without `USER_REGISTERED` (research 14 F2).
- **Form closed early or errors on submit:** screenshot, post in `#open-house`, email the organiser, and keep trying; do not change addresses.
- **V2 not ready at G1:** ship V1 with the "Known accounting limits of the V1 vault" section in the README and the V1 address blocks; do not tick Paxos/USDG; roll the frontend back with Vercel "promote previous deployment" if it was already switched.
- **Feeds stale on submission day:** refresh them; if ops is down, run `scripts/refresh-feeds.sh robinhood-testnet` on V1 with a funded key in the environment.
- **Video not ready:** submit without a pitch video; the demo video is the one to protect (203 of 207 public submissions have it).
- **Character limit rejected by the form:** shorten the label, not the address; the full list lives in the README (the last line may read "full list: <repo>/README.md#deployed-addresses" if it fits in 300 characters).

## E. After submission

- [ ] Screenshot the submitted project page and the confirmation.
- [ ] Leave the keeper, the pinger and the health watchdog running until judging ends (rewards are set for 2026-10-12 per the live timeline).
- [ ] Do not redeploy contracts or change addresses; frontend-only fixes are allowed and must not break the linked routes.
- [ ] Post the build-in-public thread (E11-T8) only after the project page is confirmed.
