# V2 review (E8-T3)

- **Reviewer**: independent security reviewer (did not write the code), 2026-10-03. Method: `docs/security/review-checklist-v2.md` followed in order, plus the extra hunt of the dispatch.
- **Verdict for G1: PASS WITH CONDITIONS. No open Critical. No open High.** The conditions are listed in "Conditions to close G1" (five Medium test gaps to fix or accept, three Medium design residuals that the coordinator already decided to accept).
- Repository untouched except `docs/security/review-v2.md` and `docs/security/poc-v2/**`. Builds and tests used `FOUNDRY_OUT` and `FOUNDRY_CACHE_PATH` in the scratchpad. No `.env*` read, no key, no network transaction, no install, no commit, ports 3000/3001 untouched.
- Final suite on the unmodified tree: `forge test --match-path "contracts/test/v2/**"`: **486 passed, 0 failed, 0 skipped (34 suites)**. (First run of the session showed 474: the test agent added `unit/Coverage.t.sol` while the review ran. The previously known failure `test_gas_executeRebalanceAllLegs` passes now.)

## Scope (sha256, first 16 hex of each reviewed file)

```
1f91b9960e0c16fd contracts/v2/MarketplaceRegistryV2.sol     b8ade4be5b8f8520 contracts/v2/faucet/FengFaucet.sol
6a26e5e235271642 contracts/v2/RebalanceEngineV2.sol         cabb12a1dd25e450 contracts/v2/oracle/ChainlinkPriceOracleV2.sol
f7121b4c2fdd120d contracts/v2/StrategyFactoryV2.sol         59bf0aab61d70779 contracts/v2/oracle/FengAggregator.sol
b3afb20c8e182626 contracts/v2/StrategyLens.sol              9ca350f8d3b06c65 contracts/v2/venue/OracleDesk.sol
b14949d40f5b520e contracts/v2/StrategyTokenV2.sol           a487f6b191f4b2b3 contracts/v2/mocks/MockUSDGV2.sol
17312522baf83ef5 contracts/v2/StrategyVaultV2.sol           ec780807c58b70d9 script/DeployV2.s.sol
a33ae8a71f7da260 contracts/v2/VaultDeployerV2.sol           54fd1c263a6cb0bd script/SeedV2.s.sol
0c52c6f26d7bbdeb scripts/deploy-v2.sh
dad1494da92e852d script/DeployLive.s.sol   0e4e64b0712b42c0 script/SeedLive.s.sol   (appeared during the review, read lightly, see R-V2-22)
```

Interfaces under `contracts/v2/interfaces/**` and all of `contracts/test/v2/**` were read and executed. Any later change to a hashed file invalidates this verdict for that file.

## Findings

Severity rubric from the checklist (section 9). "Fix" is the minimal change. PoC files are in `docs/security/poc-v2/` (`Review.t.sol`, `Killers.t.sol`; they import `../v2/helpers/DeployV2Helper.sol`, so run them from `contracts/test/v2r/` of a scratch copy, never inside the repo test tree).

