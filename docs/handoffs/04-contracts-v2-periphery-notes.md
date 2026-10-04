# 04 Contracts V2 periphery: implementation notes (lane A, agent C2)

Spec: `docs/handoffs/04-contracts-v2.md`. Scope: oracle, desk, mocks, faucet, deploy and seed scripts, ABI sync, `foundry.toml` additions. The vault, factory, registry, engine and token are agent C1.

## Files

Contracts (all under `contracts/v2/`): `interfaces/IVenue.sol`, `interfaces/IPriceOracleV2.sol`, `interfaces/IOracleDesk.sol` (also holds the small `IRegistryGate` interface), `interfaces/IFengAggregator.sol`, `interfaces/IFengFaucet.sol`, `interfaces/IMockUSDGV2.sol`, `oracle/FengAggregator.sol`, `oracle/ChainlinkPriceOracleV2.sol`, `venue/OracleDesk.sol`, `mocks/MockUSDGV2.sol`, `faucet/FengFaucet.sol`.
Scripts: `script/DeployV2.s.sol`, `script/SeedV2.s.sol`, `script/DeployLive.s.sol`, `script/SeedLive.s.sol`, `scripts/deploy-v2.sh`, `scripts/sync-abi.sh`.
This pass (anchor window and deploy hardening) changed `contracts/v2/oracle/FengAggregator.sol`, `script/DeployV2.s.sol`, `scripts/deploy-v2.sh`, `src/lib/abi/generated/fengAggregator.ts` (regenerated; the other modules are rewritten by `scripts/sync-abi.sh` from the current build) and this file. `SeedV2`, `DeployLive`, `SeedLive`, `OracleDesk`, `FengFaucet` are unchanged.
Generated: `src/lib/abi/generated/**` (20 modules plus `index.ts`, written by `scripts/sync-abi.sh`; `strategyLens.ts` is new, `oracleDesk.ts` gained `maxSwapUsdg`, `setMaxSwapUsdg`, `MaxSwapSet`, `SwapTooLarge`).
Config: `foundry.toml` gained `[profile.deep.fuzz]` and `[profile.deep.invariant]` only. V1 compile settings are untouched; V1 `StrategyVault` and `StrategyFactory` creation and runtime bytecode hashes are identical before and after (sha256 recorded in the C2 scratchpad).
No `MockStockTokenV2`: the spec lists none, V2 reuses V1 `MockStockToken` unchanged.

## Deviations from the frozen spec

None in the frozen function set, errors, events or constants, except two added views on `FengAggregator` (`ANCHOR_WINDOW()`, `anchorSetAt()`, item 12) and the `OracleDesk` cap (item 11). Differences that are decisions, not divergences:

