# 04. Contracts V2: implementation notes (lane A core, agent C1)

Scope: `StrategyTokenV2`, `StrategyVaultV2`, `StrategyFactoryV2`, `VaultDeployerV2`, `MarketplaceRegistryV2`, `RebalanceEngineV2`, `StrategyLens` (new), and the interfaces `IStrategyVaultV2`, `IMarketplaceRegistryV2`, `IStrategyFactoryV2` (also holds `IVaultDeployerV2`), `IRebalanceEngineV2`, `IStrategyTokenV2`. Spec: `docs/handoffs/04-contracts-v2.md`. V1 checksums: `docs/handoffs/v1-sources.sha256` (re-checked at the end, identical).

## 1. Deviations from the spec (read these first)

| # | Deviation | Why | Who must act |
|---|---|---|---|
| D1 | `quoteRedeem(shares)` and `previewRedeemInKind(shares)` are NOT on the vault. They live in the new read-only `StrategyLens` (`quoteRedeem(vault, shares)`, `previewRedeemInKind(vault, shares)`), spec 3.5 fallback (2). | EIP-170 on `VaultDeployerV2`, not on the vault. The deployer embeds the vault creation code, so its runtime is vault initcode plus about 600 bytes. With both functions on the vault the deployer is 25,4xx bytes, over 24,576. The spec gate (vault runtime at most 23,500, deployer at most 24,000) cannot hold together: a vault of 23,500 bytes runtime would need a deployer of about 31,000. | Frontend and ops: read these two through the lens. Deploy lane: deploy `StrategyLens` (no constructor args) and add `lens` to `addresses.json` and to `sync-abi.sh` (`StrategyLens` to `strategyLensAbi`). Tests already use it. |
| D2 | Nested USDG redeem and nested rebalance sell compute the child leg `minOut` from `child.previewRedeem(shares)` times `(BPS - maxSlippageBps)/BPS` (the same oracle based bound used for every other sell), not from `child.quoteRedeem(shares)`. | `quoteRedeem` is not on the vault (D1). The bound is stricter than a quote based one, still passes for spreads below `maxSlippageBps`. | none |
| D3 | The child redeem leg is wrapped as `ChildRedeemFailed(childToken, reason)` in redeem AND in rebalance sells (spec wraps only the redeem leg). A failing child buy leg in `deposit` or rebalance bubbles the child's own revert. | One code path, smaller bytecode. | none |
| D4 | Every sell (redeem and rebalance) is bounded per leg by `valueOf(amount, Floor) * (BPS - maxSlippageBps) / BPS` against the oracle, and reverts `SlippageExceeded(got, min)` below it. Spec states this only for rebalance. | Same helper, protects a redeemer against a venue that pays less than the oracle band. | none |
| D5 | Dust handling: a sell leg whose oracle value floors to 0 is skipped (the slice stays in the vault); a rebalance buy with `spend < MIN_LEG_USDG` after proportional scaling is skipped. | A 1 unit leg would make the desk revert `ZeroAmount` and brick the call. | none |
| D6 | The vault constants `BPS`, `MAX_CONSTITUENTS`, `MAX_SLIPPAGE_BPS`, `LEG_TOLERANCE_BPS`, `THRESHOLD_BAND_BPS`, `CHECKPOINT_MIN_INTERVAL`, `VIRTUAL_ASSETS` are private (no getter); `VIRTUAL_SHARES` and `MIN_LEG_USDG` stay public. `USDG_UNIT` immutable removed (unused). | About 400 bytes, EIP-170 on the deployer. | none (they are not in the ABI table of spec 5.1) |
| D7 | `IStrategyFactoryV2` gains `error ZeroAddress()` (constructor, all non-zero including `maxPriceStaleness`). `IStrategyTokenV2` gains `NotVault` and `ZeroAddress` errors. | The spec says "all non-zero" without naming an error. | none |
| D8 | `VaultDeployerV2.deploy` forwards `msg.data[4:]` as the constructor argument bytes (assembly `create`), instead of `new StrategyVaultV2(params)`. Same ABI, same behaviour, vault ctor validates the arguments. | The calldata to memory to ABI re-encode of `VaultParams` cost about 630 bytes of deployer code. | none |
| D9 | `redeemInKindExcluding` is KEPT (spec fallback (1) would remove it first). Measured saving of removing it: about 40 bytes, because it shares the whole `redeemInKind` body. | Not worth losing the C-11 protection. | none |
| D10 | `maxPriceStaleness` check in `_checkAllFresh` is written `updatedAt + maxPriceStaleness < block.timestamp` (no underflow if a feed ever reports a future timestamp). | robustness | none |