| ID | Sev | Row | File:line | Description | Proof | Fix | Status |
|---|---|---|---|---|---|---|---|
| R-V2-01 | Medium (F-01) | X-01, C-21 | `oracle/FengAggregator.sol:51-59` | `updateAnswer` bounds each push against the anchor, then moves the anchor to the new answer. No time or cumulative limit, so a holder of `UPDATER_ROLE` walks the price `1.15^n` in one block. | `Review.t.sol::PoC_Walk.test_X01_walkWithinOneBlock`: 10 pushes in one block, price x4.04 (deviation 1500). | 7-line "anchor window" in `docs/security/poc-v2/F01-anchor-window.patch`: the anchor may only move once per `ANCHOR_WINDOW` (1 hour); inside the window every answer stays within `maxDeviationBps` of the same anchor. Verified: the same PoC now reverts `DeviationTooHigh` on the second push; no new external function. Costs: two existing unit tests need a `vm.warp(1 hours)` between steps (`test_updateAnswer_withinBound`, `test_shock_thenRestore`), the invariant handler's `pushPrice` moves the price less often (suite still green), ops cannot follow a move above `maxDeviationBps` inside one hour except through `shockAnswer` or `forceAnswer`. | OPEN, ACCEPTED by coordinator. Mitigation exists (under 20 lines, verified); recommend adopting it before the demo if the +18 percent two-step script is changed to the shock path or spaced 1 hour. |
| R-V2-02 | Medium (F-02) | X-02 | `script/DeployV2.s.sol:173-186`, `venue/OracleDesk.sol:225-228` | The sandbox desk is deployed with `maxSwapUsdg == 0`, which means unlimited. One transaction can trade the whole reserve at a walked price. The Live deploy does set a cap (25 USDG per swap, `DeployLive.s.sol:107,151`). | `Review.t.sol::PoC_Walk.test_F02_relayerDrainsDeskReserveInOneTx`: the relayer deposits 10,000 USDG, walks TSLA x4, redeems, ends with 25,177.38 USDG; desk reserve loses 15,177.38 USDG in one tx. | (a) one line in `_deployDesk`: `desk.setMaxSwapUsdg(<per-swap cap>)`. (b) optional in-contract hourly outflow cap, 15 lines, `docs/security/poc-v2/F02-window-cap.patch`: sell-side USDG outflow per hour at most `10 * maxSwapUsdg`, no new function (reuses `setMaxSwapUsdg`); compiles, 486 tests still green, needs one new test (not written). It does not bound token-inventory outflow in `Inventory` mode. | OPEN, ACCEPTED by coordinator. Reserve is the maximum loss; state it in the README. |
| R-V2-03 | Medium | X-02, X-14 | `script/DeployLive.s.sol:133-135,151` | The Live desk (real Paxos USDG reserve, real stock tokens in inventory) prices through the shared `ChainlinkPriceOracleV2`, and `_deploy` points the real token addresses at the sandbox `FengAggregator` feeds. The relayer key that can walk the sandbox feeds therefore also moves Live prices. Only brake: per-swap cap 25 USDG (`DEFAULT_MAX_SWAP_WHOLE_USDG`), which does not limit the number of swaps in one transaction. | Read; follows from R-V2-01 plus the two lines above. | Document it in the README and RUNBOOK; adopt R-V2-01 mitigation; optionally use the R-V2-02(b) window cap on the Live desk (the cap value is already set there). | OPEN, decision needed from coordinator (testnet tokens, so no real-value loss, but the "Live" label implies a stronger guarantee). |
| R-V2-04 | Medium (test gap) | C-09, M-13 | `contracts/test/v2/unit/VaultV2Base.sol:636-650` | Mutant M-13 (parent `_checkAllFresh` ignores strategy-token children) survives all 486 tests. `test_nested_staleChildBlocksParent` uses `expectPartialRevert(StalePrice)`, which the child's own check satisfies when the parent calls `child.deposit`. The vault code is correct; the test does not prove it. | `mut-results`: M-13 survived at 64 fuzz runs and again in an isolated build. | Add `Killers.t.sol::test_K1_parentCheckpointRevertsOnStaleChild` (parent `checkpoint()` with a stale child must revert `StalePrice(childToken, T0)`): passes on the real code, kills M-13 (verified). | OPEN, fix the test. |
| R-V2-05 | Medium (test gap) | C-23, M-06 | `StrategyVaultV2.sol:439` | Mutant M-06 (delete `forceApprove(venue, 0)` in `_swap`) survives. `HostileVenue` always pulls the full `amountIn`, so no test ever leaves a residual allowance. `invariant_noOpenApprovals` cannot see it either. | Isolated run: 486 passed with the line deleted. | Add `Killers.t.sol::test_K2_partialPullLeavesNoAllowance` (a venue that pulls half; assert `allowance(vault, venue) == 0`): passes on real code, kills M-06 (verified). | OPEN, fix the test. |
| R-V2-06 | Medium (test gap) | spec 2.3, M-09 | `venue/OracleDesk.sol:214-215` | Mutant M-09 (`priceBuy` Floor instead of Ceil) and E14 (`priceSell` Ceil instead of Floor) survive. With 8-decimal feeds the 18-decimal price is a multiple of 1e10, so `p * (BPS +- s) / BPS` is exact and the rounding direction is never exercised. Latent for a feed whose answer is not a multiple of 10000 at 18 decimals. | Isolated runs, both survive. | Add `Killers.t.sol::test_K3_deskBuyPriceRoundsUpWithOddPrice` (feed with 18 decimals and an odd answer, compare `quoteExactIn` with an independent ceil): passes on real code, kills M-09 (verified). Add the sell mirror. | OPEN, fix the test. |
| R-V2-07 | Medium (test gap) | C-29, D4, E10 | `StrategyVaultV2.sol:431-432` | Mutant E10 (remove `_atLeast(got, minOut)` after the sell leg in `_sell`) survives. The venue enforces `minAmountOut` itself; the vault check is defence in depth against a short-delivering venue and is untested on the sell side. | Mutant run. | Add a `HostileVenue` test: sell leg with `shortBps` above the tolerance must revert `SlippageExceeded` in `redeem` (not only in rebalance). | OPEN, fix the test. |
| R-V2-08 | Medium (test gap) | C-30, E15 | `StrategyVaultV2.sol:157` | Mutant E15 (idle-USDG slice of `redeem` rounded Ceil instead of Floor) survives: `invariant_redeemNeverAboveNav` allows `+8` slack and `test_redeem_equalsQuoteWithinDust` is tolerant, so a rounding direction flip that pays the redeemer 1 unit extra per call is invisible. Economically harmless (1 unit per call, gas cost far higher) but the direction claim of C-30 is not enforced. | Mutant run. | Add `Killers.t.sol::test_K4_redeemIdleSliceRoundsDown` (idle-only vault, redeem `S/3`, assert `out == mulDiv(idle, sh, S)` exactly): passes on real code, kills E15 (verified). | OPEN, fix the test. |
| R-V2-09 | Low | C-15, I4 | `StrategyVaultV2.sol:513-519` | `_flags` raises `thresholdBased` when a weight exceeds `effectiveMax`, but `_sellPass` only trades above `target + tolerance`. For a vault below about 10 USDG (tolerance is at least `MIN_LEG_USDG`) the flag stays true after `executeRebalance` with no trade possible: `rebalanceNeeded()` is true forever, the keeper re-runs it every tick, each run emits events and resets timestamps. | `PoC_Misc.test_dustVaultPerpetualFlag`: 2 USDG vault, TSLA +1 percent, flag still 1 after `executeRebalance`. | `docs/security/poc-v2/R08-R09-flags.patch` (4 lines): add `&& cur[i] > (total * target)/BPS + tol` to the flag. Verified: flag clears, 486 tests green; costs +128 bytes (vault runtime 16,818, initcode 23,505, deployer runtime 24,135, margin 441 under 24,576). Alternative: ops filter by minimum NAV (already F-08). | OPEN, fix or accept. |
| R-V2-10 | Low | C-16 | `StrategyVaultV2.sol:515` | A vault with `supply == 0` and a donated token balance reports `thresholdBased == true` and `executeRebalance` executes. The spec says an empty vault is never "needed". The existing test only covers `total == 0`. | `PoC_Misc.test_emptyVaultDonationFlag`. | Same patch as R-V2-09: `if (total == 0 || supply == 0) return (timeBased, false);`. Verified. | OPEN, fix or accept. |
| R-V2-11 | Low | X-08, F-13 | `oracle/ChainlinkPriceOracleV2.sol:465-472`, `venue/OracleDesk.sol:211`, `StrategyVaultV2.sol:503` | The oracle accepts any `updatedAt`. A future `updatedAt` passes the vault freshness check, then the desk reverts with `Panic(0x11)` (`block.timestamp - updatedAt`); a near-`uint256.max` `updatedAt` overflows `updatedAt + maxPriceStaleness` in `_checkAllFresh`. `setFeed` does not require code at the feed. Only reachable through an owner-set feed (the `FengAggregator` always stamps `block.timestamp`), so latent. Zero, negative and 30-decimal answers behave correctly (revert `InvalidPrice`, scale down). | `PoC_Oracle.test_X08_futureUpdatedAt` (priceStatus fresh, deposit reverts `0x4e487b71...11`), `test_X08_maxUpdatedAt`, `test_X08_decimals30`, `test_X08_zeroAndNegative`. | In `getPrice`: `if (updatedAt_ > block.timestamp) revert InvalidPrice(token);`; in `setFeed`: `require feed.code.length > 0` as a custom error. | OPEN, fix or accept. |
| R-V2-12 | Low | G-02 | `RebalanceEngineV2.sol:14`, `MarketplaceRegistryV2.sol:28` | Two revert strings (`require(..., "zero registry")`, `"zero admin"`) against the custom-errors-only convention. | `rg 'require\(\|revert\("' contracts/v2` | Replace with `if (x == address(0)) revert ZeroAddress();` (declare the error in the interface). | OPEN, trivial. |
| R-V2-13 | Low (F-04) | X-04 | `script/DeployV2.s.sol:31-32,100` | Default faucet funding 0.004 ETH at 0.0002 ETH per claim pays 20 claims; `dailyCap` is 40, so the cap is never reached and `FaucetEmpty` fires after 20 claims. | Arithmetic. | Default `FAUCET_ETH_FUND_WEI` to `dailyCap * ethPerClaim` (0.008 ETH) or lower `DEFAULT_FAUCET_DAILY_CAP` to 20. | OPEN, ACCEPTED by coordinator; one-line script change recommended. |
| R-V2-14 | Low (F-09) | X-03, X-15 | `script/DeployV2.s.sol:116-210` | One deployer key keeps `DEFAULT_ADMIN_ROLE` or ownership of the registry, oracle, desk, every feed, MockUSDG (also `MINTER_ROLE`), faucet and the stock tokens; guardian and relayer and dispenser default to the same key when the env variables are unset. The script never transfers or renounces. | Read. | Require distinct `GUARDIAN_ADDRESS` and `RELAYER_ADDRESS` in the script (revert if equal to the deployer on `robinhood-testnet`) and state the single-admin model in the README. | OPEN, documentation. |
| R-V2-15 | Low | X-10, F-08 | `RebalanceEngineV2.sol:9,19` | `checkUpkeep()` scans 200 vaults; measured 6.64M gas for 200 empty two-asset vaults. Populated six-asset or depth-2 vaults cost several times more and can exceed a public RPC `eth_call` gas cap. `getAllStrategies()` is unbounded. | `PoC_Misc.test_X10_250VaultsKeeper` (205 vaults: no revert, 6,636,830 gas). | Ops must page with `checkUpkeepRange(offset, 25..50)` and never call `getAllStrategies()` in the UI or keeper. | OPEN, ops note. |
| R-V2-16 | Low | G-11 | `scripts/fund.sh:34,38`, `scripts/keeper.sh:54`, `scripts/refresh-feeds.sh:35` | `--private-key "$KEY"` puts the key in argv (visible in `ps`). Pre-existing V1/ops scripts, not the V2 deploy path (`deploy-v2.sh` and the Forge scripts use `vm.envUint`, and no script echoes a secret). | `rg -- '--private-key' scripts`. | Use `cast ... --private-key` only through an env-fed wallet (`ETH_PRIVATE_KEY` env var supported by cast) or a keystore. | OPEN, accept for testnet. |
| R-V2-17 | Info | C-18, D5 | `StrategyVaultV2.sol:421-425` | A `redeem` whose total share value is about 2.000 to 2.002 units (6 decimals: about 0.000002 USDG) reverts `ZeroAmount`: the vault's oracle value of a leg is 1 unit, the desk output after the 10 bps spread floors to 0. `redeemInKind` is the exit; no value at risk. | `Killers.t.sol::DustWindow` (39 of 40 consecutive dust sizes revert). | None needed; the UI can enforce a minimum redeem. | ACCEPT. |
| R-V2-18 | Info | C-07 | `StrategyFactoryV2.sol:132` | `NestedTokenNotLeaf` is dead code: `childDepth >= MAX_DEPTH` at line 128 already rejects any child that holds a strategy token (E12 survives as an equivalent mutant). | Mutant E12. | Keep (defence in depth) or remove to save bytes. | ACCEPT. |
| R-V2-19 | Info (F-06) | X-07 | `StrategyVaultV2.sol:444-446` | `ChildRedeemFailed(childToken, bytes reason)` copies the whole child revert data. The child is trusted factory-built vault code, so the payload is bounded. | Read. | None. | ACCEPT. |
| R-V2-20 | Info | C-31, C-24, P-12 | various | Declared deviations verified: `quoteRedeem` and `previewRedeemInKind` live in `StrategyLens` (stateless, view-only, no storage, not under `nonReentrantView`); extra public `MIN_LEG_USDG` and `VIRTUAL_SHARES`; OZ `EnforcedPause`, `ExpectedPause`, `ReentrancyGuardReentrantCall`, `SafeERC20FailedOperation`, `Paused`, `Unpaused` in the ABI; factory `ZeroAddress`. Deployer runtime 24,007 bytes (spec 24,000, EIP-170 limit 24,576, margin 569): any vault growth above about 550 bytes breaks the deployer. Four spec test names do not exist literally (`test_rawUsdgDonation_doesNotAffectNav` and `test_depth2_redeem_returnsInnerStrategyTokenUnits` are the superseded V1 names; `test_redeemInKind_childSharesNotUnwound` is `test_nested_redeemInKind_childSharesNotUnwound`; `test_redeemInKindExcluding_skipsFrozenToken` is `..._skipsSliceAndIdle` plus `test_frozenVault_...`). `invariant_paused_redeemStillWorks` is not a separate invariant; it is covered by the `chaos` pause mode and `ghost_redeemPaused` in I5 and by `test_redeem_neverPaused`. | `forge inspect` ABI diff. | None. | ACCEPT. |
| R-V2-21 | Info (F-03, F-11) | C-21 | `oracle/FengAggregator.sol:61-63,76-81` | `forceAnswer` is unbounded by design (admin). `refresh()` re-stamps a shocked answer. No `getRoundData`. `ENABLE_SHOCK` defaults to off (`DeployV2.s.sol:99`); when on, the relayer holds a +/-30 percent lever from the anchor. | Read. | None beyond F-03 advice. | ACCEPT. |
| R-V2-22 | Info | scope | `script/DeployLive.s.sol`, `script/SeedLive.s.sol`, `scripts/deploy-v2.sh` | The Live scripts were not in the input list and appeared mid-review. Read lightly: preflight asserts `decimals() == 6` for USDG and `uiMultiplier() == 1e18` per token (X-13 pass), desk uses `Inventory` mode, no secrets printed, `maxSwapUsdg` set. Not audited line by line. See R-V2-03. | Read. | Second pass if Live ships. | NOT FULLY REVIEWED. |
| R-V2-23 | Info | P-06 | V1 files | `forge fmt --check` fails on three V1 files only (`contracts/MarketplaceRegistry.sol`, `contracts/test/ChainlinkPriceOracle.t.sol`, `script/Deploy.s.sol`); every V2 file is clean. V1 sources must stay byte-identical (P-01), so do not format them. | `forge fmt --check`. | None. | ACCEPT. |

No Critical and no High were found. The paths the rubric names as High (exit blocked under stale feeds, empty desk or pause; share minting without value; theft through the first-depositor or donation route; reentrancy value extraction) were attacked and did not break (details under "What was attacked").

## Threat-model findings F-01 to F-13

