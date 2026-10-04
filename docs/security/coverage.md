# V2 test coverage (E8-T2, second pass)

Scope: `contracts/v2/**` excluding `contracts/v2/mocks`. Tests: `contracts/test/v2/**` (independent test author). Second pass after the review (`docs/security/review-v2.md`), the anchor window in `FengAggregator`, the desk `maxSwapUsdg` cap, the faucet and `DeployV2` default changes and the `_flags` fix (R-V2-09, R-V2-10).

## Result against thresholds

| Metric | Threshold | Measured | Status |
|---|---|---|---|
| Lines | 90 percent | 99.63 percent (811 of 814) | pass |
| Statements | none set | 98.79 percent (1064 of 1077) | info |
| Branches | 80 percent | 94.76 percent (181 of 191) | pass |
| Functions | none set | 100.00 percent (137 of 137) | info |

Per file (lines / branches):

| File | Lines | Branches |
|---|---|---|
| `MarketplaceRegistryV2.sol` | 100.00 (65/65) | 100.00 (14/14) |
| `RebalanceEngineV2.sol` | 100.00 (29/29) | 100.00 (7/7) |
| `StrategyFactoryV2.sol` | 100.00 (70/70) | 91.67 (22/24) |
| `StrategyLens.sol` | 100.00 (31/31) | 100.00 (7/7) |
| `StrategyTokenV2.sol` | 100.00 (12/12) | 100.00 (2/2) |
| `StrategyVaultV2.sol` | 99.41 (339/341) | 94.12 (64/68) |
| `VaultDeployerV2.sol` | 100.00 (7/7) | 100.00 (2/2) |
| `faucet/FengFaucet.sol` | 100.00 (41/41) | 90.00 (9/10) |
| `oracle/ChainlinkPriceOracleV2.sol` | 95.65 (22/23) | 83.33 (5/6) |
| `oracle/FengAggregator.sol` | 100.00 (73/73) | 90.00 (9/10) |
| `venue/OracleDesk.sol` | 100.00 (122/122) | 97.56 (40/41) |

Known uncovered branches: `StrategyFactoryV2` depth above `MAX_DEPTH` and `NestedTokenNotLeaf` (unreachable behind the earlier `DepthExceeded` check, equivalent mutant E12, review R-V2-18), the `catch` in the vault `priceStatus` child recursion, and a few single-line defensive checks.

## How it was measured

Plain `forge coverage` (optimizer and via-IR off, no `--ir-minimum`, which is terminated by SIGTERM in this environment). Separate Foundry dirs, 16 invariant runs per invariant:

```
FOUNDRY_OUT=<dir> FOUNDRY_CACHE_PATH=<dir> FOUNDRY_INVARIANT_FAILURE_PERSIST_DIR=<dir> FOUNDRY_INVARIANT_RUNS=16 \
forge coverage --report summary --match-path "contracts/test/v2/**" \
  --no-match-coverage "(contracts/mocks|contracts/v2/mocks|contracts/test|script|contracts/MarketplaceRegistry\.sol|contracts/RebalanceEngine\.sol|contracts/StrategyFactory\.sol|contracts/StrategyToken\.sol|contracts/StrategyVault\.sol|contracts/oracle)"
```

The coverage run reports 531 passed, 2 failed (533): `test_gas_createStrategy` (6.57M against a 6.5M ceiling) and `test_gas_vaultDeployer` (6.27M against 5.5M). They fail only because coverage builds without the optimizer; they pass in the normal build.

## Run commands and results

| Check | Command | Result |
|---|---|---|
| V2 suite, default profile (fuzz 256, invariant 256 runs, depth 64) | `forge test --match-path "contracts/test/v2/**"` | 533 passed, 0 failed, 0 skipped (41 suites) |
| V1 regression | `forge test --no-match-path "contracts/test/v2/**"` | 48 passed, 0 failed (8 suites) |
| Invariant and fuzz folders, deep profile (invariant 2000 runs depth 64, fuzz 1000 runs) | `FOUNDRY_PROFILE=deep forge test --match-path "contracts/test/v2/{invariant,fuzz}/**"` | 58 passed, 0 failed (11 suites); `Invariant6Dec` and `Invariant18Dec` each 2000 runs, 128,000 calls, 0 reverts |
| New fuzz tests in `unit`, deep profile (1000 runs) | `FOUNDRY_PROFILE=deep forge test --match-path "contracts/test/v2/unit/**" --match-test testFuzz` | 5 passed, 0 failed |

Always export `FOUNDRY_OUT`, `FOUNDRY_CACHE_PATH` and `FOUNDRY_INVARIANT_FAILURE_PERSIST_DIR` when other agents share the repo.

## Tests added in the second pass

| File | What it pins |
|---|---|
| `unit/Aggregator.t.sol` | Anchor window: the two broken tests adapted (anchor unchanged inside the window, moves after one hour); stepped pushes stay bounded against the same anchor (+9.99 percent lands, +10.01 percent `DeviationTooHigh`, exact boundary lands and one unit more reverts), anchor moves only at `anchorSetAt + ANCHOR_WINDOW`, hourly walk is geometric, one-block walk of 10 pushes reverts (review F-01 PoC), fuzz that the price never leaves the band inside a window, `shockAnswer` +18 percent works and +30.01 percent `ShockTooHigh`, shock leaves anchor and window alone, relayer and shocker cannot `forceAnswer`, `forceAnswer` restarts the window, `refresh` leaves anchor alone |
| `unit/ReviewKillers.t.sol` | R-V2-04 parent `checkpoint` with a stale child, R-V2-05 partial-pull venue leaves allowance 0, R-V2-06 desk buy price rounds up and sell price rounds down with an odd 18 decimal price, R-V2-07 sell leg short delivery reverts `SlippageExceeded` in `redeem`, R-V2-08 idle slice rounds down exactly (plus a fuzz over idle-only vaults) |
| `unit/ReviewFollowups.t.sol` | R-V2-09 dust vault never reports `thresholdBased` and the flag always clears after `executeRebalance` (fuzz), R-V2-10 empty vault with donated tokens is never needed, `ZeroAddress` custom errors in the engine and registry constructors, desk `maxSwapUsdg` (`SwapTooLarge` on swap and quote, buy and sell side, owner-only setter, event, 0 = unlimited, no state on failure, fuzz boundary), faucet defaults (0.0001 ETH per claim, cap 40, claim 41 `DailyCapReached(40)`, 0.004 ETH pays exactly 40), `DeployV2` guards and defaults through a harness that inherits the script |

The `DeployV2` check does not use `forge script`: a harness inherits `DeployV2` and calls its internal `_loadConfig` and `_deploy` with `vm.setEnv`, so no key is read, nothing is broadcast and `deployments/` is not written. `run()` itself (key, broadcast, JSON output) is not covered by unit tests.

## Mutant check (isolated copy of the tree, one mutant at a time, new and adapted tests only)

All 13 mutants are killed: M-13 (parent ignores child freshness), M-06 (no approve reset), M-09 (buy price Floor), E14 (sell price Ceil), E10 (no sell-side `_atLeast`), E15 (idle slice Ceil), old `_flags` empty-vault condition, old `_flags` dust condition, anchor always moves, anchor never moves, window 1 day, desk cap no-op, desk cap ignored on the sell side.