Not implemented: the management fee (S13, excluded by the spec). Nothing else from P0 or P1 was dropped: P0 set, plus redeemInKindExcluding, depositInKind and previewDepositInKind, quoteRedeem and previewRedeemInKind (via lens), registry updateMeta and pagination, engine checkUpkeepRange, are all present.

## 2. Sizes (`forge build --sizes`, solc 0.8.24, evm paris, optimizer 200, via_ir false)

| Contract | Runtime (B) | Initcode (B) | Gate |
|---|---|---|---|
| StrategyVaultV2 | 16,818 | 23,505 | at most 23,500 runtime: ok |
| StrategyFactoryV2 | 5,619 | 6,601 | at most 12,000: ok |
| VaultDeployerV2 | 24,135 | 24,167 | spec 24,000 (135 bytes over the spec figure), EIP-170 24,576: ok with 441 bytes margin |
| MarketplaceRegistryV2 | 6,298 | 6,652 | ok |
| RebalanceEngineV2 | 2,573 | 2,771 | ok |
| StrategyTokenV2 | 2,380 | 3,266 | ok |
| StrategyLens | 4,264 | 4,296 | ok |

The deployer margin is thin: any future addition to the vault of more than about 440 bytes of initcode breaks `VaultDeployerV2`. If more room is needed, the next step is spec fallback (3) (external library for the rebalance leg math, which needs library linking in `DeployV2.s.sol`); not applied.

## 3. Gas (local forge run, 6 constituents, 18 decimal stock tokens, 6 decimal USDG, mint-mode desk, second depositor into a funded vault)

| Operation | Gas | Ceiling (3.2) |
|---|---|---|
| `deposit` (6 legs) | 781,481 | 1.8M |
| `depositInKind` | 305,214 | 600k |
| `redeem` USDG (a quarter of a position, 6 legs sold) | 950,882 | 1.8M |
| `redeemInKind` | 284,771 | 700k |
| `executeRebalance` (threshold hit, shock of +/-15 percent on all six feeds) | 867,129 | 2.2M |
| `checkpoint` | 219,967 | 300k |
| depth-2 `deposit` (3 child vaults with 3 assets each plus 3 stocks) | 2,005,327 | 3.2M |
| depth-2 `redeem` | 2,013,676 | none stated |
| `createStrategy` (6 constituents) | 4,564,701 | 6.5M |
| `VaultDeployerV2` deployment | about 5.0M (code deposit of 24,135 bytes at 200 gas per byte is 4.8M, plus 21k) | 5.5M |

All inside the ceilings. Numbers come from a throwaway probe test kept outside the repo (scratchpad), not from `contracts/test`.

## 4. Behaviour notes for the frontend and ops lanes

- Share decimals are 18; `inceptionSharePrice()` is `1e6` units for `d = 6` and for `d = 18` (that is 1e-12 USDG per share at `d = 18`). Use the function, not a literal 1.00. Share price display: `sharePrice() / 10**usdgDecimals` per 1e18 shares.
- `previewDeposit`, `previewRedeem`, `sharePrice`, `weights`, `totalAssetsUSDG` never check staleness (they revert only if the oracle itself reverts, for example `FeedNotSet`). Mutating functions check every non-strategy feed and recurse into children through `priceStatus()`.
- `redeem` pays physical pro-rata and sells every slice through the venue; it reverts `StalePrice`, `InsufficientLiquidity`, `VenueSlippage`, `ChildRedeemFailed` in the failure modes of spec 5.1. The UI should offer `redeemInKind` on those. `lens.quoteRedeem(vault, shares)` gives the venue aware estimate for `minUsdgOut`; `redeemInKindExcluding(shares, receiver, owner, skipMask)` has bit `i` for constituent `i` and bit `n` for idle USDG.
- `executeRebalance` and `rebalanceNeeded` use `effectiveMaxWeightBps(i)`; the engine skips a vault whose view reverts.
- `redeemInKind` returns the tokens in constituent order with idle USDG last; child strategy tokens come back as child shares.
- `NavCheckpoint(timestamp, totalAssets, totalSupply)` is emitted by deposit, depositInKind, redeem (post state, floor NAV), executeRebalance and `checkpoint()`; not by `redeemInKind`.
- `StrategyVaultV2.guardian()` pauses only deposit, depositInKind and executeRebalance. `paused()` is the OZ `Pausable` view; the error is OZ `EnforcedPause()`.
- Registry meta tags accept `[a-z0-9-]` only, at most 3 tags of at most 16 bytes, description at most 160 bytes. `getStrategies(offset, limit)` clamps; `checkUpkeepRange(offset, limit)` does not clamp `limit` (the registry does).
- Factory reverts `ZeroAddress()` in the constructor when any argument (including `maxPriceStaleness`) is zero.
- No `block.number` anywhere. No constructor argument or storage holds a key or secret.