| F | Status | Evidence |
|---|---|---|
| F-01 relayer walk | OPEN, ACCEPTED (coordinator). Cheaper in-contract mitigation exists: R-V2-01 patch, 7 lines, verified against the PoC. | PoC x4.04 in one block. |
| F-02 desk exposure | OPEN, ACCEPTED. Sandbox desk has no cap (R-V2-02); Live desk has a 25 USDG per-swap cap only. Optional 15-line hourly cap, compiled and regression-checked, not behaviour-tested. A fully closing in-contract fix does not exist within 20 lines. | PoC: 10,000 in, 25,177 out, 15,177 USDG taken from the reserve. |
| F-03 shock role | MITIGATED by default (`ENABLE_SHOCK` off, `shockEnabled` false). When enabled it is the same key as the relayer unless a separate address is set. | `DeployV2.s.sol:99,205-208`. |
| F-04 faucet funding | OPEN, ACCEPTED. 20 claims funded against a cap of 40 (R-V2-13). | arithmetic |
| F-05 staleness 12 h vs 6 h | DECISION PENDING. Both the factory and the desk take the same `cfg.maxPriceStaleness` (`DeployV2.s.sol:162,175`), default 43200, override `MAX_PRICE_STALENESS=21600`. Record the final value. | consistent in code |
| F-06 returndata copy | ACCEPTED (R-V2-19). | |
| F-07 permissionless deployer | OPEN, ACCEPTED. A direct `deploy(params)` call works and yields an unregistered vault that the desk refuses (`NotVault`); `test_vaultCreatedByStrangerIsNotRegistered`, `Review.t.sol::test_deployer_direct`. | |
| F-08 registry spam / keeper | PARTLY FIXED (`MAX_SCAN` 200, `checkUpkeepRange`, per-vault try/catch, `performRebalance` gate). Residual: R-V2-09, R-V2-15. | |
| F-09 single key | OPEN (R-V2-14). | |
| F-10 desk owner powers | ACCEPTED (trusted owner; every owner function emits an event: `SpreadSet`, `MaxSwapSet`, `ReserveFunded`, `ReserveWithdrawn`, `InventoryFunded`, `InventoryWithdrawn`, `TokenConfigured`). | |
| F-11 refresh pins shock | ACCEPTED (R-V2-21). | |
| F-12 naming drift | CLOSED: code and spec agree (`updateAnswer`, `setParams`); aggregator default `maxDeviationBps` 1000 is a declared deviation (periphery notes). | |
| F-13 oracle sanity | PARTLY FIXED (non-positive reverts, decimals above 18 scale down, `isSupported`, `priceDecimals`). Residual: R-V2-11. | |

## Conditions to close G1

1. Fix or explicitly accept R-V2-04 to R-V2-08 (five tests, killer tests already written and verified in `docs/security/poc-v2/Killers.t.sol`; they belong in `contracts/test/v2/**`, which this review does not edit).
2. Coordinator records the acceptance of R-V2-01, R-V2-02, R-V2-03 (F-01, F-02, Live shares the sandbox oracle) and the F-05 value.
3. Low items R-V2-09 to R-V2-16 fixed or listed in `docs/security/known-limitations.md`.

Recommended order if time is short: R-V2-01 patch (7 lines), R-V2-02(a) one-line cap, R-V2-09/10 patch (4 lines), the four killer tests. Re-run P-04 to P-09 after any vault change (deployer margin is 441 to 569 bytes).

## Checklist results

### Preflight and global gates

| Row | Result | Evidence |
|---|---|---|
| P-01 | PASS | `sha256sum -c docs/handoffs/v1-sources.sha256`: no line not OK. |
| P-02 | PASS | solc 0.8.24, evm paris, via_ir false, runs 200. |
| P-03 | PASS | deep: fuzz 1000, invariant 2000, depth 64, fail_on_revert true. |
| P-04 | PASS | `forge build --force`: clean, no warning from `contracts/v2`. |
| P-05 | PASS | runtime bytes: vault 16,690 (initcode 23,377), factory 5,619, deployer 24,007 (spec figure 24,000, 7 over, limit 24,576, margin 569), desk 8,378, faucet 3,120, lens 4,264. |
| P-06 | PASS for V2 | only three V1 files fail fmt (R-V2-23). |
| P-07 | PASS | V1 suite 48 passed, 0 failed. |
| P-08 | PASS | V2 suite 486 passed, 0 failed. |
| P-09 | PASS | deep invariants: `Invariant6Dec` and `Invariant18Dec` (13 invariants each, 2000 runs, depth 64, about 670 s each), `InflationAttackV2` four variants, `DepthCycleV2`: 26 passed. Deep fuzz: 32 passed (1000 runs). |
| P-10 | PASS | `forge coverage` on V2 (mocks, tests, scripts excluded), no `--ir-minimum` needed: lines 98.21 percent (1045/1064), statements 95.94, branches 84.70 (227/268), functions 100; lowest file branches 83.33 (`ChainlinkPriceOracleV2`). |
| P-11 | PASS | gas report maxima: deposit 996,026 (ceiling 1.8M), depositInKind 417,406 (600k), redeem 948,688 (1.8M), redeemInKind 366,355 (700k), executeRebalance 924,786 (2.2M), checkpoint 217,056 (300k), createStrategy 4,550,450 (6.5M), deployer deployment 5,213,710 (5.5M). |
| P-12 | PASS with naming notes | 4 names not literal, all explained in R-V2-20. |
| P-13 | PASS | ABI diff against spec: only the declared deviations (R-V2-20). |
| G-01 | PASS | no pragma other than `^0.8.24`. |
| G-02 | FAIL (Low) | R-V2-12. |
| G-03 | PASS | no `block.number`, `blockhash`, `prevrandao`, `difficulty`. |
| G-04 | PASS | no address literal in `contracts/v2` or `script`; the Paxos USDG and the five token constants live in `scripts/deploy-v2.sh` defaults only. |
| G-05 | PASS | only hit: assembly `create` in `VaultDeployerV2.sol:11` (reviewed, see below) and the two bounded `.call{value}` in the faucet (`FengFaucet.sol:53,71`, checked, `nonReentrant`). No `tx.origin`, `selfdestruct`, `delegatecall`, `ecrecover`, `.send`, `unchecked`. |
| G-06 | PASS | no code comments in `contracts/v2`. |
| G-07 | PASS | no raw `transfer`, `transferFrom`, `approve` in `contracts/v2`; `using SafeERC20` in vault and desk (the faucet moves no ERC-20, it calls `mint`). |
| G-08 | PASS | only `type(uint256).max` is the min-tracker start at `StrategyVaultV2.sol:249`. |
| G-09 | PASS | mutating ABI: `checkpoint deposit depositInKind executeRebalance pause redeem redeemInKind redeemInKindExcluding unpause`; all `nonReentrant` except guardian-only `pause`/`unpause`; every balance-reading view has `nonReentrantView` (`previewDeposit`, `previewDepositInKind`, `previewRedeem`, `totalAssetsUSDG`, `sharePrice`, `weights`, `rebalanceNeeded`). |
| G-10 | PASS | no transient storage. |
| G-11 | PASS with Low | no `set -x`, `printenv`, `.env` access, or echo of a secret; `--private-key` in argv in three V1/ops scripts (R-V2-16). |
| G-12 | PASS | 64-hex hits only in docs (transaction hashes, pool ids, constructor arguments, checked by context with values masked) and the public Anvil key in `dev/fixture/script/Deploy.s.sol` (count 1). |
| G-13 | PASS | no `console2.log` of a key or secret. |
| G-14 | PASS | `.gitignore:42` `.env*`. |
| G-15 | PASS | every privileged function listed in X-15 below. |

### Spec findings C-01 to C-36

