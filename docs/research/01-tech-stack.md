# 01 — Tech Stack

Scope: answers Track A of `docs/research/00-brief.md` for the Composable Strategy Marketplace
(StrategyFactory, StrategyVault, RebalanceEngine/Keeper, Marketplace Registry — PRD §8). This repo
is greenfield; nothing was audited. Chain-specific facts (Robinhood Chain testnet identity, deployed
oracle addresses, ArbOS version) are explicitly left to Track B and only referenced here where they
gate a tech-stack decision.

## Summary

- **Foundry over Hardhat.** Foundry is the faster default for a Solidity-heavy hackathon build:
  native Rust binary, Solidity-native tests/fuzzing, no Node startup cost. Hardhat 3 (Sep 2026,
  Rust-rewritten "EDR" core) has closed much of the testing-speed gap and now supports
  Foundry-compatible Solidity tests, but its edge is TypeScript-coupled tooling — not the differentiator
  this team needs. Recommendation: Foundry for contracts, plain `viem`/`wagmi`/`ethers` in the Next.js
  app for the frontend-contract boundary (no Hardhat needed for that).
- **Custom vault, ERC-4626-shaped interface, not literal single-asset ERC-4626 inheritance.**
  OpenZeppelin's `ERC4626.sol` (current master, pragma `^0.8.24`) is fundamentally single-asset — the
  spec assumes one `asset()`. The PRD needs a Strategy Token backed by a *basket* of tokenized
  stocks plus USDG. The pattern used by the multi-asset extension the Ethereum community actually
  standardized for this exact gap (ERC-7575, "Multi-Asset ERC-4626 Vaults," still a late draft as of
  early 2026 per search results — not a finalized, audited OZ implementation) confirms the diagnosis:
  plain ERC-4626 doesn't fit. Recommended shape: `StrategyToken` is a normal ERC-20 (satisfies PRD's
  "ERC-20 Strategy Token" and makes composability trivial — a parent vault just holds child
  Strategy Token balances like any other ERC-20); `StrategyVault` exposes ERC-4626-*flavored*
  deposit/redeem semantics (`previewDeposit`, `totalAssets`-equivalent NAV) with **USDG as the
  canonical single settlement asset** — deposits/redemptions happen in USDG, and the vault internally
  allocates/liquidates the underlying stock-token basket per the strategy's weights. This satisfies
  PRD §6.1's explicit USDG requirement while sidestepping ERC-4626's single-asset assumption. Direct
  stock-token deposits (not just USDG) are a stretch feature, not MVP.
- **Keeper/automation: build a permissionless/incentivized manual keeper, don't bet the demo on
  Chainlink Automation or Gelato being live on Robinhood Chain testnet.** Chainlink's own supported-networks
  page (fetched 2026-09-28) lists only **Arbitrum One and Arbitrum Sepolia** — no generic Orbit/L3
  support — and, more importantly, **classic Chainlink Automation (v1.x and v2.1) is already past its
  sunset date** (v1.x: June 30 2026; v2.1: July 31 2026, testnet cutoff June 24 2026 — all before
  today, 2026-09-28). Chainlink's own docs now redirect Automation users to the **Chainlink Runtime
  Environment (CRE)**, a newer, more general, enterprise-oriented orchestration product (Swift,
  UBS, J.P. Morgan are cited adopters) with materially higher setup complexity — not a fit for a
  10-day hackathon on an unconfirmed-support testnet. Gelato's Web3 Functions product is still live
  (`docs.gelato.cloud`, fetched 2026-09-28) and Gelato explicitly documents Arbitrum Orbit RaaS
  support, but whether Gelato has *this specific* Robinhood Chain testnet configured is unconfirmed
  (Track B). Given that uncertainty, the safe hackathon default is a **permissionless `rebalance()`
  entry point** on `RebalanceEngine` — anyone (a cron-driven bot you run yourself, or literally any
  wallet) can call it once `checkRebalanceNeeded()`-equivalent conditions are true, optionally with a
  small caller incentive. This has zero third-party infra dependency and is demo-safe; layer Gelato
  Web3 Functions on top only if Track B confirms it reaches the testnet.
