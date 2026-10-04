# Feng threat model (E8-T1)

- **Version**: 1.0, written 2026-10-03 by the independent security reviewer (not the author of the contracts).
- **Scope**: Feng on Robinhood Chain testnet (chain 46630): the V1 contracts deployed today, the frozen V2 spec (`docs/handoffs/04-contracts-v2.md`, "the spec"), the ops layer (price relayer, keeper, faucet wallet) and the frontend trust surface that touches funds. Standing decisions are not relitigated: testnet only, USDG deposits and redeems, depth cap 2, keys only through env variables.
- **Inputs read**: plan sections 0, 4, 5.5, 5.6, E2, E3, E4, E8 and 8.5; the spec in full; `docs/research/03-domain.md`, `07-testnet-reality-check.md`, `09-price-source-and-feed.md`; every V1 contract under `contracts/` (not the tests).
- **What this document is not**: it is not a review of the V2 code. At the time of writing `contracts/v2/` held only `IFengAggregator`, `IPriceOracleV2`, `IVenue`, `FengAggregator` and `ChainlinkPriceOracleV2` (glanced at twice, see F-01 and F-13, not reviewed). The code review is the second dispatch and follows `docs/security/review-checklist-v2.md`.
- **Evidence produced for this document** (all local, no RPC, no key, no transaction): (a) an exact-integer Python model of the spec share math, about 2.4 million trials over USDG decimals 0, 2, 6, 8, 9, 12, 15 and 18 plus a targeted wei-class search (section 5, T-01); (b) three Foundry proofs of concept against a scratch copy of the V1 sources (`docs/security/poc/V1Exploits.t.sol`, run instructions in the file header; results in section 6 and in `known-limitations.md`).
- **Cross references**: threats are `T-xx`, findings against the spec are `F-xx`, checklist rows are `C-xx` / `I-xx` (spec ids), `X-xx` (extra checks introduced here), `G-xx` (global gates), all in `review-checklist-v2.md`.

## 0. Headline findings (read this first)

1. **V1 is exploitable today by anyone, and the exploit is three function calls.** The price feeds behind the deployed V1 vaults are `MockV3Aggregator` with an ungated `updateAnswer`. V1 mints shares at NAV (stock value only), but redeems a pro-rata share of the idle USDG pot. An attacker sets every constituent price to 1 (8 decimals), deposits 1 USDG (receives about a million times the existing supply of shares), restores the price and redeems: the proof of concept took 20,000.98 USDG out of a vault that held 20,000.00 USDG of other people's deposits after putting in 1.00. Mock USDG, so no real value is at risk, but this is the "smart contract quality" criterion. It is also why V1 must not be described as secure anywhere in the submission. Details: T-06 (V1 row), `known-limitations.md` KL-V1-01 to KL-V1-03.
2. **V1 payouts do not follow NAV** (separate from the exploit): proof of concept with a price doubling between two deposits: Alice (deposited 100 at price 250) `previewRedeem` 200, actual payout 133.33; Bob (deposited 100 at price 500) `previewRedeem` 100, actual payout 66.67. Value moves from the later depositor to the earlier one.
3. **V1 delegated redeem (C-02) is real**: any caller redeems an owner's shares to any receiver once the owner approved the vault on the share token (proof of concept: 1,000 USDG taken from Alice by an unrelated address).
4. **V2 spec is sound on the headline items** (inflation, decimals, nested NAV, reentrancy, exits that never depend on the oracle). The residual V2 risks that matter are not in the vault math: (a) the relayer key is bounded per update but not per unit of time, so a stolen key walks the price anywhere inside one block (F-01); (b) the desk has no exposure cap, so a manipulated price drains the reserve in one transaction (F-02); (c) `ENABLE_SHOCK=1` gives the same relayer key a plus or minus 30 percent lever (F-03); (d) the faucet ETH budget funds 20 claims, not 200 (F-04); (e) `maxPriceStaleness` is 12 hours in the spec but 6 hours in R2 (F-05). None is a Critical on testnet. Each is cheap to tighten before G1.
5. **One trust concentration the spec does not call out**: the deployer key is admin or owner of nearly everything (stock-token admin, USDG admin and minter, every aggregator admin, oracle owner, desk owner, registry admin, faucet admin) and is the default guardian. See T-21.

## 1. System and trust boundaries

```
                  Robinhood API (rhj/prices)        <- off-chain, unauthenticated, no SLA
                            |
                      RELAYER (key R)  ---- updateAnswer / refresh / shockAnswer ----+
                                                                                    v
 user wallet ---> StrategyVaultV2 (depth 1 or 2) --reads--> ChainlinkPriceOracleV2 --> FengAggregator x6
      |   ^            |   |  \                                  (owner: deployer)       (admin: deployer)
      |   |            |   |   +--child.deposit/redeem--> StrategyVaultV2 (depth 1)
      |   |            |   v
      |   |            |  OracleDesk (IVenue)  <-- registry.isRegistered(msg.sender) gate
      |   |            |   | mint mode: holds MINTER_ROLE on mock Stock tokens
      |   |            |   | inventory mode: holds real tokens + USDG reserve
      |   |            v   v
      |   |        USDG (mock 6 dec | Paxos 6 dec)       Stock tokens (mock | real, upgradeable, blocklist, pause)
      |   +--- shares: StrategyTokenV2 (vault-only mint/burn/burnFrom)
      |
      +--> FengFaucet (dispenser = server wallet F) --> ETH drip + MockUSDGV2.mint
 KEEPER (key K): RebalanceEngineV2.performRebalance / checkpoint     GUARDIAN: pause / unpause three entry points
 StrategyFactoryV2 -> VaultDeployerV2 -> new StrategyVaultV2   MarketplaceRegistryV2 (FACTORY_ROLE = factory only)
```

Trust boundaries that matter: user to vault (untrusted input, hostile receivers and tokens in tests only); vault to oracle and venue (immutable, curated, trusted); relayer to feed (role-gated, bounded per update); feed to vault (trusted answer, staleness-checked); issuer tokens to vault (trusted code that can change, upgradeable proxies); off-chain ops hosts to chain (keys in env only).

## 2. Assets

