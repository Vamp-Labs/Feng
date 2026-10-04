# 05 — Synthesis

Reads: `01-tech-stack.md`, `02-robinhood-testnet.md`, `03-domain.md` (all returned 2026-09-28, all
research-rule compliant — every finding cited or flagged as an open question, no track came back
thin). This file is the single source of truth Step 5 (tooling) and Step 6/7 (roles/handoffs) build
from; nothing below is decided from memory.

## Timeline finding — read this first, it changes the plan

`03-domain.md` §"Arbitrum Open House Singapore Buildathon" and `02-robinhood-testnet.md` §10 both
confirm, from the Arbitrum Foundation's own blog: the **online Buildathon runs 2026‑09‑14 →
2026‑10‑04**. Today is **2026‑09‑28**. That leaves **6 days**, not the PRD's own suggested 10-day
phased plan (PRD §11: Day 1–3 contracts, Day 4–5 composability, Day 6–8 frontend, Day 9–10 polish).

**Decision: the PRD's §11 timeline is superseded by the real deadline.** Every handoff below scopes
for 6 days, not 10, which means: no PRD "Nice to Have" ships (creator leaderboard, reputation score,
strategy tags), the Marketplace stays a plain on-chain-read list with no indexer/subgraph, and every
role's P1 work only starts once every P0 on the demo path is green — per the standing rule already in
this PM's process, but worth restating because the margin for slippage is now near zero. This is
flagged again at the gate as a fact to confirm with the user, since it's the single biggest planning
input this session surfaced.

## Decisions

### 1. Chain and network — Robinhood Chain testnet, chain ID 46630

**Decision:** target Robinhood Chain testnet as primary. Chain ID `46630`, RPC
`https://rpc.testnet.chain.robinhood.com`, block explorer `https://explorer.testnet.chain.robinhood.com`
(Blockscout), gas token ETH. Confirmed Arbitrum Orbit/Nitro, settling to Ethereum Sepolia.
**Finding:** `02-robinhood-testnet.md` §1–2, cross-validated by four independent sources (ChainList,
Chainstack, TrustSwap, Dwellir).
**Fallback, also decided:** Arbitrum Sepolia (chain ID `421614`) as a config-swap fallback if the
team hits faucet/asset/oracle blockers on Robinhood Chain testnet mid-build — same tooling, and
Robinhood Chain testnet itself bridges to/from Ethereum Sepolia via the canonical Arbitrum bridge, so
this isn't a disconnected fallback. **Finding:** `02-robinhood-testnet.md` Recommendation 4.
**This directly satisfies the user's explicit testnet-only instruction for this session**, resolving
the PRD's own ambiguity (PRD §4 success-metrics table says "Robinhood Chain (testnet/mainnet)") in
favor of testnet — see Contradictions Resolved below.

### 2. Contract framework — Foundry

**Decision:** Foundry (`forge`/`cast`/`anvil`/`chisel`), `forge-std` v1.16.2, no Hardhat.
**Finding:** `01-tech-stack.md` §1 and Recommendations table — Hardhat 3 closed the testing-speed gap
but its differentiator (deep TypeScript coupling) isn't needed; a second toolchain is pure overhead
on a 6-day build. Frontend talks to contracts via `wagmi`/`viem` reading ABI JSON that `forge build`
already emits — no Hardhat needed for that boundary either.

### 3. StrategyVault — custom contract, ERC-4626-shaped interface, USDG as sole settlement asset

