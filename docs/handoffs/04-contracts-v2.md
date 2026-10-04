# 04. Contracts V2: frozen implementation spec (E3-T0)

- **Status**: FROZEN on 2026-10-03 by the E3-T0 architect/reviewer. Three agents work from this file without asking questions: `GP/contracts` (author), `GP/tests` (independent test author), `GP/review` (independent reviewer). The frontend lane (`work:frontend`), the ops lane (`GP/ops`) and the deploy lane (`GP/deploy`) build against section 5 and section 6.
- **Change control**: any deviation needs a written "Request" to the coordinator; do not diverge silently. Section 7 lists the only parts allowed to move (items tagged `to align with R2` or `to align with R3`).
- **Inputs read**: `docs/brainstorm/2026-10-03-feng-v2-plan.md` (sections 0, 1, 4 D1-D8 and D11, 5.1, E3, E4, E8, 8.1, 8.2, 8.5), all of `contracts/**` (V1), `contracts/test/**`, `script/Deploy.s.sol`, `script/SeedStrategies.s.sol`, `docs/handoffs/contracts.md`, `docs/research/03-domain.md` recommendations 1-5, `docs/research/07-testnet-reality-check.md` sections 2.1-2.3. `docs/research/09-price-source-and-feed.md` did NOT exist when this was written, so the FengAggregator mechanism is proposed here and marked `to align with R2`.
- **Verification done while writing**: the share-math formulas and the inflation-attack parameters were checked with a throwaway Python model of the exact integer formulas below (results quoted in 1.2 and 1.8). No Solidity was compiled, no chain call was made, no key was touched.
- **Conventions (binding)**: Solidity 0.8.24, `evm_version = "paris"` (no `PUSH0`, no transient storage, so `ReentrancyGuardTransient` is forbidden; use `ReentrancyGuard` from OZ 5.7.0 which already provides `nonReentrantView`), OpenZeppelin v5 imported from `@openzeppelin/contracts/`, custom errors only (no revert strings), no code comments in code, library-first (OZ `Pausable`, `ReentrancyGuard`, `AccessControl`, `Ownable`, `SafeERC20`, `Math`), never use `block.number` (Arbitrum Nitro semantics return an L1-derived number; use `block.timestamp` only), no hardcoded addresses in `.sol`.

---

## 0. Decisions at a glance