| ID | Asset | Where | Why an attacker cares | Value today |
|---|---|---|---|---|
| A1 | Holder value: constituents, idle USDG, share token balances | each vault | theft, dilution, freezing | mock (sandbox), small real (Live) |
| A2 | Desk USDG reserve (10,000,000 mock USDG at deploy) and desk token inventory (Live) | `OracleDesk` | the only counterparty that pays USDG on redeem and rebalance sells | mock; real USDG in Live is whatever a human claimed from the Paxos faucet |
| A3 | Price integrity | `FengAggregator` x6, `ChainlinkPriceOracleV2` | every mint, redeem and rebalance prices off it | decides A1 and A2 |
| A4 | Exit availability | `redeem*` paths | users must always be able to leave (Stream Finance lesson, `03-domain.md`) | core product claim |
| A5 | Faucet ETH balance (default 0.004 ETH) and the mock USDG supply | `FengFaucet`, `MockUSDGV2` | denial of judge onboarding, leaderboard gaming | the demo |
| A6 | Gas balances of relayer, keeper, faucet-dispenser wallets | EOAs | if empty, ops stop | 0.005 ETH-class |
| A7 | Admin and owner keys (deployer; guardian if separate) | env of the human | god mode on testnet | high |
| A8 | Registry integrity and marketplace listing quality | `MarketplaceRegistryV2` | impersonation, spam, keeper drain | reputational |
| A9 | Secrets: `DEPLOYER_PRIVATE_KEY`, `RELAYER_PRIVATE_KEY`, `KEEPER_PRIVATE_KEY`, `FAUCET_PRIVATE_KEY`, `CRON_SECRET` | env, Vercel or Railway | take over ops | high |
| A10 | The judging experience (site, faucet, demo run) | whole product | availability is the real testnet risk | the submission |

## 3. Actors

| ID | Actor | Capability assumed |
|---|---|---|
| X1 | Anonymous user / first depositor / attacker | any EOA or contract, can create strategies, can deploy through `VaultDeployerV2`, creating a vault costs about 0.00003 to 0.00005 ETH |
| X2 | Informed trader | watches `api.robinhood.com` and other markets faster than the relayer ticks |
| X3 | Malicious strategy creator | chooses name, symbol, constituents, weights, interval, `maxSlippageBps`, metadata |
| X4 | Sybil faucet farmer | scripts fresh addresses, rotating IPs |
| X5 | Token issuer (Robinhood Stock tokens, Paxos USDG) | can pause, blocklist, upgrade proxies, change `uiMultiplier` |
| X6 | Compromised relayer key `R` | holds `UPDATER_ROLE` (and `SHOCK_ROLE` if `ENABLE_SHOCK=1`) |
| X7 | Compromised keeper key `K`, dispenser key `F`, or `CRON_SECRET` | keeper: pays gas only; dispenser: `claimFor`; cron secret: triggers `/api/ops/tick` |
| X8 | Insider: deployer, desk owner, oracle owner, guardian | the testnet admin set (often one key) |
| X9 | Data source failure | Robinhood API returns zeros, wrong decimals, stale or poisoned values; TLS interception by the user's ISP |
| X10 | Phisher | lookalike vault or token, decoy USDG, XSS through metadata |
| X11 | Sequencer | centralised on testnet; ordering and downtime, no public mempool |

## 4. Trust assumptions

| Component | We trust it to | If it fails | Blast radius | Control in spec or plan | Residual |
|---|---|---|---|---|---|
| **Price relayer** (key R, host, code) | push correct prices at most every 5 min within bounds | wrong price accepted up to `maxDeviationBps` (spec 1500, R2 1000) per update, unlimited updates per block | every vault valuation and every desk fill; with `SHOCK_ROLE` a further 3000 bps off the anchor | role gate, per-update deviation bound against the anchor, `revokeRole`, `forceAnswer` re-anchor | stolen key is bounded per update only (F-01) |
| **Robinhood price API** | return sane quotes | wrong decimals, zero, frozen weekend quote, schema drift | relayer pushes a plausible wrong price, or nothing | relayer parsing rules (R2 R-A: tokenBid/tokenAsk, spread guard 500 bps, band check, halt skip), on-chain bound | no SLA; terms of use unconfirmed (R2 open question 1) |
| **FengAggregator admin** (deployer) | not abuse `forceAnswer`, `setParams`, `setShockEnabled` | any price | same as relayer, unbounded | none beyond key custody | single key |
| **ChainlinkPriceOracleV2 owner** (deployer) | point feeds at honest aggregators | `setFeed` to any contract (even an EOA) or `removeFeed` | all valuations or a DoS of `deposit`/`redeem` (`redeemInKind` survives) | `onlyOwner`, events | single key |
| **Desk reserve and owner** | pay USDG on sells, deliver tokens on buys | `redeem` and rebalance sells revert (`InsufficientLiquidity`); owner can `withdrawReserve`, `setSpreadBps` up to 100 bps, `setToken(Unsupported)` at any time | USDG redeem path of every vault | registry gate, accounting identity I8, `redeemInKind` | trusted owner (T-09) |
| **Guardian** (default deployer) | pause only when needed | deposits and rebalances blocked indefinitely | liveness of deposits | cannot touch exits or funds, immutable per factory | no expiry (R-05) |
| **Deployer** | secure its key | total control on testnet | everything | key in env only, never printed | concentration (T-21) |
| **Faucet dispenser wallet** (key F) | call `claimFor` only after server-side limits | up to `min(dailyCap, funded ETH / ethPerClaim)` claims per day to attacker addresses | faucet ETH, mock USDG supply | `DISPENSER_ROLE`, EOA-only recipients, one claim per address, daily cap | sybil limits live off-chain (T-11) |
| **Keeper** (key K) | call `performRebalance`, `checkpoint` | nothing breaks; liveness only | rebalance timing | permissionless, anyone can replace it | gas drain by spam vaults (T-13) |
| **Token issuers** (X5) | keep ERC-20 semantics, no hooks, no fees | frozen transfers, changed behaviour, changed `uiMultiplier` | any vault holding the token | `redeemInKindExcluding`, measured balance deltas, Live script asserts `uiMultiplier == 1e18` | out of scope to recover (spec 1.7) |
| **Sequencer / chain** | order and include transactions | stale prices pile up, exits delayed | liveness | `redeemInKind` is oracle-free, timestamps only | no Chainlink sequencer feed on testnet |
| **OpenZeppelin 5.7.0**, solc 0.8.24, evm paris | be correct | any library bug | all | pinned, library-first rule | no audit of the V2 code besides this process |
| **USDG = 1.00 USD** | stay pegged | NAV is wrong in USD terms; relative accounting stays consistent | economic only | explicit assumption S3 | out of scope (R-09) |

## 5. Attack catalogue

Rating scale. **Likelihood**: H = plausible for any user or any key leak during the judging window; M = needs skill, targeting or a specific market condition; L = needs privileged access or contradictory conditions. **Impact** is rated for the testnet product (T) and, in brackets, for the same defect with real value at stake (R): Crit / High / Med / Low / Info. **Status**: M = mitigated in the spec, P = partially mitigated, A = accepted or out of scope, R = request to the coordinator (finding F-xx). "V1" lines say what the deployed V1 does today.

### Summary matrix