1. FengAggregator default `maxDeviationBps` is 1000 (R2, per the assignment) instead of the 1500 in spec 2.4 and 6.2. `maxShockBps` stays 3000, caps stay 5000/5000. Admin `setParams` accepts `1 <= maxDeviation <= 5000` and `maxDeviation <= maxShock <= 5000` (else `InvalidParams`). Since the anchor window (item 12) the old two-step +18 percent path (two back-to-back `updateAnswer` pushes of at most 10 percent) no longer works inside one hour; the demo move is `shockAnswer` (item 12).
2. `AnswerUpdated` is emitted on every new round (update, refresh, shock, force, and once in the constructor), in addition to the specific `AnswerShocked` / `AnswerForced` events, so a Chainlink-style indexer sees every round.
3. `OracleDesk` gates through a local `IRegistryGate.isRegistered(address)` instead of importing C1's `IMarketplaceRegistryV2`, so it compiles without C1. Same selector.
4. `OracleDesk.quoteExactIn` follows the pricing rule literally: zero input or zero output reverts `ZeroAmount`. A vault must skip dust legs before quoting.
5. `OracleDesk.tokenInventory(token)` is the desk's live token balance (also in mint mode); only USDG has funded/withdrawn counters (`accounting()`).
6. (changed, review R-V2-14 / F-09) `DeployV2` on `DEPLOY_NETWORK=robinhood-testnet` reverts unless `RELAYER_ADDRESS` is set and differs from the deployer (`RelayerAddressRequired()`, `RelayerAddressIsDeployer()`) and `FAUCET_ADDRESS` is set and differs from the deployer (`FaucetAddressRequired()`, `FaucetAddressIsDeployer()`). `FAUCET_DISPENSER_ADDRESS` is still read as a fallback name when `FAUCET_ADDRESS` is unset. `GUARDIAN_ADDRESS` may stay unset: the guardian then defaults to the deployer (it is the immutable pauser of every vault; it can only pause deposits, deposit-in-kind and rebalance, never redeem). Any other network name (`anvil`, `dry-local`) keeps the old defaults (all three roles fall back to the deployer) so local rehearsals work unchanged. `scripts/deploy-v2.sh robinhood-testnet deploy|all` also checks both variables before it starts forge, and treats the four errors as a precondition (no retry loop).
7. `maxPriceStaleness` is 43200 (12 h, spec). R2 prefers 6 h for the sandbox; set `MAX_PRICE_STALENESS=21600` before `DeployV2` to switch. It is immutable per factory and desk.
8. Output directory is `deployments/<DEPLOY_NETWORK>-v2/addresses.json`; for `robinhood-testnet` that is the spec path. `live` stock tokens and USDG come from env (`LIVE_*`, defaulted in `deploy-v2.sh`, values from doc 07) so no address literal sits in a `.sol` file; `live.strategyFactory`, `live.venue` are the zero address until E4.
9. `scripts/sync-abi.sh` also generates the eight V1 contracts (`strategyVaultAbi`, `strategyFactoryAbi`, `strategyTokenAbi`, `marketplaceRegistryAbi`, `rebalanceEngineAbi`, `chainlinkPriceOracleAbi`, `mockUsdgAbi`, `mockV3AggregatorAbi`) as the assignment asked; the spec list of 11 is included unchanged.
10. (this pass) `StrategyLens` (C1 request D1) is deployed by `DeployV2` (no constructor args) and written as `lens` in `addresses.json` and into `sync-abi.sh` / `strategyLensAbi`. The frontend reads `quoteRedeem` and `previewRedeemInKind` through it.
11. (this pass, coordinator decision, parameter level only) Faucet daily cap default is now 40 (env `FAUCET_DAILY_CAP`, was a constant 200). `OracleDesk` gained one owner-settable parameter `maxSwapUsdg` (public, default 0 = unlimited, `setMaxSwapUsdg(uint256)` onlyOwner, event `MaxSwapSet`, error `SwapTooLarge(usdgAmount, maxSwapUsdg)`; 17 added lines; constructor and every existing signature unchanged). It caps the USDG side of one `swapExactIn` and of `quoteExactIn` (so `lens.quoteRedeem` reverts instead of promising a swap the desk would refuse). (changed, review R-V2-02(a)) `DeployV2` now calls `desk.setMaxSwapUsdg(5000 whole USDG * 10^usdgDecimals)` on the Sandbox desk (env `SANDBOX_MAX_SWAP_WHOLE_USDG`, whole USDG, default 5000); `DeployLive` keeps 25 USDG on the Live desk (`LIVE_MAX_SWAP_USDG`). Consequence: one deposit, redeem or rebalance leg above 5,000 USDG reverts `SwapTooLarge`, so a 10,000 USDG faucet balance cannot be put into a vault in one deposit when a leg exceeds 5,000 (a two-asset 60/40 vault: legs 6,000 and 4,000 revert; EVMO 40/30/30 passes). The UI should show the per-leg limit (read `maxSwapUsdg()` on the desk). An over-cap deposit, rebalance leg or redeem leg reverts `SwapTooLarge`; the user path is `redeemInKind` or a smaller amount. The interface `IOracleDesk` was not touched (outside this lane's file list), so the new function and error are only on the concrete `OracleDesk` ABI.

12. (this pass, review R-V2-01 / F-01, coordinator decision) `FengAggregator` anchor window, patch `docs/security/poc-v2/F01-anchor-window.patch` applied as written plus one view. `updateAnswer` still requires `|answer - anchor| <= maxDeviationBps * anchor`, but the anchor now moves to the new answer only when `block.timestamp >= anchorSetAt + ANCHOR_WINDOW` (1 hour); inside the window every push is measured against the same anchor, so the price cannot walk `1.1^n`. `forceAnswer` (admin) sets the anchor and restarts the window; the constructor starts a window. `shockAnswer` is unchanged (SHOCK_ROLE, only when `shockEnabled`, bound `maxShockBps` = 3000 from the anchor, never moves the anchor), so the demo +18 percent shock works at any time, also right after deployment. New ABI members, views only: `ANCHOR_WINDOW()` (3600) and `anchorSetAt()` (timestamp of the last anchor move). No function, event or error signature changed (`IFengAggregator` is untouched; the two members exist on the concrete contract only, like `maxSwapUsdg`). Operational consequences: (a) a real-price move larger than `maxDeviationBps` (10 percent) of the anchor cannot be followed by pushes before the window ends: it needs the shock path or `forceAnswer`; (b) a relayer that catches up in several steps in one tick (the ops default `OPS_MAX_STEP_BPS` 900, `OPS_MAX_STEPS_PER_TICK` 3) gets `DeviationTooHigh` on the second step of any catch-up above 10 percent, because the anchor is still the old one; normal 10 bps pushes and heartbeats are unaffected; (c) first seeding does not use stepped pushes: `DeployV2` constructs every feed at `INIT_PRICE_*` (the admin seeds the price at creation), and a later large re-price is `forceAnswer` by the admin (rehearsed below, +40 percent accepted and the anchor follows).
13. (this pass, review R-V2-13 / F-04, coordinator decision) Faucet defaults moved in `DeployV2` (the contract takes them as constructor arguments, it has no defaults of its own): ETH per claim 0.0001 ETH (a V2 transaction costs about 0.00001 ETH at 0.01 gwei), 10,000 mock USDG per claim, daily cap 40 (`FAUCET_DAILY_CAP`), default funding `FAUCET_ETH_FUND_WEI` = `dailyCap * ethPerClaim` = 0.004 ETH, which pays exactly 40 claims.

## Accepted residual risks (coordinator decision, not mitigated in code)

- F-01 relayer walk: MITIGATED in code by the anchor window (item 12): with a stolen `UPDATER_ROLE` key the price stays within `maxDeviationBps` (10 percent) of the anchor for an hour, and the anchor itself moves at most once per hour, so the reachable price is about `1.1^k` after `k` hours, not `1.1^n` in one block. Residual: a stolen key still drifts the price 10 percent per hour (and 30 percent from the anchor when `ENABLE_SHOCK=1` gives it `SHOCK_ROLE`). Operational: `revokeRole`, alert on `AnswerUpdated` frequency, keep the relayer key off any shared machine.
- F-02 desk exposure: the Sandbox desk now has `maxSwapUsdg` 5,000 USDG per swap (item in the deviation list); there is still no per-hour outflow cap, so the reserve of 10,000,000 mock USDG is the maximum loss (worthless by definition). The Live desk is bounded by what the deployer funded (about 30 USDG reserve plus about 3.5 of each token at the R1 sizing) plus `maxSwapUsdg` 25 per swap.
- F-04 faucet funding: CLOSED by item 13 (0.004 ETH at 0.0001 ETH per claim pays 40 claims; cap 40). Shown on a local anvil: 40 claims leave the faucet at 0 wei, claim 41 reverts `DailyCapReached(40)` (0x7d9bfdae). No human check on the server remains an off-chain item.
- F-09 single key: the deployer still holds admin on registry, oracle, desk, every feed, MockUSDG, faucet and the stock tokens; relayer, faucet dispenser are now separate addresses on `robinhood-testnet` and the guardian defaults to the deployer unless `GUARDIAN_ADDRESS` is set. The script never transfers or renounces admin roles.

## Environment variable names

Secrets (read from the environment only, never printed, never written): `DEPLOYER_PRIVATE_KEY`.
Required on `robinhood-testnet` (public addresses, each different from the deployer): `RELAYER_ADDRESS` (gets `UPDATER_ROLE` on all six feeds, plus `SHOCK_ROLE` when `ENABLE_SHOCK=1`), `FAUCET_ADDRESS` (gets `DISPENSER_ROLE` on the faucet; `FAUCET_DISPENSER_ADDRESS` is still accepted as the old name).
Public or tuning: `DEPLOY_NETWORK` (set by `deploy-v2.sh`), `GUARDIAN_ADDRESS` (optional, default deployer), `ENABLE_SHOCK` (`1`), `SANDBOX_MAX_SWAP_WHOLE_USDG` (default 5000), `FAUCET_ETH_FUND_WEI` (default `FAUCET_DAILY_CAP * 0.0001 ether` = 4000000000000000), `FAUCET_DAILY_CAP` (default 40), `INIT_PRICE_TSLA|AMZN|NFLX|PLTR|AMD` (8-decimal integers, spec defaults), `MAX_PRICE_STALENESS` (default 43200), `USDG_DECIMALS` (default 6, rehearsal of the 18 decimal shape), `LIVE_USDG`, `LIVE_TOKEN_TSLA|AMZN|NFLX|PLTR|AMD` (defaulted in `deploy-v2.sh` to the R1 addresses; required by `DeployLive`), `ROBINHOOD_TESTNET_RPC_URL` (optional override).
Live only: `LIVE_MAX_SWAP_USDG` (whole USDG, default 25), `LIVE_DESK_USDG_BPS` (share of the deployer's real USDG sent to the desk reserve, default 3000), `LIVE_DESK_STOCK_BPS` (share of each real token balance sent to the desk, default 7000), `LIVE_MIN_SEED_USDG` (whole USDG, default 15, `SeedLive` aborts below it), `LIVE_SEED_BPS` (share of the deployer's remaining real USDG to deposit, default 10000), `LIVE_HARDFORK` (forge runtime hardfork for the Live scripts, default `osaka`).
Script behaviour: `DEPLOY_MAX_ATTEMPTS` (default 8), `REDEPLOY=1`, `RESEED=1`, `FORGE_EXTRA_ARGS`, dry mode only: `DRY_RPC_URL` (must be local), `DRY_BROADCAST_DIR`, `ANVIL_PORT`, `ANVIL_EXTRA_ARGS`, `KEEP_DRY_OUTPUT=1`.

## Commands

```
export DEPLOYER_PRIVATE_KEY=...   # testnet-only key, exported by the caller, never in a file
export RELAYER_ADDRESS=0x...  FAUCET_ADDRESS=0x...        # both required on robinhood-testnet, both different from the deployer
export GUARDIAN_ADDRESS=0x...                              # optional, default is the deployer
export ENABLE_SHOCK=1                                      # demo shock role for the relayer
scripts/deploy-v2.sh robinhood-testnet all          # deploy then seed (writes deployments/robinhood-testnet-v2/addresses.json)
scripts/deploy-v2.sh robinhood-testnet deploy       # step 1 only
scripts/deploy-v2.sh robinhood-testnet seed         # step 2 only
scripts/deploy-v2.sh robinhood-testnet live-deploy  # Live desk + Live factory, funds the desk from the deployer's real balances
scripts/deploy-v2.sh robinhood-testnet live-seed    # LIVE-AI, LIVE-5, LIVE-CORE sized from the deployer's actual on-chain balances
scripts/deploy-v2.sh robinhood-testnet live         # both Live steps (needs the sandbox deploy first)
scripts/deploy-v2.sh dry all                        # throwaway local anvil, public anvil account, outputs removed
scripts/sync-abi.sh [--build] [--check]             # after forge build; --check fails if generated files are stale
```

Behaviour: `forge script ... --broadcast --slow -vv`. On failure the script compares the broadcast `run-latest.json` hash with its value at start: changed means a partial broadcast, next attempt adds `--resume`; unchanged means nothing was sent, next attempt is a plain retry (so a stale completed file can never be mistaken for progress). It refuses a second deploy or seed while the addresses file points at live code on the chain (`REDEPLOY=1`, `RESEED=1` override). Cast probes are retried. Refuses to start without `DEPLOYER_PRIVATE_KEY` (non-dry). Prints public addresses only.
Live order of operations on the real testnet: (1) `deploy` (and `seed`) the Sandbox set, (2) claim real USDG at https://faucet.paxos.com?token=USDG&network=ROBINHOOD to the deployer address (100 USDG) and the Robinhood stock faucet (5 of each token), verify with `cast call <USDG> "balanceOf(address)(uint256)" <deployer>`, (3) `live-deploy`, (4) make sure the relayer pushed within `maxPriceStaleness` (the Live scripts abort otherwise), (5) `live-seed`. The Live scripts need the same deployer key as the Sandbox set (it owns the shared oracle and is the registry admin). They run forge with `--hardfork osaka` (see Findings) and refuse a second Live set (`live.strategyFactory` already has code, `live.vaults` not empty). Preconditions that abort before any transaction (no retry, message printed): real USDG paused or decimals other than 6, `uiMultiplier() != 1e18`, token paused, no code, deployer not the oracle owner or registry admin, `SeedLive` real USDG balance below `LIVE_MIN_SEED_USDG`, stale shared feed, desk inventory below the computed need.
Caveat: both scripts write the JSON during the simulation phase (as V1 does), so a failed broadcast leaves a file whose addresses are predictions; the `has_code` guard handles this.
Caveat: `forge script` compiles `contracts/test/**` too. While tests are mid-edit, pass `FORGE_EXTRA_ARGS="--skip contracts/test/**"`.

## Rehearsal, anchor window pass (no code size limit disabled anywhere)

Plain local anvil (chain 31337, default EIP-170), public anvil accounts only: 0 deployer, 1 relayer (`RELAYER_ADDRESS`), 2 engine caller, 3 faucet dispenser (`FAUCET_ADDRESS`), 5 user. `ENABLE_SHOCK=1 DRY_RPC_URL=http://127.0.0.1:18647 KEEP_DRY_OUTPUT=1 FORGE_EXTRA_ARGS="--skip contracts/test/**" USDG_DECIMALS=<6|18> scripts/deploy-v2.sh dry all`: both decimal shapes deployed and seeded 10 strategies (exit 0, `VaultDeployerV2` passes the default limit). Then, on EVMO (TSLA 40 / AMD 30 / PLTR 30), identical at 6 and 18 decimals:

| Step | Result |
|---|---|
| desk `maxSwapUsdg()` | 5,000 USDG in units (5000000000 at 6 decimals, 5000e18 at 18) |
| faucet params / balance | 0.0001 ETH, 10,000 USDG, cap 40, balance 0.004 ETH; `DISPENSER_ROLE`: acct 3 true, deployer false |
| `claimFor(user)` | ok, user gets exactly 0.0001 ETH and 10,000 USDG; second claim `AlreadyClaimed` (0x2058b6db) |
| 40 claims, then claim 41 | `claimsToday` 40, faucet balance 0 wei; claim 41 `DailyCapReached(40)` (0x7d9bfdae) |
| relayer pushes inside one window (anchor 371.62) | +0.1 percent ok, +8 percent ok, +9.99 percent ok, +10.01 percent of the anchor `DeviationTooHigh` (0x9b666618), anchor unchanged; a 10 bps down push and `refresh()` ok |
| `shockAnswer` +18 percent of the anchor, relayer | ok (438.51), anchor stays 371.62; deployer (no role) reverts `AccessControlUnauthorizedAccount` (0xe2517d3f); +30.01 percent `ShockTooHigh` (0x5adbd904) |
| `performRebalance` from acct 2 (not the deployer) | weights [4402, 2798, 2798] to [4000, 2999, 2999], `rebalanceNeeded` (false, false) after |
| after +1 h | push anchor +9 percent ok and the anchor moves (`anchorSetAt` advances); +9 percent more ok; +15 percent of the new anchor `DeviationTooHigh`; `forceAnswer` by the relayer reverts, by the admin +40 percent ok and the anchor follows |
| `redeem` half (after the price is forced back) | NAV (`previewRedeem`) 502.749007 USDG (6 dec), `lens.quoteRedeem` 502.246257, paid 502.246257: NAV minus paid is 10.0000 bps of NAV (same at 18 decimals, 502.749009 to 502.246260) |
| `redeemInKind` of the remainder | ok, shares 0 |

Precondition checks (forge script, `DEPLOY_NETWORK=robinhood-testnet`, simulation against the local anvil, nothing broadcast): no `RELAYER_ADDRESS` `RelayerAddressRequired()`; relayer equal to the deployer `RelayerAddressIsDeployer()`; no `FAUCET_ADDRESS` `FaucetAddressRequired()`; faucet equal to the deployer `FaucetAddressIsDeployer()`; both set and distinct: runs, guardian in `addresses.json` equals the deployer; the old name `FAUCET_DISPENSER_ADDRESS` still accepted. `scripts/deploy-v2.sh robinhood-testnet deploy` without `RELAYER_ADDRESS` stops before any forge or network call.

Tests with the anchor window and the new defaults: V1 48 passed; V2 `forge test --match-path "contracts/test/v2/**"` 484 passed, 2 failed (486). The two failures are tests that assume the anchor moves on every push, to be adapted by the test lane (`vm.warp(1 hours)` between steps or an assertion on the unchanged anchor): `Aggregator.t.sol::test_updateAnswer_withinBound` (asserts `anchorAnswer() == 460e8` right after the first push, now still 400e8) and `Aggregator.t.sol::test_shock_thenRestore` (asserts the anchor is 405e8 after the restore push, now still 400e8). No test depends on `DeployV2` or on the old 0.0002 ETH default.

## Rehearsal, first pass (no code size limit disabled anywhere)

No `--disable-code-size-limit` on forge or anvil. Plain local anvil (chain 31337, default EIP-170) and a local `anvil --fork-url https://rpc.testnet.chain.robinhood.com` (chain 46630, started with `--retries 60 --fork-retry-backoff 300`; `forge`/`cast` against it hit `database error` on TLS interception now and then, the helper retried). Anvil account 0 (public) is the deployer and relayer, account 1 calls the engine, account 2 is the user. No key other than anvil's public ones was used and nothing was sent to a real network.

Commands (scratch helpers `rehearse.sh`, `gas.sh` live in the C2 scratchpad, not in the repo):
```
FOUNDRY_OUT=<scratch>/out-c2 FOUNDRY_CACHE_PATH=<scratch>/cache-c2
DRY_RPC_URL=http://127.0.0.1:18547 DRY_BROADCAST_DIR=<dir> KEEP_DRY_OUTPUT=1 ENABLE_SHOCK=1 \
  FORGE_EXTRA_ARGS="--skip contracts/test/**" scripts/deploy-v2.sh dry all          # USDG_DECIMALS=6 and again with USDG_DECIMALS=18
```
Result: all 10 strategies deployed and seeded at both 6 and 18 decimals (`VaultDeployerV2` 24,007 bytes passes the default limit). Then with `cast` on EVMO (TSLA 40 / AMD 30 / PLTR 30), identical flow at both decimals:

| Step | USDG 6 | USDG 18 |
|---|---|---|
| faucet `claimFor(user)` (10,000 USDG), second claim | ok, `AlreadyClaimed` (0x2058b6db) | same |
| `deposit` 1,000 USDG | 999.000994 shares, gas 378,275 (0x5c5a3) | 999.000999 shares |
| TSLA 371.62 to 438.45 (+17.98%) in two `updateAnswer` of +8.62% | both accepted | same |
| +25% in one `updateAnswer` | `DeviationTooHigh` (0x9b666618) | same |
| single `shockAnswer` +18% on AMD (bound 3000) | accepted, gas 45,847 | n/a |
| weights, `rebalanceNeeded` | [4402, 2798, 2798], (false, true) | same |
| `performRebalance` from account 1 (not the deployer) | ok, gas 416,877, weights [4000, 2999, 2999], (false, false) | same |
| `checkpoint()` after +31 min | ok, gas 130,401 | ok |
| `redeem` half: `previewRedeem` (NAV) / `lens.quoteRedeem` / paid | 535.387582 / 534.852193 / 534.852193 | 535.387584 / 534.852197 / 534.852197 |
| NAV minus payout | 0.535389 USDG = 10.000 bps (exactly the desk sell spread) | 10.000 bps |
| `redeemInKind` of the remainder | ok, shares 0, tokens in constituent order, idle USDG 0 | same |

Spec tolerance: the vault's per leg slippage bound is `maxSlippageBps` 100; the observed gap to NAV is 10 bps, so the redeem is NAV minus the desk spread inside the tolerance, and payout equals `quoteRedeem` to the unit.

`maxSwapUsdg` demo (sandbox desk, USDG 18 decimals, cast): default 0; a non-owner `setMaxSwapUsdg` reverts `OwnableUnauthorizedAccount` (0x118cdaa7); owner set 100 USDG (`MaxSwapSet`); EQ5 deposit of 1,000 USDG (five legs of 200) reverts `SwapTooLarge` (0xe07292c4) and `quoteExactIn` of 150 USDG reverts the same; a deposit of 400 (legs of 80) succeeds; reset to 0 and the 1,000 USDG deposit succeeds.

### Gas and transaction count (anvil fork of the real testnet, receipts from the broadcast files)

| Script | Transactions (creations) | Total gas | ETH at 0.01 gwei (`cast gas-price` on the real chain returned 10,000,000 wei) |
|---|---|---|---|
| `DeployV2` (incl. `StrategyLens`, 0.004 ETH sent to the faucet) | 59 (20) | 25,697,071 | 0.000257 |
| `SeedV2` (10 strategies, 26,200 mock USDG seeded) | 31 | 51,319,046 | 0.000513 |
| `DeployLive` (second desk and factory, five feeds, funding) | 26 (2) | 4,910,922 | 0.000049 |
| `SeedLive` (3 strategies, about 70 real USDG) | 9 | 16,798,058 | 0.000168 |
| Total | 125 | 98,725,097 | 0.000987 |

Anvil has no L1 fee component. `eth_estimateGas` on the real RPC (a read, no transaction) for the same creation bytecode gave 5,726,533 for `VaultDeployerV2` against 5,215,214 on anvil (+9.8 percent) and 1,072,981 for `StrategyLens` against 974,148 (+10.1 percent), so budget about 1.1x: about 0.0011 ETH of gas for everything, plus the 0.004 ETH funding of the faucet (recoverable with `withdrawEth`). The deployer held 0.00818 ETH when last read, which covers it. A forge dry estimate without `--broadcast` cannot price `SeedV2` or `SeedLive` before the factory exists on the chain, so the seed numbers come from the local broadcast.

### Live rehearsal (fork of the real testnet, real tokens at their real addresses, no fakes except the failure cases)

Funding: no key exists, so the real holders were impersonated on the local fork only (`anvil_impersonateAccount`, USDG holder 0x545F...b983, stock holder 0x13aF...FaFFb) to give anvil account 0 exactly 100 USDG and 5 of each token, the shape of the real deployer after the faucets.
- `deploy-v2.sh dry live-deploy`: `uiMultiplier() == 1e18`, USDG decimals 6, not paused: ok; `setFeed(realToken, sandboxFeed)` for five tokens; second `OracleDesk` (Inventory mode, `maxSwapUsdg` 25 USDG), second `StrategyFactoryV2`, `FACTORY_ROLE` on the shared registry; desk funded 30 USDG and 3.5 of each token (30 percent and 70 percent of the deployer balances read on chain). The `live` object in `addresses.json` was written with `strategyFactory`, `venue`, `maxSwapUsdg`, `deskSpreadBps` (schema 5.3 plus those two extra keys).
- `deploy-v2.sh dry live-seed` sized the deposits from the real balance: LIVE-AI 24.5, LIVE-5 24.5, LIVE-CORE (nested, depth 2) 21.0 USDG; `live.vaults` written with `universe: "live"` and depth. Registry `strategyCount` 13 (10 sandbox plus 3 live).
- On chain after the seed: `LIVE-5` redeem of half the shares, NAV 12.237762, `quoteRedeem` 12.225525, paid 12.225525 (9.999 bps, spread 10 bps). Real TSLA `depositInKind` of 0.01 TSLA into LIVE-CORE minted shares (it needs a vault where TSLA is below max weight; 0.5 TSLA into LIVE-5 correctly reverted `ExceedsMaxWeight`). LIVE-AI deposit of 100 USDG reverted `SwapTooLarge`, 50 USDG succeeded. A +8.62% push on the shared sandbox TSLA feed moved LIVE-5 weights to [2135, 1966, ...]; `engine.checkUpkeep` listed it and `performRebalance` from a non-deployer returned [2000, 1999, ...]. So one relayer serves both universes.
- Aborts, nothing sent: `SeedLive` with the deployer holding 0.175 real USDG printed the balance, the budget and the 15,000,000 unit minimum and reverted `SeedLive: deployer real USDG is below the minimum. Claim USDG at https://faucet.paxos.com, then retry`; `DeployLive` with `LIVE_TOKEN_TSLA` pointed at a code stub returning 2e18 reverted `DeployLive: uiMultiplier is not 1e18 for TSLA`; with no code, `DeployLive: no code for TSLA`.

Tests: `forge test --match-path "contracts/test/v2/**"` in the C2 out dir after the `OracleDesk` change: 486 passed, 0 failed (34 suites). V1 hashes in `docs/handoffs/v1-sources.sha256` all OK. `forge fmt --check` clean on the changed `.sol` files.

### Findings from the rehearsal

1. Real Stock tokens run solc 0.8.33 for evm osaka; forge's default runtime hardfork follows `evm_version = paris`, so a script that calls a real token fails in simulation with `EvmError: NotActivated`. The Live scripts must run with `--hardfork osaka` (runtime only, it does not change the compile target of the contracts we deploy). `deploy-v2.sh` adds it for `*Live.s.sol` (`LIVE_HARDFORK` overrides). Anything else that simulates against the real tokens (tests, tools) needs the same.
2. `eth_estimateGas` on anvil returns the bare minimum: `redeem` sent with gas limit exactly equal to the estimate ran out of gas (limit 516,639, refunds only apply after) in about one run in three. Rehearsal sends use +30 percent. The frontend must add a gas buffer (a quarter or more) to estimates for `redeem`, `deposit` and `performRebalance`; flagged to C1/frontend.
3. The desk does not wrap a reverting real token (pause, blocklist) into `InsufficientLiquidity`; the swap reverts with the token's own error (R1 suggested wrapping; not done, the function set is frozen). The UI should treat any desk revert as "use redeemInKind".

## Cut-line items

None dropped by this lane. `FengAggregator.shockAnswer`/`SHOCK_ROLE`, desk inventory mode and the faucet are all implemented.

## Requests

1. Resolved by C1: the EIP-170 request is closed (`VaultDeployerV2` 24,007 bytes, margin 569). The margin is thin; any vault change above about 550 bytes of initcode breaks it.
2. R2 mentions an optional `lastChangeAt()` view on the aggregator; not added because the function set is frozen (the anchor window added only `ANCHOR_WINDOW()` and `anchorSetAt()`). Request to add it if the UI wants "market closed, price unchanged since Friday".
3. Frontend: read `quoteRedeem` and `previewRedeemInKind` through `StrategyLens` (`lens` in `addresses.json`); add a gas buffer to estimates (Finding 2); treat `SwapTooLarge` on the Live desk as "use redeemInKind or a smaller amount"; filter vaults by the `universe` field (`sandbox` vs `live`) because both factories share one registry; Live strategies must show the "admin-controlled tokens" disclosure from R1.
4. Coordinator: the Live scripts need the Paxos and Robinhood faucet claims first (human step H1/H2 in R1) and the same deployer key as the Sandbox set.
5. Optional (C1 file, not done): `IOracleDesk` does not declare `maxSwapUsdg`; add it if the UI should read the cap through the interface.

## Open risks

- The relayer key can steer sandbox prices (and, through the shared feeds, Live prices) by 10 percent of the anchor per hour (30 percent from the anchor on the shock path when enabled); revoke with `revokeRole` (F-01, mitigated by the anchor window, not removed).
- Ops (`src/ops/relayer.ts`, not in this lane, to hand over): (1) for a `feng` feed it simulates and sends `pushAnswer(int256)`, but `FengAggregator` exposes `updateAnswer(int256)`; `src/ops/abi.ts` `fengAggregatorWriteAbi` has to be corrected or no push will ever land on V2; (2) its catch-up of a move above 10 percent (steps of 900 bps, three per tick) fails with `DeviationTooHigh` from the second step because the anchor does not move inside an hour: for a large re-price use `forceAnswer` (admin) or wait one window per step; read `anchorSetAt()` to know when the anchor may move. Because Live reads the same feeds, a relayer outage or weekend heartbeat staleness also stops Live deposits (`StalePrice`); `SeedLive` aborts on a stale feed.
- The Live desk quotes at the sandbox oracle with a 10 bps spread against a real token stock held in inventory: a stale or manipulated price lets a trader drain the funded inventory up to `maxSwapUsdg` per swap, repeatedly (F-02, accepted; funds at risk are only what the deployer put in the desk, about 30 USDG and 3.5 of each token at the R1 sizing).
- Real USDG and Stock tokens are admin controlled (pause, freeze or blocklist, upgrade). If the Live vault or desk address is frozen, deposits and redeems revert and funds sit until the admin acts (R1 section 2 and 3). Sandbox is the default product; Live is additive.
- `deploy-v2.sh` gas costs above come from a local anvil run, not the real chain; real fees add an L1 component (about 10 percent on the two probes). Faucet funding of 0.004 ETH at 0.0001 ETH per claim covers the 40 claims of the daily cap.
- `forge script` still compiles `contracts/test/**` unless `--skip` is passed; the scripts write `addresses.json` during simulation (including a Live `strategyFactory` prediction), so after a failed Live broadcast the file holds predictions; the `has_code` guards and `DeployLive` itself handle this.
- The Live seed splits the real USDG 35/35/30 across LIVE-AI, LIVE-5, LIVE-CORE after the 30 percent desk funding; with 100 USDG that is 24.5, 24.5 and 21.0, each inside the 25 USDG per-swap cap by construction (`_capped` shrinks a deposit rather than letting a leg exceed the cap).
- `forge fmt` was run on all C2 files; generated ABI files are not formatted and may trip a repo-wide Prettier or ESLint run (frontend lane to ignore the directory).

## Not done

- No transaction was sent to the real testnet by this lane and no real key was used. The real-testnet run of `DeployV2`, `SeedV2`, `DeployLive`, `SeedLive` is pending the deployer's key, the faucet claims, and the coordinator's go.
- `IOracleDesk` and the generated frontend types do not expose `maxSwapUsdg` through the interface (see Requests 5).
- Per-hour desk outflow cap (F-02) and the faucet human check (F-04): accepted residual risks, not implemented. The F-01 rate limit is now the anchor window (item 12).
- `docs/handoffs/RUNBOOK-DEPLOY.md` (outside this lane) still names `FAUCET_DISPENSER_ADDRESS`, a 0.004 ETH funding that "pays 20 claims" and says `RELAYER_ADDRESS` may be left unset; it needs the new names and the two required variables.
