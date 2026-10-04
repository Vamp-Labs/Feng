# HackQuest submission answers (E11-T3)

Copy-paste values for the Arbitrum Open House Singapore Online Buildathon form. Field labels and order are verbatim from `docs/research/14-hackquest-submission.md` section F4 (read from the live form on 2026-10-03). Every input in the form is capped at **300 characters**; each block below shows its length and PASS or FAIL against that cap. Counts are Unicode characters with a newline counted as 1; if the browser counts a newline as 2, the token block grows by 3 and still passes.

**Skeleton pass.** Every V2-PENDING and ADDRESS-PENDING marker is resolved by the coordinator after Gate G1 (2026-10-04 10:21 SGT). Address blocks below are the V1 deployment as of 2026-10-03; regenerate them with `scripts/gen-addresses-md.sh` (it checks length and format itself) and paste the new blocks. Do not paste a block that shows FAIL.

Deadlines (research 14 F1): registration closes 2026-10-04 23:58 SGT, submission closes 2026-10-04 23:59 SGT. Target submission: 2026-10-04 17:59 SGT. Registration must show "Registered" and the page button must read "Start Submit" (checklist in `docs/submission/CHECKLIST.md`).

Format rule for every address line: `network: address — label` with an em dash (U+2014) and one space on each side, network name exactly `Robinhood Chain`.

Recount any block locally: `printf '%s' "$BLOCK" | LC_ALL=C.UTF-8 wc -m`.

## A. Hackathon form fields, in the order of the live form

### 1. Link to frontend/UI/website of your project

`[V2-PENDING: confirm the final production URL and that /marketplace returns 200 on it; the 2026-10-03 baseline found /marketplace returning 404 on this host]`

```text
https://composable-strategy-marketplace.vercel.app
```

Characters: **50** of 300. **PASS**.

### 2. List your Core Protocol/ Smart Contract Addresses

`[V2-PENDING: replace with the first block printed by scripts/gen-addresses-md.sh after the V2 redeploy; V1 values shown]`

```text
Robinhood Chain: 0x9A4A62b955e28C8Ed83585412c658161A746DACa — Marketplace registry
Robinhood Chain: 0x2e33339A57B9aBedb3B94d842d6cC64b3Dc71226 — Rebalance engine
Robinhood Chain: 0xD86Ef6e14701e28BBBDd4641306b001ECC857b3B — Price oracle
```

Characters: **236** of 300. **PASS**.

### 3. List your Factory/Pool Contracts (if applicable)

Feng creates vaults dynamically, so this field applies. `[V2-PENDING: after V2 add the Live universe factory if it ships, one per line, keeping 300 characters]`

```text
Robinhood Chain: 0xB0C8B58ceD6271e13539DEE9D658b2d157d41087 — Strategy factory
```

Characters: **78** of 300. **PASS**.

### 4. List your Token Contract Address (if applicable)

These are our mock tokens; the labels say so. The strategy tokens (one per vault) are listed in the README. `[V2-PENDING: if the Live universe ships, add Paxos USDG 0x7E955252E15c84f5768B83c41a71F9eba181802F with the label Paxos USDG and keep the block at 300 characters or fewer]`

```text
Robinhood Chain: 0x6F0aa2cc939604b7e62935365521EA72C1908B70 — Mock USDG
Robinhood Chain: 0x37e2a07eA1990F775A57273D5BcDd4f09A8a3732 — Mock TSLA
Robinhood Chain: 0x7e80cb6344dF7A371fC6AC104d3fc922a4e4c4F1 — Mock AMZN
Robinhood Chain: 0x6C2c1ac3B983Bd05d720F9786D365656AbeA2759 — Mock NFLX
```

Characters: **287** of 300. **PASS**.

### 5. Which parts of your code have been produced during the Buildathon?

Honest basis: `PRD.md` and the first contracts are dated 2026-09-28, the testnet deployment file is dated 2026-09-29, the ten strategies were seeded on 2026-10-01, and the redesign and V2 work are 2026-10-01 to 2026-10-04 (`docs/handoffs/STATUS-2026-09-28-archive.md`, `docs/handoffs/BASELINE-2026-10-03.md`). The buildathon submission window opened 2026-09-14, so all of it falls inside the event. `[V2-PENDING: if the repo history is published, say that the commit history shows it]`

```text
All of it. The repo was created for this buildathon on 2026-09-28: contracts, tests, Next.js app, keeper scripts and testnet deployment were written after that date. Only forge-std and OpenZeppelin are vendored under lib/. Details: README.
```