| ID | Threat | Likelihood | Impact T (R) | Status | Residual |
|---|---|---|---|---|---|
| T-01 | Inflation and donation, 6 and 18 decimals | L | Info (Crit) | M | donations above about 1e12 USDG-equivalent out of model |
| T-02 | Share-price manipulation via desk, in-kind deposit, forced rebalance | M | Low (Med) | M/A | spread externality bounded by `ExceedsMaxWeight` |
| T-03 | Reentrancy through token hooks | L | Info (Crit) | M | token upgrade could add hooks |
| T-04 | Real token or USDG blocklist, pause, freeze of a vault | M | Med (High) | P/A | frozen slice cannot be recovered |
| T-05 | Stale, weekend, halted, corporate-action feeds | H | Med (High) | P | 12 h window; mainnet path needs per-feed staleness |
| T-06 | Relayer or feed-admin compromise | M | Med (Crit) | P, R (F-01, F-02, F-03) | per-update bound only |
| T-07 | Price API poisoning, schema drift, TLS interception | M | Low (Med) | P | plausible wrong prices inside the bound |
| T-08 | Stale-NAV arbitrage against the desk (informed flow) | H | Low (High) | A | reserve bleed; leaderboard gaming |
| T-09 | Desk reserve exhaustion, owner withdrawal | M | Med (High) | P | exits via in-kind only |
| T-10 | Desk gate trust, rogue and lookalike vaults | M | Low (Med) | P, R (F-07) | phishing by UI confusion |
| T-11 | Faucet sybil and ETH budget arithmetic | H | Med (n/a) | R (F-04) | judge onboarding outage |
| T-12 | Faucet dispenser key, cron secret, API route abuse | M | Low (n/a) | P | bounded by faucet balance |
| T-13 | Keeper griefing and DoS: failing child, spam vaults, forced rebalances | M | Low (Med) | P/A | gas drain, parent blocked by child |
| T-14 | Depth and cycles | L | Info | M | none known |
| T-15 | Registry spam, name impersonation, metadata abuse | H | Low | A | cosmetic and ops cost |
| T-16 | Unsafe approvals | M | Med (High) | M | UI max approvals |
| T-17 | V1 delegated redeem (C-02) | M | High (Crit) | M in V2, open in V1 | V1 stays open |
| T-18 | Oracle and token decimals mismatch | L | High (Crit) | M | non-standard feeds |
| T-19 | ERC-20 return-value and behaviour quirks | L | Med | M | upgradeable real tokens |
| T-20 | Guardian abuse and pause semantics | L | Low | A | no expiry |
| T-21 | Admin key concentration and compromise | M | High (Crit) | A, R (F-09) | single key |
| T-22 | Rounding, dust, `NoValueAdded` griefing | M | Low | M | dust accrues to holders |
| T-23 | Nested NAV: previews, child donation, revert coupling | M | Low | M/A | preview tolerance |
| T-24 | L2 specifics: `block.number`, timestamps, sequencer, cheap gas | L | Low | M | none |
| T-25 | Returndata bomb and gas griefing in try/catch | L | Low | R (F-06) | none if capped |
| T-26 | Frontend, deployment artifacts, decoy tokens, secret hygiene | M | Med | P | human process |
| T-27 | USDG depeg, `uiMultiplier` change | L | Med (High) | A | out of scope |
| T-28 | Share token mishandling (sent to vault, plain ERC-20) | M | Low | A | user loss only |
| T-29 | Rebalance churn bleeds holders through spread | M | Low | A | economic, not theft |
| T-30 | Mint-mode desk role and mode misconfiguration | L | Med | P | deploy-script assertions |

### T-01 Inflation and donation attack (6 and 18 decimals)

- **Scenario**. First depositor deposits a dust amount, then donates USDG (or a constituent valued by the oracle) directly to the vault to push NAV per share up, so that a later depositor's shares round down to zero or lose most of their value. Variants: donation while `S == 0` with leftover dust; donation to a child vault under a depth-2 parent; donation of a constituent token instead of USDG.
- **V1**. Offset 3 (`DECIMALS_OFFSET`), NAV excludes idle USDG so a USDG donation does not move NAV (V1 test `test_rawUsdgDonation_doesNotAffectNav`); inception price 0.001; 18-decimal USDG only (C-03, C-04).
- **V2 mitigation**. `vA = 1`, `vS = 10 ** max(18 - d, 12)`; `nb` rounded up, `na` rounded down, shares floored; deposit mints on the measured value delta; `ZeroShares`, `NoValueAdded`, `minShares`; redeem is physical pro-rata so there is no stranded value for the donor to recover.
- **Independent check (this review)**. Exact-integer model of the spec formulas (idle-only vault, zero spread, which is the attacker-favourable corner): attacker first deposit `a` in {1, 2, 3, random up to 1e8 USDG}, donation `D` up to 1e9 USDG (and small ranges), victim `V` from 1 USDG-unit class to 1e6 USDG, about 2.4 million trials over `d` in {0, 2, 6, 8, 9, 12, 15, 18}: attacker profit never positive (maximum observed 0), victim loss never above 1 smallest USDG unit (relative 1e-6 at `V = 1` USDG with `d = 6`), no trial reverted `ZeroShares` in the sampled domain. Targeted search for the wei-class attacker (a in {1, 2, 10}, D chosen as `V * vS / k`): the victim never lost value (the virtual shares dilute the attacker). The model omits venue legs and constituents, so I11 on the real contracts remains the acceptance evidence.
- **Likelihood** L (no profit found). **Impact** Info on testnet; Crit if profitable on mainnet. **Status** M.
- **Residual**. Donations above about 1e12 USDG-equivalent are outside the model (R-17); at `d = 18` the inception price is 1e-12 USDG per share, which is correct but confusing in a UI that hardcodes 1.00; `d` below 6 is allowed by the constructor (any `d <= 18`) and should be in the decimals matrix because `MIN_LEG_USDG = max(U / 100, 1)` degenerates (X-12).
- **Checklist**: C-04, C-05, C-25, I9, I11, X-12.

### T-02 Share-price manipulation through the desk, in-kind deposits and forced rebalances

- **Scenario A, desk spread**. An attacker tries to move NAV by trading through the desk around a victim's deposit. The desk only serves registered vaults and fills at oracle price plus or minus spread, so there is no price impact to exploit; the attacker can only choose when legs execute (see T-13).
- **Scenario B, in-kind deposit**. `depositInKind` values the deposited token at the oracle (floor) with no spread. If the oracle is above what the vault could realise (desk sells at `p * (1 - spread)`), the depositor receives shares for value the vault later loses on the exit spread; the loss is socialised (C-27, R-14). For a child strategy token the value is `child.previewRedeem`, i.e. pre-spread NAV.
- **Scenario C, forced rebalance**. Donating a constituent to push its weight above `effectiveMax` forces a threshold rebalance; holders pay about 0.2 percent of the shifted notional (C-28). The donor loses the whole donation, so the attack costs 500 times what it extracts.
- **Mitigation**. Measured value delta for USDG deposits; `ExceedsMaxWeight` guard on in-kind deposits; effective threshold `max(maxWeightBps, target + 10 bps)`; leg tolerance 10 bps; sells before buys; registry gate on the desk; `NoValueAdded`.
- **Likelihood** M. **Impact** Low (Med). **Status** M for A and C, A for B (documented externality bounded by `amount * 2 * spreadBps`).
- **Residual**. In-kind dilution of up to 20 bps of the deposited notional per in-kind deposit in the worst case; negligible on testnet.
- **Checklist**: C-15, C-17, C-27, C-28, C-29, I4, I6, X-09.