- **Oracle: keep the pricing interface abstract (an `IPriceOracle` your contracts call), pick the
  concrete adapter once Track B reports what's actually deployed on Robinhood Chain testnet.**
  Chainlink Price Feeds (pull-style read via `AggregatorV3Interface.latestRoundData()`, feed address
  per asset pair), Pyth (pull/push hybid via Hermes off-chain price + on-chain
  `updatePriceFeeds`/fee, and Pyth's Hermes endpoint now requires an API key as of its August 2026
  upgrade), and RedStone (modular Core/Classic/X models, explicitly markets "easy utilization... on
  any new chain built atop technologies like Arbitrum Orbit") are the three realistic candidates —
  each requires genuinely different integration code, so the `IPriceOracle` abstraction is not
  optional, it's what lets Track B's finding slot in without a contract rewrite.
- **Composability hazards are real and addressable, but concrete "existing protocol" depth-limit
  numbers were not found from a primary source** — flagged under Assumptions. What *is* well
  documented: (1) ERC-4626 vaults are a known target for the "inflation attack" (donate-then-deposit
  griefing), which OpenZeppelin mitigates with virtual shares/assets — replicate that mitigation in
  the custom vault; (2) "read-only reentrancy" (a view function returning stale/inconsistent state
  during a reentrant callback) is called out by multiple 2026 sources as a live, still-exploited
  composability hazard specifically when protocols read each other's intermediate state — exactly the
  shape of risk a Strategy Token nested inside another Strategy Token creates; (3) the EVM's hard
  call-depth ceiling of 1024 is a backstop, not a design control — the PRD's own suggestion (§10, cap
  nesting at 2–3 levels) should be enforced explicitly in `StrategyFactory` at creation time, with
  cycle detection (reject a constituent that is an ancestor of the strategy being created), not left
  to the EVM to revert on stack-too-deep.
- **OpenZeppelin Contracts v5.7.0 (released 2026-07-29, verified via GitHub API 2026-09-28) is
  current; its ERC-20/ERC-4626 sources pin `pragma solidity ^0.8.24`.** Foundry itself is at v1.8.3
  (released 2026-09-15) and `forge-std` at v1.16.2 (verified via GitHub API 2026-09-28), both current
  this month. On the compiler-version-vs-chain question: Arbitrum's own Solidity-support doc (fetched
  2026-09-28) confirms the PUSH0 opcode "was added as part of ArbOS 11 and is now supported" — so
  Solidity ≥0.8.20 (Shanghai target, which 0.8.24 is) is safe on any Arbitrum-family chain running
  ArbOS 11 or later. Robinhood Chain's actual ArbOS version is unconfirmed (Track B); until confirmed,
  set `evm_version = "paris"` in `foundry.toml` as a defensive fallback, or be ready to flip it if
  Track B shows an older ArbOS.

## Findings

### 1. Foundry vs Hardhat

- Foundry: `forge` (build/test/deploy), `cast` (CLI RPC/tx swiss-army-knife), `anvil` (local node),
  `chisel` (Solidity REPL). Tests are Solidity contracts run natively — no JS/TS transpile step.
  Source: `getfoundry.sh` (fetched 2026-09-28).
  - Current Foundry release: `v1.8.3`, published 2026-09-15. Source: GitHub API
    `api.github.com/repos/foundry-rs/foundry/releases/latest` (fetched 2026-09-28).
  - Current `forge-std` tag: `v1.16.2`. Source: GitHub API
    `api.github.com/repos/foundry-rs/forge-std/tags` (fetched 2026-09-28).
- Hardhat 3 ("What's new in Hardhat 3," `hardhat.org/docs/learn-more/whats-new`, fetched 2026-09-28
  via search): core simulation engine rewritten in Rust ("EDR"), now ships Foundry-compatible
  Solidity tests (including fuzz/invariant), still supports TypeScript integration tests alongside,
  built-in coverage (`--coverage`), and (unlike Hardhat 2) supports simulating multiple
  differently-configured networks rather than always emulating Ethereum mainnet.