| Row | Result | Evidence |
|---|---|---|
| C-01 | PASS | NAV adds idle USDG at `StrategyVaultV2.sol:532`; redeem is physical pro-rata at 154-169 (`S0` read before burn); V1 payout shape grep empty; `invariant_I1`; `test_redeem_lastHolderDrainsEverything`. |
| C-02 | PASS | `:481` passes `msg.sender` as spender; token `_spendAllowance` then `_burn` (`StrategyTokenV2.sol:29-32`); M-02 killed by both named tests. |
| C-03 | PASS | `_scale` 553-555 and `_valueOf` 539-547 are the only unit conversions; exact vectors d6 and d18; four decimal cells exist (`VaultV2_U6_S8`, `U6_S18`, `U18_S8`, `U18_S18`). |
| C-04 | PASS | `:89` `VIRTUAL_SHARES = 10 ** (d >= 6 ? 12 : 18 - d)` equals `10 ** max(18-d, 12)` for all d; `VIRTUAL_ASSETS = 1` (`:34`); inception 1e6 units at d=6 and d=18; M-05 killed by 12 tests. |
| C-05 | PASS | V1 test not carried; V2 property is "donation never profits the donor" (`InflationAttackV2`, PoC below). |
| C-06 | PASS | no `grantRole`, `hasRole`, `IAccessControl` in factory, deployer, vault, engine; registry only `_grantRole(DEFAULT_ADMIN_ROLE)` in its constructor; `test_noGrantRoleCallsOnConstituents`, `test_realTokenWithoutMinterRoleAccepted`. |
| C-07 | PASS | `StrategyFactoryV2.sol:14-19` values 2, 6, 100, 500, 1 h, 365 d; name 1-48 and symbol 2-10 at 67-68; `isSupported` on oracle and venue at 118; every error in spec 2.7 is referenced by a test; duplicate O(n^2) at 106-108 (E5 killed). |
| C-08 | PASS | oracle V2 `isSupported`, `priceDecimals`, `removeFeed`, `InvalidPrice`; V1 oracle checksum OK. See R-V2-11 for the input-sanity residual. |
| C-09 | PASS (code), test weak | vault 252-260 (`priceStatus` try/catch recursion) and 496-506 (`_checkAllFresh` calls `child.priceStatus()`); M-13 survives (R-V2-04). |
| C-10 | PASS (accepted deviation D1) | `StrategyLens.quoteRedeem` recurses into child vaults (`:348`), no storage, view only, no `nonReentrantView` (nothing on chain consumes it). |
| C-11 | PASS | `:179-185`, `:347-368`; mask bits above `n` revert `InvalidSkipMask` (E3 killed); arrays end with USDG; forfeited slices stay in the vault. |
| C-12 | PASS | OZ `Pausable`; `whenNotPaused` only at 100, 124, 292; redeem paths and `checkpoint` ungated; M-07 killed. |
| C-13 | PASS | `IStrategyVaultV2.sol:37` indexed timestamp. |
| C-14 | PASS | event diff vs spec: only OZ `Paused`/`Unpaused`; `test_rebalance_emitsCheckpointThenRebalanced`. |
| C-15 | PASS | `_effectiveMax` 526-528 is `min(10000, max(maxWeightBps, target+10))`; M-14 killed. Residual dust loop: R-V2-09. |
| C-16 | PASS for the spec test, gap found | R-V2-10. |
| C-17 | PASS | sell pass then buy pass at 301-302; M-15 killed. |
| C-18 | PASS | `_redeemChild` 442-447 wraps `ChildRedeemFailed`; nested tests present. |
| C-19 | PASS | engine `MAX_SCAN` 9, gate 27, try/catch 37-39 and 49-51; E4 killed. |
| C-20 | PASS | no `block.number`; `registerStrategy` only `FACTORY_ROLE` (:34); creator-only `updateMeta` (:52, E6 killed); description at most 160, at most 3 tags of at most 16 bytes, charset `[a-z0-9-]`, duplicates rejected (:112-124); pagination clamp (:62-68). Revert string at `:28` (R-V2-12). |
| C-21 | PASS | six `onlyRole` in the aggregator (`updateAnswer`, `refresh`, `shockAnswer`, `forceAnswer`, `setParams`, `setShockEnabled`); no `updateRoundData`; `_updatedAt` assigned only `block.timestamp` (constructor and `_push`); `<=` bound; M-11a and M-11b killed. Per-update-only bound is R-V2-01. |
| C-22 | PASS | `getPrice` called only for constituents (`:262`, `:574`). |
| C-23 | PASS (code), test weak | `forceApprove(x, a)` then `forceApprove(x, 0)` at 409-411 and 437-439; desk has no approvals; M-06 survives (R-V2-05). |
| C-24 | PASS | sizes P-05; `via_ir` false; constructor takes `VaultParams memory`. |
| C-25 | PASS | `decimals() <= 18` checks at vault 65 and 73, factory 46, desk constructor and `setToken`. |
| C-26 | PASS | child paused blocks parent deposit and rebalance, not parent redeem: `test_pause_*`, `test_nested_*`. |
| C-27 | PASS | `_guardWeight` (E1 killed), USDG reverts, empty desk works, value at oracle. |
| C-28 | PASS (accepted risk) | handler `donate`; donor loses (PoC). |
| C-29 | PASS (code), sell check untested | measured deltas at 485-489 (`_pull`), 416-417 (`_buy`), 431-432 (`_sell`); returned `amountOut` never credited (`rgn amountOut` shows only the interface); every desk `_pull` call site passes `msg.sender` (`OracleDesk.sol:81,93,151,168`); M-12 killed; E10 survives (R-V2-07). |
| C-30 | PASS (code), E15 survives | `nb` Ceil via `_values(cs, true)` before the pull (`:107`), `na` Floor after (`:113`), shares Floor via `Math.mulDiv`; M-01 killed (R-V2-08 for the redeem side). |
| C-31 | PASS | `struct Constituent` only in `contracts/interfaces/IStrategyVault.sol`; ABI as R-V2-20. |
| C-32 | PASS | gate at `OracleDesk.sol:72`, `quoteExactIn` ungated; M-08 killed. |
| C-33 | PASS, decision open | R-V2 F-05 above. |
| C-34 | PASS | `executeRebalance` and `checkpoint` carry only `nonReentrant` (+ `whenNotPaused` on the first). |
| C-35 | PASS | pagination clamp; keeper must use `checkUpkeepRange` (R-V2-15). |
| C-36 | PASS | `test_deposit_previewWithinTolerance`, `test_vector_depth2_derivedFromChild`. |

### Invariants I1 to I11

| Row | Result | Evidence |
|---|---|---|
| I1 | PASS | `invariant_I1_previewSumEqualsNav` against an independent NAV (`InvariantBase.sol:43,77`); default and deep green. |
| I2 | PASS | `invariant_I2_roundTrip`; deep green. Reviewer probe: my own fuzz (below) with a 1 unit first deposit and a large second deposit stays inside the bound. |
| I3 | PASS | `invariant_I3_sharePriceNeverDrops` (`S >= 1e18` guard, relative 1e-6 matches `VIRTUAL_SHARES / S`). |
| I4 | PASS | `invariant_I4_rebalanceCostBounded`; donation-then-rebalance covered by the handler `donate`. |
| I5 | PASS | `invariant_I5_inKindAlwaysWorks` with `chaos` modes stale, desk `Unsupported`, reserve withdrawn, feed removal and guardian pause toggles. |
| I6 | PASS | `invariant_I6_noMintWithoutValue`; `\.mint\(` appears only in `_issue` (called by `deposit` and `depositInKind`). |
| I7 | PASS | `DepthCycleV2`: depth 3, duplicates, self and ancestor, unknown token (fuzzed addresses); `vaultOf` is written after deployment (`StrategyFactoryV2.sol:90`), so a predicted vault-token address cannot be a constituent. M-10 killed. |
| I8 | PASS | `invariant_I8_deskAccounting` (equality without donations). |
| I9 | PASS | `Invariant6Dec` and `Invariant18Dec` share one base; my probes add d=0 and d=2. |
| I10 | PASS | one `test_reentrancy_*` per entry point (13 hostile calls each, all revert `ReentrancyGuardReentrantCall`); M-03 and M-04 killed. Reviewer probes: a hook that calls a sibling vault (5 attempts, 0 successes, share prices unchanged) and a hook that calls the desk (2 attempts, 0 successes) in `PoC_Misc.test_hookCallsSiblingAndDesk`. |
| I11 | PASS | `InflationAttackV2` four variants at default and deep. Reviewer fuzz `PoC_Inflation_U{0,2,6,18}`: attacker deposits 1..1e6 units, donates 0..5e7 USDG either as USDG or as TSLA, victim deposits 1..5e6 units; asserts the victim keeps at least `V` minus 25 bps minus one share's worth, and the attacker's claim is at most `a + donation` plus the same tolerance. 20,000 runs per test, 8 tests, 0 failures. |
| V-01 | PASS | 13 handler functions all called (about 300 calls each per 64-run sample), `ghost_unexpectedRevert` false; expected reverts about 22 percent of calls. |
| V-02 | PASS | handler and base recompute NAV from raw balances and oracle prices (`_independentNav`, `_valueOf`). |
| V-03 | PASS | only `vm.assume` is address filtering in `DepthCycleV2.t.sol:41-42`. |
| V-04 | PASS | `fail_on_revert` true; handler classifies selectors (`Handler.sol:113-145`). |
| V-05 | PASS | handler is the only `targetContract`; `targetSelector` list in `InvariantBase.sol:35`; nothing excluded. |

### Extra checks X-01 to X-17

| Row | Result | Evidence |
|---|---|---|
| X-01 | FAIL (F-01 open) | R-V2-01. |
| X-02 | FAIL (accepted) | R-V2-02, R-V2-03. |
| X-03 | PASS locally, D-checks not run | `FACTORY_ROLE` granted to the factory only (`DeployV2.s.sol:167`, Live factory `DeployLive.s.sol:158`); vaults hold no mint role; the desk holds `MINTER_ROLE` on the five mock stocks (`DeployV2.s.sol:179`). |
| X-04 | FAIL (Low) | R-V2-13. |
| X-05 | PASS | no `safeTransferFrom` with a non-`msg.sender` source except desk `_pull`, whose four call sites pass `msg.sender`. |
| X-06 | PASS | `test_vaultCreatedByStrangerIsNotRegistered`, M-08 killed. |
| X-07 | PASS (accepted) | R-V2-19. |
| X-08 | PARTIAL | R-V2-11. |
| X-09 | PASS | `PoC_Misc.test_X09_donateToChildNeverProfits`: donating 3,000 USDG to a child vault returns 10,311 to a 10,000 parent holder, less than 13,000 paid in plus donated. |
| X-10 | PASS with ops note | R-V2-15; no revert at 205 vaults. |
| X-11 | PASS | script writes (`script/*.s.sol`) hold addresses and numbers only (`DeployV2.s.sol:320`, `SeedV2.s.sol:61`, `DeployLive.s.sol:205`, `SeedLive.s.sol:74`). |
| X-12 | PASS | PoC fuzz at d=0 and d=2 (inflation, rounding, tolerance widened to 12 units for d<=2 because one unit is a dollar or a cent). `MIN_LEG_USDG` is `max(unit/100, 1)`. |
| X-13 | PASS | `DeployLive.s.sol:119-128`: decimals 6, `uiMultiplier == 1e18`, not paused, before any broadcast. |
| X-14 | PASS | the Paxos USDG address appears once, in `scripts/deploy-v2.sh`; the two decoy addresses appear nowhere; Live uses `Inventory`, sandbox uses `Mint`. |
| X-15 | PASS | privileged inventory below. |
| X-16 | NOT DONE | `src/ops/*` is outside this dispatch's input list. |
| X-17 | PASS | no `dangerouslySetInnerHTML` under `src`. |
| D-01 to D-08 | NOT APPLICABLE | no V2 broadcast yet. |

Privileged functions (all emit an event):

| Contract | Function | Caller | Effect |
|---|---|---|---|
| StrategyVaultV2 | `pause`, `unpause` | immutable `guardian` | stops `deposit`, `depositInKind`, `executeRebalance`; never redeem or checkpoint. OZ events. |
| MarketplaceRegistryV2 | `grantRole(FACTORY_ROLE)` | registry admin | allows registering vaults. |
| FengAggregator | `updateAnswer`, `refresh` | `UPDATER_ROLE` | price within `maxDeviationBps` of the anchor (R-V2-01). `AnswerUpdated`. |
| FengAggregator | `shockAnswer` | `SHOCK_ROLE`, only if `shockEnabled` | price within `maxShockBps` of the anchor. `AnswerShocked`. |
| FengAggregator | `forceAnswer`, `setParams`, `setShockEnabled` | admin | unbounded price, bounds (caps 5000), shock switch. `AnswerForced`, `ParamsSet`, `ShockEnabledSet`. |
| ChainlinkPriceOracleV2 | `setFeed`, `removeFeed` | owner | feed wiring. `FeedSet`, `FeedRemoved`. |
| OracleDesk | `setToken`, `setSpreadBps` (at most 100), `setMaxSwapUsdg`, `fundReserve`, `withdrawReserve`, `fundInventory`, `withdrawInventory` | owner | trusted (F-10). All emit. |
| FengFaucet | `claimFor` | `DISPENSER_ROLE` | one claim per address, `dailyCap`, EOA only. `Claimed`. |
| FengFaucet | `setParams`, `withdrawEth` | admin | `ParamsSet`, `EthWithdrawn`. |
| MockUSDGV2 | `mint` | `MINTER_ROLE` | sandbox money. |