**Decision:** `StrategyVault` is a custom contract, not `is ERC4626`. Deposit/redeem happen in USDG
only (matches PRD §6.1's USDG requirement directly and reduces NAV math to "one asset in, basket
out"). `StrategyToken` is kept a bare OZ `ERC20`, minted/burned only by its vault — this is what makes
nesting (a Strategy Token held as a constituent of another Strategy Token) work for free, since any
ERC-20-holding code path already supports it. Port OpenZeppelin's virtual-shares/decimals-offset
inflation-attack mitigation into the custom USDG↔share exchange-rate math from day one.
**Finding:** `01-tech-stack.md` §2 — OZ's `ERC4626.sol` is single-asset by design; ERC-7575
(multi-asset ERC-4626) is still an immature, non-audited, non-OZ-shipped draft, too risky to build a
hackathon MVP's core primitive on. Independent validation: Index Coop's production `SetToken` is also
a plain ERC-20 with a separate module doing the accounting, not an ERC-4626 vault (`01-tech-stack.md`
§2, cross-referenced in `03-domain.md`'s comparable-protocols section).
**Rejected:** literal `ERC4626` inheritance (wrong asset-cardinality assumption); ERC-7575 (immature
draft, no reference implementation); direct multi-token deposit as MVP (deferred as a stretch feature
per `01-tech-stack.md` §2 — USDG-only in/out is the P0 flow).

### 4. Composability — depth cap of exactly 2, enforced at creation time, with cycle detection

**Decision:** `MAX_DEPTH = 2` (depth 1 = a Strategy Token holding only raw underlying assets —
stocks/USDG; depth 2 = a Strategy Token holding other depth-1 Strategy Tokens). No depth 3.
`StrategyFactory.createStrategy()` computes `depth = max(constituent depths) + 1`, reverts if it
exceeds `MAX_DEPTH`, and walks the constituent graph to reject any self-reference/ancestor-reference
(circular composition) — both checks at creation time, not left to runtime revert behavior.
**Finding, and how a contradiction was resolved:** `01-tech-stack.md` §5 restates the PRD's own
unsourced suggestion of "2–3" and recommends enforcing whatever number is chosen, but found no
primary-source precedent for a specific number. `03-domain.md` Recommendation 1 independently arrives
at a **hard cap of exactly 2**, grounded in two concrete pieces of evidence Track A didn't have:
the Stream Finance/Elixir Nov-2025 collapse (recursive vault-of-vault looping was the root mechanical
cause of a $93M loss) and a documented Aave-adjacent exploit chain (160 nested calls, 8.6M gas) that
shows cost and attack surface compounding with depth. **Track C's more specific, evidence-grounded
number wins**: `MAX_DEPTH = 2`. This is also sufficient to satisfy PRD §12's own success definition
("Strategy inside Strategy" — depth 2 demonstrates that fully) without incurring depth-3's
compounding inflation-attack and gas risk that `01-tech-stack.md` §2 and `03-domain.md`'s
ERC-4626-nesting findings both independently flag.
**Also decided, same source (`03-domain.md` Recommendations 2–5), folded into the contracts role's
requirements:** on-chain cycle detection at creation time; nested-token NAV must recurse into live
constituent NAV, never a cached/stale/hardcoded value (the direct mechanical cause of the Stream
Finance contagion — a lending market read xUSD at a hardcoded $1); redemption of an outer Strategy
Token must redeem pro-rata in units of an inner Strategy Token, never force-unwind the inner token's
own underlying (avoids promising instant liquidity against a constituent that may not have it); and
rebalance/redeem must be gated on oracle-freshness given tokenized equities' market-hours-specific
staleness risk (an addition beyond the PRD's original generic "Oracle / pricing issues" risk row).

### 5. Keeper/automation — permissionless entrypoint, self-run cron for the demo

**Decision:** `RebalanceEngine.performRebalance(strategyId)` (or similar) is a permissionless,
publicly-callable function guarded by an on-chain time-elapsed/threshold-breached check, driven for
the demo by the team's own off-chain cron script (`cast send` on an interval). No third-party
automation network is required for the demo to work.
**Finding:** `01-tech-stack.md` §3 — Chainlink Automation (classic, v1.x and v2.1) is past its own
documented sunset dates (June 30/July 31 2026, both before today) and Chainlink is redirecting users
to the enterprise-oriented CRE product; OpenZeppelin Defender retired July 1 2026 (also past); Gelato
Web3 Functions is live but whether its executors reach Robinhood Chain testnet specifically is
unconfirmed (`02-robinhood-testnet.md` doesn't resolve it either — genuinely open). Given a 6-day
budget, betting the demo on an unconfirmed third-party integration is the wrong trade.
**Rejected:** Chainlink Automation classic (sunset), Chainlink CRE (enterprise-scale tooling,
disproportionate setup cost for 6 days), OpenZeppelin Defender (actively being decommissioned).
Gelato Web3 Functions is not rejected outright — it may be layered on top of the same permissionless
function later as P2 polish if time remains and reach is confirmed, but it is not on the P0 path.

### 6. Oracle — Chainlink-shaped interface now, Mock adapter for the demo, swappable by config

**Decision:** define `IPriceOracle` (`getPrice(address token) returns (uint256 price, uint256
updatedAt)`), implemented at first by a `MockV3Aggregator`-shaped contract the team deploys itself
(matching Chainlink's own `AggregatorV3Interface`/`latestRoundData()` pattern), swappable to a real
feed address via the same per-network `deployments/<network>/addresses.json` config file used for
every other testnet address. Chainlink is the concrete adapter target, not RedStone or Pyth, because
`02-robinhood-testnet.md` §7 confirms **Chainlink is Robinhood Chain's own announced/confirmed oracle
partner** (stated at testnet launch) and its mainnet Data Feeds already use exactly this
`AggregatorV3Interface` shape for tokenized-equity pricing — matching the mock now to the real
contract's eventual shape means swapping in a genuine testnet feed address later (if one appears) is
a config change, not a rewrite.
**Finding, and a real gap the plan must carry forward:** `02-robinhood-testnet.md` §7 is explicit that
Chainlink Data Feeds for Robinhood Chain are **documented by Chainlink only for mainnet** — no
testnet feed-address table was found anywhere despite a dedicated search, even though Chainlink CCIP
(a different product) is confirmed live on testnet with real addresses. This is carried into
Unverified Assumptions below and into the Integration role's P0 checklist (ask in the buildathon's
own dev channel, re-check the Chainlink docs page closer to demo day).
**Rejected as the primary bet:** committing code directly to Pyth (Hermes now requires an API key as
of its Aug-2026 upgrade — added setup friction with no confirmed benefit) or RedStone (`01-tech-stack.md`
§4's working hypothesis, since RedStone markets easy portability to new Orbit chains, but this is
speculation Track B did not confirm or deny) as the sole oracle without an interface abstraction —
rejected in favor of the interface-plus-mock-plus-swap approach, which de-risks the "what if the
apparent partner (Chainlink) genuinely isn't live on testnet" scenario either way.

### 7. Underlying assets — mock USDG + mock stock tokens, matched to the real interface shape, swappable by config

**Decision:** deploy `MockUSDG` (18-decimal ERC-20) and mock stock-token ERC-20s for a small ticker
set — TSLA, AMZN, NFLX, PLTR, AMD, matching the exact set the official Robinhood Chain testnet faucet
distributes per `02-robinhood-testnet.md` §5 — each implementing a `uiMultiplier()` function to match
the real Stock Token interface shape Chainlink's own docs describe. All addresses live in
`deployments/<network>/addresses.json`, never hardcoded in a contract or a frontend component, so
real testnet addresses can be substituted with a one-line config change the moment they're confirmed.
**Finding:** `02-robinhood-testnet.md` §5–6 — no official testnet address list for stock tokens or
USDG was found (only unverified, community-sourced addresses for TSLA/AMZN/NFLX from an unofficial
GitHub README, explicitly not from Robinhood's own docs); the official faucet is the only documented
path to obtain real testnet stock tokens or USDG, and its own gating step ("verify yourself") is
undocumented. **Decision explicitly does not block on this** — `02-robinhood-testnet.md` Recommendation
2 states this directly: deploying mocks behind a config file removes the blocker entirely for Day
1 contract work.

### 8. Marketplace Registry — on-chain contract, read directly by the frontend via RPC, no indexer

**Decision:** `MarketplaceRegistry` is an on-chain contract holding the list of deployed
`StrategyVault`s plus minimal metadata (name, creator, constituent list, depth). The frontend reads it
directly via RPC `view` calls — no subgraph, no off-chain indexer, no separate backend service.
**Finding:** `01-tech-stack.md` §"Implications per role" (frontend) — explicitly recommends exposing
NAV/state as `view` functions "so the frontend can read it directly via RPC without needing a
subgraph/indexer for the hackathon timeline." Given the 6-day budget (not 10), this is not just a
nice-to-have simplification, it removes an entire piece of infrastructure (and a fourth role) from
the plan.

### 9. Versions

**Decision:** Solidity `^0.8.24`, OpenZeppelin Contracts `v5.7.0`, Foundry `v1.8.3`, `forge-std`
`v1.16.2`. Set `evm_version = "paris"` explicitly in `foundry.toml` as a defensive default (compiles
without PUSH0) until Robinhood Chain testnet's ArbOS version is confirmed to support it (very likely
for a chain launched Feb 2026 on modern Nitro, per `01-tech-stack.md` §6 reasoning from Arbitrum's own
ArbOS-11 PUSH0 support doc, but not independently confirmed for this specific chain).
**Finding:** `01-tech-stack.md` §6, all versions verified directly via GitHub API / raw source fetch,
not from memory.

## Contradictions resolved

| Contradiction | Sides | Resolution | Why |
|---|---|---|---|
| Composability depth cap | `01-tech-stack.md`: "2–3" (restating PRD §10, no sourced number) vs. `03-domain.md`: hard cap of exactly 2 (evidence-grounded) | **2**, exactly | Track C's number is grounded in a specific, dated real-world incident (Stream Finance/Elixir) and a documented gas/attack-surface-compounding pattern; Track A's "2–3" is just restating the PRD's own unsourced guess. More specific, better-evidenced source wins. |
| PRD's target network (§4: "testnet/mainnet") vs. this session's scope | PRD leaves it open | **Testnet, exclusively**, chain ID 46630 | The user's explicit instruction for this run overrides the PRD's own ambiguity; the PRD predates this session's scoping decision. |
| PRD's 10-day phased timeline (§11) vs. the actual Buildathon deadline | PRD §11 assumes 10 days from an unstated start; Buildathon (`02-robinhood-testnet.md` §10, `03-domain.md`) runs 2026‑09‑14→10‑04 | **6 days remaining from today (2026‑09‑28)**, every handoff scopes to that, PRD "Nice to Have" row is fully cut from MVP | The Buildathon's own dates are independently confirmed by two research tracks from the Arbitrum Foundation's own blog; the PRD's day-count was written without reference to a real calendar date. |
| Whether the Buildathon requires testnet or mainnet deployment | Not found in any primary source by either `02-robinhood-testnet.md` §10 or `03-domain.md`'s Buildathon section — one AI-search synthesis claimed "Arbitrum Sepolia is the baseline requirement" but neither track could trace it to a citable page | **Proceed on Robinhood Chain testnet per the user's explicit instruction; do not treat the untraceable "Sepolia baseline" claim as real.** Flagged as an open question to resolve on HackQuest directly, not assumed either way. | No primary source exists to resolve this either direction; inventing a rule would violate the research rules both tracks were held to. Un-sourced claims are explicitly discarded, not adopted "just in case." |
| Mainnet chain ID: `4663` (four independent sources) vs. `5042` (one AI-summarized secondary source) | Internal to `02-robinhood-testnet.md` §1, already resolved there | **4663** — not actually relevant to this build (testnet-only), recorded here only so downstream roles don't get confused by the `5042` number if they see it in a source | `02-robinhood-testnet.md` traced `5042` to an unrelated chain ("Arc") via a targeted follow-up search; `4663` is corroborated independently by four sources. |

## The stack, fixed

- **Chain:** Robinhood Chain testnet, chain ID `46630`, RPC `https://rpc.testnet.chain.robinhood.com`,
  explorer `https://explorer.testnet.chain.robinhood.com` (Blockscout), gas token ETH. Fallback:
  Arbitrum Sepolia, chain ID `421614`, selected by a `DEPLOY_NETWORK`/`NEXT_PUBLIC_NETWORK` env var.
- **Contracts:** Foundry v1.8.3, `forge-std` v1.16.2, OpenZeppelin Contracts v5.7.0, Solidity
  `^0.8.24`, `evm_version = "paris"` (defensive).
- **Core contracts:** `StrategyToken` (plain OZ ERC-20), `StrategyVault` (custom, ERC-4626-shaped,
  USDG-only settlement, virtual-shares inflation mitigation), `StrategyFactory` (MAX_DEPTH=2 + cycle
  detection at creation), `RebalanceEngine` (permissionless `performRebalance`, time + threshold
  triggers, oracle-freshness gate), `MarketplaceRegistry` (on-chain list, read via RPC).
  Supporting: `MockUSDG`, mock stock-token ERC-20s (TSLA/AMZN/NFLX/PLTR/AMD, `uiMultiplier()`
  interface), `MockV3Aggregator`-shaped `IPriceOracle` implementation.
- **Frontend:** Next.js (App Router, Server Components by default per standing rules), `wagmi`/`viem`
  for wallet connect + contract calls, ABIs read from `forge build`'s `out/` output, no subgraph/indexer.
- **Config:** one `deployments/<network>/addresses.json` per network (`robinhood-testnet`,
  `arbitrum-sepolia`), consumed identically by Foundry deploy scripts and the frontend — no address is
  ever hardcoded in a contract or a component.
- **Keeper:** off-chain cron script calling the permissionless `performRebalance` entrypoint on an
  interval; no third-party automation network required for the demo.
- **Buildathon target:** Arbitrum Open House Singapore, online Buildathon, deadline **2026‑10‑04**
  (6 days from today).

## Unverified assumptions that still stand (for the gate)

1. **Whether Chainlink Data Feeds (or any oracle) are actually deployed with real addresses on
   Robinhood Chain testnet** — Chainlink's own docs document this integration for mainnet only; no
   testnet feed-address table was found. (`02-robinhood-testnet.md` §7)
2. **No real testnet USDG contract address was found** anywhere, despite USDG being confirmed
   generally deployed on Robinhood Chain (both networks). (`02-robinhood-testnet.md` §6)
3. **Testnet stock-token addresses are unofficial/community-sourced only** (from a GitHub README, not
   Robinhood's own docs) and need re-verification against the explorer before any real use.
   (`02-robinhood-testnet.md` §5)
4. **`docs.robinhood.com` and the testnet Blockscout explorer were unreachable from the research
   environment all session** (TLS certificate errors on every attempt, both WebFetch and raw `curl`)
   — plausibly an environment-local issue, not a real outage, but every claim sourced only through
   those domains was relayed secondhand via sources that quote them. The team should verify both from
   an ordinary browser before trusting any address or claim sourced only that way.
   (`02-robinhood-testnet.md` §"Operational finding")
5. **The Buildathon's own submission requirements — a testnet-vs-mainnet deployment mandate, a
   deliverables checklist (contract addresses, verified source, demo video), and a numeric judging
   rubric — were not found in any primary source** by either research track that looked for them.
   HackQuest registration (`arbitrum-singapore.hackquest.io`) is required to see the full rules.
   (`02-robinhood-testnet.md` §10, `03-domain.md` Assumptions)
6. **The official faucet's "verify yourself" gating step is undocumented** — unknown whether it's a
   simple captcha or something stricter. (`02-robinhood-testnet.md` §3)
7. **Robinhood Chain testnet's exact ArbOS version (and therefore PUSH0/Shanghai-EVM support) is
   unconfirmed** — defensively mitigated by setting `evm_version = "paris"`. (`01-tech-stack.md` §6)
8. **Whether Gelato Web3 Functions executors are actually configured for Robinhood Chain testnet is
   unconfirmed** — not required for the P0 keeper design, only relevant if pursued as P2 polish.
   (`01-tech-stack.md` §3)
9. **Composability depth cap of exactly 2 is original engineering reasoning derived from documented
   general hazards (Stream Finance precedent, ERC-4626 nesting-compounds-inflation-risk), not a
   reported existing-protocol precedent** — no comparable protocol was found to state a specific
   numeric depth limit. (`03-domain.md` Recommendation 1, `01-tech-stack.md` §5)

If a track comes back thin during Step 6/7 drafting, it will be re-dispatched before any handoff
relying on it is finalized — none needed re-dispatch this round; all three came back fully cited.