Characters: **239** of 300. **PASS**.

### 6. Which sponsor/partner technologies have you used as part of your project?

Checkbox, multiple, mandatory. Tick exactly these:

| Option | Tick | Why, and what we can show |
|---|---|---|
| Have not used any | No | Not true. |
| GMX | No | Not used. |
| **Robinhood Chain** | **Yes** | Deployed on Robinhood Chain testnet (chain ID 46630); addresses in field 2 to 4. |
| Dune Analytics | No | Not used. |
| ZeroDev | No | Not used. |
| Fhenix | No | Not used. |
| Alchemy | No | Not used (public RPC). |
| AWS | No | Not used. |
| **OpenZeppelin** | **Yes** | OpenZeppelin Contracts 5.7.0: `ERC20`, `AccessControl`, `Ownable`, `ReentrancyGuard`, `SafeERC20`, `Math`, `Pausable` (the last for V2). Verified by `grep -rn @openzeppelin contracts/`. |
| Paxos/USDG | Only if true | `[V2-PENDING: tick ONLY if the Live universe with the real Paxos USDG 0x7E955252E15c84f5768B83c41a71F9eba181802F is deployed, verified on chain, and shown in the demo. If the deployment uses only MockUSDG, leave it unticked. Never tick it for a mock-only deployment (research 14 recommendation 7).]` |

Chainlink is not an option in the form. Do not claim Chainlink feeds on testnet: there are none (research 07 section 2.3). The oracle adapter reads the Chainlink `AggregatorV3Interface`, which is what the mainnet path needs; say so only in free text.

### 7. Contract Address (single input)

Placeholder in the form: "Paste contract address here"; not required. How it maps to a network is not visible without login (research 14 F4 item 7). Paste the factory, because it is the entry point that creates every vault:

```text
0xB0C8B58ceD6271e13539DEE9D658b2d157d41087
```

Characters: **42**. `[V2-PENDING: use the V2 strategy factory address]`

### 8. Custom Track

Disabled in the live form (`enabled: false`, no options). Nothing to select.

## B. Project profile (HackQuest project page)

These fields are not in the hackathon form. The labels were read from the public GraphQL query shape, not from the logged-in screens, so the user must check the exact labels and limits when clicking "Start Submit" (checklist step 4). Length limits for these fields are unknown; the values below are short on purpose.

### Project name

```text
Feng
```

Characters: **4** of 300. **PASS**.

### One-line intro (`oneLineIntro`)

Limit unknown; this value is short enough for any plausible cap (under 100 characters).

```text
Investment strategies as composable onchain primitives on Robinhood Chain.
```

Characters: **74** of 300. **PASS**.

### Description (`description`)

The cap shown is 1,000, an assumption, because the real limit is not public. `[V2-PENDING: add one sentence for what V2 added if it ships, and keep the last sentence about mocks either way]`

```text
Feng turns an investment strategy into an ERC-20. A creator picks constituents, target weights, a max weight per asset and a rebalance interval; the factory deploys a vault and a Strategy Token. Users deposit USDG and hold the token. A permissionless keeper rebalances when the interval elapses or any asset drifts above its cap. A Strategy Token can be a constituent of another strategy (depth cap 2) and the parent reads the child's NAV live. Live on Robinhood Chain testnet: factory, registry, rebalance engine, an oracle adapter over Chainlink's AggregatorV3Interface, and a Next.js app with Privy wallets. The default universe uses mock Stock Tokens, mock USDG and mock price feeds; the README states what is real and what is mocked.
```

Characters: **738** of 1000. **PASS**.

### Tracks (`tracks`, sector)

Pick from the dropdown what exists: **DeFi** and **RWA** (or the closest labels such as "Real World Assets", "Asset Management", "Tokenization"). Do not pick AI, Gaming or Social.

### Tech stack (`teachStack`)

Enter as separate tags if the field is a tag input: Solidity, Foundry, OpenZeppelin, Robinhood Chain, Arbitrum, Chainlink (interface), TypeScript, Next.js, React, wagmi, viem, Privy, Tailwind CSS.

```text
Solidity 0.8.24, Foundry, OpenZeppelin v5, Robinhood Chain testnet (Arbitrum Orbit L2), Chainlink AggregatorV3Interface (mock feeds on testnet), TypeScript, Next.js 16, React 19, wagmi, viem, Privy, Tailwind, framer-motion, GSAP, bash and cast for the keeper
```

Characters: **258** of 1000. **PASS**.