### Mutation tests (reduced fuzz and invariant runs, then isolated rebuilds for survivors)

Checklist set (17 mutants: M-11 in two variants): **14 killed, 3 survived** (M-06, M-09, M-13).

| Mutant | Result | Killed by |
|---|---|---|
| M-01 nb Floor | killed | `testFuzz_sharesMatchIndependentFormula`, `testFuzz_previewDepositNeverBelowActualByMuch`, `test_deposit_previewWithinTolerance`, `test_vector_roundTrip_d6`, `test_vault_zeroReceiverAndTinyAmounts` (11 failures) |
| M-02 burnFrom spender | killed | both C-02 tests (8 failures) |
| M-03 no `nonReentrant` on redeem | killed | six `test_reentrancy_*` |
| M-04 no `nonReentrantView` | killed | six `test_reentrancy_*` |
| M-05 `VIRTUAL_SHARES = 1` at d=18 | killed | `test_inceptionSharePriceExact`, `InflationAttackV2` fuzz and model tests, vectors (12 failures) |
| M-06 drop approval reset | **SURVIVED** | none (R-V2-05); `Killers.test_K2` kills it |
| M-07 pause on redeem, off on deposit | killed | `test_redeem_neverPaused`, `test_deposit_revertsWhenPaused` |
| M-08 no desk gate | killed | `test_swap_onlyRegisteredVault`, `test_vaultCreatedByStrangerIsNotRegistered` |
| M-09 `priceBuy` Floor | **SURVIVED** | none (R-V2-06); `Killers.test_K3` kills it |
| M-10 `MAX_DEPTH = 3` | killed | `test_constants`, `test_chainOfNestedStrategies_neverExceedsMaxDepth` |
| M-11a `>=` bound | killed | `test_updateAnswer_withinBound` and two more |
| M-11b no role on `updateAnswer` | killed | `test_updateAnswer_roleGated` |
| M-12 credit `amount` not delta | killed | `test_deposit_feeOnTransferUsdgMintsFewerShares`, `test_deposit_feeUsdgNeverOvermints_fuzz` |
| M-13 skip child freshness | **SURVIVED** | none (R-V2-04); `Killers.test_K1` kills it |
| M-14 `effectiveMax = maxWeightBps` | killed | `test_rebalance_thresholdUsesEffectiveMax`, `test_maxWeightBand` |
| M-15 buy pass before sell pass | killed | `test_rebalance_sellsBeforeBuys` |
| M-16 no EOA check | killed | `test_contractRecipientRejected` |

Extra mutants chosen by the reviewer (16): killed E1 (`_guardWeight`), E2 (`NoValueAdded`), E3 (skip mask check), E4 (engine registry gate), E5 (duplicate check), E6 (creator-only `updateMeta`), E7 (`hasClaimed`), E8 (`shockEnabled`), E9 (desk `minAmountOut`), E11 (checkpoint rate limit), E16 (burn before reading supply, 52 failures), E17 (dust-leg skip). Survived: E10 (R-V2-07), E12 (equivalent, R-V2-18), E14 (R-V2-06), E15 (R-V2-08).

Proposed killer tests for the four real survivors are in `docs/security/poc-v2/Killers.t.sol` (`test_K1` to `test_K4`); each passes on the real code and fails on its mutant in an isolated build.

## What was attacked (beyond the checklist)

- **Share math, both directions, d = 0, 2, 6, 18**: 20,000-run fuzz with USDG and stock donations between a first deposit and a victim deposit; no profit above the tolerance, victim loss bounded by one share's worth plus spread. Rounding sides read line by line: deposit `nb` Ceil / `na` Floor / shares Floor, redeem Floor everywhere, desk buy price Ceil with output Floor, sell price Floor with output Floor. Virtual shares make a new depositor in a dust-sized vault receive up to `VIRTUAL_SHARES / S` too many shares (1e-6 relative at 1 USDG of supply at d=6); this is the documented I3 tolerance, costs the existing holders at most their own dust, and is dominated by the 20 bps round-trip spread whenever any leg is bought.
- **Reentrancy** through every token hook path: deposit, depositInKind, redeem, redeemInKind, redeemInKindExcluding, executeRebalance (existing suite), plus sibling-vault and desk targets (mine). Cross-vault hooks cannot read stale parent state in a profitable way (nb is read before the pull; a donation made in the hook to a child costs more than it gives, X-09). Desk swaps are guarded by the desk's own `nonReentrant`.
- **Approvals**: three reset sites, all exact; only the partial-pull path is untested (R-V2-05).
- **Nested deposit and redeem**: child legs go through `child.deposit` and `child.redeem(this, this)`; a failing child blocks the parent's deposit, rebalance and USDG redeem (documented T-13, C-26), never `redeemInKind`. Parent-child coupling through the desk lock is safe (hooks calling a sibling during a desk call revert on the desk guard).
- **Desk**: registry gate, reserve accounting (I8), Mint versus Inventory, spread rounding, drain by price manipulation (R-V2-01/02/03). Owner-only funding and withdrawal.
- **Aggregator**: role gating (6 functions), bound arithmetic (`int256` subtraction of two positives cannot overflow; `uint80` round counter), non-positive answers, shock path (anchor never moves on shock, restore works), refresh (R-V2-21).
- **Factory, registry, engine**: constituent validation order, duplicate and depth/cycle rules, immutables, metadata bounds, pagination, per-vault try/catch; spam is paid in gas (about 4.5M per vault).
- **Faucet**: effects before interaction, `nonReentrant`, EOA check (a contract under construction has no code at claim time but cannot call back because the dispenser, not the recipient, initiates the call), once per address, daily cap, dispenser role. EIP-7702 delegated accounts have code and are rejected (UX only).
- **VaultDeployerV2 assembly create**: the calldata tail of `deploy(VaultParams)` is byte-identical to the constructor argument encoding of one dynamic struct; a zero result reverts with the constructor's returndata (`EmptyConstituents`, `WeightsMustSumTo10000` bubble, malformed calldata and an empty payload revert); trailing junk is ignored; the returned token equals `vault.token()`; deployed vaults are unregistered. Initcode (24,039) and runtime (24,007) sizes are within EIP-170 and EIP-3860.
- **StrategyLens**: no storage, view only; reverts where the desk quote reverts (stale, cap, zero output).

## Not done / tooling gaps

- Static analysis not run: Slither, Aderyn, Echidna, Medusa and Halmos are not installed. **Request to coordinator**: install Slither and Aderyn (and optionally Echidna or Medusa for a stateful run independent of Foundry) in a scratch environment, or authorise the reviewer to do it.
- Section 7 post-deploy checks D-01 to D-08 (no deploy yet), X-16 (`src/ops`), `DeployLive` and `SeedLive` line-by-line (R-V2-22), the frontend (only the `dangerouslySetInnerHTML` grep).
- The mutation survivors were found with 64 fuzz runs and 32 invariant runs for the first pass; each survivor was re-run in an isolated build at the same reduced setting and confirmed with a targeted killer test, not with the full 256/256 profile.

## Open risks accepted (for the README)

1. A stolen or malicious relayer key can set any price within a few blocks (F-01); the desk reserve is the maximum loss on the sandbox desk, and the Live desk inherits the sandbox feeds (R-V2-03).
2. The desk owner, registry admin, oracle owner, aggregator admin, faucet admin and the guardian are one deployer key unless the environment separates them (F-09).
3. A depth-2 vault depends on its children for deposit, rebalance and USDG redeem; `redeemInKind` is the always-available exit.
4. Dust-sized vaults (below about 10 USDG) can show a perpetual rebalance flag (R-V2-09) and a USDG redeem of about two units can revert (R-V2-17).
5. `VaultDeployerV2` has 441 to 569 bytes of size margin; the vault cannot grow much without a restructure.
6. No third-party audit and no static analysis tool run; this review, the independent tests and the mutation results stand in for them.

---

# Pass 2 (independent re-review, gating G1)

- **Reviewer**: second independent adversarial pass, 2026-10-04. Repository untouched except this file and `docs/security/poc-v2/Pass2.t.sol`. Builds, tests and mutants ran with `FOUNDRY_OUT` and `FOUNDRY_CACHE_PATH` in the scratchpad and a scratch copy of the tree (`<scratchpad>/r2/repo`). No `.env*` read, no key used (only the public Anvil default key against an in-memory EVM), no network transaction, no install, no commit, ports 3000/3001 untouched.
- **Verdict for G1: PASS, no open High or Critical.** Open items are Medium or lower and listed below. The five pass-1 test gaps are closed, the pass-1 patches for R-V2-01, 02(a), 09, 10, 12, 13 are in the tree and verified. Residual Mediums (R-V2-24 plus the carried R-V2-02, R-V2-03) need the coordinator's recorded acceptance, nothing blocks on code.

## Runs