- Secondary-source consensus (dev.to comparison pieces, flagged as non-primary, cross-checked
  against the two projects' own docs above rather than trusted alone): Foundry remains the default
  recommendation for protocol/audit-focused work in 2026; Hardhat's edge is when contracts are
  "tightly coupled to a TypeScript frontend/backend" or teams already live in Node.js tooling and
  plugins. Several teams run both — Foundry for tests, Hardhat for deploy scripts — but that's
  unnecessary tooling overhead for a 10-day build.
- No Arbitrum-Orbit-specific tooling gap was found for either framework: both compile standard EVM
  bytecode and deploy via a plain RPC URL + private key; neither requires chain-specific plugins for
  a generic Orbit chain. Contract *verification* (Arbiscan/Blockscout-equivalent) on a brand-new
  Orbit testnet explorer is a Track B concern (does the explorer exist, is it Blockscout or
  Etherscan-compatible), not a Foundry/Hardhat capability gap.

### 2. ERC-4626 vs custom vault

- OpenZeppelin's `ERC4626.sol` (master branch, fetched via raw GitHub 2026-09-28) is `pragma solidity
  ^0.8.24` and implements the single-asset tokenized-vault standard: one `asset()`, `totalAssets()`,
  `deposit`/`mint`/`withdraw`/`redeem` against that one asset. It is not designed to hold N
  independently-weighted underlying tokens.
- ERC-7575 ("Multi-Asset ERC-4626 Vaults," `eips.ethereum.org/EIPS/eip-7575`) exists precisely to
  patch this gap by decoupling the ERC-20 share token from the ERC-4626 vault-accounting logic so one
  share can sit behind multiple entry points/assets. Per search-result characterization it was "in
  late draft as of early 2026" — i.e., not a mature, widely-audited standard to build directly on for
  a hackathon; OpenZeppelin has not shipped an ERC-7575 reference implementation in `openzeppelin-contracts`
  (only an ERC-7535 *native-asset* extension was found, which is a different, narrower problem —
  making ETH itself depositable into an otherwise-single-asset vault, via PR #6624, not multi-token
  baskets).
- ERC-7540 ("Asynchronous ERC-4626 Tokenized Vaults") is the standard for vaults whose
  redemption doesn't settle same-transaction (used in production by Centrifuge/UltraYield for
  RWA/off-chain-settlement cases). Not required for MVP since Robinhood Chain testnet asset
  liquidity should be on-chain/instant, but worth knowing about if a constituent Strategy Token's
  redemption ever needs a request→fulfill flow (e.g., an illiquid nested strategy).
- Comparable protocol architecture: Set Protocol v2 / Index Coop's "Index Protocol" (docs at
  `docs.indexcoop.com`, fetched 2026-09-28 via search) does **not** use ERC-4626 at all — `SetToken`
  is a plain ERC-20, and separate "modules" attached to it handle issuance, redemption, fees, and
  composability. That's the same shape being recommended here (ERC-20 Strategy Token + a vault
  contract that owns the multi-asset accounting logic), and it's independent validation that
  multi-asset basket tokens in production don't route through ERC-4626.
- Inflation/donation attack: empty/low-liquidity vaults are attackable by depositing a small amount
  then donating assets directly to the vault to skew the share price, griefing the next depositor.
  OpenZeppelin's mitigation is virtual shares/assets (a decimals offset added to both sides of the
  exchange-rate computation) — this needs to be replicated in a custom vault since it won't be
  inherited for free. Source: OpenZeppelin blog "A Novel Defense Against ERC4626 Inflation Attacks"
  and `openzeppelin-contracts` issue/PR history (#3706, #3979), fetched 2026-09-28.
- **Recommendation:** build `StrategyVault` as a custom contract, ERC-4626-*inspired* in interface
  naming/semantics (matches PRD §8's explicit "ERC-4626 inspired (or custom vault)" framing) but not
  a literal `is ERC4626`. Use USDG as the single settlement asset for deposit/redeem (directly
  satisfies PRD §6.1's USDG requirement and keeps NAV math to "one asset in, basket out" instead of
  "N assets in various proportions"), apply the OZ virtual-shares mitigation to the USDG-share
  exchange rate, and keep `StrategyToken` a bare ERC-20 so nested composability (a Strategy Token
  held as a constituent inside another StrategyVault) needs no special-casing — any ERC-20-holding
  code path already supports it.

### 3. Keeper/automation

- **Chainlink Automation.** Supported-networks page (`docs.chain.link/chainlink-automation/overview/supported-networks`,
  fetched 2026-09-28) lists Arbitrum One (Registry `0x37D9...`) and Arbitrum Sepolia (Registry
  `0x8194...`) — no generic "Arbitrum Orbit" or custom-chain entry. Separately, and more
  importantly: the same page and `docs.chain.link/chainlink-automation` (fetched 2026-09-28) both
  state Automation v1.x sunsets **June 30, 2026** and v2.1 sunsets **July 31, 2026** (testnet:
  **June 24, 2026**) — all three dates are in the past relative to today (2026-09-28). Chainlink is
  actively directing Automation users to migrate to the **Chainlink Runtime Environment (CRE)**
  (`docs.chain.link/cre/reference/cla-migration-ts`, `blog.chain.link/introducing-chainlink-runtime-environment/`,
  fetched via search 2026-09-28) — a considerably broader orchestration product (multi-trigger,
  multi-chain workflows) aimed at institutional users (Swift, Euroclear, UBS, J.P. Morgan, Mastercard
  cited as adopters). Registering an upkeep also requires LINK funding and a deployed
  Registry/Registrar pair on the target chain (`docs.chain.link/chainlink-automation/guides/register-upkeep`,
  fetched 2026-09-28) — infrastructure that would need to exist on Robinhood Chain testnet
  specifically, which is unconfirmed.
- **Gelato.** Web3 Functions product is live and documented at `docs.gelato.cloud/web3-services/web3-functions`
  (confirmed reachable via search-indexed pages, fetched 2026-09-28; note `docs.gelato.network`
  now 301-redirects to `docs.gelato.cloud`, and a couple of specific sub-paths tried returned 404,
  so treat exact current page structure as approximate, not the top-level product existence). Gelato
  explicitly documents Arbitrum Orbit support at the infrastructure level (`docs.gelato.cloud/rollup-as-a-service/rollup-stacks/arbitrum-orbit`
  — Gelato is also a Rollup-as-a-Service provider for Orbit chains, and separately offers USDC-as-gas-token
  tooling for Orbit L2/L3s per a Gelato blog post found via search, fetched 2026-09-28). This does not
  by itself confirm Gelato executors are configured for Robinhood Chain testnet — that's Track B.
- **OpenZeppelin Defender.** Explicitly being sunset: the hosted Defender platform retires **July 1,
  2026** (already past as of today) per OpenZeppelin's own "Defender Sunset FAQ"
  (`www.openzeppelin.com/news/defender-sunset-faq`, fetched 2026-09-28). OpenZeppelin is pushing
  users to self-hosted, open-source **Relayer** and **Monitor** Docker images instead of the SaaS
  dashboard. Given the sunset, Defender is **not recommended** as a keeper mechanism for this build —
  it's being actively decommissioned, not merely legacy.
- **Recommendation:** implement `RebalanceEngine.rebalance(strategyId)` (or similar) as a
  **permissionless, publicly-callable function** guarded by an on-chain condition check
  (time-elapsed or threshold-breached, matching PRD §6.1's "Time-based" and "Threshold-based"
  triggers), optionally with a small caller reward paid from vault fees to incentivize third-party
  callers. Drive it during the hackathon with your own cron/script (a trivial off-chain bot calling
  `cast send` or a Node script on an interval) — zero dependency on any third-party automation
  network being deployed on an unconfirmed testnet. If Track B confirms Gelato Web3 Functions
  reaches Robinhood Chain testnet, layer it on top of the same permissionless function later — no
  contract change needed, since Gelato would just be *a* caller. Do not build around Chainlink
  Automation (classic) given its sunset status, and do not use OpenZeppelin Defender at all.

### 4. Oracle options

- **Chainlink Price Feeds.** Pull-style read pattern: contract calls `AggregatorV3Interface.latestRoundData()`
  on a per-asset-pair feed contract address; feed isn't "pushed" into your contract automatically, you
  read it on demand. Requires knowing the feed address per asset per network (published in Chainlink's
  address registries). Source: `docs.chain.link/data-feeds/using-data-feeds`, fetched 2026-09-28.
  Integration effort: low if a feed for the exact tokenized-stock pair already exists on the target
  chain (Track B question), otherwise zero (Chainlink doesn't let you self-deploy a feed cheaply for
  a custom asset).
- **Pyth Network.** Pull/hybrid model: an off-chain "Hermes" endpoint serves signed price updates
  that your frontend/keeper fetches and submits on-chain via `updatePriceFeeds` (paying a small fee),
  after which the contract can read the freshly-pushed price. Source: `docs.pyth.network/price-feeds/core/push-feeds/evm`,
  fetched 2026-09-28. Notable current-state finding: **Pyth's Hermes endpoint now requires an API key**
  following Pyth's own-stated "August 2026 core upgrade" (per the fetched page) — this is new setup
  friction versus older Pyth integration guides that assumed anonymous access, and should be budgeted
  into setup time. Pyth lists sponsored feeds across roughly 10 EVM mainnets in the fetched snapshot;
  whether Robinhood Chain testnet (or Arbitrum Sepolia as a proxy) is covered is a Track B question.
  Integration requires a price-feed ID per asset (not a per-chain contract address the way Chainlink
  feeds work) plus fee-payment handling in the calling contract.
- **RedStone.** Modular, three integration models — "Core" (cheapest, on-demand pull, gas-minimal),
  "Classic" (spread-out periodic updates), "X" (speed/security-prioritized) — explicitly marketed as
  portable to new chains including ones "built atop technologies like Arbitrum Orbit." Source:
  `docs.redstone.finance` introduction/architecture pages, fetched 2026-09-28 via search (RedStone
  also has an Arbitrum-specific Stylus blog post from Arbitrum's own blog,
  `blog.arbitrum.io/how-redstone-is-advancing-oracle-capabilities-with-stylus/`, evidencing an active
  RedStone↔Arbitrum-ecosystem relationship, though that post is about Stylus specifically, not
  Robinhood Chain). RedStone claims coverage of "110+ chains" generally — a plausible fit for a
  newer/smaller Orbit chain precisely because its adapter-contract model is designed to be
  redeployed per-chain rather than requiring Chainlink/Pyth's own infra team to onboard the chain.
- **Recommendation:** define an `IPriceOracle` interface (`getPrice(address token) returns (uint256,
  uint256 updatedAt)` or similar) inside `StrategyVault`/`RebalanceEngine` now, and write the
  concrete adapter (Chainlink `AggregatorV3Interface` wrapper, Pyth Hermes-consumer wrapper, or
  RedStone adapter) once Track B reports what's actually live on Robinhood Chain testnet. Given
  RedStone's stated ease of new-chain deployment and Orbit-specific messaging, it's the most likely
  to be the "actually available" answer for a brand-new testnet if Track B finds nothing chain-native
  — but this is a hypothesis for Track B to confirm/deny, not a finding about Robinhood Chain itself.

### 5. Composability / nesting hazards

- **Read-only reentrancy** is repeatedly named (Halborn, dev.to 2026 retrospective, an arXiv
  cross-DApp detection paper) as *the* composability-specific hazard class: a view function can be
  called mid-reentrancy while the calling contract's own state is inconsistent, and a second protocol
  trusting that view's return value gets a wrong answer. This maps directly onto Strategy-Token-in-
  Strategy-Token: if `ParentVault` reads `ChildVault.totalAssets()`/NAV mid-transaction while
  `ChildVault` is itself mid-rebalance or mid-redeem, the parent can get a stale/manipulated number.
  Mitigation: standard `nonReentrant` guards are necessary but not sufficient (they don't protect
  *external* callers of your view functions) — the pattern that actually closes this hole is to only
  ever read NAV/price state after any state-mutating call has fully returned (never mid-call), and to
  treat any child StrategyVault's exposed price/NAV getters as needing their own reentrancy lock or a
  "settled state" flag that parents check before trusting the value. Sources: Halborn
  "What Is Read-Only Reentrancy?", a 2026 DEV Community "defense playbook" retrospective, and the
  general reentrancy pattern documented by OpenZeppelin's own `ReentrancyGuard` — all fetched via
  search 2026-09-28; treat the dev.to piece as a secondary/non-primary source used only for framing,
  cross-checked against the mechanism description in the arXiv paper and Halborn's writeup.
- **Circular composition / depth limits.** No primary source (Set Protocol / Index Coop docs, an
  audited nested-vault reference implementation) with a concrete stated depth-limit number or
  documented cycle-detection algorithm was found — flagged under Assumptions below rather than
  invented. What is confirmed: the EVM itself hard-stops call chains at depth 1024 (a backstop, not a
  usable design control — you'd run out of gas or hit weird partial-revert states long before that in
  practice). PRD §10 already proposes capping nesting at "2–3" levels; this should be enforced
  explicitly and cheaply: `StrategyFactory.createStrategy()` should (a) look up each constituent's
  stored nesting depth, reject if `max(constituentDepths) + 1 > MAX_DEPTH`, and (b) walk the
  constituent list for self-reference/ancestor-reference and reject cycles, both as an O(depth) check
  at creation time (cheap, since depth is capped small) rather than relying on runtime revert
  behavior during a redemption/rebalance cascade.
- **Gas cost of nested rebalancing.** Not separately sourced beyond general knowledge; flagged as an
  open question for Track B/implementation: a rebalance of a parent strategy that itself triggers
  rebalances of nested child strategies could multiply gas cost per triggering call. The
  permissionless-keeper design above (recommendation §3) means whoever calls `rebalance()` eats that
  cost, so this should be load-tested against Robinhood Chain testnet's actual gas costs once known
  (Track B), and the depth cap directly bounds the worst case.

### 6. OpenZeppelin Contracts / Solidity compiler version

- OpenZeppelin Contracts current release: **v5.7.0**, published **2026-07-29T16:43:07Z**. Verified
  directly via `curl https://api.github.com/repos/OpenZeppelin/openzeppelin-contracts/releases/latest`
  (2026-09-28). `contracts/token/ERC20/extensions/ERC4626.sol` on the `master` branch pins
  `pragma solidity ^0.8.24` — verified directly via `curl` against the raw GitHub content URL
  (2026-09-28).
- Arbitrum's own "Solidity support" doc (`docs.arbitrum.io/solidity-support`, fetched directly via
  `curl` 2026-09-28, page states "Last updated on Sep 17, 2026") confirms: "OPCODE PUSH0 — This
  OPCODE was added as part of ArbOS 11 and is now supported." ArbOS 11 (finalized ~early 2024 per
  the Arbitrum Foundation forum AIP, `forum.arbitrum.foundation/t/aip-arbos-version-11/19696`) added
  Shanghai-EVM support including PUSH0, meaning Solidity ≥0.8.20 (which defaults to targeting
  Shanghai) is safe to deploy on any Arbitrum chain running ArbOS 11+.