| # | Decision | Section |
|---|---|---|
| S1 | V2 lives side by side in `contracts/v2/`; every V1 file stays byte-identical until Gate G1 (V1 verification on Blockscout depends on the unchanged source and on `foundry.toml` solc, evm, optimizer 200). | 3 |
| S2 | Share token has 18 decimals. USDG decimals `d` are read from the token (`d <= 18`). Mint pricing uses virtual assets `vA = 1` and virtual shares `vS = 10 ** max(18 - d, 12)`. Inception price is exactly 1.00 USDG per share for `d <= 6` (real Paxos USDG is 6). | 1.2 |
| S3 | NAV `totalAssetsUSDG()` = idle USDG balance + oracle value of every constituent balance (strategy-token constituents valued by the child's `previewRedeem`). USDG is assumed to be 1.00 USD; the vault never reads a USDG feed. | 1.2 |
| S4 | `deposit` mints on the **measured value delta** (`navAfter(floor) - navBefore(ceil)`), so venue spread is paid by the depositor. | 1.2 |
| S5 | `redeem`/`redeemInKind` pay physical pro-rata of every balance by `shares / totalSupply` (no virtual terms on the redeem side). USDG redeem sells each slice through the venue; in-kind redeem needs no oracle and no venue. | 1.2, 1.3 |
| S6 | Nested USDG redeem unwinds the child through `child.redeem` and reverts with `ChildRedeemFailed` if the child cannot. `redeemInKind` returns child shares. | 1.3 |
| S7 | Rebalance: sells first, USDG is the pivot, targets come from `targetWeightBps` over total NAV including idle USDG, 10 bps leg tolerance, effective threshold `max(maxWeightBps, target + 10 bps)`. | 1.4 |
| S8 | `NavCheckpoint(uint256 indexed timestamp, uint256 totalAssets, uint256 totalSupply)` on deposit, depositInKind, redeem, executeRebalance and a public `checkpoint()` limited to once per 30 minutes per vault. `redeemInKind` emits none (no oracle). | 1.5 |
| S9 | Guardian (immutable, per factory) can pause only `deposit`, `depositInKind`, `executeRebalance`. `redeem`, `redeemInKind`, `checkpoint` are never paused. | 1.6 |
| S10 | A new `StrategyTokenV2` adds `burnFrom(owner, spender, amount)` that spends the spender's allowance; V1's "owner approves the vault" delegated redeem is a hole and is not carried over. | 1.1 C-02 |
| S11 | `OracleDesk` only trades with registered vaults (registry gate), mint mode and inventory mode, 10 bps each side, USDG reserve of 10,000,000 mock USDG. | 2.3 |
| S12 | `VaultDeployerV2` (stateless) creates vaults so the factory bytecode stays under EIP-170. | 3.4 |
| S13 | The management fee (E3-T8) is NOT part of V2: no storage, no parameter, no event. | 7.3 |

---

## 1. Review of the section 8.1 sketch against the current code

### 1.1 Conflicts, holes and ambiguities (each with a decision)

Severity: **H** = would lose or misprice user funds or block exit; **M** = breaks a plan requirement or a lane contract; **L** = hygiene or ambiguity.

| ID | Finding (V1 evidence) | Sev | Decision |
|---|---|---|---|
| C-01 | V1 `redeem` pays `usdgToken.balanceOf(vault) * shares / supply` (`StrategyVault.sol:116`) while `previewRedeem` is NAV based, and `_totalAssetsUSDG` omits idle USDG. Payout and preview disagree after any price move. | H | NAV includes idle USDG; redeem pays physical pro-rata of everything; `previewRedeem` equals the pro-rata NAV (1.2). |
| C-02 | V1 delegated redeem: `msg.sender != owner` does `safeTransferFrom(owner, vault, shares)` using the owner's allowance **to the vault** (`StrategyVault.sol:121`). `msg.sender` is never checked, so if an owner ever approves the vault, any caller can redeem the owner's shares to any receiver. | H | `StrategyTokenV2.burnFrom(owner, spender, amount)` (vault-only) spends `allowance(owner, msg.sender-of-vault)` then burns. V1 `StrategyToken` is unchanged and not reused by V2. |
| C-03 | V1 deposit math assumes 18-decimal USDG: `(slice * 1e18) / price` (`StrategyVault.sol:96`); real USDG is 6. | H | All conversions go through `valueOf` / `tokensForValue` with `d` and per-constituent decimals (1.2). |
| C-04 | Sketch says "virtual-share inflation protection retained" and "inception price 1.00". V1 offset 3 gives inception price 0.001 and the 18 vs 6 decimal cases need different offsets. A Python model of the exact formulas shows `vA = 1`, `vS = 1` (d = 18) is exploitable (attacker deposits a few wei, donates idle USDG, the victim's shares round down; example from the model: attacker 528 wei, donation 591,054 USDG, victim deposit 6,021 USDG, victim loses about 110 USDG and the attacker nets about 97 USDG). | H | `vA = 1`, `vS = 10 ** max(18 - d, 12)`. Re-run in the model: for `d` in {6, 12, 18}, donation up to 1e9 USDG, 300k trials each, attacker profit never positive and victim loss never above the 0.2 percent round trip spread. For `d = 18` the inception price becomes 1e-12 USDG per share (the frontend must use `inceptionSharePrice()`, not a literal 1.00). |
| C-05 | V1 raw USDG donation test (`InflationAttack.t.sol` `test_rawUsdgDonation_doesNotAffectNav`) asserts NAV is unchanged by a donation. V2 NAV includes idle USDG, so donations raise NAV. | M | That test is superseded; the V2 property is "donation never profits the donor and never hurts a later depositor beyond rounding" (I11). |
| C-06 | V1 factory calls `IAccessControl(token).grantRole(MINTER_ROLE, vault)` on every non-strategy constituent (`StrategyFactory.sol:93`); this reverts for real tokens. | H | V2 factory never calls constituent contracts except `decimals()`/`isSupported` reads. The `OracleDesk` (not the vault) holds `MINTER_ROLE` in mint mode. |
| C-07 | V1 factory accepts any address as a constituent (no oracle, no venue check), no cap on constituent count, no minimum weight, no interval floor, no name/symbol limits. | M | V2 factory: 1 to 6 constituents, `oracle.isSupported && venue.isSupported` per non-strategy token, weight at least 100 bps, interval 1 hour to 365 days, `maxSlippageBps` 1 to 500, name 1 to 48 bytes, symbol 2 to 10 bytes. |
| C-08 | Sketch `IPriceOracle` has no `isSupported` and no price decimals. | M | `IPriceOracleV2 is IPriceOracle` adds `isSupported(address)` and `priceDecimals()` (always 18). V1 `ChainlinkPriceOracle` is not edited (frozen); `ChainlinkPriceOracleV2` is a new contract. |
| C-09 | V1 `_checkAllFresh` skips strategy-token constituents (`StrategyVault.sol:229`). A parent could therefore price a child NAV from a stale child feed in `redeem`/in-kind valuation. | H | Vault exposes `priceStatus()`; `_checkAllFresh` recurses into children through it and reverts `StalePrice(childToken, oldestUpdatedAt)`. |
| C-10 | Sketch `redeem(..., minUsdgOut)` plus `previewRedeem` documented as "oracle NAV before spread": the actual payout is lower by the sell spread, so a UI that sets `minUsdgOut` from `previewRedeem` needs a tolerance. | M | Add `quoteRedeem(shares)` (venue-aware estimate, recursive into children). `previewRedeem` stays "pro-rata NAV before spread". The frontend uses `quoteRedeem` for `minUsdgOut`. |
| C-11 | Sketch `redeemInKind` returns `(tokens, amounts)`; not stated whether idle USDG is included, and one blocked token (Stock tokens are `onlyNotBlocked`/`onlyNotPaused`, 07 section 2.1) would revert the whole call and trap the exit. | H | Arrays include idle USDG as the last element. `redeemInKind` is atomic. `redeemInKindExcluding(..., skipMask)` lets the redeemer forfeit chosen slices (bit `i` = constituent `i`, bit `n` = idle USDG) so a frozen asset cannot trap the rest. Cut-line item 2. |
| C-12 | Sketch `error Paused()`. Library-first rule says use OZ `Pausable`, which defines `EnforcedPause()`/`ExpectedPause()` and `Paused(address)`/`Unpaused(address)` events. | L | Use OZ `Pausable`; guardian-gated `pause()`/`unpause()` wrappers; no custom `Paused` error. Frontend decodes `EnforcedPause`. |
| C-13 | Sketch `NavCheckpoint(totalAssets, totalSupply)` carries no timestamp; `eth_getLogs` returns block numbers only, and per-block `eth_getBlockByNumber` for a sparkline is expensive. | M | `NavCheckpoint(uint256 indexed timestamp, uint256 totalAssets, uint256 totalSupply)`. |
| C-14 | Sketch `Rebalanced(timestamp, timeBased, thresholdBased, sharePrice)` changes the V1 topic. | L | Accepted: V2 ABI is a separate ABI; V1 and V2 are never mixed in one deployment. Per-leg `LegTraded` events are added for the explorer and the "rebalance moment" UI. |
| C-15 | Threshold rule dust loop: V1 seeds have `maxWeightBps == targetWeightBps` for STRM, EVMO, EQ5, CHIP, BLTZ, CLCM. With a venue spread, a just-rebalanced overweight leg ends 0.01 to 0.2 percent above target, so `weightBps > maxWeightBps` can fire again immediately and loop (cost: spread on every cycle). | H | `weightBps > effectiveMax(i)` where `effectiveMax(i) = min(10000, max(maxWeightBps, targetWeightBps_i + 10))`. Identical to the plan rule whenever the band `max - target` is at least 10 bps; leg tolerance and convergence argument in 1.4. |
| C-16 | V1 `rebalanceNeeded` returns `timeBased = true` for an empty vault, so the keeper would trade and emit events for nothing. | L | `timeBased` requires `totalSupply() > 0`. `rebalanceNeeded()` returns `(false, false)` while paused. |
| C-17 | V1 buys a child strategy token with whatever idle USDG is available (`_rebalanceConstituent`) before sells have run, order-dependent. | M | Strict two-pass rebalance: all sells, then proportional buys from the USDG budget (1.4). |
| C-18 | V1 nested redeem returned child shares (`test_depth2_redeem_returnsInnerStrategyTokenUnits`). Sketch says USDG `redeem` must unwind via `child.redeem` and revert if the child cannot. | M | Decision S6. The V1 test is superseded and replaced by two V2 tests (USDG unwinds the child; in-kind returns child shares). |
| C-19 | V1 `RebalanceEngine.checkUpkeep` is unbounded and one reverting vault (for example an oracle `InvalidPrice`) reverts the whole view, blinding the keeper; `performRebalance` accepts any address. | M | V2 engine: per-vault `try/catch` in `checkUpkeep`, paged `checkUpkeepRange(offset, limit)`, `checkUpkeep()` scans at most 200, `performRebalance` requires a registered vault (`NotRegisteredVault`). |
| C-20 | V1 registry has no metadata, no `isRegistered`, no pagination; `registerStrategy` has a fixed 3-argument signature. | M | `MarketplaceRegistryV2` is a new contract (V1 deployed registry stays). No block number is stored (Arbitrum). Frontend finds creation through `StrategyRegistered` logs. |
| C-21 | `MockV3Aggregator.updateAnswer` is open and `updateRoundData` can back-date. | M | `FengAggregator` (2.4): role-gated, deviation-bounded, no back-dating. V1 mock untouched. |
| C-22 | The oracle feed set contains a USDG feed but V1 vault never reads it (USDG = 1.00 assumed). Ambiguity for a depeg. | L | Keep the assumption (S3); the USDG feed stays deployed for continuity and ops display only. A USDG depeg is out of scope (7.2 R-09). |
| C-23 | V1 `forceApprove` to child vaults is never reset. | M | Every approval is set to exactly the amount for one call and reset to 0 right after, also for venue pulls. |
| C-24 | Contract size and stack depth: V2 vault is about 2x V1; the factory embeds the vault creation code, so factory runtime would be about vault size plus 5 KB and may exceed 24,576 bytes (EIP-170). `via_ir` is false and must stay false (V1 verification). | H | `VaultDeployerV2` (S12) holds the vault creation code; factory stays small. Size gate in 3.5. Struct param `VaultParams` for the constructor (stack depth). |
| C-25 | `StrategyVault` constructor never validates `usdg`/constituent decimals, and V1 never reads decimals. | M | Constructor reads `decimals()` of USDG (must be at most 18) and of each constituent (at most 18) and caches them packed with the constituent (3.1). |
| C-26 | Pausing semantics unspecified for nested and for the engine. | M | See 1.6 table. A child paused for deposit blocks the parent's buy legs (parent rebalance and deposit revert); child redeem is never paused so exits work. Accepted (R-13). |
| C-27 | `depositInKind` shifts composition and the later rebalance spread is paid by all holders (externality). | M | In-kind deposit reverts `ExceedsMaxWeight(token)` if it would leave that token above `effectiveMax`; residual externality is bounded by `amount * 2 * spreadBps` and documented (R-14). |
| C-28 | Donation of a constituent token to the vault can push a weight above threshold to force a rebalance. | L | Not preventable; attacker loses the donated value to force a cost of about 0.2 percent of the shifted notional. Documented (R-14). |
| C-29 | V1 `deposit` computes `shares` before pulling tokens and trusts nominal amounts. Fee-on-transfer USDG would over-mint. | H | Measured deltas for every pull and every swap output (1.7). |
| C-30 | NAV rounding direction: V1 floors both sides of the share formula. A floored `navBefore` over-mints to the depositor by up to `n` units. | M | `navBefore` rounds UP, `navAfter` rounds DOWN, `valueAdded = navAfter - navBefore`, shares floor (1.2). |
| C-31 | `getConstituents()` shape and `Constituent` struct must stay identical for the existing frontend hooks. | L | Reuse V1 `Constituent` from `contracts/interfaces/IStrategyVault.sol` unchanged. |
| C-32 | Public permissionless desk would be arbitraged against a lagging oracle (reserve bleed) and could be used to manipulate vault sellers. | M | Desk swaps are gated to registered vaults (`registry.isRegistered(msg.sender)`); quotes stay public. |
| C-33 | The sketch leaves `maxPriceStaleness` implicit; V1 uses 24 h. Plan pre-mortem says "12 h hard floor" for feed age with a 30 minute push cadence. | L | Factory immutable `maxPriceStaleness = 12 hours` in the V2 deployment (`to align with R2`, config value in `addresses.json`). |
| C-34 | Sketch does not say who may call `executeRebalance` and `checkpoint`. | L | Both permissionless; conditions are enforced inside the vault. |
| C-35 | Registry spam: factory creation is permissionless and the registry is unbounded. | L | Paged reads; frontend may filter; not prevented (R-06). |
| C-36 | `previewDeposit` cannot be exact for nested vaults because the child NAV moves during the child deposit. | L | Documented tolerance: actual shares never exceed the preview by more than rounding; preview exceeds actual by at most `(n + 2) * ceil((S + vS) / (A + vA))` for depth 1, and by at most 0.01 percent for depth 2 with child TVL of at least 1 USDG. `minShares` absorbs it. |

### 1.2 Share math (exact)

Notation. `d` = USDG decimals (`usdgDecimals`, at most 18), `U = 10 ** d`. `S = token.totalSupply()` (18 decimals). `bal_i` = `IERC20(token_i).balanceOf(vault)`, `dec_i` = constituent decimals (at most 18), `p_i` = `oracle.getPrice(token_i)` (USD per 1 whole token scaled by 1e18, validated positive by the oracle). `idle` = `usdg.balanceOf(vault)`. `BPS = 10_000`. `mulDiv` is OZ `Math.mulDiv(a, b, c, rounding)`.

Constants (immutable per vault, derived in the constructor):

```
VIRTUAL_ASSETS = 1
VIRTUAL_SHARES = 10 ** max(18 - d, 12)
```

Leg valuation (USDG units):

```
valueOf(i, amount, Floor) = mulDiv(amount, p_i, 10 ** (dec_i + 18 - d), Floor)          non-strategy constituent
valueOf(i, amount, Ceil)  = mulDiv(amount, p_i, 10 ** (dec_i + 18 - d), Ceil)
valueOf(i, amount, Floor) = child.previewRedeem(amount)                                   strategy token constituent
valueOf(i, amount, Ceil)  = child.previewRedeem(amount) + (amount > 0 ? 1 : 0)
tokensForValue(i, v)      = mulDiv(v, 10 ** (dec_i + 18 - d), p_i, Floor)                 non-strategy only
```

NAV:

```
totalAssets(r) = idle + sum_i valueOf(i, bal_i, r)          r in {Floor, Ceil}
totalAssetsUSDG() = totalAssets(Floor)
```

Share formulas (all `mulDiv`, rounding stated):

| Function | Formula | Rounding |
|---|---|---|
| `previewDeposit(a)` | `valueAdded = (a - sum slice_i over executed legs) + sum valueOf(i, quoteOut_i, Floor)` where `slice_i = floor(a * w_i / BPS)`; a leg is executed only if `slice_i >= MIN_LEG_USDG`; `quoteOut_i = venue.quoteExactIn(usdg, token_i, slice_i)`; for a child leg `valueOf = child.previewRedeem(child.previewDeposit(slice_i))`. `shares = mulDiv(valueAdded, S + VIRTUAL_SHARES, totalAssets(Ceil) + VIRTUAL_ASSETS, Floor)` | floor, against depositor |
| `deposit(a, receiver, minShares)` | `nb = totalAssets(Ceil)` BEFORE pulling funds. `received = balanceDelta(usdg)` of the pull. Run the legs (below). `na = totalAssets(Floor)`. `valueAdded = na - nb` (revert `NoValueAdded` if `na <= nb`). `shares = mulDiv(valueAdded, S + VIRTUAL_SHARES, nb + VIRTUAL_ASSETS, Floor)` (revert `ZeroShares` if 0; revert `SlippageExceeded(shares, minShares)` if below). | `nb` up, `na` down, shares floor |
| `previewDepositInKind(token, amount)` | `valueAdded = valueOf(i, amount, Floor)`; `shares` as above with `totalAssets(Ceil)` | floor |
| `depositInKind(token, amount, receiver, minShares)` | `nb = totalAssets(Ceil)` before the pull; `got = balanceDelta(token)`; `valueAdded = valueOf(i, got, Floor)`; same share formula; weight guard `valueOf(i, bal_i_after, Floor) * BPS / totalAssets(Floor) <= effectiveMax(i)` | as above |
| `previewRedeem(shares)` | `S == 0 ? 0 : mulDiv(shares, totalAssets(Floor), S, Floor)` | floor, against redeemer |
| `redeem(shares, receiver, owner, minUsdgOut)` | `S0 = S` captured before the burn; `part_i = floor(bal_i * shares / S0)`; `idlePart = floor(idle * shares / S0)` (idle read before any sale); each `part_i` sold through the venue (or `child.redeem`); `usdgOut = idlePart + sum measuredUsdgDelta_i`; revert `ZeroAssets` if 0; revert `SlippageExceeded(usdgOut, minUsdgOut)` if below | floor |
| `quoteRedeem(shares)` | `idlePart + sum venue.quoteExactIn(token_i, usdg, part_i)` (child: `child.quoteRedeem(part_i)`) | floor |
| `redeemInKind(shares, receiver, owner)` | transfers `part_i` of every constituent and `idlePart` of USDG; no oracle, no venue, no external call except the token transfers | floor |
| `sharePrice()` (USDG units per 1e18 shares) | `S == 0 ? inceptionSharePrice() : mulDiv(totalAssets(Floor), 1e18, S, Floor)` | floor |
| `inceptionSharePrice()` | `mulDiv(1e18, VIRTUAL_ASSETS, VIRTUAL_SHARES, Floor)` = `1e6` units for every `d <= 6` and `d = 18` | floor |
| `weights()[i]` | `totalAssets(Floor) == 0 ? 0 : floor(valueOf(i, bal_i, Floor) * BPS / totalAssets(Floor))`; idle weight is `BPS - sum` | floor |

Why virtual terms only on the mint side: redeem uses physical pro-rata by `S`, so the sum of all holders' previews equals NAV (I1) and the last holder drains the vault with no stranded dust. The virtual terms only matter while `S` is comparable to `VIRTUAL_SHARES` (about 1e-6 shares for `d = 6`), where they stop a donation from rounding a later depositor to zero shares.

Consequences that tests must encode: a deposit at share price above 1.00 dilutes the price by at most about `(VIRTUAL_SHARES / S) * (p - 1) / p` (below 1e-6 relative for a pool of at least 1 share) so I3 allows `1 unit + 1e-6 relative` for `S >= 1e18`; and a deposit then immediate full redeem at constant prices returns at least `input * (1 - 2 * spreadBps / 10000) - (2n + 3)` units.

### 1.3 Nested deposit and redeem paths (depth 2)

A depth-2 vault P holds depth-1 child strategy tokens (constituents flagged `isStrategyToken`). The factory guarantees (kept from V1): the child was created by the same factory (`vaultOf[token] != 0`), the child's depth is 1, and the child has no strategy-token constituents. P and the child share the same USDG, oracle and venue.

| Operation | Path for a strategy-token constituent |
|---|---|
| `deposit` | `slice_i = floor(received * w_i / BPS)`. P computes `minShares = child.previewDeposit(slice_i) * (BPS - maxSlippageBps) / BPS`, approves the child vault for exactly `slice_i`, calls `child.deposit(slice_i, address(P), minShares)`, resets the approval to 0. The child mints its own shares on its own measured value delta (it pays its own venue spread). P's `valueAdded` then counts `child.previewRedeem(childBalance)` after the call. |
| `depositInKind(childToken, amount, ...)` | The depositor sends child shares directly; `valueAdded = child.previewRedeem(got)`. No child call other than the view. Requires `priceStatus()` fresh recursively. |
| `redeem` (USDG) | `childShares_i = floor(childBal * shares / S0)`. P calls `child.redeem(childShares_i, address(P), address(P), minOut)` with `minOut = child.quoteRedeem(childShares_i) * (BPS - maxSlippageBps) / BPS` (P is both caller and owner, so no allowance is needed). USDG received is measured as a balance delta. If the child call reverts for any reason (stale feed, desk cannot buy, reserve empty, child pause cannot happen because redeem is never paused) P reverts with `ChildRedeemFailed(childToken, reason)`. The user's safe exit is `redeemInKind`. This keeps `docs/research/03-domain.md` recommendation 4: no promise of instant USDG against an asset that may not unwind. |
| `redeemInKind` | Returns `childShares_i` of the child token itself, with no call into the child. |
| `executeRebalance` sell | `sharesToRedeem = floor(childBal * sellValue / currentValue)` (at most `childBal`), `child.redeem(..., minOut)` as above. |
| `executeRebalance` buy | `child.deposit(spend, address(P), minShares)` as above. |
| NAV | `child.previewRedeem(childBal)`, live, never cached (recommendation 3). |
| Freshness | `_checkAllFresh` calls `child.priceStatus()` and reverts `StalePrice(childToken, oldestUpdatedAt)` if the child is not fresh. |

Reverting semantics: a leg failure inside `deposit` or `executeRebalance` reverts the whole call (all or nothing); there is no per-leg `try/catch` except the one in the redeem child leg that rewraps the revert as `ChildRedeemFailed`.

### 1.4 Rebalance ordering, targets, idle USDG, tolerance, threshold

Definitions:

```
T            = totalAssets(Floor)                      includes idle USDG
target_i     = floor(T * targetWeightBps_i / BPS)
cur_i        = valueOf(i, bal_i, Floor)
tol          = max(floor(T * LEG_TOLERANCE_BPS / BPS), MIN_LEG_USDG)
LEG_TOLERANCE_BPS = 10
MIN_LEG_USDG = max(U / 100, 1)                         0.01 USDG
```

`rebalanceNeeded()` (view, `nonReentrantView`):

```
if paused: return (false, false)
timeBased      = S > 0 && block.timestamp >= lastRebalanceTimestamp + rebalanceInterval
thresholdBased = T > 0 && exists i: floor(cur_i * BPS / T) > effectiveMax(i)
effectiveMax(i) = min(BPS, max(maxWeightBps, targetWeightBps_i + THRESHOLD_BAND_BPS))     THRESHOLD_BAND_BPS = 10
```

The threshold rule `weightBps > maxWeightBps` is preserved verbatim for every vault whose band (`maxWeightBps - target_i`) is at least 10 bps; for tighter bands (the max == target seeds) the effective threshold is `target + 10 bps`. Weights are measured against total NAV including idle USDG (same denominator as `weights()`).

`executeRebalance()` (`nonReentrant`, `whenNotPaused`):

1. Compute `(timeBased, thresholdBased)`; revert `RebalanceNotNeeded` if both false.
2. `_checkAllFresh()`.
3. Compute `T`, `cur_i`, `target_i`, `tol`.
4. **Pass 1, sells.** For every `i` with `cur_i > target_i + tol`: `excess = cur_i - target_i`.
   - Non-strategy token: `amount = min(bal_i, tokensForValue(i, excess))`; skip if 0; approve venue for exactly `amount`; `minOut = valueOf(i, amount, Floor) * (BPS - maxSlippageBps) / BPS`; `venue.swapExactIn(token_i, usdg, amount, minOut, address(this))`; reset approval to 0; measure the USDG delta; revert `SlippageExceeded(delta, minOut)` if below; emit `LegTraded(token_i, false, delta, amount)`.
   - Strategy token: `sharesToRedeem = floor(bal_i * excess / cur_i)`; `child.redeem(sharesToRedeem, this, this, minOut)`; emit `LegTraded`.
5. **Pass 2, buys.** `budget = usdg.balanceOf(this)` (idle plus sale proceeds; this is how idle USDG gets deployed). For every `i` with `cur_i + tol < target_i`: `deficit_i = target_i - cur_i`. `totalDeficit = sum deficit_i`. If `budget >= totalDeficit`, `spend_i = deficit_i`; otherwise `spend_i = floor(deficit_i * budget / totalDeficit)`. Execute each buy with `minOut = tokensForValue(i, spend_i) * (BPS - maxSlippageBps) / BPS` (child: `minShares = child.previewDeposit(spend_i) * (BPS - maxSlippageBps) / BPS`), approvals exact and reset, deltas measured, `LegTraded(token_i, true, spend_i, delta)`.
6. `lastRebalanceTimestamp = block.timestamp` (even if no leg executed), `lastCheckpointTimestamp = block.timestamp`.
7. Emit `NavCheckpoint(timestamp, totalAssets(Floor), S)` then `Rebalanced(timestamp, timeBased, thresholdBased, sharePrice())`.

Properties: (a) USDG is the only pivot (the venue pair is always token <-> USDG); (b) sells strictly precede buys; (c) legs inside tolerance are skipped, so a vault that is within 10 bps of target trades nothing; (d) convergence: after a rebalance an overweight leg sits at target within rounding, and its weight can exceed target only by `target_w * lossFraction` where the loss is the spread paid on the shifted notional, so a repeat trade is at most about `target_w * spread` (below 1 percent) of the previous one and stops inside tolerance; (e) idle USDG above tolerance is deployed on the next rebalance, not on a deposit (deposit already deploys its own slices).

Time-based and threshold flags are independent; both can be true. A time-based call with no leg to trade still advances `lastRebalanceTimestamp` and emits `Rebalanced` (the UI treats it as "checked, no trade").

### 1.5 Event emission points and the checkpoint rate limit

| Event | Emitted by | When |
|---|---|---|
| `Deposit(sender, receiver, usdgAmount, shares)` | `deposit` | after shares minted; `usdgAmount` is the measured received amount |
| `DepositInKind(sender, receiver, token, amount, valueUsdg, shares)` | `depositInKind` | after shares minted; `amount` measured |
| `Redeem(sender, receiver, owner, shares, usdgAmount)` | `redeem` | after the USDG transfer |
| `RedeemInKind(sender, receiver, owner, shares)` | `redeemInKind`, `redeemInKindExcluding` | after the transfers |
| `LegTraded(token, buy, usdgAmount, tokenAmount)` | `deposit`, `redeem`, `executeRebalance` | once per executed venue or child leg |
| `NavCheckpoint(timestamp, totalAssets, totalSupply)` | `deposit`, `depositInKind`, `redeem`, `executeRebalance`, `checkpoint` | after state changes, using the post-state NAV (floor) |
| `Rebalanced(timestamp, timeBased, thresholdBased, sharePrice)` | `executeRebalance` | last event of the call |

`checkpoint()` (vault, permissionless, `nonReentrant`): reverts `CheckpointTooSoon(nextAllowedAt)` if `block.timestamp < lastCheckpointTimestamp + CHECKPOINT_MIN_INTERVAL` where `CHECKPOINT_MIN_INTERVAL = 30 minutes`; runs `_checkAllFresh()`; computes NAV; emits `NavCheckpoint`; sets `lastCheckpointTimestamp`. Every other emission point also sets `lastCheckpointTimestamp`, so a busy vault never needs the hourly call. `RebalanceEngineV2.checkpoint(address[])` calls each vault inside `try/catch` and skips the ones that revert (too soon, stale, not registered); it never reverts for a bad entry. `redeemInKind` emits no `NavCheckpoint` because computing NAV needs the oracle and I5 requires it to work with dead feeds; share price is unchanged by a pro-rata exit, so the history has no gap that matters.

### 1.6 Guardian semantics, approvals, reentrancy

| Function | Paused | Notes |
|---|---|---|
| `deposit`, `depositInKind`, `executeRebalance` | revert `EnforcedPause` | `pause()` and `unpause()` callable only by the immutable `guardian` (`NotGuardian`) |
| `redeem`, `redeemInKind`, `redeemInKindExcluding` | **never paused** | the guardian cannot block an exit |
| `checkpoint`, all views | not paused | `rebalanceNeeded()` returns `(false, false)` while paused so the keeper stays quiet |

The guardian cannot move funds, change parameters or upgrade anything. Pause has no expiry (testnet; see R-05). The guardian is the deployer address unless `GUARDIAN_ADDRESS` is set.

Approvals: before every external pull by the venue or a child vault the vault calls `forceApprove(spender, exactAmount)` and after the call `forceApprove(spender, 0)`. No infinite approvals, none left open across transactions. `forceApprove` (OZ `SafeERC20`) is used so tokens that require a zero-first approval still work.

Reentrancy: `deposit`, `depositInKind`, `redeem`, `redeemInKind`, `redeemInKindExcluding`, `executeRebalance`, `checkpoint` are `nonReentrant`; every view that reads vault balances or NAV is `nonReentrantView` (so a hostile token hook that calls back into a view mid-execution reverts). State effects before interactions: shares are burned before any token leaves the vault in `redeem`; in `deposit`, shares are minted after the legs because the share count depends on the measured delta, and the guard (not ordering) protects that window. The child vault has its own guard, which is entered and left inside the parent's call, so the parent to child call is safe.

### 1.7 Fee-on-transfer, rebasing, blocked transfers

- **Measure, never trust.** Every USDG pull, every token pulled in `depositInKind`, every swap output and every child redeem output is measured as `balanceOf(after) - balanceOf(before)`. Returned `amountOut` values are ignored for accounting (only compared in a sanity check). Fee-on-transfer USDG or tokens therefore mint fewer shares and never over-mint.
- **No cached balances.** Constituent balances are read live in every call, so a rebasing token (or a corporate-action change of balance) is reflected in NAV, never double counted by a deposit (deposit uses deltas) and never stored.
- **Desk is robust too:** `OracleDesk.swapExactIn` prices on the measured received amount of `tokenIn`.
- **Blocked or paused real token or USDG** (07 section 2.1: Stock `transfer`, `transferFrom`, `approve` are `onlyNotPaused` and `onlyNotBlocked`; Paxos USDG has a blocklist and pause): any transfer involving a blocked address reverts. Resulting behaviour: `deposit` and `redeem` revert (cannot move the token); `redeemInKind` reverts atomically; `redeemInKindExcluding` lets the user exit with every other asset and forfeit the frozen slice to the remaining holders; nothing is lost silently. **Out of scope:** recovering a frozen asset, a blocklisted vault address at the token issuer, USDG depegs, `uiMultiplier` changes after a corporate action (the Live deploy asserts `uiMultiplier() == 1e18` in the script, not in the contract), tokens whose `transfer` has side effects other than reentrant hooks and fees, fee-on-transfer tokens on the `redeemInKind` receiving side (the receiver simply receives less), and ERC-777 tokens as production constituents (the factory only admits tokens that both the oracle and the venue support, a curated set; hostile tokens appear only in tests).

### 1.8 Worked example with numbers

Setup: USDG `d = 6` (U = 1e6), vault `V` = TSLA 50 percent and AMZN 50 percent, both 18-decimal tokens, TSLA at 400 USD and AMZN at 250 USD, desk spread 10 bps each side (buy at `price * 1.001` rounded up, sell at `price * 0.999` rounded down), no idle remainder. `VIRTUAL_SHARES = 1e12`, `VIRTUAL_ASSETS = 1`. Unit scale for tokens: `10 ** (18 + 18 - 6) = 1e30`.

1. Alice deposits 1,000 USDG (1,000,000,000 units) into the empty vault, `minShares = 0`.
   - `nb = totalAssets(Ceil) = 0`. Slices: 500,000,000 each.
   - TSLA buy: price 400.4e18, `out = floor(500e6 * 1e30 / 400.4e18) = 1,248,751,248,751,248,751` wei (1.248751 TSLA). AMZN buy: price 250.25e18, out 1,998,001,998,001,998,001 wei (1.998002 AMZN).
   - `na = floor(1.248751... * 400) + floor(1.998001... * 250)` = 499,500,499 + 499,500,499 = **999,000,998** units (floor of the two legs, 999.000998 USDG). `valueAdded = 999,000,998`.
   - `shares = floor(999,000,998 * (0 + 1e12) / (0 + 1)) = 999,000,998,000,000,000,000` wei = **999.000998 shares**.
   - `sharePrice() = floor(999,000,998 * 1e18 / 999,000,998e12) = 1,000,000` = **1.000000 USDG**. Alice paid 1,000.000000 and holds 999.000998 USDG of value: she bore the 0.0999 percent spread, existing holders (none) bore nothing.
2. TSLA moves to 440. `totalAssetsUSDG() = 1,048,951,048` (1,048.951048 USDG), `sharePrice() = 1,050,000` (1.05).
3. Bob deposits 500 USDG. `nb = totalAssets(Ceil) = 1,048,951,050` (ceil adds 2 units over the floor value). After the two buys: `na = 1,548,451,548`; `valueAdded = 499,500,498`; `shares = floor(499,500,498 * (999,000,998e12 + 1e12) / (1,048,951,050 + 1)) = 475,714,759,070,294,789,189` wei = **475.714759 shares**. Share price stays 1.05.
4. Alice redeems all her shares in USDG at TSLA 440. `S = 1,474.715757` shares; her fraction is `999,000,998e12 / S`. `previewRedeem = 1,048,951,049`. Sell prices: TSLA 439.56, AMZN 249.75. Payout `usdgOut = 1,047,902,098` units = **1,047.902098 USDG**. A UI that applies 1 percent slippage to `quoteRedeem` sets `minUsdgOut` about 1,037.4 USDG and passes. Alice's round trip: paid 1,000, received 1,047.90 (price effect +4.8 percent after paying the full spread both ways).
5. Same trade at `d = 18` (U = 1e18, `VIRTUAL_SHARES = 1e12`): `valueAdded = 999,000,999,000,999,000,650` units, shares `= valueAdded * 1e12 = 999,000,999,000,999,000,650,000,000,000,000` wei, `sharePrice() = 1,000,000` units = 1e-12 USDG per 1e18 shares (that is the `inceptionSharePrice()`), Bob's shares `475,714,761,429,047,142,891,859,410,430,839`, Alice's payout `1,047,902,097,902,097,901,179` units. The USDG value of Alice's position is identical to the 6-decimal case within 1e-6.

Test authors: these integers are the exact vectors for `test_vector_roundTrip_d6` and `test_vector_roundTrip_d18` (assert shares, payout and `sharePrice()` exactly; tolerances are only for the previews). A depth-2 vector is derived from this one in the tests with a child holding TSLA/AMZN 50/50.

---

## 2. Final Solidity interfaces (declarations only)

All files below are new, under `contracts/v2/`. `Constituent` is imported from the unchanged V1 file `contracts/interfaces/IStrategyVault.sol`. Declarations only; bodies and NatSpec are the author's job, comments are forbidden in code.

### 2.1 IVenue (`contracts/v2/interfaces/IVenue.sol`)

```solidity
pragma solidity ^0.8.24;

interface IVenue {
    event Swapped(
        address indexed vault,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    error ZeroAmount();
    error ZeroAddress();
    error NotVault(address caller);
    error UnsupportedPair(address tokenIn, address tokenOut);
    error InsufficientLiquidity(address token);
    error VenueSlippage(uint256 got, uint256 min);
    error StalePrice(address token, uint256 updatedAt);

    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        returns (uint256 amountOut);

    function quoteExactIn(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut);

    function isSupported(address token) external view returns (bool);

    function usdg() external view returns (address);
}
```

Rules: exactly one of `tokenIn`/`tokenOut` is `usdg()` and the other satisfies `isSupported` (else `UnsupportedPair`); `isSupported(usdg())` is false; `swapExactIn` pulls `tokenIn` from `msg.sender` with `transferFrom` (the caller approved exactly `amountIn`), sends `tokenOut` to `recipient`, reverts `VenueSlippage(got, min)` if `got < minAmountOut`. `R3` may add a v4 adapter that satisfies the same interface (`to align with R3`: only the gating behaviour of `NotVault` is desk specific).

### 2.2 IPriceOracleV2 and ChainlinkPriceOracleV2 (`contracts/v2/interfaces/IPriceOracleV2.sol`, `contracts/v2/oracle/ChainlinkPriceOracleV2.sol`)

```solidity
pragma solidity ^0.8.24;

import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";

interface IPriceOracleV2 is IPriceOracle {
    function isSupported(address token) external view returns (bool);

    function priceDecimals() external view returns (uint8);
}
```

`ChainlinkPriceOracleV2 is IPriceOracleV2, Ownable` (OZ). Same adapter behaviour as V1 `getPrice` (answer must be positive else `InvalidPrice(token)`, scale to 18 decimals, `FeedNotSet(token)` if unset) plus:

```solidity
interface IChainlinkPriceOracleV2Admin {
    event FeedSet(address indexed token, address indexed feed);
    event FeedRemoved(address indexed token);

    error FeedNotSet(address token);
    error InvalidPrice(address token);
    error ZeroAddress();

    function feeds(address token) external view returns (address);
    function setFeed(address token, address feed) external;
    function removeFeed(address token) external;
}
```

`isSupported(token) = feeds[token] != address(0)`. `priceDecimals()` returns the constant 18. Owner is the deployer (testnet).

### 2.3 OracleDesk (`contracts/v2/venue/OracleDesk.sol`)

```solidity
pragma solidity ^0.8.24;

import {IVenue} from "../interfaces/IVenue.sol";

interface IOracleDesk is IVenue {
    enum Mode {
        Unsupported,
        Mint,
        Inventory
    }

    event TokenConfigured(address indexed token, Mode mode, uint8 decimals);
    event SpreadSet(uint16 spreadBps);
    event ReserveFunded(address indexed from, uint256 amount);
    event ReserveWithdrawn(address indexed to, uint256 amount);
    event InventoryFunded(address indexed token, address indexed from, uint256 amount);
    event InventoryWithdrawn(address indexed token, address indexed to, uint256 amount);

    error SpreadTooHigh(uint16 spreadBps);
    error NotConfigured(address token);
    error DecimalsTooHigh(address token, uint8 decimals);

    function owner() external view returns (address);
    function oracle() external view returns (address);
    function registry() external view returns (address);
    function maxPriceStaleness() external view returns (uint256);
    function spreadBps() external view returns (uint16);
    function mode(address token) external view returns (Mode);
    function tokenDecimals(address token) external view returns (uint8);
    function reserveUsdg() external view returns (uint256);
    function tokenInventory(address token) external view returns (uint256);
    function accounting()
        external
        view
        returns (uint256 fundedUsdg, uint256 withdrawnUsdg, uint256 buyUsdgIn, uint256 sellUsdgOut);

    function setToken(address token, Mode mode_) external;
    function setSpreadBps(uint16 spreadBps_) external;
    function fundReserve(uint256 amount) external;
    function withdrawReserve(address to, uint256 amount) external;
    function fundInventory(address token, uint256 amount) external;
    function withdrawInventory(address token, address to, uint256 amount) external;
}
```

Constructor: `OracleDesk(address owner_, address usdg_, address oracle_, address registry_, uint16 spreadBps_, uint256 maxPriceStaleness_)`. `Ownable` (OZ). `MAX_SPREAD_BPS = 100`. Behaviour:

- **Gate**: `swapExactIn` requires `IMarketplaceRegistryV2(registry).isRegistered(msg.sender)` else `NotVault(msg.sender)`. `quoteExactIn` is public.
- **Prices** (token decimals `dec`, USDG decimals `d`, oracle price `p`, `k = dec + 18 - d`): `priceBuy = ceil(p * (10000 + spreadBps) / 10000)`, `priceSell = floor(p * (10000 - spreadBps) / 10000)`. Buy (`usdg -> token`): `out = floor(amountIn * 10**k / priceBuy)`. Sell (`token -> usdg`): `out = floor(amountIn * priceSell / 10**k)`. Rounding always favours the desk. Zero output reverts `ZeroAmount`.
- **Staleness**: reverts `StalePrice(token, updatedAt)` if `block.timestamp - updatedAt > maxPriceStaleness` (set equal to the vault value).
- **Mint mode** (mock stock): the desk holds `MINTER_ROLE` on the token. Buy: pull USDG, `IMintableStockToken(token).mint(recipient, out)`. Sell: `transferFrom(vault -> desk)` then `IMintableStockToken(token).burn(address(this), amount)`; pay USDG from reserve; revert `InsufficientLiquidity(usdg)` if `usdg.balanceOf(desk) < out`.
- **Inventory mode** (any ERC-20, real tokens): buy transfers `out` from the desk's token balance (revert `InsufficientLiquidity(token)` if short); sell receives the token into the desk balance and pays USDG from reserve.
- **Accounting (I8)**: `fundedUsdg` (sum of `fundReserve`), `withdrawnUsdg`, `buyUsdgIn` (measured USDG received on buys), `sellUsdgOut` (USDG paid on sells). Identity: `usdg.balanceOf(desk) >= fundedUsdg + buyUsdgIn - sellUsdgOut - withdrawnUsdg`, with equality unless someone donates USDG directly. Inventory identity per token mirrors it with `fundInventory`/`withdrawInventory`.
- `setToken` caches `decimals()` (at most 18, else `DecimalsTooHigh`). `Unsupported` stops all swaps for the token (vault `redeem` then reverts, `redeemInKind` is unaffected).
- Safety: `nonReentrant` on `swapExactIn`; transfers via `SafeERC20`; no approvals held by the desk.

### 2.4 FengAggregator (`contracts/v2/oracle/FengAggregator.sol`) (`to align with R2`)

`docs/research/09-price-source-and-feed.md` did not exist at freeze time. The mechanism below is the proposal; R2 may change the numeric defaults (deviation, shock caps, cadence) but not the function set without a Request.

```solidity
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../../interfaces/AggregatorV3Interface.sol";

interface IFengAggregator is AggregatorV3Interface {
    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);
    event AnswerShocked(int256 indexed current, int256 indexed anchor, uint256 indexed roundId);
    event AnswerForced(int256 indexed current, uint256 indexed roundId, address indexed by);
    event ParamsSet(uint16 maxDeviationBps, uint16 maxShockBps);
    event ShockEnabledSet(bool enabled);

    error DeviationTooHigh(int256 answer, int256 anchor, uint16 maxDeviationBps);
    error ShockTooHigh(int256 answer, int256 anchor, uint16 maxShockBps);
    error ShockDisabled();
    error InvalidAnswer(int256 answer);
    error InvalidParams();

    function UPDATER_ROLE() external view returns (bytes32);
    function SHOCK_ROLE() external view returns (bytes32);
    function MAX_DEVIATION_CAP_BPS() external view returns (uint16);
    function MAX_SHOCK_CAP_BPS() external view returns (uint16);

    function anchorAnswer() external view returns (int256);
    function latestAnswer() external view returns (int256);
    function maxDeviationBps() external view returns (uint16);
    function maxShockBps() external view returns (uint16);
    function shockEnabled() external view returns (bool);

    function updateAnswer(int256 answer) external;
    function refresh() external;
    function shockAnswer(int256 answer) external;
    function forceAnswer(int256 answer) external;
    function setParams(uint16 maxDeviationBps_, uint16 maxShockBps_) external;
    function setShockEnabled(bool enabled) external;
}
```

`FengAggregator is IFengAggregator, AccessControl`. Constructor: `(address admin, uint8 decimals_, string description_, int256 initialAnswer, uint16 maxDeviationBps_, uint16 maxShockBps_)`; `admin` gets `DEFAULT_ADMIN_ROLE`; `initialAnswer` becomes both `latestAnswer` and `anchorAnswer`; `decimals_ = 8` for every deployed feed; `shockEnabled` starts false. Defaults for the deployment: `maxDeviationBps = 1500`, `maxShockBps = 3000`, caps `MAX_DEVIATION_CAP_BPS = 5000`, `MAX_SHOCK_CAP_BPS = 5000`.

- `updateAnswer(answer)` (`UPDATER_ROLE`): `answer > 0` else `InvalidAnswer`; `|answer - anchor| * 10000 <= anchor * maxDeviationBps` else `DeviationTooHigh`; new round, `updatedAt = block.timestamp`; `anchor = latest = answer`. Deviation is always measured against the **anchor** (the last non-shock answer), so a shock followed by a restore to market price passes.
- `refresh()` (`UPDATER_ROLE`): new round with the current `latestAnswer` and a fresh `updatedAt`; no deviation check, anchor unchanged. This is the `hold` mode heartbeat even while a shock is displayed.
- `shockAnswer(answer)` (`SHOCK_ROLE`, requires `shockEnabled`): `|answer - anchor| * 10000 <= anchor * maxShockBps` else `ShockTooHigh`; new round; `latest = answer`; anchor unchanged; emits `AnswerShocked`. This is what `scripts/demo-shock.sh` uses (for example TSLA +18 percent, then `updateAnswer(market)` to restore).
- `forceAnswer(answer)` (`DEFAULT_ADMIN_ROLE`): bypasses every bound, resets the anchor, emits `AnswerForced`. Use only to re-anchor after a long outage or at seed time.
- `latestRoundData()` returns `(roundId, latest, updatedAt, updatedAt, roundId)`; `decimals()` returns the constructor value; `description()` the constructor string; `version()` returns 1. There is no back-dating anywhere.

### 2.5 StrategyTokenV2 (`contracts/v2/StrategyTokenV2.sol`)

```solidity
pragma solidity ^0.8.24;

interface IStrategyTokenV2 {
    function vault() external view returns (address);
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function burnFrom(address owner, address spender, uint256 amount) external;
}
```

`StrategyTokenV2 is ERC20` (OZ), 18 decimals, immutable `vault`, every mutator `onlyVault` (`require(msg.sender == vault)` is replaced by `error NotVault()`), `burnFrom` calls `_spendAllowance(owner, spender, amount)` then `_burn(owner, amount)`.

### 2.6 StrategyVault V2 (`contracts/v2/interfaces/IStrategyVaultV2.sol`, `contracts/v2/StrategyVaultV2.sol`)

```solidity
pragma solidity ^0.8.24;

import {Constituent} from "../../interfaces/IStrategyVault.sol";

struct VaultParams {
    string name;
    string symbol;
    address usdg;
    address oracle;
    address venue;
    address guardian;
    Constituent[] constituents;
    uint16 maxWeightBps;
    uint16 maxSlippageBps;
    uint8 depth;
    uint256 rebalanceInterval;
    uint256 maxPriceStaleness;
}

interface IStrategyVaultV2 {
    event Deposit(address indexed sender, address indexed receiver, uint256 usdgAmount, uint256 shares);
    event DepositInKind(
        address indexed sender,
        address indexed receiver,
        address indexed token,
        uint256 amount,
        uint256 valueUsdg,
        uint256 shares
    );
    event Redeem(
        address indexed sender, address indexed receiver, address indexed owner, uint256 shares, uint256 usdgAmount
    );
    event RedeemInKind(address indexed sender, address indexed receiver, address indexed owner, uint256 shares);
    event LegTraded(address indexed token, bool buy, uint256 usdgAmount, uint256 tokenAmount);
    event Rebalanced(uint256 indexed timestamp, bool timeBased, bool thresholdBased, uint256 sharePrice);
    event NavCheckpoint(uint256 indexed timestamp, uint256 totalAssets, uint256 totalSupply);

    error ZeroAmount();
    error ZeroAddress();
    error ZeroShares();
    error ZeroAssets();
    error NoValueAdded();
    error EmptyConstituents();
    error TooManyConstituents();
    error WeightsMustSumTo10000();
    error UnsupportedDecimals(address token, uint8 decimals);
    error ConstituentIsUsdg();
    error InvalidMaxSlippage(uint16 maxSlippageBps);
    error StalePrice(address token, uint256 updatedAt);
    error SlippageExceeded(uint256 got, uint256 min);
    error InsufficientLiquidity(address token);
    error TokenNotConstituent(address token);
    error ExceedsMaxWeight(address token);
    error ChildRedeemFailed(address childToken, bytes reason);
    error RebalanceNotNeeded();
    error CheckpointTooSoon(uint256 nextAllowedAt);
    error NotGuardian();
    error InvalidSkipMask();

    function deposit(uint256 usdgAmount, address receiver, uint256 minShares) external returns (uint256 shares);

    function depositInKind(address token, uint256 amount, address receiver, uint256 minShares)
        external
        returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner, uint256 minUsdgOut)
        external
        returns (uint256 usdgOut);

    function redeemInKind(uint256 shares, address receiver, address owner)
        external
        returns (address[] memory tokens, uint256[] memory amounts);

    function redeemInKindExcluding(uint256 shares, address receiver, address owner, uint256 skipMask)
        external
        returns (address[] memory tokens, uint256[] memory amounts);

    function previewDeposit(uint256 usdgAmount) external view returns (uint256 shares);
    function previewDepositInKind(address token, uint256 amount) external view returns (uint256 shares);
    function previewRedeem(uint256 shares) external view returns (uint256 usdgOut);
    function quoteRedeem(uint256 shares) external view returns (uint256 usdgOut);
    function previewRedeemInKind(uint256 shares)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts);

    function totalAssetsUSDG() external view returns (uint256);
    function sharePrice() external view returns (uint256);
    function inceptionSharePrice() external view returns (uint256);
    function weights() external view returns (uint16[] memory currentBps);
    function effectiveMaxWeightBps(uint256 index) external view returns (uint16);
    function priceStatus() external view returns (bool fresh, uint256 oldestUpdatedAt);

    function getConstituents() external view returns (Constituent[] memory);
    function depth() external view returns (uint8);
    function rebalanceNeeded() external view returns (bool timeBased, bool thresholdBased);
    function executeRebalance() external;
    function checkpoint() external;

    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);

    function token() external view returns (address);
    function usdgToken() external view returns (address);
    function usdgDecimals() external view returns (uint8);
    function priceOracle() external view returns (address);
    function venue() external view returns (address);
    function guardian() external view returns (address);
    function maxWeightBps() external view returns (uint16);
    function maxSlippageBps() external view returns (uint16);
    function rebalanceInterval() external view returns (uint256);
    function maxPriceStaleness() external view returns (uint256);
    function lastRebalanceTimestamp() external view returns (uint256);
    function lastCheckpointTimestamp() external view returns (uint256);
}
```

The ABI types above are authoritative (for example `token()` returns `address`); the author may declare typed immutables (`StrategyTokenV2 public immutable token`) without inheriting the interface for those getters, as V1 does. `StrategyVaultV2 is ReentrancyGuard, Pausable` (and implements `IStrategyVaultV2`), constructor `(VaultParams memory p)`; it deploys `new StrategyTokenV2(p.name, p.symbol, address(this))`. Constants: `BPS = 10_000`, `MAX_CONSTITUENTS = 6`, `MAX_SLIPPAGE_BPS = 500`, `LEG_TOLERANCE_BPS = 10`, `THRESHOLD_BAND_BPS = 10`, `CHECKPOINT_MIN_INTERVAL = 30 minutes`. Roles: only `guardian` (immutable address, not an AccessControl role). Constructor validation: usdg decimals at most 18, `1 <= n <= 6`, weights sum 10,000, no constituent equals `usdg`, each constituent decimals at most 18 (`UnsupportedDecimals`), `maxSlippageBps` in 1..500, `guardian != 0`.

Semantics not obvious from the signatures:

- `redeemInKind` returns `tokens = [constituent_0 .. constituent_{n-1}, usdg]` and matching `amounts`; `previewRedeemInKind` returns the same shape without any oracle or venue call.
- `redeemInKindExcluding`: bit `i` of `skipMask` set means constituent `i` is not transferred (its slice stays in the vault); bit `n` skips idle USDG; any bit above `n` reverts `InvalidSkipMask`; the skipped amounts in the returned `amounts` are 0.
- `msg.sender != owner` in any redeem requires `allowance(owner, msg.sender) >= shares` on the share token (via `burnFrom`).
- `depositInKind(token, ...)` with `token == usdg` reverts `TokenNotConstituent` (use `deposit`).
- `priceStatus()` never reverts: it returns `(false, 0)` if any oracle call reverts, otherwise `fresh = all non-strategy constituents satisfy block.timestamp - updatedAt <= maxPriceStaleness and all children report fresh`, and `oldestUpdatedAt` the minimum observed.
- `getConstituents()` returns the V1 `Constituent` shape in creation order.

### 2.7 StrategyFactory V2 and VaultDeployerV2 (`contracts/v2/StrategyFactoryV2.sol`, `contracts/v2/VaultDeployerV2.sol`)

```solidity
pragma solidity ^0.8.24;

import {Constituent} from "../../interfaces/IStrategyVault.sol";
import {StrategyMeta} from "./IMarketplaceRegistryV2.sol";
import {VaultParams} from "./IStrategyVaultV2.sol";

interface IVaultDeployerV2 {
    function deploy(VaultParams calldata params) external returns (address vault, address token);
}

interface IStrategyFactoryV2 {
    event StrategyCreated(address indexed vault, address indexed token, address indexed creator, uint8 depth);

    error EmptyConstituents();
    error TooManyConstituents();
    error ZeroAddressConstituent();
    error DuplicateConstituent();
    error ConstituentIsUsdg();
    error UnsupportedConstituent(address token);
    error WeightsMustSumTo10000();
    error WeightTooSmall(address token);
    error MaxWeightExceeded();
    error InvalidMaxWeight();
    error InvalidInterval();
    error InvalidMaxSlippage();
    error InvalidName();
    error InvalidSymbol();
    error UnknownStrategyToken();
    error DepthExceeded();
    error NestedTokenNotLeaf();
    error UnsupportedUsdgDecimals(uint8 decimals);
    error VenueUsdgMismatch();

    function createStrategy(
        string calldata name,
        string calldata symbol,
        Constituent[] calldata constituents,
        uint16 maxWeightBps,
        uint256 rebalanceInterval,
        uint16 maxSlippageBps,
        StrategyMeta calldata meta
    ) external returns (address vault, address token);

    function vaultOf(address token) external view returns (address);
    function registry() external view returns (address);
    function priceOracle() external view returns (address);
    function venue() external view returns (address);
    function usdg() external view returns (address);
    function usdgDecimals() external view returns (uint8);
    function guardian() external view returns (address);
    function vaultDeployer() external view returns (address);
    function maxPriceStaleness() external view returns (uint256);
    function MAX_DEPTH() external view returns (uint8);
    function MAX_CONSTITUENTS() external view returns (uint8);
    function MIN_WEIGHT_BPS() external view returns (uint16);
    function MAX_SLIPPAGE_BPS() external view returns (uint16);
    function MIN_REBALANCE_INTERVAL() external view returns (uint256);
    function MAX_REBALANCE_INTERVAL() external view returns (uint256);
}
```

(The relative import for `StrategyMeta` is illustrative; the author resolves paths.) Constructor: `StrategyFactoryV2(address registry_, address priceOracle_, address venue_, address usdg_, address guardian_, address vaultDeployer_, uint256 maxPriceStaleness_)`: all non-zero; reads `decimals()` of `usdg_` (at most 18 else `UnsupportedUsdgDecimals`); requires `IVenue(venue_).usdg() == usdg_` (`VenueUsdgMismatch`). Constants: `MAX_DEPTH = 2`, `MAX_CONSTITUENTS = 6`, `MIN_WEIGHT_BPS = 100`, `MAX_SLIPPAGE_BPS = 500`, `MIN_REBALANCE_INTERVAL = 1 hours`, `MAX_REBALANCE_INTERVAL = 365 days`.

`createStrategy` order of checks and effects:

1. `n` in 1..6; name 1..48 bytes; symbol 2..10 bytes; `maxSlippageBps` 1..500; interval within bounds; `maxWeightBps` in 1..10,000.
2. For each constituent: non-zero, not `usdg`, no duplicate, `targetWeightBps >= 100`, `targetWeightBps <= maxWeightBps`; if not a strategy token require `IPriceOracleV2.isSupported(token) && IVenue.isSupported(token)` else `UnsupportedConstituent`; if a strategy token require `vaultOf[token] != 0`, child depth less than `MAX_DEPTH`, child has no strategy-token constituent (V1 rules unchanged: `UnknownStrategyToken`, `DepthExceeded`, `NestedTokenNotLeaf`).
3. Weights sum to 10,000; resulting `depth` is `1 + max child depth`.
4. `(vault, token) = vaultDeployer.deploy(VaultParams{...})` with `usdg`, `oracle`, `venue`, `guardian`, `maxPriceStaleness` from the factory immutables.
5. `vaultOf[token] = vault`; `registry.registerStrategy(vault, token, msg.sender, meta)` (validates and stores `meta`); `emit StrategyCreated`.
No `grantRole`, no call to any constituent besides view reads. The factory needs `FACTORY_ROLE` on the registry.

`VaultDeployerV2` is stateless and permissionless: `deploy` does `new StrategyVaultV2(params)` and returns the vault and its token. A vault created by anyone but the factory is never registered, cannot trade on the desk and cannot be used as a child, so it carries no trust.

### 2.8 MarketplaceRegistry V2 (`contracts/v2/interfaces/IMarketplaceRegistryV2.sol`, `contracts/v2/MarketplaceRegistryV2.sol`)

```solidity
pragma solidity ^0.8.24;

struct StrategyMeta {
    string description;
    string[] tags;
}

struct StrategyInfoV2 {
    address vault;
    address token;
    address creator;
    uint8 depth;
    uint256 createdAt;
    string description;
    string[] tags;
}

interface IMarketplaceRegistryV2 {
    event StrategyRegistered(address indexed vault, address indexed token, address indexed creator);
    event MetaUpdated(address indexed vault, string description, string[] tags);

    error AlreadyRegistered();
    error NotRegistered();
    error NotCreator();
    error DescriptionTooLong();
    error TooManyTags();
    error InvalidTag();
    error DuplicateTag();

    function registerStrategy(address vault, address token, address creator, StrategyMeta calldata meta) external;
    function updateMeta(address vault, StrategyMeta calldata meta) external;

    function getAllStrategies() external view returns (address[] memory vaults);
    function getStrategies(uint256 offset, uint256 limit) external view returns (address[] memory vaults);
    function strategyCount() external view returns (uint256);
    function isRegistered(address vault) external view returns (bool);
    function getStrategyInfo(address vault)
        external
        view
        returns (address token, address creator, uint8 depth, uint256 createdAt);
    function getStrategyInfoV2(address vault) external view returns (StrategyInfoV2 memory);
    function getStrategyMeta(address vault) external view returns (StrategyMeta memory);
}
```

`MarketplaceRegistryV2 is AccessControl, IMarketplaceRegistryV2`, `FACTORY_ROLE`, constructor `(address admin)`. `getStrategyInfo` keeps the V1 return shape so existing hooks keep working. `registerStrategy` (only `FACTORY_ROLE`) reads `IStrategyVaultV2(vault).depth()`, stores `createdAt = block.timestamp` and the meta, emits `StrategyRegistered` and `MetaUpdated`. `updateMeta` is callable only by the stored creator (`NotCreator`), same validation, emits `MetaUpdated`. Meta limits (constants `MAX_DESCRIPTION_BYTES = 160`, `MAX_TAGS = 3`, `MAX_TAG_BYTES = 16`): description at most 160 bytes (no charset rule, the frontend escapes), at most 3 tags, each 1..16 bytes of `[a-z0-9-]` only (`InvalidTag`), no duplicates (`DuplicateTag`). `getStrategies` returns an empty array when `offset >= count` and clamps `limit`.

### 2.9 RebalanceEngine V2 (`contracts/v2/RebalanceEngineV2.sol`)

```solidity
pragma solidity ^0.8.24;

interface IRebalanceEngineV2 {
    event RebalancePerformed(address indexed vault, address indexed keeper);
    event CheckpointsRecorded(address indexed caller, uint256 requested, uint256 recorded);

    error RebalanceNotNeeded(address vault);
    error NotRegisteredVault(address vault);

    function registry() external view returns (address);
    function MAX_SCAN() external view returns (uint256);

    function checkUpkeep() external view returns (address[] memory vaultsNeedingRebalance);
    function checkUpkeepRange(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory vaultsNeedingRebalance);
    function performRebalance(address vault) external;
    function checkpoint(address[] calldata vaults) external returns (uint256 recorded);
}
```

`MAX_SCAN = 200`. `checkUpkeep()` equals `checkUpkeepRange(0, MAX_SCAN)`. Both wrap each vault's `rebalanceNeeded()` in `try/catch` (a failing vault is simply skipped). `performRebalance(vault)` requires `registry.isRegistered(vault)` (`NotRegisteredVault`), re-checks `rebalanceNeeded()` (`RebalanceNotNeeded`), calls `executeRebalance()` and emits `RebalancePerformed(vault, msg.sender)`. `checkpoint(vaults)` skips unregistered entries and entries whose `checkpoint()` reverts, returns and emits the count recorded. Everything is permissionless.

### 2.10 MockUSDG V2 (`contracts/v2/mocks/MockUSDGV2.sol`)

```solidity
pragma solidity ^0.8.24;

interface IMockUSDGV2 {
    function MINTER_ROLE() external view returns (bytes32);
    function mint(address to, uint256 amount) external;
    function decimals() external view returns (uint8);
}
```

`MockUSDGV2 is ERC20, AccessControl`, constructor `(address admin, uint8 decimals_)`, name "Mock Global Dollar", symbol "USDG", `decimals()` returns the immutable `decimals_` (deploy passes 6; tests pass 6 and 18), `admin` gets `DEFAULT_ADMIN_ROLE` and `MINTER_ROLE`, `mint` is `onlyRole(MINTER_ROLE)`. This is a sandbox mock; the Live universe uses Paxos USDG.

### 2.11 FengFaucet (`contracts/v2/faucet/FengFaucet.sol`)

```solidity
pragma solidity ^0.8.24;

interface IFengFaucet {
    event Claimed(address indexed recipient, address indexed dispenser, uint256 ethAmount, uint256 usdgAmount);
    event ParamsSet(uint256 ethPerClaim, uint256 usdgPerClaim, uint256 dailyCap);
    event EthWithdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error AlreadyClaimed(address recipient);
    error DailyCapReached(uint256 dailyCap);
    error FaucetEmpty();
    error RecipientIsContract(address recipient);
    error TransferFailed();

    function DISPENSER_ROLE() external view returns (bytes32);
    function usdg() external view returns (address);
    function ethPerClaim() external view returns (uint256);
    function usdgPerClaim() external view returns (uint256);
    function dailyCap() external view returns (uint256);
    function hasClaimed(address recipient) external view returns (bool);
    function claimsToday() external view returns (uint256);
    function currentDay() external view returns (uint256);

    function claimFor(address recipient) external;
    function setParams(uint256 ethPerClaim_, uint256 usdgPerClaim_, uint256 dailyCap_) external;
    function withdrawEth(address payable to, uint256 amount) external;
    receive() external payable;
}
```

`FengFaucet is AccessControl, ReentrancyGuard`, constructor `(address admin, address usdg_, uint256 ethPerClaim_, uint256 usdgPerClaim_, uint256 dailyCap_)`. `claimFor` requires `DISPENSER_ROLE` (the server wallet `FAUCET_PRIVATE_KEY`; nobody else, so fresh-address sybils cannot call it directly), recipient non-zero and an EOA (`recipient.code.length == 0`, else `RecipientIsContract`), `!claimed[recipient]` (`AlreadyClaimed`), day counter `block.timestamp / 1 days` with `claimsToday < dailyCap` (`DailyCapReached`), `address(this).balance >= ethPerClaim` (`FaucetEmpty`). Effects (mark claimed, count) before interactions; then `MockUSDGV2(usdg).mint(recipient, usdgPerClaim)` and a `call{value: ethPerClaim}` (revert `TransferFailed` on failure). Defaults: `ethPerClaim = 0.0002 ether`, `usdgPerClaim = 10_000 * 10**d`, `dailyCap = 200`. `setParams` and `withdrawEth` require `DEFAULT_ADMIN_ROLE`. The faucet needs `MINTER_ROLE` on `MockUSDGV2`. It is sandbox only.

---

## 3. Storage, gas, file paths, build and test commands

### 3.1 Vault storage layout (`StrategyVaultV2`)

Immutables (no storage slots): `token`, `usdgToken`, `usdgDecimals`, `priceOracle`, `venue`, `guardian`, `maxWeightBps`, `maxSlippageBps`, `rebalanceInterval`, `strategyDepth`, `maxPriceStaleness`, `VIRTUAL_SHARES`, `USDG_UNIT`, `MIN_LEG_USDG`, `constituentCount`.

Storage:

| Slot | Content |
|---|---|
| inherited | OZ `ReentrancyGuard` (1 slot), OZ `Pausable` (1 slot) |
| 0 | `uint64 lastRebalanceTimestamp; uint64 lastCheckpointTimestamp` (packed; public getters are written explicitly to return `uint256` so the ABI matches V1) |
| 1..n | `Slot[] _constituents` where `struct Slot { address token; uint16 targetWeightBps; bool isStrategyToken; uint8 decimals; }` is 24 bytes, one slot per constituent (6 constituents = 6 slots) plus 1 length slot |

Each external call loads the constituents once into a memory array (`Slot[] memory cs`) and passes it down (6 cold SLOADs, 12.6k gas); the vault never reads the array again in the same call. Do not store balances, NAV or weights.

### 3.2 Gas notes and ceilings for 6 constituents

At the measured 0.01 gwei price (07 section 2.4) all of these cost under 0.00005 ETH, so the ceilings are about block and tooling limits, not cost. Estimated breakdown per desk leg: approve set and reset about 30k, registry gate call about 5k, oracle read (cold) about 10k, token pull about 30k, mint or transfer about 50k, measured balance reads about 6k, event about 3k. `totalAssets` costs about 12k per leg per pass.

| Operation (6 constituents, depth 1) | Ceiling gate (`forge test --gas-report`) |
|---|---|
| `deposit` | at most 1.8M gas |
| `depositInKind` | at most 600k |
| `redeem` (USDG) | at most 1.8M |
| `redeemInKind` | at most 700k |
| `executeRebalance` (all 6 legs trade) | at most 2.2M |
| `checkpoint` | at most 300k |
| depth-2 `deposit` (3 of 6 constituents are children with 3 assets each) | at most 3.2M |
| `createStrategy` | at most 6.5M (code deposit of about 20 KB costs about 4M) |
| `VaultDeployerV2` deployment | at most 5.5M |

If a ceiling is exceeded by more than 25 percent the author reports it as a Request; do not silently relax. `checkUpkeep()` over 10 vaults is a view and stays far below any RPC gas cap.

### 3.3 V1 stays buildable and deployable until G1: decision

Decision: **side by side in `contracts/v2/` with distinct contract names** (`StrategyVaultV2`, `StrategyFactoryV2`, `StrategyTokenV2`, `MarketplaceRegistryV2`, `RebalanceEngineV2`, `ChainlinkPriceOracleV2`, `OracleDesk`, `FengAggregator`, `MockUSDGV2`, `FengFaucet`, `VaultDeployerV2`) so Foundry artifacts never collide with V1. In place was rejected because (a) V1 contract verification on Blockscout (E7-T2 rehearsal) needs the unchanged source, (b) V1 tests (48) must keep guarding the live deployment, (c) a failed G1 would otherwise need a revert. V1 files that V2 imports unchanged: `contracts/interfaces/IStrategyVault.sol` (for `Constituent`), `contracts/interfaces/IPriceOracle.sol`, `contracts/interfaces/AggregatorV3Interface.sol`, `contracts/interfaces/IMintableStockToken.sol`, `contracts/mocks/MockStockToken.sol`. No V1 file is edited. Before the first edit lane A records `sha256sum` of every V1 `.sol` (including those imported) into `docs/handoffs/v1-sources.sha256` and re-checks it at G1; there is no git repository, so this file is the guard. `foundry.toml` keeps solc 0.8.24, evm `paris`, optimizer 200, `via_ir = false`; only additive profiles are allowed (3.6).

### 3.4 Files to create or change

Create (lane A, `GP/contracts`):

```
contracts/v2/interfaces/IVenue.sol
contracts/v2/interfaces/IPriceOracleV2.sol
contracts/v2/interfaces/IStrategyVaultV2.sol
contracts/v2/interfaces/IMarketplaceRegistryV2.sol
contracts/v2/interfaces/IStrategyFactoryV2.sol
contracts/v2/interfaces/IRebalanceEngineV2.sol
contracts/v2/interfaces/IOracleDesk.sol
contracts/v2/interfaces/IFengAggregator.sol
contracts/v2/interfaces/IFengFaucet.sol
contracts/v2/interfaces/IStrategyTokenV2.sol
contracts/v2/StrategyVaultV2.sol
contracts/v2/StrategyTokenV2.sol
contracts/v2/StrategyFactoryV2.sol
contracts/v2/VaultDeployerV2.sol
contracts/v2/MarketplaceRegistryV2.sol
contracts/v2/RebalanceEngineV2.sol
contracts/v2/venue/OracleDesk.sol
contracts/v2/oracle/ChainlinkPriceOracleV2.sol
contracts/v2/oracle/FengAggregator.sol
contracts/v2/faucet/FengFaucet.sol
contracts/v2/mocks/MockUSDGV2.sol
script/DeployV2.s.sol
script/SeedV2.s.sol
scripts/deploy-v2.sh
scripts/sync-abi.sh
docs/handoffs/v1-sources.sha256
```

Create (lane A tests, `GP/tests`, independent of the author): `contracts/test/v2/**` (4.1). Change: `foundry.toml` additive only (3.6). Generated, not hand-written: `src/lib/abi/generated/**` (5.3). Not touched: every V1 `.sol`, V1 tests, `script/Deploy.s.sol`, `script/SeedStrategies.s.sol`, `scripts/deploy.sh`, `scripts/seed.sh`, existing `src/lib/abi/*.ts`.

### 3.5 Build, test and size commands

```
forge build
forge build --sizes
forge fmt --check
forge test --no-match-path "contracts/test/v2/**"
forge test --match-path "contracts/test/v2/**"
FOUNDRY_PROFILE=deep forge test --match-path "contracts/test/v2/invariant/**"
FOUNDRY_PROFILE=deep forge test --match-path "contracts/test/v2/fuzz/**"
forge test --match-path "contracts/test/v2/**" --gas-report
forge coverage --report summary --no-match-coverage "(contracts/mocks|contracts/v2/mocks|contracts/test|script)"
forge coverage --ir-minimum --report summary --no-match-coverage "(contracts/mocks|contracts/v2/mocks|contracts/test|script)"
```

Gates: `forge build` has no errors and no stack-too-deep; the V1 command (`--no-match-path`) keeps V1 at 48 passing; `forge build --sizes` shows `StrategyVaultV2` runtime at most 23,500 bytes, `StrategyFactoryV2` at most 12,000, `VaultDeployerV2` at most 24,000 (EIP-170 is 24,576). If the vault exceeds 23,500, apply in order: (1) remove `redeemInKindExcluding` and the `InvalidSkipMask` path (cut-line item 2), (2) move `quoteRedeem`/`previewRedeemInKind` into a read-only `StrategyLens` contract that takes a vault address (frontend change only), (3) split rebalance leg math into an external linked library; do not enable `via_ir` and do not change `optimizer_runs`.

### 3.6 `foundry.toml` additions (additive)

```
[profile.deep.fuzz]
runs = 1000

[profile.deep.invariant]
runs = 2000
depth = 64
fail_on_revert = true
```

The default profile is unchanged (`fuzz.runs = 256`, `invariant.runs = 256`, `depth = 64`, `fail_on_revert = true`). Because `fail_on_revert = true`, handlers must never let an unexpected revert escape (4.2).

---

## 4. Test plan

### 4.1 Layout (owned by `GP/tests`, written from this spec, not from the implementation)

```
contracts/test/v2/helpers/DeployV2Helper.sol        deploys the full stack, parameterised by usdgDecimals and constituent decimals
contracts/test/v2/mocks/HostileTokens.sol           reentrant, blocklist/pause, fee-on-transfer, rebasing, no-return, return-false tokens
contracts/test/v2/mocks/HostileVenues.sol           lying amountOut, short-delivery, reentrant venue
contracts/test/v2/unit/*.t.sol                      per contract
contracts/test/v2/fuzz/ShareMath.t.sol              stateless fuzz
contracts/test/v2/invariant/Handler.sol             shared handler
contracts/test/v2/invariant/Invariant6Dec.t.sol     I1-I10 at d = 6
contracts/test/v2/invariant/Invariant18Dec.t.sol    I1-I10 at d = 18
contracts/test/v2/invariant/InflationAttackV2.t.sol I11 at d = 6 and d = 18
contracts/test/v2/invariant/DepthCycleV2.t.sol      I7 ported from V1
```

### 4.2 Fuzz handler design (`Handler.sol`)

Actors: 4 depositors, 1 keeper, 1 guardian, 1 relayer (holds `UPDATER_ROLE`), 1 attacker. Vault under test: a 3-asset depth-1 vault plus a depth-2 vault P that holds it. Every handler action wraps the target call in `try/catch`; an expected revert selector (list: `EnforcedPause`, `StalePrice`, `SlippageExceeded`, `InsufficientLiquidity`, `RebalanceNotNeeded`, `CheckpointTooSoon`, `ZeroShares`, `ZeroAssets`, `NoValueAdded`, `ExceedsMaxWeight`, `ChildRedeemFailed`) increments a ghost counter; any other selector sets `ghost_unexpectedRevert = true` and `invariant_noUnexpectedRevert` asserts it is false. Inputs are clamped with `bound`.

| Handler | Action | Ghosts recorded |
|---|---|---|
| `deposit(actor, amount)` | mint USDG, approve, `deposit` with `minShares = previewDeposit * 99%` | `usdgIn`, `shares`, independent `valueAdded` (handler recomputes it from before/after balances and oracle prices with its own copy of `valueOf`), NAV before/after, `sharePrice` before/after |
| `depositInKind(actor, assetSeed, amount)` | mint the constituent via the desk-owner path in the test, approve, deposit | same |
| `redeem(actor, frac)` | `redeem` fraction of the actor's shares with `minUsdgOut = quoteRedeem * 99%` | `usdgOut`, preview, share price before/after |
| `redeemInKind(actor, frac)` | `redeemInKind`, also `redeemInKindExcluding` with random mask | amounts, balances before/after |
| `pushPrice(assetSeed, bps)` | relayer `updateAnswer` within +/- 10 percent of anchor | none |
| `warp(dt)` | `vm.warp` by 0..2 days | none |
| `rebalance()` | `engine.performRebalance` if `checkUpkeep` lists the vault | NAV before/after, traded notional from `LegTraded` logs |
| `checkpoint()` | `engine.checkpoint([vault])` | event count |
| `chaos(mode)` | modes: let feeds go stale (warp past `maxPriceStaleness`), `desk.setToken(Unsupported)`, withdraw desk reserve, `setToken(Mint)` back, guardian pause/unpause | mode flag |
| `donate(assetSeed, amount)` | attacker donates USDG or a constituent directly to the vault | donated value |

### 4.3 Invariant to test mapping (I1 to I11 of section 8.5)

| ID | Statement | Concrete check |
|---|---|---|
| I1 | Redeemable value equals NAV within rounding | `invariant_previewSumEqualsNav`: sum over all actors of `previewRedeem(balanceOf(actor))` is at most `totalAssetsUSDG()` and at least `totalAssetsUSDG() - (actorCount + 1)`; `previewRedeem(totalSupply()) == totalAssetsUSDG()` exactly; `totalAssetsUSDG() == idle + sum independentOracleValue(i)` recomputed by the test |
| I2 | Round trip returns at least input minus twice (spread plus slippage) | in the handler for `deposit` then `redeem` of the same actor at constant prices: `out >= in * (BPS - 2*spreadBps) / BPS - (2n + 3)`; and the spec bound `out >= in * (BPS - 2*(spreadBps + maxSlippageBps)) / BPS` also holds with price noise when no price moved more than `maxSlippageBps` between the two calls |
| I3 | Share price does not fall on deposit, redeem, in-kind | with unchanged prices and `S >= 1e18` before the action: `sharePriceAfter >= sharePriceBefore - 1 - sharePriceBefore / 1e6`; for `redeemInKind` exact within 1 unit |
| I4 | A rebalance changes NAV by at most the spread cost | `navBefore - navAfter <= tradedNotional * spreadBps / BPS * (1 + 1/BPS) + (n + 2)` and `navAfter <= navBefore + (n + 2)`; with a child leg the bound is `2 *` that |
| I5 | `redeemInKind` always succeeds with stale feeds and an empty venue | after `chaos` modes (stale, `Unsupported`, reserve withdrawn, `FeedNotSet` through `removeFeed`), `redeemInKind` and `previewRedeemInKind` succeed and pay exactly `floor(balance * shares / S)` per token; also while the vault is paused |
| I6 | No path mints shares without equal measured value | `sharesMinted <= valueAddedIndependent * (S + vS) / (navBeforeIndependentCeil + 1)`; `totalSupply` is unchanged by `executeRebalance`, `checkpoint`, `redeemInKind` except by burning; no mint on `donate` |
| I7 | Depth at most 2, no cycles | port `DepthCycle.t.sol` against `StrategyFactoryV2` (depth 3 reverts `DepthExceeded`, unknown strategy token reverts, duplicates revert, a strategy cannot contain itself or an ancestor) |
| I8 | Desk reserve accounting identity | `usdg.balanceOf(desk) >= funded + buyIn - sellOut - withdrawn` after every action, equality when no donation; `sellOut` never exceeds `funded + buyIn - withdrawn`; the same per token in inventory mode |
| I9 | All of the above hold for USDG with 6 and 18 decimals | `Invariant6Dec` and `Invariant18Dec` inherit one abstract base with `_usdgDecimals()`; the unit decimals matrix (4.5) runs the same vectors |
| I10 | A hostile token with reentrant hooks cannot extract value | `ReentrantToken` registered as an inventory-mode constituent in a dedicated vault; its hook tries `deposit`, `depositInKind`, `redeem`, `redeemInKind`, `executeRebalance`, `checkpoint`, `previewRedeem`, `totalAssetsUSDG` on the vault and the child; every attempt reverts with `ReentrancyGuardReentrantCall` (state-changing) or reverts (views); the attacker contract's USDG plus share value never exceeds what it put in |
| I11 | First depositor inflation attack stays unprofitable | `InflationAttackV2`: for `d` in {6, 18}, fuzz `a in [2, 1e8 * U]` first deposit, `D in [0, 1e9 * U]` direct USDG donation (and a constituent donation), victim `V in [U, 1e6 * U]` with `minShares = 0`: either the victim deposit reverts (`ZeroShares`, `NoValueAdded`) or the victim's full redeem returns at least `V * (1 - 25 bps) - 3` units, and the attacker's total redeemed amount is at most `a + D` (no profit beyond 1 unit). Include the concrete scenario `a = 1 wei`-class first deposit. |

Invariants also asserted globally: `invariant_noUnexpectedRevert`, `invariant_supplyEqualsSumBalances`, `invariant_noOpenApprovals` (the vault's allowance to the venue and to the child vault is 0 for USDG and every constituent after every action), `invariant_vaultNeverHoldsNegative` (trivial) and `invariant_paused_redeemStillWorks`.

### 4.4 Unit tests that must exist (names are the contract between author and tester)

Vault V2 (each at `d = 6` and `d = 18`): `test_inceptionSharePriceExact`, `test_vector_roundTrip_d6`, `test_vector_roundTrip_d18` (the integers in 1.8), `test_deposit_revertsOnStalePrice`, `test_deposit_revertsWhenPaused`, `test_deposit_minSharesEnforced`, `test_deposit_dustLegsStayIdleAndCountInNav`, `test_deposit_feeOnTransferUsdgMintsFewerShares`, `test_deposit_previewWithinTolerance`, `test_deposit_idleIncludedInNav`, `test_depositInKind_valueAtOracle`, `test_depositInKind_exceedsMaxWeightReverts`, `test_depositInKind_usdgReverts`, `test_depositInKind_worksWithEmptyDesk`, `test_redeem_equalsQuoteWithinDust`, `test_redeem_revertsOnStale`, `test_redeem_neverPaused`, `test_redeem_delegatedNeedsAllowanceOfCaller`, `test_redeem_vaultApprovalDoesNotAuthorizeCaller` (regression for C-02), `test_redeem_minUsdgOutEnforced`, `test_redeem_lastHolderDrainsEverything`, `test_redeemInKind_returnsAllConstituentsAndIdle`, `test_redeemInKind_childSharesNotUnwound`, `test_redeemInKindExcluding_skipsFrozenToken`, `test_redeemInKindExcluding_invalidMask`, `test_nested_redeemUsdg_unwindsChild`, `test_nested_redeemUsdg_childFailureWrapsReason`, `test_nested_staleChildBlocksParent` (C-09), `test_nested_depositUsesChildMinShares`, `test_rebalance_sellsBeforeBuys` (assert event order `LegTraded(sell)` before `LegTraded(buy)`), `test_rebalance_deploysIdle`, `test_rebalance_skipsLegsInsideTolerance`, `test_rebalance_thresholdUsesEffectiveMax` (max == target vault does not refire after a rebalance), `test_rebalance_thresholdFiresAboveMax` (port of V1 multi-asset skew), `test_rebalance_timeBasedNoTradeStillAdvancesTimestamp`, `test_rebalance_emptyVaultNeverNeeded`, `test_rebalance_pausedNotNeeded`, `test_rebalance_emitsCheckpointThenRebalanced`, `test_checkpoint_rateLimited`, `test_checkpoint_resetByDeposit`, `test_checkpoint_revertsOnStale`, `test_pause_onlyGuardian`, `test_approvalsAlwaysZeroAfterCalls`, `test_priceStatus_recursesIntoChild`, `test_weights_sumPlusIdleIs10000`, `test_reentrancy_*` (one per entrypoint with `ReentrantToken`).
Factory V2: every error in 2.7, plus `test_noGrantRoleCallsOnConstituents`, `test_realTokenWithoutMinterRoleAccepted`, `test_depth3Reverts`, `test_vaultCreatedByStrangerIsNotRegistered`, `test_maxWeightBand`. Registry V2: meta limits, `updateMeta` only creator, pagination bounds, `isRegistered`. Engine V2: failing vault skipped in `checkUpkeep`, `performRebalance` registry gate, `checkpoint` skips unregistered and reverting vaults. Desk: spread rounding favours desk, both modes, reserve identity, registry gate, stale gate, `Unsupported` stops swaps, inventory short-fall errors. Aggregator: deviation bound versus anchor, shock then restore, `refresh` keeps the answer and moves `updatedAt`, `forceAnswer` re-anchors, role gating, parameter caps. Oracle V2: `isSupported`, `priceDecimals`, `removeFeed`, `InvalidPrice`. Faucet: once per address, daily cap, contract recipient rejected, dispenser-only, empty faucet, reentrant recipient impossible (EOA only). MockUSDGV2: decimals 6 and 18, minter gating. StrategyTokenV2: vault-only mutators, `burnFrom` spends allowance.

### 4.5 Decimals matrix

| USDG decimals | Constituent decimals | Required |
|---|---|---|
| 6 | 18 | all unit, fuzz, invariant tests (production shape) |
| 18 | 18 | all unit, fuzz, invariant tests |
| 6 | 8 | share math, deposit, redeem, rebalance, in-kind (proves `dec_i` handling) |
| 18 | 8 | share math and deposit only |

Each cell asserts: inception `sharePrice() == inceptionSharePrice()`, preview versus actual tolerance, no overflow at `1e12 * U` deposits, `valueOf`/`tokensForValue` round trips within 1 unit, and I11.

### 4.6 Hostile mocks (all in `contracts/test/v2/mocks/`)

- `ReentrantToken` (ERC-777 style): ERC-20 whose `transfer` and `transferFrom` call a configurable hook on `from` and `to` after the balance update; the hook calls a configurable selector on a configurable target.
- `BlocklistToken` and `BlockableUSDG`: per-address blocklist plus global pause; `transfer`, `transferFrom`, `approve` revert for blocked `from`, `to` or spender (Paxos/Stock behaviour); toggled mid-test to freeze the vault or the desk.
- `FeeOnTransferToken`: skims a configurable bps on every transfer, usable as USDG or as a constituent.
- `RebasingToken`: shares-based balance with `rebase(int256 bps)`.
- `NoReturnToken` (USDT style) and `ReturnFalseToken`: exercise `SafeERC20`.
- `HostileVenues`: returns a larger `amountOut` than delivered, delivers less than `minAmountOut`, reenters the vault.

### 4.7 Coverage and run thresholds (E8-T2)

`forge coverage` on `contracts/v2/**` excluding mocks: at least 90 percent lines and 80 percent branches (if `forge coverage` hits stack-too-deep use `--ir-minimum` and say so in the report). All invariants pass at the default profile (256 runs, depth 64) and at least once with `FOUNDRY_PROFILE=deep` (2000 runs). V1 suite still 48 of 48. Gas ceilings of 3.2 respected. The reviewer (`GP/review`) signs off with no open High or Critical before G1.

---

## 5. ABI-facing surface for frontend and ops

### 5.1 Functions the frontend and ops use (V2 ABI)

| Contract | Function | Returns |
|---|---|---|
| `StrategyVaultV2` | `deposit(uint256,address,uint256)` | `uint256 shares` |
|  | `depositInKind(address,uint256,address,uint256)` | `uint256 shares` |
|  | `redeem(uint256,address,address,uint256)` | `uint256 usdgOut` |
|  | `redeemInKind(uint256,address,address)` | `address[] tokens, uint256[] amounts` |
|  | `redeemInKindExcluding(uint256,address,address,uint256)` | `address[] tokens, uint256[] amounts` |
|  | `previewDeposit(uint256)`, `previewDepositInKind(address,uint256)` | `uint256` |
|  | `previewRedeem(uint256)`, `quoteRedeem(uint256)` | `uint256` |
|  | `previewRedeemInKind(uint256)` | `address[] tokens, uint256[] amounts` |
|  | `totalAssetsUSDG()`, `sharePrice()`, `inceptionSharePrice()` | `uint256` (USDG units; `sharePrice` is USDG units per 1e18 shares) |
|  | `weights()` | `uint16[]` (bps per constituent, idle is `10000 - sum`) |
|  | `effectiveMaxWeightBps(uint256)` | `uint16` |
|  | `priceStatus()` | `bool fresh, uint256 oldestUpdatedAt` |
|  | `getConstituents()` | `Constituent[] (token, targetWeightBps, isStrategyToken)` |
|  | `depth()` | `uint8` |
|  | `rebalanceNeeded()` | `bool timeBased, bool thresholdBased` |
|  | `executeRebalance()`, `checkpoint()` | none |
|  | `paused()`, `guardian()`, `venue()`, `priceOracle()`, `token()`, `usdgToken()` | `bool` / `address` |
|  | `usdgDecimals()` | `uint8` |
|  | `maxWeightBps()`, `maxSlippageBps()` | `uint16` |
|  | `rebalanceInterval()`, `maxPriceStaleness()`, `lastRebalanceTimestamp()`, `lastCheckpointTimestamp()` | `uint256` |
| `StrategyFactoryV2` | `createStrategy(string,string,Constituent[],uint16,uint256,uint16,StrategyMeta)` | `address vault, address token` |
|  | `vaultOf(address)`, `venue()`, `priceOracle()`, `usdg()`, `usdgDecimals()`, `guardian()`, `maxPriceStaleness()` | `address` / `uint8` / `uint256` |
| `MarketplaceRegistryV2` | `getAllStrategies()`, `getStrategies(uint256,uint256)` | `address[]` |
|  | `strategyCount()`, `isRegistered(address)` | `uint256` / `bool` |
|  | `getStrategyInfo(address)` | `address token, address creator, uint8 depth, uint256 createdAt` (V1 shape) |
|  | `getStrategyInfoV2(address)` | `StrategyInfoV2` |
|  | `getStrategyMeta(address)`, `updateMeta(address,StrategyMeta)` | `StrategyMeta` / none |
| `RebalanceEngineV2` | `checkUpkeep()`, `checkUpkeepRange(uint256,uint256)` | `address[]` |
|  | `performRebalance(address)`, `checkpoint(address[])` | none / `uint256 recorded` |
| `OracleDesk` | `quoteExactIn`, `reserveUsdg()`, `tokenInventory(address)`, `accounting()`, `spreadBps()`, `mode(address)` | for the ops health block |
| `FengAggregator` | `latestRoundData()`, `decimals()`, `updateAnswer(int256)`, `refresh()`, `shockAnswer(int256)`, `forceAnswer(int256)`, `anchorAnswer()`, `shockEnabled()` | relayer and demo script |
| `ChainlinkPriceOracleV2` | `getPrice(address)`, `isSupported(address)`, `priceDecimals()`, `feeds(address)` | `(uint256 price, uint256 updatedAt)` / `bool` / `uint8` / `address` |
| `FengFaucet` | `claimFor(address)`, `hasClaimed(address)`, `claimsToday()`, `dailyCap()`, `ethPerClaim()`, `usdgPerClaim()` | server wallet and UI state |
| `MockUSDGV2`, `StrategyTokenV2` | ERC-20 reads, `mint` (minter only) | share token is a plain ERC-20 for the UI |

Error selectors the UI must decode (from the ABI): `StalePrice`, `SlippageExceeded`, `InsufficientLiquidity`, `VenueSlippage`, `ExceedsMaxWeight`, `ChildRedeemFailed`, `EnforcedPause`, `CheckpointTooSoon`, `ZeroShares`, `NoValueAdded`, `NotGuardian`, `AlreadyClaimed`, `DailyCapReached`, `FaucetEmpty`. Suggested actions: `StalePrice`, `InsufficientLiquidity`, `ChildRedeemFailed`, `VenueSlippage` on redeem show "Redeem in kind"; `SlippageExceeded` shows "Increase tolerance or retry"; `EnforcedPause` shows "Deposits are paused, you can still redeem".

### 5.2 Events (V2)

| Contract | Event | Indexed |
|---|---|---|
| vault | `Deposit(sender, receiver, usdgAmount, shares)` | sender, receiver |
| vault | `DepositInKind(sender, receiver, token, amount, valueUsdg, shares)` | sender, receiver, token |
| vault | `Redeem(sender, receiver, owner, shares, usdgAmount)` | sender, receiver, owner |
| vault | `RedeemInKind(sender, receiver, owner, shares)` | sender, receiver, owner |
| vault | `LegTraded(token, buy, usdgAmount, tokenAmount)` | token |
| vault | `Rebalanced(timestamp, timeBased, thresholdBased, sharePrice)` | timestamp |
| vault | `NavCheckpoint(timestamp, totalAssets, totalSupply)` | timestamp |
| vault | OZ `Paused(account)`, `Unpaused(account)` | none |
| factory | `StrategyCreated(vault, token, creator, depth)` | all three addresses |
| registry | `StrategyRegistered(vault, token, creator)`, `MetaUpdated(vault, description, tags)` | vault (and token, creator) |
| engine | `RebalancePerformed(vault, keeper)`, `CheckpointsRecorded(caller, requested, recorded)` | vault, keeper / caller |
| desk | `Swapped(vault, tokenIn, tokenOut, amountIn, amountOut, recipient)`, `TokenConfigured`, `SpreadSet`, `ReserveFunded`, `ReserveWithdrawn`, `InventoryFunded`, `InventoryWithdrawn` | as declared |
| aggregator | `AnswerUpdated(current, roundId, updatedAt)`, `AnswerShocked`, `AnswerForced`, `ParamsSet`, `ShockEnabledSet` | as declared |
| faucet | `Claimed(recipient, dispenser, ethAmount, usdgAmount)` | recipient, dispenser |

History for the frontend: `NavPoint = { t: timestamp, price: totalAssets * 1e18 / totalSupply / 10 ** usdgDecimals }` from `NavCheckpoint`; the since-inception return is `sharePrice() / inceptionSharePrice() - 1` and needs no history. Strategy discovery uses `getStrategies` plus `getStrategyInfoV2`; no block numbers exist on chain, find creation with `StrategyRegistered` logs.

### 5.3 `deployments/<name>/addresses.json` schema v2 (additions to plan section 8.2)

Same shape as plan 8.2, plus these keys (all additive; a file without `schemaVersion` is V1):

```json
{
  "schemaVersion": 2,
  "chainId": 46630,
  "rpcUrl": "https://rpc.testnet.chain.robinhood.com",
  "explorerUrl": "https://explorer.testnet.chain.robinhood.com",
  "deployedAt": 1790000000,
  "usdg": "0x...",
  "usdgDecimals": 6,
  "stockTokens": { "TSLA": "0x...", "AMZN": "0x...", "NFLX": "0x...", "PLTR": "0x...", "AMD": "0x..." },
  "priceOracles": { "TSLA": "0x...", "AMZN": "0x...", "NFLX": "0x...", "PLTR": "0x...", "AMD": "0x...", "USDG": "0x..." },
  "oracle": "0x...",
  "venue": "0x...",
  "vaultDeployer": "0x...",
  "faucet": "0x...",
  "guardian": "0x...",
  "strategyFactory": "0x...",
  "rebalanceEngine": "0x...",
  "marketplaceRegistry": "0x...",
  "maxPriceStaleness": 43200,
  "deskSpreadBps": 10,
  "defaultMaxSlippageBps": 100,
  "checkpointMinInterval": 1800,
  "vaults": [
    { "symbol": "AIGR", "name": "AI Growth", "vault": "0x...", "token": "0x...", "universe": "sandbox", "depth": 1 }
  ],
  "live": {
    "usdg": "0x7E955252E15c84f5768B83c41a71F9eba181802F",
    "usdgDecimals": 6,
    "stockTokens": { "TSLA": "0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E" },
    "strategyFactory": "0x...",
    "venue": "0x...",
    "vaults": []
  }
}
```

New keys versus 8.2: `deployedAt`, `vaultDeployer`, `maxPriceStaleness`, `deskSpreadBps`, `defaultMaxSlippageBps`, `checkpointMinInterval`, and `name` and `depth` per vault entry. `priceOracles` maps ticker to the `FengAggregator` address (V1 meaning kept). The `oracle` key is the `ChainlinkPriceOracleV2` that all vaults read. Ops reads `maxPriceStaleness` for its 35 minute alarm and its 12 hour hard floor. Written by `DeployV2.s.sol` (and `vaults` filled by `SeedV2.s.sol`) to `deployments/robinhood-testnet-v2/addresses.json`; after G1 E7-T3 archives V1 and copies the V2 file to `deployments/robinhood-testnet/addresses.json`. Secrets and keys never appear in the file; only public addresses.

### 5.4 `scripts/sync-abi.sh` contract

- Input: `out/<File>.sol/<Contract>.json` produced by `forge build`; tool: `jq` (declare it in the script header check, exit 1 if missing).
- Output directory: `src/lib/abi/generated/`. The script owns this directory exclusively and rewrites it entirely; it never touches the hand-written V1 files `src/lib/abi/*.ts` (the frontend retires those at G1).
- One file per contract, file name = camelCase contract name, content exactly `export const <camelName>Abi = <abi json, 2-space indent> as const;` plus a trailing newline, nothing else (no comments, no header). `<camelName>` is the contract name with the first letter lower-cased and `USDG` written `Usdg`.
- Barrel `src/lib/abi/generated/index.ts` re-exports every constant: `export { strategyVaultV2Abi } from "./strategyVaultV2";` and so on.
- Contract list and export names (fixed): `StrategyVaultV2` to `strategyVaultV2Abi`, `StrategyFactoryV2` to `strategyFactoryV2Abi`, `StrategyTokenV2` to `strategyTokenV2Abi`, `MarketplaceRegistryV2` to `marketplaceRegistryV2Abi`, `RebalanceEngineV2` to `rebalanceEngineV2Abi`, `OracleDesk` to `oracleDeskAbi`, `ChainlinkPriceOracleV2` to `chainlinkPriceOracleV2Abi`, `FengAggregator` to `fengAggregatorAbi`, `FengFaucet` to `fengFaucetAbi`, `MockUSDGV2` to `mockUsdgV2Abi`, `MockStockToken` to `mockStockTokenAbi`.
- Exit code 1 if any listed artifact is missing or has an empty ABI; idempotent (second run produces no diff); `--check` flag runs the generation to a temp directory and fails if it differs from the committed files (for CI).
- The `Constituent` type is not generated; the frontend derives types with `abitype`/viem from the const ABIs.
- Lane rules from plan 8.4 hold: only this script writes `src/lib/abi/generated/**`; lane C imports from it; lane B reads it.

---

## 6. Deploy and seed plan

### 6.1 Environment variable names (values never printed, never written to files)

`DEPLOY_NETWORK` (set to `robinhood-testnet`; output goes to `deployments/robinhood-testnet-v2/`), `DEPLOYER_PRIVATE_KEY` (secret), `GUARDIAN_ADDRESS` (optional, default deployer), `RELAYER_ADDRESS` (public address that receives `UPDATER_ROLE`), `FAUCET_DISPENSER_ADDRESS` (public address of the server wallet behind `FAUCET_PRIVATE_KEY`), `ENABLE_SHOCK` (`1` grants `SHOCK_ROLE` to the relayer and sets `shockEnabled`), `FAUCET_ETH_FUND_WEI` (default `4000000000000000`, 0.004 ETH, the E10-T5 budget), optional `INIT_PRICE_TSLA`, `INIT_PRICE_AMZN`, `INIT_PRICE_NFLX`, `INIT_PRICE_PLTR`, `INIT_PRICE_AMD` (8-decimal integers). Defaults are the 2026-10-03 mid prices from 07 section 2.3: TSLA `37162000000`, AMZN `25030000000`, NFLX `6707000000`, PLTR `18863000000`, AMD `62862000000`.

### 6.2 `script/DeployV2.s.sol` (single broadcast, order of creation)

1. `MockUSDGV2(deployer, 6)`.
2. Five `MockStockToken` (TSLA, AMZN, NFLX, PLTR, AMD; name `"Mock <T>"`, `uiMultiplier 1e18`, admin deployer). Fresh instances: V2 does not reuse V1 mocks.
3. Six `FengAggregator` (five stocks plus USDG): `decimals 8`, initial answers from section 6.1 (USDG `1e8`), `maxDeviationBps 1500`, `maxShockBps 3000`; description `"<T> / USD"`.
4. `ChainlinkPriceOracleV2(deployer)`; `setFeed` for the five stocks and the USDG token.
5. `MarketplaceRegistryV2(deployer)`.
6. `OracleDesk(deployer, usdg, oracle, registry, 10, 43200)`; `setToken(stock, Mint)` for the five; `stock.grantRole(MINTER_ROLE, desk)` for the five.
7. Desk reserve: `usdg.mint(deployer, 10_000_000e6)`, `usdg.approve(desk, 10_000_000e6)`, `desk.fundReserve(10_000_000e6)`.
8. `VaultDeployerV2()`.
9. `StrategyFactoryV2(registry, oracle, desk, usdg, guardian, vaultDeployer, 43200)`.
10. `RebalanceEngineV2(registry)`.
11. `registry.grantRole(FACTORY_ROLE, factory)`.
12. `FengFaucet(deployer, usdg, 0.0002 ether, 10_000e6, 200)`; `usdg.grantRole(MINTER_ROLE, faucet)`; `faucet.grantRole(DISPENSER_ROLE, FAUCET_DISPENSER_ADDRESS)`; fund the faucet with `FAUCET_ETH_FUND_WEI` through a plain value transfer.
13. Aggregators: `grantRole(UPDATER_ROLE, RELAYER_ADDRESS)` on all six; if `ENABLE_SHOCK == 1`, `grantRole(SHOCK_ROLE, RELAYER_ADDRESS)` and `setShockEnabled(true)` on the five stock feeds.
14. Write `deployments/robinhood-testnet-v2/addresses.json` (schema 5.3) with `vaults` empty and `deployedAt = block.timestamp`.

### 6.3 `script/SeedV2.s.sol`

Reads the v2 addresses file; the deployer already holds `MINTER_ROLE` on `usdg`. It never calls `updateAnswer` (the deviation bound and the relayer own prices); the feeds are fresh from the deploy minutes before. Steps: mint the total seed amount to the deployer, create the ten strategies in this order (leaves first so CORE and CONV can reference tokens by index), approve and deposit the seed amount per vault with `minShares = previewDeposit(amount) * 99 / 100`, then write the `vaults` array back to the JSON. `maxSlippageBps = 100` for all ten. Meta strings must satisfy the registry limits (the script asserts lengths).

| # | Symbol | Name | Constituents (weight bps) | maxWeight | Interval | Seed USDG | Tags |
|---|---|---|---|---|---|---|---|
| 0 | AIGR | AI Growth | PLTR 3500, AMD 3500, AMZN 3000 | 4000 | 7 d | 5,000 | ai, growth |
| 1 | STRM | Streaming Giants | NFLX 6000, AMZN 4000 | 6000 | 3 d | 2,500 | media, streaming |
| 2 | EVMO | EV Momentum | TSLA 4000, AMD 3000, PLTR 3000 | 4000 | 1 d | 3,000 | momentum, ev |
| 3 | EQ5 | Big Five Equal | TSLA, AMZN, NFLX, PLTR, AMD 2000 each | 2000 | 7 d | 4,000 | equal-weight, index |
| 4 | DEFC | Defensive Core | AMZN 4000, NFLX 3000, AMD 3000 | 4000 | 7 d | 1,500 | core, defensive |
| 5 | CHIP | Chip Tilt | AMD 6000, TSLA 4000 | 6000 | 14 d | 1,000 | semis, tilt |
| 6 | BLTZ | High Beta Blitz | PLTR 5000, TSLA 5000 | 5000 | 1 h | 2,000 | high-beta, fast |
| 7 | CLCM | Cloud & Commerce | AMZN 5000, PLTR 2500, NFLX 2500 | 5000 | 7 d | 2,500 | cloud, commerce |
| 8 | CORE | Core Satellite | AIGR 4000, EQ5 4000, TSLA 2000 (depth 2) | 4000 | 7 d | 3,500 | composed, core |
| 9 | CONV | Conviction Mix | STRM 4000, CHIP 3000, PLTR 3000 (depth 2) | 4000 | 1 d | 1,200 | composed, conviction |

Seed total 26,200 USDG (the six decimals make these realistic judge-sized positions; the faucet gives each judge 10,000 mock USDG). Descriptions (each at most 160 bytes) are one plain English sentence per strategy, for example AIGR: "Tilt toward AI compute and analytics: Palantir, AMD and Amazon, rebalanced weekly." CORE: "Composed strategy: AI Growth and Big Five Equal plus a Tesla satellite." The author writes the rest in the same style. Total gas for the ten creations is about 10 times the 6.5M ceiling in the worst case, so the script is broadcast with `--slow` and `--resume` and never rerun from scratch (plan preamble).

Per-vault effective thresholds after seeding: STRM, EVMO, EQ5, CHIP, BLTZ, CLCM have `max == target` so they use `target + 10 bps` (C-15); the demo shock (for example TSLA +18 percent on EVMO) lifts TSLA from 40 percent to about 44 percent and crosses the threshold.

### 6.4 `scripts/deploy-v2.sh`

Wraps `forge script script/DeployV2.s.sol` then `forge script script/SeedV2.s.sol` with `--rpc-url`, `--broadcast`, `--slow`, retry on transient TLS errors, and on failure re-runs the same command with `--resume`. It reads `DEPLOYER_PRIVATE_KEY` from the environment only, never echoes it, never writes it, never reads any `.env*` file itself (the caller exports the variable). After a successful run it prints only addresses.

### 6.5 Role grant matrix (after DeployV2)

| Contract | Role or owner | Holder |
|---|---|---|
| `MockUSDGV2` | `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` | deployer; `MINTER_ROLE` also faucet |
| `MockStockToken` x5 | `DEFAULT_ADMIN_ROLE` | deployer; `MINTER_ROLE` granted to desk only (vaults hold none) |
| `FengAggregator` x6 | `DEFAULT_ADMIN_ROLE` | deployer; `UPDATER_ROLE` relayer; `SHOCK_ROLE` relayer only when `ENABLE_SHOCK=1` |
| `ChainlinkPriceOracleV2` | owner | deployer |
| `OracleDesk` | owner | deployer |
| `MarketplaceRegistryV2` | `DEFAULT_ADMIN_ROLE`; `FACTORY_ROLE` | deployer; factory |
| `StrategyFactoryV2`, `RebalanceEngineV2`, `VaultDeployerV2` | none | none |
| `FengFaucet` | `DEFAULT_ADMIN_ROLE`; `DISPENSER_ROLE` | deployer; server wallet |
| each vault | `guardian` | `GUARDIAN_ADDRESS` or deployer |

### 6.6 Live universe deltas (for E4, no new contract needed)

`script/DeployLive.s.sol` (E4-T2) deploys a second `OracleDesk` (inventory mode for the five real faucet tokens `TSLA 0xC9f9...3bd4E` and its siblings, `usdg = 0x7E955252E15c84f5768B83c41a71F9eba181802F`) and a second `StrategyFactoryV2` pointing at that desk; the oracle is shared (`ChainlinkPriceOracleV2.setFeed(realToken, existingAggregator)`), the registry is shared (`FACTORY_ROLE` granted to the second factory). Before any broadcast the script asserts `uiMultiplier() == 1e18` on each real token and `decimals() == 6` on the real USDG, funds the desk with the real USDG reserve and real token inventory the human claimed, and uses demo-scale deposits. If R1 shows that real USDG or Stock tokens block contract transfers, E4 stops and Sandbox stays the product.

---

## 7. Open points, risks, cut line

### 7.1 Open points and who resolves them

| # | Open point | Owner | Default frozen here |
|---|---|---|---|
| O-1 | FengAggregator numeric parameters (`maxDeviationBps 1500`, `maxShockBps 3000`, push cadence 30 min or 10 bps, weekend and halt behaviour using `refresh()`), source terms of the Robinhood price API, `maxPriceStaleness 12 h` (`to align with R2`) | R2 agent (`docs/research/09-price-source-and-feed.md`), then `GP/contracts` changes constants only | values in 2.4 and 6.2 |
| O-2 | Whether the `IVenue` shape (exact-in, quote, `isSupported`, `usdg`) is enough for a Uniswap v4 adapter (the registry gate is desk specific) (`to align with R3`) | R3 agent | shape in 2.1 |
| O-3 | Whether real Stock tokens and Paxos USDG accept transfers from contract vaults and desks, and what a blocklist hit does (affects Live and the value of `redeemInKindExcluding`) | R1 agent | Live is additive, Sandbox is the default |
| O-4 | Blockscout verification of vaults created by `VaultDeployerV2` (constructor argument is a struct with dynamic arrays; creation by contract) | R4 agent | verify core contracts first, vaults through standard JSON input |
| O-5 | Desk parameters (reserve 10,000,000 mock USDG, spread 10 bps, default `maxSlippageBps` 100), user confirmation (plan open question 12) | coordinator and user | as stated |
| O-6 | V2 becomes the production key `deployments/robinhood-testnet` after G1 (plan open question 3) | coordinator and user | yes, V1 archived |
| O-7 | Who is the guardian (separate address versus deployer) | user | deployer unless `GUARDIAN_ADDRESS` is provided |
| O-8 | Faucet budget and sybil limits: 0.0002 ETH and 10,000 mock USDG per address, daily cap 200, dispenser role held only by the server wallet; plus the per-IP rule in Vercel Firewall (E10-T5) | `GP/ops` and user | as stated |

### 7.2 Risk list

| ID | Risk | Mitigation or status |
|---|---|---|
| R-01 | Schedule: V2 is the critical path to G1 | cut line 7.3; the V1 deployment stays live and fresh |
| R-02 | Vault bytecode size or stack-too-deep without `via_ir` | `VaultDeployerV2`, `VaultParams` struct, size gate 3.5, ordered fallbacks |
| R-03 | The mint-mode desk is a simulation of a market | README "real versus mocked" table; inventory mode and the Live universe use real tokens |
| R-04 | Relayer centralisation and stale-NAV arbitrage (informed users trade before the next push) | deviation-bounded role-gated feed, 30 min or 10 bps cadence, 10 bps desk spread, 12 h hard staleness, testnet mock USDG; a mainnet path needs Chainlink plus a redemption fee (documented) |
| R-05 | Guardian can pause deposits and rebalances indefinitely | exits never pausable; testnet; document; rotate by redeploy only |
| R-06 | Registry spam through permissionless creation (each creation about 0.00005 ETH) | paged reads, frontend filters; not prevented |
| R-07 | A real token or USDG freezes the vault or the desk | `redeemInKindExcluding`; out of scope to recover |
| R-08 | Corporate actions change `uiMultiplier` or balances | out of scope; script asserts `1e18` at Live deploy |
| R-09 | USDG depeg (vault assumes 1.00 USD) | out of scope; documented in the threat model (E8-T1) |
| R-10 | Never use `block.number` on this chain | rule in the conventions; registry stores `createdAt` only |
| R-11 | Depth-2 gas and revert coupling (a child paused or failing blocks the parent's deposit and rebalance) | all-or-nothing legs, keeper simulates before sending, exits always available |
| R-12 | Desk reserve exhausted so USDG redeems and rebalance sells revert | `redeemInKind`; reserve 10,000,000 against seeds of 26,200; ops health shows `reserveUsdg()` |
| R-13 | Paused child blocks a parent buy leg | accepted; parent exits unaffected |
| R-14 | In-kind deposit and donation externalise a rebalance spread (about 0.2 percent of the shifted notional) | `ExceedsMaxWeight` guard bounds the shift; documented |
| R-15 | Preview versus actual mismatch for depth-2 deposits | tolerance in C-36; frontend sets `minShares` from the preview with the user's slippage |
| R-16 | `forge coverage` needs `--ir-minimum` (branch figures less accurate) | state it in the report |
| R-17 | Virtual-share protection is bounded: donations above about 1e12 USDG-equivalent are outside the model | supply-bounded on testnet; users also set `minShares` |
| R-18 | Share price drops by up to about `vS/S` relative on a deposit at price above 1 (virtual shares) | sub 1e-6 for pools of at least 1 share; I3 tolerance |

### 7.3 Cut line and minimum viable V2

If G1 timing slips, drop in this order, stopping as soon as the schedule recovers:

1. **E3-T8 management fee**: already excluded (no storage, no parameter, no event). Adding it later requires a new factory.
2. **`redeemInKindExcluding`** (and `InvalidSkipMask`): keep atomic `redeemInKind`.
3. **`depositInKind` and `previewDepositInKind`** (and `DepositInKind`, `ExceedsMaxWeight`): in-kind deposit goes before in-kind redeem; `redeemInKind` is never dropped.
4. **`OracleDesk` inventory mode and the Live universe** (E4): Sandbox only.
5. **`quoteRedeem` and `previewRedeemInKind`**: frontend uses `previewRedeem` with a 0.5 percent extra tolerance.
6. **`FengAggregator.shockAnswer`/`SHOCK_ROLE`**: the demo script uses `forceAnswer` with the deployer key instead.
7. **Registry `updateMeta` and `getStrategies` pagination**, and the engine's `checkUpkeepRange`.
8. **`FengFaucet` contract**: fall back to the E10-T1 V1 path (server wallet tops up from a pre-funded balance).

**Minimum viable V2 (never cut)**: `FengAggregator` (updater role, deviation bound, `refresh`), `ChainlinkPriceOracleV2` (`isSupported`), `OracleDesk` mint mode with the registry gate and 10 bps spread, `StrategyTokenV2` with `burnFrom`, `StrategyVaultV2` with `deposit` on measured value delta, `redeem` pro-rata, `redeemInKind`, previews, `totalAssetsUSDG` including idle, `sharePrice`, sells-before-buys rebalance with effective threshold, `NavCheckpoint` plus rate-limited `checkpoint`, guardian pause (deposit and rebalance only), approval resets, reentrancy guards, decimals handling at 6 and 18, `StrategyFactoryV2` with `maxSlippageBps`, `MarketplaceRegistryV2` with creation-time meta, `RebalanceEngineV2` (`checkUpkeep`, `performRebalance`, `checkpoint`), `MockUSDGV2`, `DeployV2`, `SeedV2`, `sync-abi.sh`, and tests I1, I2, I5, I6, I8, I10, I11 plus the decimals matrix for `d` in {6, 18}.

### 7.4 Hand-off checklist

- `GP/contracts`: build section 2 exactly, record the V1 checksums first (3.3), report sizes and gas against 3.2 and 3.5.
- `GP/tests`: write section 4 from this spec before reading the implementation; use the integer vectors in 1.8.
- `GP/review`: review against section 1 (each C-xx finding has a regression test named in 4.4) and against the I1 to I11 mapping; no open High or Critical before G1.
- `work:frontend` and `GP/ops`: build against section 5; consume `src/lib/abi/generated/**` and `deployments/robinhood-testnet-v2/addresses.json` only.
- `GP/deploy`: run `scripts/deploy-v2.sh` after G1 using section 6.