| Command | Result |
|---|---|
| `forge test --match-path "contracts/test/v2/**"` | **533 passed, 0 failed, 0 skipped (41 suites)** (pass 1: 486) |
| `forge test --no-match-path "contracts/test/v2/**"` (V1) | **48 passed, 0 failed** (8 suites) |
| `sha256sum -c docs/handoffs/v1-sources.sha256` | all OK, V1 sources byte-identical |
| `forge build --sizes` | VaultDeployerV2 runtime **24,135** bytes, initcode 24,167, margin **441** under 24,576 (was 24,135 in the pass-1 patch estimate, matches); StrategyVaultV2 16,818 (init 23,505); FengAggregator 3,744; OracleDesk 8,378; StrategyFactoryV2 5,619; FengFaucet 3,120; StrategyLens 4,264 |
| Global greps G-01..G-08, G-10, G-11, G-13, G-14 | G-01, 02, 03, 04, 06, 07, 10, 13 empty or as expected. G-02 is now clean (R-V2-12 fixed). G-05: only `VaultDeployerV2.sol:11` assembly and the two bounded faucet `.call{value}`. G-08: only the `type(uint256).max` min-tracker. G-11: only `--private-key` in `fund.sh`, `keeper.sh`, `refresh-feeds.sh`, `demo-shock.sh` (argv, accepted for testnet), no `set -x`, no echo of a secret. G-14 `.gitignore:42 .env*`. |
| G-12 secret scan | hits only in docs (transaction hashes, a grep pattern in `BASELINE-2026-10-03.md`, pool ids) and the public Anvil key in `dev/fixture` (count 1). Values masked, nothing echoed. |
| X-17 `dangerouslySetInnerHTML` under `src` | none |
| New PoC `poc-v2/Pass2.t.sol` (scratch copy, `contracts/test/v2r/`) | 9 tests, all pass: window alternation fuzz (256 runs x 60 operations), shock-refresh-restore, round trip, anchor stick, cap exits (3), round trip PoC, coarse-token flag |
| Mutants on the changed code (12) | **12 of 12 killed**: A1 `>` instead of `>=` at the window, A2 `forceAnswer` without `anchorSetAt`, A3 `updateAnswer` without `anchorSetAt`, A5 window 0, A6 `refresh` moving the anchor, V1 flag without the `target + tol` clause, V2 flag without `supply == 0`, V3 `timeBased` without `supply > 0`, D1 quote without cap, D2 sell without cap, D3 buy without cap, D4 cap `>=`. |
| Pass-1 survivors re-run (6) | **6 of 6 killed** now: M-13 (`test_R04`), M-06 (`test_R05`), M-09 and E14 (`test_R06_*`), E10 (`test_R07`), E15 (`test_R08`). |

## Scope hashes (sha256, first 16 hex)

```
e228b7ab1e7a7a4e contracts/v2/oracle/FengAggregator.sol    3f606e3ed44240de contracts/v2/StrategyVaultV2.sol
9ca350f8d3b06c65 contracts/v2/venue/OracleDesk.sol         2d2d40534e7c83d1 contracts/v2/MarketplaceRegistryV2.sol
24cbdfbceabb11d8 contracts/v2/RebalanceEngineV2.sol        a33ae8a71f7da260 contracts/v2/VaultDeployerV2.sol
0be5aa8c2e83332e script/DeployV2.s.sol                     dad1494da92e852d script/DeployLive.s.sol
0e4e64b0712b42c0 script/SeedLive.s.sol                     eec6a8d4472cf27e scripts/deploy-v2.sh
4c79d9ddd470476b scripts/demo-shock.sh                     0e2d1514a71e491b scripts/ops-worker.ts
src/ops: abi f7a1fafa, auth afac660a, config 5e058636, faucet e910af8e, health c607c2d5, keeper 1a86cdef, prices b0dcc6e7, relayer 052c2153, rpc fbccd4e6, scan 3619b0c8, tick 315fbf7a
src/app/api: faucet/route 50b1fa98, ops/health/route 91ffcef7, ops/tick/route fdc4178b
```
(`OracleDesk.sol`, `FengFaucet.sol`, `ChainlinkPriceOracleV2.sol`, `StrategyFactoryV2.sol`, `StrategyLens.sol` are byte-identical to pass 1 (`9ca350f8`, `b8ade4be`, `cabb12a1`, `f7121b4c`, `b3afb20c`). `maxSwapUsdg` therefore already existed in pass 1.)

## Pass-2 findings

| ID | Sev | Row | File:line | Description | Proof | Fix | Status |
|---|---|---|---|---|---|---|---|
| R-V2-24 | Medium (residual of R-V2-01/02/03) | X-01, X-02 | `oracle/FengAggregator.sol:53-64`, `venue/OracleDesk.sol:67-104` | The anchor window bounds the price LEVEL (always within `maxDeviationBps` of one anchor per hour) but not the round trip inside one window: the updater can set `A(1-D)`, trade in, set `A(1+D)`, trade out, set back, all in one block against the same anchor. Profit per cycle is about `2D x leg`, repeatable without limit, bounded only by the per-swap cap (5,000 sandbox, 25 Live) and the desk reserve. The unbounded `1.15^n` walk of R-V2-01 is gone; this is what is left. | `Pass2.t.sol::PoC2_RoundTrip.test_oneTxRoundTripInsideWindow` (helper feed D = 1500, cap 5,000): 5 cycles of a 7,000 USDG deposit, relayer 10,000 to 16,081 USDG, desk reserve loss 6,081 USDG, one block. At the deployed D = 1000 the rate is about 20 percent of the leg per cycle. | Accept (testnet, key is trusted, reserve is the maximum loss) or add the hourly outflow cap of `F02-window-cap.patch` on the desk. A cheaper partial: none found that does not break same-second keeper flows on an Orbit chain. | OPEN, needs coordinator acceptance. Not blocking. |
| R-V2-25 | Low | spec 2.3, C-15, I5 | `venue/OracleDesk.sol:225-228`, `script/DeployV2.s.sol:39,200`, `script/DeployLive.s.sol:32,151` | The cap (sandbox 5,000 USDG, Live 25 USDG, both directions, also on `quoteExactIn`, correct) makes three things revert with `SwapTooLarge`: (a) a USDG `redeem` whose pro-rata leg exceeds the cap; (b) a USDG `deposit` whose largest leg exceeds the cap, i.e. max deposit is `cap / maxWeight` (10,000 for a 50/50 vault, which is exactly the faucet amount; 8,333 for a 60 percent leg; Live 62.5 USDG for LIVE-AI, 125 for LIVE-5 and LIVE-CORE); (c) `executeRebalance`. **No lockout**: `redeemInKind` and `redeemInKindExcluding` never touch the desk (PoC: an 80k vault redeems fully in kind; chunked USDG redeems work). Rebalance threshold: a leg exceeds the cap when `V x delta_w > cap / (1 - spread)`. Largest vault whose rebalance always fits at the sandbox cap: 50/50 vault, one asset +30 percent (shock limit): `delta_w` 6.52 percent, so **V above about 76,700 USDG** bricks it; the two assets moving +30 and -30 percent: `delta_w` 15 percent, **V above about 33,300 USDG**; one asset +10 percent: V above 210,000; six equal weights, one +30 percent: V above 126,000. Live (25 USDG): equal five-weight vault above about 550 USDG, LIVE-AI similar. While bricked, `rebalanceNeeded()` stays true and the keeper logs a revert each tick (engine try/catch keeps other vaults moving). All seeded sandbox vaults are at most 5,000 USDG (`SeedV2.s.sol:153-279`), so the demo is far below every threshold. | `PoC2_Cap`: `test_capBlocksBigRedeemButNotInKind`, `test_capChunkedRedeemWorks`, `test_capBricksRebalanceAboveThreshold` (80k vault, TSLA +30 percent shock: flag true, `executeRebalance` reverts). | UI: read `maxSwapUsdg()` and cap deposit and redeem size at `cap / maxWeight`, offer in-kind exit on `SwapTooLarge`. Ops: owner raises the cap with `setMaxSwapUsdg` as vaults grow; document the table above. | OPEN, document. |
| R-V2-26 | Low / Info | C-15, R-V2-09 | `StrategyVaultV2.sol:513-524` | The R-V2-09 fix clears the flag only if the sell pass can trade `excess`. For a constituent whose smallest unit is worth more than the tolerance (0-decimal token at $400, the factory allows decimals 0 to 18) `amount = excess x scale / price` floors to 0, no sale happens and `thresholdBased` stays true after `executeRebalance`: keeper loop again, one wasted rebalance per tick. Real tokens (18 decimals) are not affected. | `PoC2_FlagsCoarse.test_coarseTokenFlagStaysTrue` (20k vault, 0-decimal TSLA at +30 percent: flag 1 before and 1 after). | Accept (no 0-decimal asset is planned), or reject `decimals < 6` in the factory (factory has 18 KB of size margin, vault has none). | OPEN, ACCEPT. |
| R-V2-27 | Low (Medium if the RPC URL carries a key) | X-16 | `src/ops/rpc.ts:276-284`, `src/ops/health.ts:350,519`, `src/ops/scan.ts:32`, `src/app/api/ops/health/route.ts` | `GET /api/ops/health` is unauthenticated and copies `shortError(error)` into `alarms`. `shortError` appends viem's `details`, which for an HTTP error is the provider's response body. A provider that echoes the request URL or key leaks it to anyone. Reproduced with a local server that answers 401 `invalid key SECRETAPIKEY123 for /v2/SECRETAPIKEY123`: the short error contains the secret. The default RPC (public Robinhood endpoint) has no key, so the impact depends on `OPS_RPC_URL*`. Other health content (wallet addresses, balances, feed ages, vault NAV, desk reserve) is chain data, no secret, no RPC URL, no env value. The 15 s cache bounds the cost per instance. | Node script against viem `HttpRequestError` (output only in this report, not in the repo). | In `shortError` (or only for public responses) replace `https?://\S+` and any token of 20 or more `[A-Za-z0-9_-]` with `<redacted>`, or return fixed strings on the public route and keep the detail in the authenticated tick response. | OPEN, fix before a keyed RPC is configured. |
| R-V2-28 | Low | X-16 | `src/ops/faucet.ts:71-72,82-86,176-296`, `config.ts:193` | Faucet drain model. Contract mode (`OPS_FAUCET_MODE=contract`): on-chain once per address and `dailyCap` 40 per day, so the ETH at risk is `40 x 0.0001 = 0.004 ETH` per day (the whole funding) and the dispenser pays gas only for simulated-successful claims (at most 40 per day). A sybil with 40 fresh addresses empties the day: availability loss, no larger loss. The in-memory limiters (6 per 10 min per IP, 1 per minute per address) are per serverless instance, and `x-forwarded-for` first hop is trusted when `x-vercel-forwarded-for` is absent (spoofable off Vercel; behind Vercel the header is overwritten). The IP map has a size-triggered cleanup only (slow memory growth under spoofed keys). **Default mode is `v1`** when `OPS_FAUCET_MODE` is unset: the legacy wallet-funded path has no on-chain cap, so its only bound is the limiters and the wallet balance. Address input: `isAddress` then `getAddress`, passed as a typed argument, no SSRF or injection surface; responses carry only `status` and `txHash`; errors go to `console.error` as `shortError` text. | Read; arithmetic. | Set `OPS_FAUCET_MODE=contract` in the V2 environment (or default to `contract` when the deployment has a `faucet` address). State the daily cap as the real limit. | OPEN, config and document. |
| R-V2-29 | Low | X-16 | `src/ops/prices.ts:324-329`, `src/ops/relayer.ts:226-227` | Price API trust. Checked and fine: `tokenSymbol` must equal the requested symbol, `isTradingHalt` boolean, decimal-only strings (a JS number like `1e+21` is rejected), `bid > 0`, `ask >= bid`, spread at most 500 bps, mid scaled with rounding, USDG pinned to 1.0, move over `sanityMoveBps` (50 percent) against the on-chain price is held, V2 pushes are clamped to `min(maxStepBps 900, maxDeviationBps)` of the anchor, and the contract enforces the same bound plus the window, so a hostile API moves a V2 feed by at most 9 percent per hour. Gaps: (a) `generatedAt` missing or unparsable skips the clock check (fail-open), so a cached or replayed well-formed body is accepted; (b) `decidePush` sends `refresh()` whenever the quote is unavailable, halted, wide or held, and the keeper's forced refresh does the same to clear `StalePrice`: the on-chain price keeps looking fresh while it is stale, which defeats the staleness guard by design (ties to F-05); (c) V1 mock feeds have no on-chain bound and only the 50 percent sanity check, but V1 defaults to `hold` mode (no API use). | Read. | Treat a missing `generatedAt` as an error; stop heartbeat `refresh` after N missed quotes or after `OPS_HARD_MAX_AGE_SEC`; keep V1 in `hold`. | OPEN, accept or fix. |
| R-V2-30 | Low | X-16 | `src/ops/auth.ts`, `src/app/api/ops/tick/route.ts` | Bearer check is sound: SHA-256 of both sides, `timingSafeEqual` on equal-length digests (constant time, no length leak), empty or unset `CRON_SECRET` returns false (fail-closed), missing header rejected. Responses on failure carry no detail. The tick runs real transactions on GET and POST; unauthenticated callers only get a 401. No minimum length or entropy check on `CRON_SECRET`; two overlapping authorised ticks race on the pending nonce (reverts or replacement errors only, no double effect). The summary (authorised only) can contain `shortError` text, see R-V2-27. | Read. | Refuse a `CRON_SECRET` shorter than 32 characters at start. | OPEN, trivial. |
| R-V2-31 | Low | G-11, D | `scripts/deploy-v2.sh:121-126,190-202,214,233,248`, `script/DeployV2.s.sol:284-340`, `script/DeployLive.s.sol:205`, `script/SeedLive.s.sol:74` | (a) `has_code` returns 2 when `cast code` fails but every use is `if has_code ...`, so an unreachable or intercepted RPC makes the "refuse a second deploy, second live set, second seed" guards fall through to the broadcast (fail-open; the script notes TLS interception on the endpoint). Verified with a stub returning 2. (b) The scripts write `deployments/<net>-v2/addresses.json` with `vm.writeFile` and `vm.writeJson` unconditionally; a manual run without `--broadcast` overwrites the real deployment record with simulated addresses (verified in the scratch tree: a dry run wrote `anvil-v2/addresses.json`). `deploy-v2.sh` always passes `--broadcast`, so only manual use is exposed. (c) Line 126 prints `$RPC_URL`; (d) the `DRY_RPC_URL` glob `http://127.0.0.1:*` also matches `http://127.0.0.1:1@evil.example/` (userinfo form), so the public Anvil key could sign for a remote RPC (funds-neutral). Key handling otherwise clean: keys only through `vm.envUint` or env variables, nothing echoed, argv exposure only in the accepted `cast` calls. | Run in scratch tree; stub test. | (a) `has_code ...; rc=$?; [[ $rc -eq 2 ]] && exit 1`. (b) gate writes with `vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)`. (c) print the host only. (d) match `http://127.0.0.1:[0-9]*` exactly. | OPEN, small. |
| R-V2-32 | Info | X-13, X-14 | `script/DeployLive.s.sol:116-137`, `script/SeedLive.s.sol` | Line-by-line read of the Live scripts (verdict below). Residuals: the issuer parameters (`uiMultiplier`, `paused`, blocklists) are checked once at deploy time and nowhere on chain: a later split or a blocklisted desk or vault address freezes the USDG paths of that token (in-kind exit with `redeemInKindExcluding` still works). Env overrides of `LIVE_USDG` and `LIVE_TOKEN_*` are not compared to the expected addresses (only code, decimals, `uiMultiplier`, not paused). A broadcast that fails after the first vault leaves registered, empty or unseeded vaults and a `live.vaults` JSON written during simulation (resume handles it, the guard looks at `vaults[0]` code). Raw `IERC20.approve` on real tokens (they return bool). | Read. | Re-check `uiMultiplier` and `paused` before the demo; keep the runbook step. | ACCEPT. |