## 5. Test status and findings about the independent tests (not edited)

Final run, `forge test --match-path "contracts/test/v2/**"` (default profile, 256 fuzz runs, 256 invariant runs, depth 64): 460 passed, 1 failed (461 total). All unit, vector (`test_vector_roundTrip_d6` and `_d18` exact integers), matrix (6 and 18 decimal USDG, 18 and 8 decimal stocks), fuzz and invariant suites pass, including I1 to I11 for both decimals.

The one failure is a test defect, not vault code: `test_gas_executeRebalanceAllLegs` pushes a feed from 250 to 212 (-15.2 percent), above the aggregator `maxDeviationBps` of 1500, so `FengAggregator.updateAnswer` reverts `DeviationTooHigh(21200000000, 25000000000, 1500)` before the vault is reached. Fix: push two steps or stay within 15 percent.

Earlier runs of the same suites (while the tests were being written) showed these test side problems, since fixed or still worth knowing, listed because they are easy to reintroduce:

1. I6 for in-kind deposits must use `valueOf(delta, Floor)` as independent value (spec 1.2); `navAfter(floor) - navBefore(ceil)` differs by up to one unit per non-empty leg.
2. I4 cost bound: the `usdgAmount` of a sell `LegTraded` is the USDG received after the spread, so the notional is `received / (1 - s)`; the bound must use `traded * s / (BPS - s)`.
3. After `oracle.removeFeed` every priced view reverts `FeedNotSet` by design; handlers and invariants must treat that state as expected.
4. I2 round trip is not valid on a vault whose supply was driven to about zero by `redeemInKindExcluding` with a forfeited slice: the next depositor becomes the only holder and redeems the orphaned assets (observed: in 70,715.9 USDG, out 71,355.3 USDG). That is the intended forfeit semantics (spec C-11), the same as a raw donation into an empty vault.
5. I8 desk identity (`donate` USDG to the desk, then `withdrawReserve`) is a desk and ghost accounting matter, unrelated to vault code.

## 5b. Review follow-up (docs/security/review-v2.md: R-V2-09, R-V2-10, R-V2-12)

- R-V2-09 and R-V2-10, `StrategyVaultV2._flags`: `if (total == 0 || supply == 0) return (timeBased, false);` and a leg raises `thresholdBased` only when its weight is above `effectiveMax` and its value is above `target value + _tolerance(total)` (the same bound `_sellPass` uses). A dust vault (about 10 USDG or less) no longer reports a threshold flag it cannot act on, and an empty vault with donated tokens is never "needed". Runtime +128 bytes (16,690 to 16,818); the deployer margin went from 569 to 441 bytes.
- R-V2-12: the two revert strings are now `ZeroAddress()` custom errors, declared in `IRebalanceEngineV2` and `IMarketplaceRegistryV2` (engine constructor with a zero registry, registry constructor with a zero admin). `rg 'require\(|revert\("' contracts/v2` finds nothing.
- Verified with `docs/security/poc-v2/Review.t.sol` copied to a scratch project: `test_dustVaultPerpetualFlag` now logs thresholdBased 0 (was 1 and stayed 1 after `executeRebalance`), `test_emptyVaultDonationFlag` logs thresholdBased 0 (was 1 and `executeRebalance` succeeded).
- Suites after the change: V2 484 passed, 2 failed (486); both failures are `AggregatorTest` (`test_shock_thenRestore`, `test_updateAnswer_withinBound`) and come from the concurrent oracle change, not from the vault, engine or registry. V1 48 of 48.

## 6. Verification record

- `forge build` (whole repo, `FOUNDRY_OUT` and `FOUNDRY_CACHE_PATH` in the scratchpad): clean, no stack-too-deep.
- `forge build --sizes`: table in section 2.
- `forge fmt --check` on every file in lane A: clean after `forge fmt` on the vault.
- V1: `sha256sum` of every V1 `.sol` (contracts excluding `contracts/v2` and `contracts/test/v2`) identical to `docs/handoffs/v1-sources.sha256` at the start and the end; V1 suite 48 of 48.
- No transaction was sent, no key was used, no `.env*` file was read, nothing was pushed or committed. No new dependency (OpenZeppelin 5.7.0 already in `lib/`).
- No code comments in any lane A file.