### T-03 Reentrancy through token hooks (ERC-777 style, callbacks, venue)

- **Scenario**. A constituent, USDG or venue calls back during `transfer`, `transferFrom`, `mint`, `burn` or a swap, re-entering `deposit`, `redeem`, `executeRebalance`, a view that reads balances, or a sibling vault that shares the desk.
- **Mitigation**. OZ `ReentrancyGuard` on every state-changing vault function; `nonReentrantView` on every view that reads balances or NAV (read-only reentrancy); the desk is `nonReentrant`; the faucet is `nonReentrant`, effects before the ETH call, recipients restricted to code-less addresses (where EIP-7702 is live, delegated EOAs have code and are rejected). Shares are burned before tokens leave in `redeem`; in `deposit` shares are minted after the legs because the share count needs the measured delta, so the guard, not ordering, protects that window (spec 1.6). Real tokens here (Paxos USDG, Stock) are plain ERC-20 without hooks, hostile tokens exist only as test mocks.
- **Cross-vault**. Parent to child calls enter the child guard, which is free; a hook inside the child that calls the parent hits the parent guard (entered); a hook that calls a different vault is covered because every vault's NAV reads are guarded and the desk is guarded.
- **Likelihood** L. **Impact** Info (Crit). **Status** M.
- **Residual**. An upgradeable real token that later adds hooks (X5) would be a new trust event; the factory only admits tokens supported by both oracle and venue, a curated set.
- **Checklist**: I10, `test_reentrancy_*`, G-09, X-05.

### T-04 Real token or USDG blocklist, pause or freeze of a vault

- **Scenario**. Stock tokens have `onlyNotPaused` and `onlyNotBlocked` on `transfer`, `transferFrom`, `approve` (07 section 2.1); Paxos USDG has a blocklist and pause by Paxos design (07 section 4, unverified whether contract recipients are affected); both are upgradeable proxies. A pause or a blocklisted vault or desk address blocks every movement of that token.
- **Effect on V2 paths**. `deposit`, `depositInKind`, `redeem` (USDG), `executeRebalance`, `redeemInKind` all revert if they must move the frozen token; `redeemInKindExcluding` lets a holder exit with every other asset and forfeit the frozen slice to the remaining holders; deposits of other assets keep minting against a NAV that includes the frozen slice at oracle value.
- **Mitigation**. Atomic revert (nothing lost silently), `redeemInKindExcluding`, Sandbox is the default universe, the Live universe is additive (E4 stops if R1 shows transfers from contracts are blocked).
- **Likelihood** M (a global testnet pause during maintenance is plausible). **Impact** Med on Live, none on Sandbox mocks (R: High). **Status** P/A: recovery of a frozen asset is out of scope (spec 1.7).
- **Residual**. Users who skip a slice forfeit it; the UI must say so. If the frozen token is USDG every USDG path is dead and only in-kind exits with the USDG slot skipped remain.
- **Checklist**: C-11, `test_redeemInKindExcluding_skipsFrozenToken`, I5, X-13, X-14.

### T-05 Stale, weekend, halted and corporate-action feeds

- **Scenario**. The relayer stops, or the market is closed. R2 measured that the API serves the Friday quote byte-identical with an advancing `generatedAt` and `isTradingHalt = false`, so the heartbeat re-publishes an old price with a fresh `updatedAt`. Corporate actions change `uiMultiplier` and Robinhood pauses its oracle. A dead relayer lets users trade at the last price for up to `maxPriceStaleness`.
- **Mitigation**. Vault reverts `StalePrice` on deposit, in-kind valuation, rebalance and USDG redeem; `redeemInKind` never reads a feed (I5); views do not revert on staleness except as noted; `_checkAllFresh` recurses into children via `priceStatus()` (C-09); relayer skips on halt, spread over 500 bps, band violations and pending multipliers (R2); ops alarm at 35 min.
- **Likelihood** H (weekends are certain). **Impact** Med. **Status** P.
- **Residual**. (a) The window is `maxPriceStaleness`: 12 h in the spec (C-33), 6 h in R2: F-05. (b) A weekend heartbeat makes the oracle look fresh while the price is frozen; the UI must not read freshness as liveness (R2 `lastChangeAt`). (c) The mainnet path needs per-feed staleness near 96 h, sequencer-uptime and `oraclePaused` checks; the single immutable `maxPriceStaleness` per vault is not mainnet-ready (limitation).
- **Checklist**: C-09, C-33, I5, X-08.

### T-06 Relayer compromise (and feed-admin compromise)