## Area results

### (1) `FengAggregator` anchor window

- **Gaming by alternating `refresh` / `updateAnswer` / `forceAnswer` / `shockAnswer`**: no way found beyond R-V2-24. `Pass2.t.sol::PoC2_AggregatorAlternation.testFuzz_alternation` (256 runs of 60 random operations from the updater and shock roles plus warps) asserts: the anchor or `anchorSetAt` moves only when `block.timestamp >= previous set time + 1 hour`, by at most `maxDeviationBps` of the previous anchor, `anchorSetAt` never decreases and never exceeds `block.timestamp`, `latestAnswer` is always within `maxShockBps` of the anchor and positive, and the number of anchor moves never exceeds elapsed hours plus one. Passes. Compounding is therefore at most `(1 + D)^hours`, not per block. `shockAnswer` never moves the anchor (E8 killed).
- **`anchorSetAt` underflow or stick**: no subtraction on it; `anchorSetAt + ANCHOR_WINDOW` cannot overflow for a timestamp. It does "stick" while only `refresh` is called (`test_anchorSticksWithoutUpdates`: 24 hours of refresh, then a +25 percent update reverts and must be taken in steps, one per hour). That is the intended rate limit; the relayer handles it by clamping and logging `held at the deviation bound ... anchor window open` (`relayer.ts:236-249`). A feed initialised at a tiny price (bound rounds to 0) can only change through `forceAnswer`; irrelevant at the 8-decimal stock prices.
- **Shock, refresh, restore**: `test_shockRefreshRestore`: shock +18 percent, 90 minutes pass, `refresh()` (keeps the shocked answer, re-stamps it), `updateAnswer(original)` lands (distance zero) and, because the window had elapsed, re-anchors to the restored value with a fresh `anchorSetAt`. The anchor stays at the pre-shock level throughout.
- **Rounding and casts**: bound is `mulDiv(uint256(anchor), bps, 10_000)` floor (anchor is positive by construction), `_distance` subtracts two positive `int256`, no overflow; `uint80(round)` counter. The `<=` bound at the exact limit passes and the next unit reverts (killed mutant A1).
- **Role separation**: `UPDATER_ROLE` (updateAnswer, refresh), `SHOCK_ROLE` (shockAnswer, only if `shockEnabled`), `DEFAULT_ADMIN_ROLE` (forceAnswer, setParams, setShockEnabled, grants). The relayer cannot force, cannot enable shock, cannot change bounds. In `DeployV2` the relayer gets `UPDATER_ROLE` on all six feeds and `SHOCK_ROLE` only if `ENABLE_SHOCK=1`; admin stays the deployer.
- ABI note: `anchorSetAt()` and `ANCHOR_WINDOW()` are public but not in `IFengAggregator`; the generated ops ABI has them (`src/lib/abi/generated/fengAggregator.ts`). Harmless.

### (2) `_flags` (R-V2-09 and R-V2-10 patch)

C-15: PASS. The threshold flag now needs both `weight > effectiveMax` and `value > target + tolerance`, which is exactly the sell pass condition, so for 18-decimal assets a flagged leg is always traded and the flag clears (existing fuzz `testFuzz_R09_thresholdFlagAlwaysClearsAfterRebalance`; mutant V1 killed). C-16: PASS: `total == 0 || supply == 0` returns `(timeBased, false)` and `timeBased` requires `supply > 0` (mutants V2 and V3 killed). New ways for the flag to lie or never clear: only (a) the coarse-decimals case R-V2-26, and (b) the desk cap R-V2-25 (flag true, rebalance reverts), and (c) a child redeem reverting `ZeroAmount` in the 2-unit dust window (R-V2-17, already accepted). Donating a token to inflate a weight costs the donor (C-28). Deployer runtime 24,135 bytes, margin 441: the vault cannot grow by more than about 400 bytes without a restructure.

### (3) `OracleDesk.maxSwapUsdg`

Applies in `swapExactIn` buy (measured `received`), sell (USDG out) and in `quoteExactIn` (`amountIn` on buy, `amountOut` on sell); equality passes, one unit over reverts (D4 killed), zero means unlimited, owner-only, emits `MaxSwapSet`. `redeemInKind` cannot be locked by it (no desk call; PoC). See R-V2-25 for the sizes.

### (4) `FengFaucet` and `DeployV2` guards

Faucet bytecode unchanged. Defaults now `0.0001 ETH` per claim, `dailyCap` 40, funding `dailyCap x ethPerClaim` = exactly 40 claims (R-V2-13 closed; `test_defaults_exactFundingPaysExactlyFortyClaims`, `test_defaults_claim41RevertsDailyCapWhenFunded`). On `DEPLOY_NETWORK=robinhood-testnet` the script reverts `RelayerAddressRequired`, `RelayerAddressIsDeployer`, `FaucetAddressRequired`, `FaucetAddressIsDeployer` before any broadcast, and `deploy-v2.sh` repeats the check for the deploy steps. Gaps: the guards key on the exact network string (a typo such as `robinhood_testnet` skips them, `deploy-v2.sh` only accepts `robinhood-testnet` or `dry`, so the script path is safe); relayer and faucet addresses may be equal to each other and the guardian may equal the deployer (R-V2-14 stays partially open: single admin key, state it in the README); the faucet dispenser is not given any role besides `DISPENSER_ROLE`.