- **Gap:** Robinhood Chain's specific ArbOS version (is it even running ArbOS 11+, given it may be a
  newly-launched Orbit chain that could in principle be pinned to an older ArbOS release, or run a
  fork that diverges) is unconfirmed — this is squarely a Track B question, not answerable from
  Arbitrum's generic docs.
- **Recommendation:** target `pragma solidity ^0.8.24` (matches current OZ, current Foundry/forge-std
  tooling, no known reason to go lower) but set `evm_version = "paris"` explicitly in `foundry.toml`
  as a defensive default (this compiles without PUSH0, avoiding the exact bug class multiple 2023-era
  audit findings — Cyfrin CodeHawks, a Centrifuge Code4rena finding — flagged for "0.8.20 on Arbitrum").
  Flip `evm_version` to `"shanghai"`/default once Track B confirms Robinhood Chain testnet's ArbOS
  version supports PUSH0 (which is very likely if it's a modern 2026-launched Orbit chain, but should
  be confirmed, not assumed).

## Recommendations

| Decision | Recommendation | Rejected alternative(s) and why |
|---|---|---|
| Contract framework | **Foundry** (forge/cast/anvil/chisel), `forge-std` v1.16.2 | Hardhat 3 — closed the testing-speed gap with Rust-based EDR and Solidity tests, but its differentiator (deep TS integration) isn't needed here; adds a second toolchain/runtime for no payoff in a Solidity-first, 10-day build. |
| Vault pattern | **Custom `StrategyVault`**, ERC-4626-*shaped* interface, USDG as the single settlement asset, OZ virtual-shares inflation mitigation ported in by hand | Literal `ERC4626.sol` inheritance — rejected because the standard is single-asset and this vault must hold a weighted multi-token basket; ERC-7575 — rejected because it's an immature, non-OZ-shipped draft standard, too risky to build a hackathon MVP's core primitive on. |
| Keeper/automation | **Permissionless `rebalance()` + self-run cron bot**, optionally fronted by Gelato Web3 Functions if Track B confirms reach | Chainlink Automation (classic) — rejected, sunset (v1.x/v2.1 both past end-of-life as of today) and unconfirmed on Robinhood Chain; Chainlink CRE — rejected as disproportionate enterprise tooling for a hackathon timeline; OpenZeppelin Defender — rejected, actively being sunset (retires 2026-07-01, already past). |
| Oracle | **Abstract `IPriceOracle` interface now; concrete adapter decided by Track B's findings** — RedStone is the working hypothesis given its "any new Orbit chain" positioning | Committing to Chainlink or Pyth now — rejected, both require a chain team/oracle provider to have already onboarded the specific chain, unconfirmed for Robinhood Chain testnet; premature lock-in risks a rewrite. |
| Composability depth | Explicit `MAX_DEPTH` (PRD suggests 2–3) + ancestor-cycle check enforced in `StrategyFactory.createStrategy()` | Relying on EVM's native call-depth revert (1024) — rejected as a design control, it's a backstop only and would surface as an unpredictable gas-exhaustion/revert deep in a user's transaction rather than a clean creation-time rejection. |
| Solidity version | `^0.8.24`, `evm_version = "paris"` defensively until Track B confirms ArbOS ≥ 11 on Robinhood Chain, then switch to default/Shanghai | Pinning to `0.8.19` — rejected, unnecessarily forfeits OZ v5.7.0 compatibility (`^0.8.24` required) and modern compiler improvements without evidence Robinhood Chain actually needs it. |