### Demo video (`demoVideo`)

`[V2-PENDING: unlisted YouTube or HackQuest-hosted mp4 link after the recording (E11-T6); must open while logged out. 203 of 207 public submissions have one, treat it as required.]`

### Pitch video (`pitchVideo`)

Optional (106 of 207 have one). `[V2-PENDING: add a link only if a separate pitch video is recorded; otherwise leave empty.]`

### Repo link (`openSourceLink`)

`[V2-PENDING: public GitHub URL after the user creates and pushes the repo (commands in docs/handoffs/BASELINE-2026-10-03.md section 7). If the repo is private, invite https://github.com/engineering-AF as a collaborator.]` The repo is MIT licensed.

### Wallet (`wallet`)

`[ADDRESS-PENDING]` The user's own Arbitrum One address that receives prizes; use the same one given at registration. Prizes are paid on Arbitrum One (research 14 F3 and F6). Never use a deployer or keeper address.

### Project progress (`projectProgress`)

Rich text field; the cap shown is an assumption. This is the long form of the "built during the buildathon" statement and of the real-versus-mocked disclosure.

```text
What works today (Robinhood Chain testnet, chain ID 46630):
- Create: StrategyFactory deploys a vault and an ERC-20 Strategy Token and registers them. Depth cap 2, cycle and leaf checks enforced on chain.
- Deposit and redeem in USDG (mock USDG in the default universe).
- Rebalance: time-based and threshold-based, permissionless through RebalanceEngine; a keeper script had sent 16 rebalances on chain as of 2026-10-03.
- Compose: two depth-2 strategies (CORE, CONV) are seeded and valued live from their children.
- Marketplace: 10 seeded strategies read from the on-chain registry; Privy wallets; 48 Foundry tests, including a first-depositor inflation test and depth/cycle invariants.

What is mocked, plainly: Stock Tokens, USDG and price feeds in the default universe are our own test contracts, prices are constants, and the V1 vault simulates custody by minting and burning. No audit. [V2-PENDING: update this block with what the V2 redeploy actually shipped (venue custody, relayer-fed prices, Live universe with real Paxos USDG, faucet, performance history) or delete the sentence if it did not ship.]

Next: settlement that matches NAV, real prices, a real venue adapter, an audit, then mainnet with Chainlink feeds (path documented in docs/research/15-mainnet-path.md).
```

Characters: **1282** of 3000. **PASS**.

### Fundraising status (`fundraisingStatus`)

```text
Not fundraising. No token. Open source under MIT.
```

Characters: **49** of 300. **PASS**.

### Prize tracks (`prizeTrack`)

Select every track the project picker offers that fits: **Overall Prize** and **Promising Products Track** (judged on the same four criteria), and **Grants** (case by case, not guaranteed). Most submissions select all three; nine selected only Overall Prize (research 14 F5). Selecting more does not remove eligibility.

## C. What we can and cannot say (accuracy rules for every field)

| Claim | Allowed? | Basis |
|---|---|---|
| Deployed on Robinhood Chain testnet | Yes | `deployments/robinhood-testnet/addresses.json`, explorer links |
| Contracts verified on the explorer | `[V2-PENDING: only after docs/handoffs/VERIFY-LOG.md shows is_verified true for the core contracts]` | not verified as of 2026-10-03 |
| Real USDG / Paxos integration | `[V2-PENDING: only if the Live universe ships]` | default universe is MockUSDG |
| Real stock prices or swaps | `[V2-PENDING: only if the relayer is live and prices are fresh on /api/ops/health]` | V1 prices are constants and mocked custody |
| Chainlink feeds | No | none on testnet; adapter reads the interface only |
| Audited | No | no audit |
| Mainnet | No | documented path only |
| Permissionless keeper | Yes, with the caveat | the contract path is permissionless; only our keeper has used it |
| Composability depth 2 with live nested NAV | Yes | CORE and CONV on chain, tests in `contracts/test/` |
| 48 Foundry tests | Yes for V1 | `docs/handoffs/BASELINE-2026-10-03.md` section 2 `[V2-PENDING: new total if V2 ships]` |

## D. Order of operations on the form

1. Fill the project profile first (section B), save the draft, do not press final submit.
2. Paste fields 1 to 5, tick sponsors (field 6), paste field 7, skip field 8.
3. Re-read each address block against the explorer; recount any block you edited.
4. Final submit by 2026-10-04 17:59 SGT; screenshot the "Submitted" state ("Submit Another Project" appears after success).