### (5) `DeployLive.s.sol` and `SeedLive.s.sol`, line by line

- **Constants**: the real Paxos USDG (`0x7E955252...802F`) and the five token addresses live only in `deploy-v2.sh` defaults; the scripts read `LIVE_USDG` and `LIVE_TOKEN_*` from the environment (`DeployLive:93,104`), so G-04 holds (no literal in `contracts/` or `script/`).
- **Preflight (`:116-137`, before any broadcast)**: code present, USDG decimals 6, USDG not paused, each token has code, `uiMultiplier == 1e18`, decimals at most 18, not paused, sandbox feed has code, deployer owns the shared oracle, deployer holds the registry admin role. A missing JSON key reverts (fail-closed, checked with `parseJsonAddress` on an empty file). Existing live factory with code is refused (`:109-113`).
- **Deploy (`:139-159`)**: points the five real token addresses at the sandbox feeds in the shared oracle (R-V2-03, now bounded by the anchor window but see R-V2-24); new `OracleDesk` with spread 10 bps, `Inventory` mode for the five tokens, cap 25 USDG; new factory (guardian from `GUARDIAN_ADDRESS`, default deployer), `FACTORY_ROLE` granted on the shared registry.
- **Funding (`:161-178`)**: 30 percent of the deployer's real USDG and 70 percent of each real token balance, read from chain before the broadcast, exact approvals then `fundReserve` / `fundInventory` (both pull measured deltas; no leftover allowance with standard tokens). Zero balances log a notice and skip. The deployer holds 5.000000 of each token and 0 USDG at last check (`docs/research/08`), so the Live desk is funded with 3.5 tokens each; USDG must come from the Paxos faucet first.
- **Who owns what after the run**: deployer EOA: shared oracle owner, registry admin, Live desk owner (can withdraw reserve and inventory at any time, trusted F-10), MockUSDG, all sandbox contracts. Live factory has no owner and an immutable config; the vault guardian is `GUARDIAN_ADDRESS` (pause only, never blocks redeem). The relayer holds `UPDATER_ROLE` on the six sandbox feeds, which also price Live (R-V2-03).
- **Shared registry**: the Live desk's gate is the shared registry, so a vault made by the sandbox factory is also "registered" for the Live desk, but a vault only calls its immutable `venue` (the sandbox desk) and cannot hold real tokens through the factory checks, so there is no path.
- **Seeding (`SeedLive`)**: reads `.live.*`, refuses a non-empty `live.vaults`, requires the factory to have code, USDG not paused, minimum budget 15 USDG (`LIVE_MIN_SEED_USDG`), budget from the actual balance times `LIVE_SEED_BPS`; each vault amount is capped so its largest desk leg is at most the cap (`maxAmount = cap x 10000 / legBps`; leg bps 4000, 2000, 2000, checked against the real look-through: LIVE-CORE largest desk swap is the 20 percent TSLA satellite, children get 40 percent each, so 0.2 x A); `_checkOracle` requires non-zero, fresh feed prices; `_checkInventory` recomputes the per-token inventory need from the look-through weights (28/18/8/24/22, verified) with a 1 percent margin and aborts with a readable message; deposits use `previewDeposit x 99 percent` as `minShares`. Fine.
- **Failure modes with a real token**: a token that pauses or blocklists the desk or a vault after deploy makes buy and sell legs revert, so USDG `deposit`, `redeem` and `executeRebalance` of the vaults holding it revert; `redeemInKind` also reverts for that token unless the holder uses `redeemInKindExcluding` with the token in the mask (the slice stays in the vault); USDG paused: same with the idle USDG slice. Pause before deploy is caught by the preflight; during the broadcast the simulation catches it, a race leaves partial state (R-V2-32).
- **`--hardfork osaka`**: `deploy-v2.sh:144-146` adds `--hardfork "${LIVE_HARDFORK:-osaka}"` for `DeployLive` and `SeedLive` only. Forge 1.8.3 accepts it (`--help`; an unknown name is rejected before any work, so a wrong value fails closed). It only changes the simulation EVM; the contracts stay `evm_version = paris`. Osaka's 2^24 per-transaction gas cap is not a problem (largest transaction `createStrategy` about 4.6M). Needed so that the real tokens' bytecode executes in the fork simulation; I could not exercise it without a fork RPC.
- **Verdict on the scripts**: no High or Critical; findings R-V2-24 (price lever), R-V2-25 (cap sizes), R-V2-31, R-V2-32.

### (6) `src/ops/**` and `src/app/api/**` (X-16)

- **Key handling**: three env keys (`KEEPER_PRIVATE_KEY`, `RELAYER_PRIVATE_KEY`, `FAUCET_PRIVATE_KEY`) read at call time in `accountFromEnv`; format-checked (`^0x[0-9a-fA-F]{64}$`); the thrown message names the variable only and `loadSigner` swallows it into "not configured" (fail-closed, critical alarm). No key or env value reaches `console.*`, the tick summary, the health report or any response (grep of `console.` and `process.env` in `src/ops`, `src/app/api`, `scripts/ops-worker.ts`). The wallet client is built per request from the account object; no key in the viem `chain` or transport config. RPC URLs are not in health or tick output; see R-V2-27 for provider error text.
- **Bearer auth**: R-V2-30, sound.
- **Faucet**: R-V2-28.
- **Health exposure**: R-V2-27.
- **Tick DoS surface**: authorised only; each tick has a 22 s budget and a 60 s `maxDuration`; unauthorised requests cost one hash. Health: one computation per 15 s per instance, `getLogs` lookback cached 60 s; many instances can still exhaust a shared RPC quota (Low, same bucket as R-V2-28).
- **Price API**: R-V2-29. **V2 `feng` relayer against the window**: the relayer reads `anchorAnswer`, `maxDeviationBps`, `ANCHOR_WINDOW`, clamps to `min(900, D)` of the anchor, chases up to three steps per tick but a second step in the same window cannot move the anchor, so extra steps only land inside the band; it detects the shock hold from `AnswerShocked` logs and sends `refresh` instead of market prices for `OPS_SHOCK_HOLD_SEC`, then restores through `updateAnswer` (works because the restore target is inside `D`). With `sanityMoveBps` 5,000 a 30 percent shock restore is never blocked. Real moves above `D` per hour lag the market by up to one hour (documented in the notes `held at the deviation bound`).

### (7) `scripts/demo-shock.sh` and `scripts/deploy-v2.sh`

demo-shock: keys from env only, never echoed; argv exposure of `cast ... --private-key` accepted; `--pct` validated by regex, symbol and vault selectors go through `jq --arg` or a strict address regex; refuses before sending when the target is outside the shock bound or the roles are missing; the EXIT trap restores through `updateAnswer(ORIGINAL)`, which the window allows as long as the pre-shock price was inside `D` of the anchor (otherwise it prints `RESTORE FAILED` with the manual command). Shell arithmetic is 64-bit, safe for 8-decimal feeds. deploy-v2: R-V2-31. Nothing else found.

## Status of the pass-1 conditions

| Pass-1 item | Status |
|---|---|
| Condition 1: five test gaps R-V2-04 to R-V2-08 | **CLOSED.** Tests landed in `contracts/test/v2/unit/ReviewKillers.t.sol` (`test_R04`, `test_R05`, `test_R06` x2, `test_R07` x2, `test_R08` + fuzz); I re-ran all six mutants (M-13, M-06, M-09, E14, E10, E15): all killed. |
| Condition 2: acceptance of R-V2-01, 02, 03 and F-05 | R-V2-01 **patched** (anchor window, public `ANCHOR_WINDOW`, `anchorSetAt`; residual is R-V2-24). R-V2-02(a) **applied** (sandbox cap 5,000, Live cap 25, `DeployV2.s.sol:200`); (b) hourly outflow cap not adopted. R-V2-03 open (shared oracle, now bounded by the window). F-05 value: both factory and desk read `MAX_PRICE_STALENESS` (default 43,200); the coordinator still has to record the final value. |
| Condition 3: Lows R-V2-09 to R-V2-16 | R-V2-09, 10 **fixed** (patch applied, verified, mutants killed; residual R-V2-26). R-V2-12 **fixed** (custom errors, `rg 'require\(|revert\("' contracts/v2` empty). R-V2-13 **fixed** (funding = cap x per-claim). R-V2-14 partial (deployer guards, single admin key remains, README statement pending). R-V2-11 (oracle `updatedAt` and `setFeed` code check) **open**, file unchanged. R-V2-15 handled in ops (`keeperPageSize` 5 to 50, `checkUpkeepRange`). R-V2-16 open, accepted for testnet. **`docs/security/known-limitations.md` still contains unresolved template markers (`{{IF F-01 ...}}`, `{{or the final amount}}`, `{{only if E4 ships}}`) and quotes the old 0.0002 ETH faucet amount**: the "list the Lows" condition is not met until that file is filled in. |
| R-V2-22 (Live scripts not fully reviewed) | **CLOSED** by this pass, see (5). |
| X-16 (`src/ops`) | **DONE**, see (6). R-V2-27 to R-V2-30 are the results. |

## G1 blocking list

None. Final: **no open High or Critical.** Before the demo, in this order: (1) coordinator records the acceptance of R-V2-24, R-V2-02(b) not adopted, R-V2-03 and the F-05 value; (2) fill `known-limitations.md` (placeholders, faucet amount, cap table of R-V2-25, single-admin key); (3) set `OPS_FAUCET_MODE=contract` and a long `CRON_SECRET` (R-V2-28, R-V2-30); (4) redact `shortError` before any keyed RPC is configured (R-V2-27); (5) `has_code` fail-open fix and `isContext` gating if the scripts are reused by hand (R-V2-31).

Open risks that stay accepted (additions to the list above): a stolen relayer key can still extract about `2D x leg` per cycle until the reserve or the cap stops it (R-V2-24); the cap makes large USDG paths revert while in-kind exits stay open (R-V2-25); no Slither, Aderyn, Echidna or Medusa run (not installed, unchanged from pass 1).