## Implications per role

**Contracts/backend engineer (StrategyFactory / StrategyVault / RebalanceEngine / Marketplace Registry):**
- Set up Foundry (`forge init`, `foundryup`), pin `forge-std` to `v1.16.2`, `openzeppelin-contracts`
  to `v5.7.0` (`^0.8.24`). Set `evm_version = "paris"` in `foundry.toml` until Track B confirms ArbOS
  version on Robinhood Chain testnet; revisit once confirmed.
- `StrategyToken`: plain OZ `ERC20`, minted/burned only by its `StrategyVault`. No special
  composability handling needed here — it's what makes nesting "just work."
- `StrategyVault`: do **not** inherit OZ `ERC4626`. Build deposit/redeem against USDG as the sole
  settlement asset; internally track basket weights and per-asset holdings; port over OZ's
  virtual-shares/decimals-offset technique for the USDG↔StrategyToken exchange rate to block the
  inflation/donation attack from day one (cheap to add, expensive to retrofit after a demo).
- `RebalanceEngine`: implement time-based and threshold-based trigger checks (PRD §6.1) behind a
  `checkUpkeep()`-style pure/view function and a permissionless `performRebalance()` — do not assume
  any external automation network is available; write your own cron/off-chain script that just calls
  it on a timer as the MVP delivery mechanism, and treat any Gelato/Chainlink integration as optional
  polish contingent on Track B.