- **Scenario**. Key R leaks, or the relayer code or host is subverted. `updateAnswer` accepts any answer within `maxDeviationBps` of the anchor, then moves the anchor to it. Nothing limits how many updates occur per block or per hour, so a stolen key reaches any price: `1.15^n` after `n` calls (ten calls make a 4x move). With `SHOCK_ROLE` (granted when `ENABLE_SHOCK=1`) a further 30 percent off the anchor is available in one call. `refresh()` can keep a manipulated price fresh indefinitely. R2 already notes "a stolen key can walk the price in stepped pushes inside one block".
- **Exploit shape**. (1) walk TSLA down 100x; (2) deposit USDG into a TSLA-heavy vault (desk mints at the low price, the attacker's shares are priced at the same low NAV); (3) walk TSLA up 100x; (4) redeem: the desk pays the reserve out at the inflated price. Upper bound: the desk reserve (10,000,000 mock USDG); the first redeemers win and later holders find the USDG path empty (they keep `redeemInKind`).
- **Mitigation in the spec**. Role gate, deviation bound against the anchor, `shockEnabled` default false, `revokeRole` and `forceAnswer` by the admin, no back-dating, per-vault `maxSlippageBps` is irrelevant (it compares the venue to the oracle, which is the manipulated source).
- **Gaps**. No minimum interval between updates, no cumulative movement bound, no desk exposure cap, the shock role shares the relayer key by default. Requests: F-01, F-02, F-03.
- **Likelihood** M (key in a Vercel or Railway environment, 5-minute tick, a route handler that signs). **Impact** Med on testnet (reserve is mock), Crit with real reserve. **Status** P.
- **V1**. The feeds are open to everyone (no key needed): see section 6 and KL-V1-02. This is strictly worse than a stolen relayer key.
- **Residual after F-01 to F-03**. A stolen key can still move a price by one bound per minimum interval and by the shock bound while the shock window is open, which an alert on `AnswerUpdated` frequency and `revokeRole` can catch within minutes.
- **Checklist**: C-21, X-01, X-02, X-03, X-15.

### T-07 Price API poisoning, schema drift, TLS interception

- **Scenario**. The API returns zeros, 100x values, a different field set, or is intercepted (the user's ISP intercepts TLS to the RPC and returns a wrong host for `api.robinhood.com`, R2 section 1.7). A relayer on the user's laptop (the `keeper.sh` fallback) is exposed to that network.
- **Mitigation**. Parse only the fields used, reject missing or non-positive values, use `tokenBid`/`tokenAsk`, spread guard, band check against `dailyLow`/`dailyHigh`, two agreeing fetches before a large move, `generatedAt` only for clock-jump detection, on-chain per-update bound, TLS verification fails closed, production relayer hosted outside the user's network (R5).
- **Likelihood** M. **Impact** Low on testnet. **Status** P. **Residual**: a plausible but wrong price inside the bound is accepted; undocumented fields `tokenBid` and `tokenAsk` may change.
- **Checklist**: X-01, ops tests in R2 section "Tests/Security".

### T-08 Stale-NAV arbitrage against the desk (informed flow)

- **Scenario**. The oracle lags the real price by up to one relayer tick (5 minutes) and by anything below the 10 bps push threshold. A trader who reads the real price (or another venue) deposits into a vault before the push and redeems after it. The desk, which fills at oracle price in mint mode with unlimited depth, is the counterparty and loses the move minus a 10 bps spread each way. Round trip is profitable for moves above about 20 bps. Monday gaps and the Sunday reopen are the large cases; the demo shock is the same effect by design. With a performance leaderboard (E5) the motive is ranking, not mock USDG.
- **Mitigation**. 10 bps desk spread, deviation-bounded and role-gated feed, 5-minute cadence, staleness window, vault pauses at the guardian's discretion; mainnet path needs Chainlink plus a redemption fee (R-04).
- **Likelihood** H if anyone cares to farm it. **Impact** Low on testnet (reserve bleed on mock USDG; no holder is diluted because shares are priced at oracle NAV and the desk takes the loss), High on mainnet. **Status** A (documented).
- **Residual**. Reserve bleed; leaderboard distortion. A per-window desk outflow cap (F-02) bounds it.
- **Checklist**: X-02, I8.

### T-09 Desk reserve exhaustion and owner powers

- **Scenario**. Organic: redeems and rebalance sells exceed the reserve. Adversarial: T-06 or T-08 drain it. Owner: `withdrawReserve`, `withdrawInventory`, `setToken(token, Unsupported)`, `setSpreadBps(100)` take effect immediately and strand every USDG redeem.
- **Mitigation**. Reserve 10,000,000 against seeds of 26,200 (R-12), `redeemInKind` needs no desk, accounting identity I8 with events for every funding movement, `reserveUsdg()` in the ops health block.
- **Likelihood** M. **Impact** Med (High if real USDG). **Status** P: the owner is trusted.
- **Residual**. USDG redeems depend on a single trusted owner; no timelock; `redeemInKind` is the only unconditional exit. Exposure cap request F-02.
- **Checklist**: I8, X-02, X-15, C-32.

### T-10 Desk gate trust, rogue and lookalike vaults

- **Scenario**. `VaultDeployerV2.deploy` is permissionless, so anyone can create a vault with any `usdg`, `oracle`, `venue`, `guardian` and any name, and it will look like a Feng vault to anyone reading bytecode shape. It is not registered (so it cannot trade on the desk and cannot be a child), but a user who deposits into it trusts a stranger's parameters. Separately, any registered vault may call `desk.swapExactIn`: a flaw in vault code is a flaw in the desk.
- **Mitigation**. Registry gate (`isRegistered`), `FACTORY_ROLE` held only by the factory, children must satisfy `vaultOf[token] != 0`, the frontend lists strategies from the registry only and filters events by registered addresses.
- **Likelihood** M. **Impact** Low (Med). **Status** P. **Residual**: phishing by UI confusion; optional hardening F-07 (factory-only deploy).
- **Checklist**: C-32, C-35, X-06, X-17.

### T-11 Faucet sybil and the ETH budget arithmetic

- **Scenario**. One claim per address is trivially bypassed by fresh addresses. The sybil defence is off-chain (the server wallet is the only `DISPENSER_ROLE` holder; per-IP rules in Vercel Firewall; E10-T5). Arithmetic the spec does not state: the default faucet funding is `FAUCET_ETH_FUND_WEI = 0.004 ETH` and `ethPerClaim = 0.0002 ETH`, so the faucet pays **20 claims**, not the `dailyCap` of 200. Twenty fresh addresses empty it, after which every judge gets `FaucetEmpty`. A full deposit-and-redeem flow costs roughly 3.7M gas, about 0.00004 ETH at 0.01 gwei, so 0.0002 ETH is five times what a judge needs.
- **Mitigation**. Dispenser-only calls, once per address, daily cap, EOA recipients, `FaucetEmpty` clean revert, plus off-chain limits. **Not mitigated**: the funding-to-claims mismatch and the absence of a human check (F-04).
- **Likelihood** H (low skill, no cost). **Impact** Med for the demo, none otherwise. **Status** R (F-04).
- **Residual**. Any public faucet is farmable; keep the budget small and the per-claim drip near the real need.
- **Checklist**: X-04, `FengFaucet` rows in the checklist.

### T-12 Faucet dispenser key, cron secret, API route abuse

- **Scenario**. Key F leaks, `CRON_SECRET` leaks, or `/api/faucet` and `/api/ops/tick` accept attacker-controlled input. F can call `claimFor` for any 200 addresses per day until the faucet ETH is gone and mint 10,000 mock USDG each. The tick route signs with the relayer key: if it accepted a price or address parameter it would become a signing oracle.
- **Mitigation**. `DISPENSER_ROLE` is revocable, bounded by `min(dailyCap, ETH balance / ethPerClaim)`; bearer check on the tick route (401 without it, E2 acceptance); keys only in env, never printed; routes take no price input (prices come only from the API fetch inside the relayer).
- **Likelihood** M. **Impact** Low. **Status** P.
- **Checklist**: G-12, X-11, X-16.

### T-13 Keeper griefing and DoS (failing child, spam vaults, forced rebalances)

- **Scenario A, child blocks parent**. A depth-2 parent buys the child with `child.deposit`; if the child is paused (guardian), stale, or its desk leg fails, the parent's `deposit` and `executeRebalance` revert (all-or-nothing, R-11, R-13). The parent's exits are unaffected (`child.redeem` is never paused; `redeemInKind` returns child shares). The griefing vector is not a third party but any condition at the child; a child stale feed also blocks the parent (C-09, intended).
- **Scenario B, keeper drain by spam**. Creation is permissionless, each creation costs about 0.00003 to 0.00005 ETH (R-06), and every created vault is registered. Many vaults, each with a dust deposit so `timeBased` is true (S > 0, 1 hour interval), make `checkUpkeep` list them; a keeper that rebalances everything spends gas on junk and `checkUpkeep()` stops at `MAX_SCAN = 200`, hiding legitimate vaults that sit beyond index 200 unless the keeper pages with `checkUpkeepRange`.
- **Scenario C, forced timing**. `executeRebalance` is permissionless, so an attacker chooses when a due rebalance executes (right after a price excursion), and can force threshold rebalances by donating (T-02 C). Each forced trade costs holders the spread.
- **Scenario D, checkpoint grief**. Dust deposits reset `lastCheckpointTimestamp` so `checkpoint()` reverts `CheckpointTooSoon`; harmless because every deposit emits `NavCheckpoint`.
- **Mitigation**. Per-vault `try/catch` and paging in the engine (C-19), `performRebalance` registry gate, keeper simulates before sending, balance floor and alert, exits independent of the keeper.
- **Gap**. No on-chain minimum TVL or creation fee; the keeper needs an off-chain allowlist or minimum-NAV filter (F-08).
- **Likelihood** M. **Impact** Low (Med). **Status** P/A.
- **Checklist**: C-19, C-26, C-34, C-35, X-10.

### T-14 Depth and cycles

- **Scenario**. Nest a strategy inside itself or build depth 3 to compound gas and NAV recursion (the Stream Finance pattern, `03-domain.md` recommendations 1 and 2).
- **Mitigation**. `MAX_DEPTH = 2`, child must be created by the same factory (`vaultOf[token] != 0`), the child must have no strategy-token constituents (`NestedTokenNotLeaf`), duplicates rejected. A cycle is impossible by construction: the strategy token exists only after the vault constructor runs and `vaultOf` is written after deploy, so a vault cannot name its own token or a later vault; vaults are immutable.
- **Likelihood** L. **Impact** Info. **Status** M. **Checklist**: C-07, I7.

### T-15 Registry spam, impersonation and metadata abuse

- **Scenario**. Thousands of junk strategies; names such as "Feng Official" or homoglyph and right-to-left characters in the 1 to 48 byte name and 2 to 10 byte symbol (no charset rule); 160-byte description with markup. Creator-only `updateMeta` lets a creator change a description after users rely on it.
- **Mitigation**. Paged reads, tag charset `[a-z0-9-]`, length limits, frontend escapes everything, shows creator and vault address, marks seeded strategies.
- **Likelihood** H. **Impact** Low. **Status** A (R-06). **Residual**: cosmetic, plus the keeper cost in T-13.
- **Checklist**: C-20, C-35, X-17.

### T-16 Unsafe approvals

- **Scenario**. Infinite approvals left to vaults, desk, children; the vault approving the venue or a child for more than one call; users approving the vault on the share token (T-17).
- **Mitigation**. `forceApprove(spender, exactAmount)` before and `forceApprove(spender, 0)` after every external pull (invariant `invariant_noOpenApprovals`); the desk holds no approvals; deposits pull only from `msg.sender`; no function takes a `from` parameter for token pulls (X-05); UI approves the exact amount.
- **Likelihood** M. **Impact** Med (High). **Status** M. **Residual**: a UI that requests `type(uint256).max` USDG approval is safe against the vault but not against future contracts; keep exact approvals.
- **Checklist**: C-23, X-05, G-08.

### T-17 Delegated-redeem hole of V1 (C-02)

- **Scenario**. V1 `redeem(shares, receiver, owner)` with `msg.sender != owner` does `safeTransferFrom(owner, vault, shares)` which spends the owner's allowance to the vault, and never checks `msg.sender`. After a single `approve(vault, x)` by the owner, any address redeems up to `x` shares to any receiver. Proved: 1,000 USDG taken from Alice (`docs/security/poc/V1Exploits.t.sol`, `test_poc_delegatedRedeemHole`).
- **V2**. `StrategyTokenV2.burnFrom(owner, spender, amount)` is vault-only and spends `allowance(owner, spender)` where the vault passes `msg.sender` as spender, so the vault's own allowance is irrelevant.
- **Likelihood** M (needs an approval that no current UI asks for). **Impact** High (Crit). **Status** M in V2; **open in V1**.
- **Checklist**: C-02, `test_redeem_vaultApprovalDoesNotAuthorizeCaller`, M-02.

### T-18 Oracle and token decimals mismatch

- **Scenario**. Feed decimals other than 8; token decimals other than 18; USDG decimals 6 or 18; the V1 18-decimal assumption (C-03); `10 ** k` overflow; truncation when feed decimals exceed 18; `uiMultiplier` misuse.
- **Mitigation**. All conversions through `valueOf`/`tokensForValue` with cached `dec_i` and `d`; every decimals read is checked `<= 18`; oracle returns 18-decimal prices and `priceDecimals()` is constant 18; `mulDiv` 512-bit; `k = dec + 18 - d <= 36` fits; `vA`, `vS` chosen per `d`; decimals matrix (6/18, 6/8, 18/18, 18/8); `FengAggregator` uses 8 decimals everywhere; relayer scales `tokenBid/tokenAsk` to 8 decimals with integer math.
- **Gaps (low)**. `ChainlinkPriceOracleV2.setFeed` accepts any address and `getPrice` does not guard `decimals() > 18` truncation to zero, `updatedAt == 0` or `updatedAt > block.timestamp` (which makes `block.timestamp - updatedAt` panic in a consumer): F-13. FengAggregator cannot back-date, so only a future non-Feng feed triggers it.
- **Likelihood** L. **Impact** High (Crit) if hit. **Status** M. **Checklist**: C-03, C-25, C-08, X-08, X-12, I9.

### T-19 ERC-20 return-value and behaviour quirks

- **Scenario**. Tokens without a return value, returning `false`, fee-on-transfer, rebasing, reverting on `approve(spender, 0)`, `decimals()` reverting or not 8-bit, approve race.
- **Mitigation**. `SafeERC20` for every call including the desk and faucet; `forceApprove`; balance deltas measured for every pull, swap output and child redeem; no cached balances (rebasing and `uiMultiplier` effects flow into NAV); hostile mocks `NoReturnToken`, `ReturnFalseToken`, `FeeOnTransferToken`, `RebasingToken`, `BlockableUSDG`.
- **Likelihood** L. **Impact** Med. **Status** M. **Residual**: the desk in inventory mode pays a measured amount only for the pulled side; a fee-on-transfer token on the receiving side of `redeemInKind` simply delivers less (out of scope, spec 1.7).
- **Checklist**: C-29, G-07, I10.

### T-20 Guardian abuse and pause semantics

- **Scenario**. A malicious or compromised guardian pauses deposits and rebalances forever, or front-runs a user by pausing. It cannot pause exits, move funds or change parameters. Pause has no expiry. Paused vault: `rebalanceNeeded()` returns `(false, false)` so the keeper idles and weights drift.
- **Likelihood** L. **Impact** Low. **Status** A (R-05). **Checklist**: C-12, C-26, `invariant_paused_redeemStillWorks`.

### T-21 Admin key concentration and compromise

- **Scenario**. The deployer key is `DEFAULT_ADMIN_ROLE` on `MockUSDGV2`, every `MockStockToken` and `FengAggregator`, owner of `ChainlinkPriceOracleV2` and `OracleDesk`, admin of the registry and the faucet, and the default guardian. Compromise or a mistake lets it: mint unlimited USDG, grant `MINTER_ROLE` on a stock token to itself and burn any holder balance including a vault's (`MockStockToken.burn(from, amount)` burns anyone's balance for a `MINTER_ROLE` holder), set any price (`forceAnswer`), repoint feeds, withdraw the reserve. V1 shares this property.
- **Mitigation**. Keys in env only; relayer, keeper and dispenser are separate keys; `FACTORY_ROLE` held by the factory only; vaults hold no mint roles in V2.
- **Likelihood** M (laptop and cloud env). **Impact** High on testnet (total), Crit real. **Status** A, R (F-09: separate guardian, drop deployer roles that are no longer needed after seeding, document).
- **Checklist**: X-03 (post-deploy role matrix), X-15, C-06.

### T-22 Rounding, dust and `NoValueAdded` griefing

- **Scenario**. Dust left by floor operations; `na <= nb` reverting small deposits when prices move inside the transaction; share price drift up to about `vS/S * (p - 1)/p` on a deposit at price above 1 (R-18).
- **Mitigation**. Rounding direction fixed against the actor (C-30), dust accrues to remaining holders, `MIN_LEG_USDG` skips dust legs that stay idle and count in NAV, I3 tolerance `1 unit + 1e-6`.
- **Likelihood** M. **Impact** Low. **Status** M. **Checklist**: C-30, I1, I3.

### T-23 Nested NAV: previews, child donation, revert coupling

- **Scenario**. `previewDeposit` for a nested vault cannot be exact (C-36); donating to a child changes the parent NAV (only profitable if the donor owns about all of both); parent NAV marks children at pre-spread `previewRedeem` while a USDG exit pays spread.
- **Mitigation**. Documented tolerance, `minShares`, parent never caches child NAV, `redeemInKind` returns child shares, depth 2 only.
- **Likelihood** M. **Impact** Low. **Status** M/A. **Checklist**: C-36, I1, X-09.

### T-24 L2 specifics

- **Scenario**. `block.number` on Nitro returns an L1-derived number; timestamps are sequencer-set and monotonic; no public mempool (no sandwich on oracle fills anyway); sequencer downtime freezes pushes; gas near 0.01 gwei makes spam almost free; `PUSH0` support unverified so evm is `paris`.
- **Mitigation**. `block.timestamp` only, never `block.number` (registry stores `createdAt`); evm `paris`; staleness window absorbs short sequencer outages; exits oracle-free.
- **Likelihood** L. **Impact** Low. **Status** M. **Checklist**: G-03, C-20.

### T-25 Returndata bomb and gas griefing in try/catch

- **Scenario**. `ChildRedeemFailed(childToken, bytes reason)` copies the child's revert data into memory with `catch (bytes memory reason)`. A hostile token inside the child could revert with a very large payload to burn the parent's gas. The tokens are curated, so this is theoretical.
- **Mitigation requested**. Cap the copied reason (for example an assembly-free `try ... catch Error(string)`/selector-only wrapper) or accept the risk explicitly: F-06. `RebalanceEngineV2` loops with `try/catch` over up to 200 vaults, each external call bounded by the vault's own code.
- **Likelihood** L. **Impact** Low. **Status** R. **Checklist**: X-07.

### T-26 Frontend, deployment artifacts, decoy tokens, secret hygiene

- **Scenario**. A wrong or tampered `addresses.json`; the decoy "USDG" tokens documented in 07 section 2.1 (`0x915Ef7c9...`, `0x8F9231B0...`); ABI drift between `out/` and `src/lib/abi/generated`; keys in logs, argv, shell history, repo or CI; `forge script` leaks; `--private-key` in `ps`; `set -x` in shell scripts. In V1 the scripts pass `--private-key "$KEY"` to `cast send` (argv exposure on a shared host).
- **Mitigation**. `script/DeployV2.s.sol` reads `vm.envUint("DEPLOYER_PRIVATE_KEY")`; addresses file holds public addresses only; Live deploy asserts `decimals() == 6` and `uiMultiplier() == 1e18`; `sync-abi.sh --check` in CI; `.env*` never read by agents.
- **Likelihood** M. **Impact** Med. **Status** P. **Checklist**: G-10, G-11, G-12, X-11, X-13, X-14, X-16.

### T-27 USDG depeg and `uiMultiplier` change

- **Scenario**. USDG trades below 1 USD; a stock split or dividend reinvestment changes `uiMultiplier`.
- **Mitigation**. USDG = 1 USD is an explicit assumption (S3, C-22); relayer holds pushes during pending corporate actions and uses `tokenBid/tokenAsk` (multiplier-adjusted); Live deploy asserts `uiMultiplier == 1e18`; balances are never cached.
- **Likelihood** L. **Impact** Med (High). **Status** A (R-08, R-09).

### T-28 Share token mishandling

- **Scenario**. Share tokens are plain ERC-20; shares sent to the vault or the token contract are stuck; infinite share approvals to a third-party contract are the user's choice. Minting shares to an arbitrary `receiver` (an airdrop of dust) is harmless.
- **Likelihood** M. **Impact** Low (user loss only). **Status** A.

### T-29 Rebalance churn bleeds holders

- **Scenario**. Short intervals (BLTZ 1 hour) and tight thresholds make every cycle pay up to 20 bps on the shifted notional; a creator can design a bleeding strategy. Not theft, an economic property that the UI should surface.
- **Mitigation**. `MIN_REBALANCE_INTERVAL` 1 hour, leg tolerance, effective threshold, skip trades inside tolerance. **Status** A.

### T-30 Mint-mode desk role and mode misconfiguration

- **Scenario**. The desk holds `MINTER_ROLE` on mock Stock tokens: its `mint` and `burn(address(this), ...)` calls are the only ways tokens appear or vanish; `setToken(token, Mint)` for a token where the desk lacks the role, or `Inventory` mode on a mock, or switching modes with inventory present, strands liquidity. The Live universe must use `Inventory` for every real token.
- **Mitigation**. Role grants and `setToken` calls in `DeployV2.s.sol` and `DeployLive.s.sol`, role matrix verified after deploy (X-03).
- **Likelihood** L. **Impact** Med. **Status** P. **Checklist**: X-03, X-14.

## 6. V1: what is exploitable today (proofs of concept)

All three ran on a scratch copy of the V1 sources on a local EVM (`forge test -vv`, 3 passed). They are not run against the chain.

| ID | Defect | Result | Preconditions |
|---|---|---|---|
| V1-P1 | Redeem pays `usdg.balanceOf(vault) * shares / supply` (`StrategyVault.sol:116`) while shares are minted at stock-only NAV (`:278-280`, `:258-263`) | Alice deposits 100 at 250, price doubles, Bob deposits 100: previews 200 and 100, payouts 133.33 and 66.67 | none |
| V1-P2 | `MockV3Aggregator.updateAnswer` is ungated (`MockV3Aggregator.sol:29-31`), so anyone sets any price; NAV-priced minting plus pot redemption lets the setter capture the pot | Vault holds 20,000 USDG of other people's deposits; attacker sets TSLA to 1 (8 decimals), deposits 1 USDG, restores 250, redeems: takes out 20,000.98 USDG | the vault's constituents' feeds must all be settable (they are, on the deployed mocks) and the call must pass `_checkAllFresh` (it does, `updateAnswer` refreshes `updatedAt`) |
| V1-P3 | `redeem` with `msg.sender != owner` spends the owner's allowance to the vault and never checks the caller (`StrategyVault.sol:118-123`) | Alice approves the vault on her share token; an unrelated address redeems her 1,000 USDG position to itself | owner approved the vault |

Why V1-P2 also hurts V2 planning: any V2 deployment that keeps the V1 mock feeds, or keeps a V1 vault live next to V2 in the same UI, inherits it. The deployed V1 feeds are open (R2 section 3) and so are the deployed vaults (same source, checksums in `docs/handoffs/v1-sources.sha256`). I did not touch the chain; confirm the live state with a read-only `cast call` before quoting live numbers.

## 7. Findings against the frozen spec (requests for the coordinator)

These are changes or decisions, not code defects. Severity is for testnet; "R" in brackets is the real-value severity.

| ID | Sev | Finding | Recommendation |
|---|---|---|---|
| F-01 | Med (Crit) | `FengAggregator.updateAnswer` bounds each update against the anchor and then moves the anchor, with no minimum interval and no cumulative bound: a stolen `UPDATER_ROLE` key reaches any price in one block (`1.15^n`). The spec headline "bounded by deviation cap" is per update only. | Add `MIN_UPDATE_INTERVAL` (for example 60 seconds, `refresh()` exempt) or a rolling window bound on the anchor; update the demo script to use `shockAnswer` for the +18 percent shock (already the spec design), and ops to step legitimate gaps across minutes. Add a test `test_aggregator_walkWithinOneBlockRejected`. Seen in the in-progress `FengAggregator.sol`: `updateAnswer` has no time check. |
| F-02 | Med (Crit) | `OracleDesk` has no exposure cap: one transaction can trade the whole reserve at a manipulated or stale price. | Add a per-swap and per-hour net USDG outflow cap (for example 10 percent of reserve per hour), emitted when hit, owner-adjustable with an event. If not adopted, document the reserve as the maximum loss. |
| F-03 | Low-Med | `ENABLE_SHOCK=1` grants `SHOCK_ROLE` to the relayer key, so a leak gives a plus or minus 30 percent lever and the shock stays "fresh" through `refresh()`. | Production deploy with `ENABLE_SHOCK=0` and `shockEnabled=false`; for the recording, a separate `SHOCK_ADDRESS` key and `setShockEnabled(true)` only for the window, then revoke. |
| F-04 | Med | Faucet funding supports 20 claims (0.004 ETH at 0.0002 ETH per claim), not 200; no human check on the server. | Set `ethPerClaim` to about 0.0001 ETH (more than two full flows) and fund 0.01 ETH for 100 claims, align `dailyCap` with funding, add the per-IP rule and a challenge (Turnstile or similar) at the route, keep the dispenser key separate. |
| F-05 | Med | `maxPriceStaleness` is 12 h in the spec (C-33) and 6 h in R2. A dead relayer leaves a 12-hour informed-trader window (T-08). | Decide once; prefer 6 h as R2 recommends, with the 35 minute alarm. Also reconcile `maxDeviationBps`: spec 1500 and shock 3000, R2 1000 and stepped pushes. |
| F-06 | Low | `ChildRedeemFailed(bytes reason)` copies unbounded returndata. | Cap the copied length or drop the payload; see T-25. |
| F-07 | Low | `VaultDeployerV2.deploy` is permissionless, enabling lookalike unregistered vaults. | Optional: one-time `initialize(factory)` and `onlyFactory` on `deploy`; otherwise document and make the UI registry-only (already planned). |
| F-08 | Low | Registry spam can drain the keeper and push real vaults past `MAX_SCAN`. | Ops-level allowlist and minimum-NAV filter; page with `checkUpkeepRange`; per-tick cap on rebalances. |
| F-09 | Med | Single deployer key holds every admin role and is the default guardian. | `GUARDIAN_ADDRESS` set to a distinct key; after seeding, renounce or transfer roles no longer needed (for example `MINTER_ROLE` on USDG from the deployer once the faucet holds it, `DEFAULT_ADMIN_ROLE` handover plan); state it in the README. |
| F-10 | Low | `OracleDesk` owner can change spread and withdraw reserve instantly. | Document as trusted; optionally require two-step changes. |
| F-11 | Low | `refresh()` can keep any displayed price fresh, including a shock. | Document; `lastChangeAt()` for the UI; alert on shock active. |
| F-12 | Info | Spec section 2.4 and R2 disagree on function names (`updateAnswer` versus `pushAnswer`, `setMaxDeviationBps` versus `setParams`) and defaults. | Update the spec table when F-05 is resolved; the ABI sync script and relayer must use the final names. |
| F-13 | Low | `ChainlinkPriceOracleV2.getPrice` (in-progress file) does not check `updatedAt` bounds, feed decimals above 18, or that `setFeed` points at a contract. | Reject `updatedAt == 0 || updatedAt > block.timestamp`, require `feed.code.length > 0` and `decimals() <= 18` in `setFeed`, or make the vault robust to a future `updatedAt` without a panic. |

## 8. Residual risk register (what remains true after the spec is implemented as written)

1. A stolen relayer key moves prices (bounded per update only) until revoked (T-06).
2. The desk reserve, owner and mint-mode simulation are trusted; informed flow bleeds the reserve (T-08, T-09, R-03).
3. Frozen or paused real tokens cannot be recovered and cost holders the forfeited slice (T-04).
4. Stale and weekend windows equal `maxPriceStaleness` (T-05); the mainnet path is not ready (single staleness value, no sequencer check).
5. A single key controls the whole testnet deployment (T-21).
6. Faucet and registry are farmable; ops must filter (T-11, T-13, T-15).
7. Depth-2 vaults depend on child availability for deposit and rebalance (T-13).
8. No third-party audit; this threat model, the independent tests and the review stand in for it. Slither and a stateful fuzzer beyond Foundry are not installed in this environment (requests: install Slither, Aderyn and Echidna or Medusa in a scratch environment for the second pass; the coordinator decides).

## 9. Assumptions and open questions

- A1. The deployed V1 feeds and vaults are the ones described in `docs/handoffs/BASELINE-2026-10-03.md` and R2 (open `updateAnswer`). Not re-verified on chain by this review.
- A2. The in-progress V2 files may change before the review; findings F-01 and F-13 refer to the state at the time of writing.
- A3. Real Paxos USDG and real Stock tokens are assumed to be plain ERC-20 without hooks or fees; whether they accept transfers from contract addresses is R1 open point O-3.
- A4. R2 values (5-minute tick, 10 bps threshold, 30-minute heartbeat) are assumed deployed; the spec is silent on cadence.
- Q1. Does the coordinator adopt F-01, F-02 and F-04 before G1, or document them in the README as accepted? Either is defensible on testnet; silence is not.