- `StrategyFactory`: enforce composability depth (store each strategy's `depth = max(constituent
  depths) + 1`, reject over `MAX_DEPTH`) and reject cyclic constituents at creation time — this is
  cheap insurance against the read-only-reentrancy-adjacent and gas-blowup risks documented above.
- Keep pricing behind an `IPriceOracle` interface; do not hardcode a Chainlink/Pyth/RedStone call
  directly into `StrategyVault`/`RebalanceEngine` logic, since the concrete oracle choice depends on
  Track B's findings and may need to change late.
- Budget setup time for Pyth's new Hermes API-key requirement if that path is chosen; budget for
  writing a RedStone adapter from scratch if that ends up being what's live on-chain (no OZ reference
  implementation to lean on there either).

**Frontend engineer (Next.js marketplace UI — wallet connect, contract calls):**
- No Hardhat dependency: read ABIs/addresses exported from the Foundry project (`forge build` writes
  ABI JSON under `out/`) and wire up with `wagmi`/`viem` (or `ethers`) directly — this is a
  Foundry+Next.js pairing, not Foundry+Hardhat.
- Deposit/redeem UX should be built around **USDG-in / USDG-out** as the primary flow (matches the
  recommended vault design) — direct multi-token deposit is not MVP, don't build UI for it unless the
  contracts team confirms it shipped.
- If Pyth is the chosen oracle, note the frontend (or a small backend proxy) may need to fetch signed
  price updates from Pyth's Hermes endpoint (now requiring an API key) and submit them as part of the
  deposit/rebalance transaction — this is meaningfully different UX/tx-construction work versus
  Chainlink's "just read a feed" pattern, so this should be reconfirmed once Track B/contracts settle
  on an oracle.
- Marketplace listing/"basic performance display" (PRD §6.1) needs NAV/price data per Strategy
  Token — expose this from the contracts as a `view` function so the frontend can read it directly
  via RPC without needing a subgraph/indexer for the hackathon timeline.
- Composability UI (creating a strategy that nests other Strategy Tokens) should surface the
  `MAX_DEPTH`/cycle-rejection contract behavior as a clear pre-submission validation message, not let
  users discover it via a failed transaction.

## Assumptions and open questions

- **Robinhood Chain's ArbOS version / PUSH0 support is unconfirmed.** Searched: "Arbitrum Orbit chain
  ArbOS version PUSH0 Shanghai default new Orbit chain 2026" — found only that ArbOS 11 (general
  Arbitrum-family upgrade) added PUSH0 support, not anything Robinhood-Chain-specific. Left as a
  Track B item; contracts team should defensively target `evm_version = "paris"` until resolved (see
  Recommendations).
- **Whether Chainlink, Pyth, or RedStone is actually deployed on Robinhood Chain testnet is
  unconfirmed** — explicitly deferred to Track B per the brief's own instruction. This doc only
  establishes the abstract integration pattern/cost for each.
- **Whether Gelato Web3 Functions executors are configured for Robinhood Chain testnet is
  unconfirmed.** Searched: "Gelato Network supported chains Arbitrum Orbit automation 2026" and
  fetched Gelato's Arbitrum Orbit RaaS doc page — found general Orbit-chain infrastructure support
  (Gelato as a rollup provider) but no explicit statement that Web3 Functions executors auto-cover
  every Orbit chain Gelato helps launch, let alone this specific one. Track B or direct testing
  needed.
- **No primary source was found for a concrete, numeric composability-depth-limit precedent from an
  existing index-token protocol** (Set Protocol / Index Coop docs describe modular architecture but
  not a stated max-nesting-depth design decision). Searched: "Index Coop Set Protocol nested
  composable index token depth limit reentrancy" and "circular composition prevention nested index
  token vault maximum depth counter pattern smart contract" — both returned only general
  smart-contract-security background, not a concrete precedent. Recorded as "not found"; the
  recommendation in this doc (explicit `MAX_DEPTH` + cycle check at creation time) is original
  engineering reasoning derived from the read-only-reentrancy and EVM call-depth research, not a
  reported existing-protocol pattern.
- **Gas cost of a multi-level nested rebalance cascade was not benchmarked** (no live contracts to
  benchmark against, and Robinhood Chain testnet gas costs are a Track B unknown). Flagged for
  implementation-time load testing once Track B resolves testnet specifics.
- **Pyth's exact testnet coverage and fee amounts for a Robinhood-Chain-relevant asset were not
  checked** (would require knowing what "tokenized stock" assets exist there first — a Track B
  dependency); only the general Hermes API-key/pull-fee mechanism was confirmed.
- A few WebFetch calls returned stale or format-degraded summaries for pages that were also
  independently verified via direct `curl`/GitHub-API calls in this session (e.g., an initial
  WebFetch of the OpenZeppelin Contracts GitHub releases page under-reported the version/date before
  the direct `curl` against the GitHub API corrected it to v5.7.0 / 2026-07-29). Where a discrepancy
  existed between a WebFetch summary and a direct `curl`/API result, the direct result is what's
  cited in Findings above.

## Sources

- Foundry: `https://getfoundry.sh/` (fetched 2026-09-28)
- Foundry latest release: `https://api.github.com/repos/foundry-rs/foundry/releases/latest` (fetched 2026-09-28, `v1.8.3`, published 2026-09-15)
- forge-std tags: `https://api.github.com/repos/foundry-rs/forge-std/tags` (fetched 2026-09-28, latest `v1.16.2`)
- Hardhat 3 "What's new": `https://hardhat.org/docs/learn-more/whats-new` and `https://hardhat.org/` (via search, fetched 2026-09-28)
- OpenZeppelin Contracts latest release: `https://api.github.com/repos/OpenZeppelin/openzeppelin-contracts/releases/latest` (fetched 2026-09-28, `v5.7.0`, published 2026-07-29)
- OpenZeppelin `ERC4626.sol` pragma: `https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/master/contracts/token/ERC20/extensions/ERC4626.sol` (fetched 2026-09-28, `pragma solidity ^0.8.24`)
- OpenZeppelin ERC-7535 native-asset PR: `https://github.com/OpenZeppelin/openzeppelin-contracts/pull/6624` (via search, fetched 2026-09-28)
- ERC-7575 "Multi-Asset ERC-4626 Vaults": `https://eips.ethereum.org/EIPS/eip-7575` (via search, fetched 2026-09-28)
- ERC-7540 "Asynchronous ERC-4626 Tokenized Vaults": `https://eips.ethereum.org/EIPS/eip-7540` (via search, fetched 2026-09-28)
- OpenZeppelin inflation-attack defense: `https://www.openzeppelin.com/news/a-novel-defense-against-erc4626-inflation-attacks`, `https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706`, `https://github.com/OpenZeppelin/openzeppelin-contracts/pull/3979` (via search, fetched 2026-09-28)
- Index Coop / Set Protocol architecture: `https://docs.indexcoop.com/index-coop-community-handbook/protocol/index-protocol`, `https://docs.indexcoop.com/index-coop-community-handbook/protocols/set-protocol-v2` (via search, fetched 2026-09-28)
- Chainlink Automation supported networks: `https://docs.chain.link/chainlink-automation/overview/supported-networks` (fetched 2026-09-28)
- Chainlink Automation overview/sunset: `https://docs.chain.link/chainlink-automation` (fetched 2026-09-28)
- Chainlink Automation upkeep registration: `https://docs.chain.link/chainlink-automation/guides/register-upkeep` (via search, fetched 2026-09-28)
- Chainlink Runtime Environment (CRE): `https://blog.chain.link/introducing-chainlink-runtime-environment/`, `https://docs.chain.link/cre/reference/cla-migration-ts` (via search, fetched 2026-09-28)
- Chainlink Price Feeds usage: `https://docs.chain.link/data-feeds/using-data-feeds` (fetched 2026-09-28)
- OpenZeppelin Defender sunset FAQ: `https://www.openzeppelin.com/news/defender-sunset-faq` (fetched 2026-09-28)
- Gelato Web3 Functions docs: `https://docs.gelato.cloud/web3-services/web3-functions` and `https://docs.gelato.cloud/rollup-as-a-service/rollup-stacks/arbitrum-orbit` (via search, fetched 2026-09-28; note `docs.gelato.network` 301-redirects to `docs.gelato.cloud`)
- Pyth EVM price feeds (pull model / Hermes / API key): `https://docs.pyth.network/price-feeds/core/push-feeds/evm` (fetched 2026-09-28)
- RedStone docs (modular architecture, Orbit portability): `https://docs.redstone.finance/docs/introduction/`, `https://docs.redstone.finance/docs/architecture/`, `https://blog.arbitrum.io/how-redstone-is-advancing-oracle-capabilities-with-stylus/` (via search, fetched 2026-09-28)
- Arbitrum Solidity support (PUSH0/ArbOS 11): `https://docs.arbitrum.io/solidity-support` (fetched directly via curl 2026-09-28, page states "Last updated on Sep 17, 2026")
- ArbOS Version 11 AIP: `https://forum.arbitrum.foundation/t/aip-arbos-version-11/19696` (via search, fetched 2026-09-28)
- Read-only reentrancy: `https://www.halborn.com/blog/post/what-is-read-only-reentrancy`, `https://dev.to/ohmygod/read-only-reentrancy-is-still-draining-defi-in-2026-a-defense-playbook-for-protocol-developers-13ei`, `https://arxiv.org/pdf/2409.18468` (via search, fetched 2026-09-28)
