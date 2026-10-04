# V2 code review checklist (E8-T3, second dispatch)

- **Version**: 1.0, 2026-10-03. Author: independent security reviewer. Companion to `docs/security/threat-model.md` (threats `T-xx`, findings `F-xx`).
- **Reads from**: `docs/handoffs/04-contracts-v2.md` ("the spec"): section 1.1 findings `C-01` to `C-36`, section 4.3 invariants `I1` to `I11`, section 3.5 build gates, section 6 deploy plan.
- **Output of the review**: `docs/security/review-v2.md` (template at the end). Rule from the plan: no open High or Critical before G1.
- **Row ids**: `P-xx` preflight, `G-xx` global code gates, `C-xx` and `I-xx` spec ids, `V-xx` invariant-suite quality, `X-xx` extra checks derived from the threat model, `M-xx` mutation tests, `D-xx` post-deploy read-only checks.

## 0. Setup (do this first, never skip the redirect)

The repository is read-only for the reviewer. `forge build` and `forge test` write `out/` and `cache/`; redirect both outside the repo with environment variables (verified to work with forge 1.8.3). Never read or print any `.env*` file.

```bash
cd "/home/cn/Projects/Competition/Web3/Arbitrum/Feng."
SCR="<session scratchpad dir>/review-v2"; mkdir -p "$SCR"   # any directory outside the repo; never inside it
export FOUNDRY_OUT="$SCR/out" FOUNDRY_CACHE_PATH="$SCR/cache"
V=contracts/v2; T=contracts/test/v2
VAULT=$V/StrategyVaultV2.sol  FACT=$V/StrategyFactoryV2.sol  DEP=$V/VaultDeployerV2.sol
DESK=$V/venue/OracleDesk.sol  AGG=$V/oracle/FengAggregator.sol  ORA=$V/oracle/ChainlinkPriceOracleV2.sol
REG=$V/MarketplaceRegistryV2.sol  ENG=$V/RebalanceEngineV2.sol  FAU=$V/faucet/FengFaucet.sol
TOK=$V/StrategyTokenV2.sol  USD=$V/mocks/MockUSDGV2.sol  SPEC=docs/handoffs/04-contracts-v2.md
rgn() { rg -n --no-heading "$@"; }                    # ripgrep 15 with PCRE2 (-P) is installed
ft() { forge test --match-path "$T/**" --match-test "$1" -vv; }   # run one named test
```

Pass criterion notation: "none" means the command must print nothing. If a file in the variable list does not exist, that is a finding (spec section 3.4 lists every path).

## 1. Preflight gates

- **P-01**
  - Check: V1 sources byte-identical (spec S1, section 3.3)
  - Command: `sha256sum -c docs/handoffs/v1-sources.sha256`
  - Pass: every line `OK`
- **P-02**
  - Check: Toolchain config unchanged
  - Command: `forge config --json | jq -c '{solc,evm:.evm_version,via_ir,runs:.optimizer_runs}'`
  - Pass: `0.8.24`, `paris`, `false`, `200`
- **P-03**
  - Check: Deep profile is additive and correct
  - Command: `FOUNDRY_PROFILE=deep forge config --json | jq -c '{f:.fuzz.runs,i:.invariant.runs,d:.invariant.depth,r:.invariant.fail_on_revert}'`
  - Pass: `1000`, `2000`, `64`, `true`
- **P-04**
  - Check: Build clean, no stack-too-deep, no warnings from V2 files
  - Command: `forge build 2>&1 | tail -20; forge build --force 2>&1 | rg -A4 -i 'warning' | rg 'contracts/v2'`
  - Pass: build succeeds; second command prints none
- **P-05**
  - Check: EIP-170 sizes (spec 3.5)
  - Command: `forge build --sizes 2>&1 | rg 'StrategyVaultV2|StrategyFactoryV2|VaultDeployerV2|OracleDesk|FengFaucet'`
  - Pass: runtime size column: vault at most 23,500, factory at most 12,000, deployer at most 24,000, all under 24,576
- **P-06**
  - Check: Format
  - Command: `forge fmt --check`
  - Pass: exit 0
- **P-07**
  - Check: V1 suite still green
  - Command: `forge test --no-match-path "contracts/test/v2/**" 2>&1 | tail -4`
  - Pass: `48 passed, 0 failed`
- **P-08**
  - Check: V2 suite green at default profile
  - Command: `forge test --match-path "$T/**" 2>&1 | tail -6`
  - Pass: 0 failed; record the pass count
- **P-09**
  - Check: Deep profile
  - Command: `FOUNDRY_PROFILE=deep forge test --match-path "$T/invariant/**" 2>&1 | tail -8` and `FOUNDRY_PROFILE=deep forge test --match-path "$T/fuzz/**" 2>&1 | tail -8`
  - Pass: 0 failed (at least one deep run is a G1 requirement)
- **P-10**
  - Check: Coverage (spec 4.7)
  - Command: `forge coverage --report summary --no-match-coverage "(contracts/mocks|contracts/v2/mocks|contracts/test|script)" 2>&1 | tail -30`; on stack-too-deep repeat with `--ir-minimum` and say so
  - Pass: lines at least 90 percent, branches at least 80 percent on `contracts/v2/**`
- **P-11**
  - Check: Gas ceilings (spec 3.2)
  - Command: `forge test --match-path "$T/**" --gas-report 2>&1 | rg 'deposit|redeem|executeRebalance|checkpoint|createStrategy|deploy'`
  - Pass: within the table in spec 3.2; more than 25 percent over is a Request, not a silent relax
- **P-12**
  - Check: Test names promised by spec 4.4 exist
  - Command: `forge test --match-path "$T/**" --list > "$SCR/list.txt" 2>&1; for n in $(rg -o 'test_[A-Za-z0-9_]+' $SPEC | sort -u | rg -v '_$'); do rg -q "$n" "$SCR/list.txt" || echo "MISSING $n"; done`
  - Pass: no `MISSING` for names that are not wildcards (`test_reentrancy_*` is checked in I10)
- **P-13**
  - Check: ABI matches spec 2.6
  - Command: see the command under C-31
  - Pass: no diff

## 2. Global code gates (grep, all over `contracts/v2`, tests excluded unless stated)

- **G-01**
  - Rule: pragma `^0.8.24` only
  - Command: `rgn 'pragma solidity' $V | rg -v '\^0\.8\.24'`
  - Pass: none
- **G-02**
  - Rule: custom errors only, no revert strings
  - Command: `rgn 'require\(|revert\("' $V`
  - Pass: none
- **G-03**
  - Rule: never `block.number` (Nitro semantics, R-10)
  - Command: `rgn 'block\.number|blockhash|prevrandao|difficulty' $V`
  - Pass: none
- **G-04**
  - Rule: no hardcoded addresses in `.sol`
  - Command: `rgn -P '0x[0-9a-fA-F]{40}\b' $V script`
  - Pass: none in contracts; `script/` may hold the Live constants only (Paxos USDG `0x7E955252...802F` and the five Stock token addresses), each asserted in the script (X-13)
- **G-05**
  - Rule: dangerous opcodes and patterns
  - Command: `rgn 'tx\.origin|selfdestruct|delegatecall|assembly|ecrecover|\.send\(' $V`
  - Pass: none; `unchecked`, `.call{value` reviewed by hand (only the faucet may use `.call{value`)
- **G-06**
  - Rule: no code comments (convention)
  - Command: `rgn -P '^\s*(//(?!\s*SPDX)|/\*)' $V`
  - Pass: none
- **G-07**
  - Rule: SafeERC20 for every ERC-20 call
  - Command: `rgn -P '\.(transfer|transferFrom|approve)\(' $V` and `rgn 'using SafeERC20' $VAULT $DESK $FAU`
  - Pass: first prints none (raw ERC-20 calls); second shows the three files
- **G-08**
  - Rule: no infinite approvals
  - Command: `rgn 'type\(uint256\)\.max|safeIncreaseAllowance|2 \*\* 256' $V`
  - Pass: none (see also C-23)
- **G-09**
  - Rule: every mutating external of the vault is guarded
  - Command: `forge inspect StrategyVaultV2 abi --json | jq -r '.[]|select(.type=="function" and .stateMutability!="view" and .stateMutability!="pure")|.name'` then `rgn -B3 'function (deposit|depositInKind|redeem|redeemInKind|redeemInKindExcluding|executeRebalance|checkpoint)\(' $VAULT | rg 'nonReentrant'`
  - Pass: each name in the first list is either `pause`/`unpause` (guardian only) or carries `nonReentrant`; every balance-reading view carries `nonReentrantView` (`rgn 'nonReentrantView' $VAULT`)
- **G-10**
  - Rule: no transient storage (evm paris)
  - Command: `rgn -i 'transient|tload|tstore' $V`
  - Pass: none
- **G-11**
  - Rule: key hygiene in scripts
  - Command: `rgn -e 'set -x' -e 'printenv' -e '--private-key' -e 'echo[^\n]*(KEY|SECRET)' -e 'source[^\n]*\.env' -e 'cat[^\n]*\.env' scripts script src/ops 2>/dev/null`
  - Pass: no `set -x`, no echo of a secret, no `.env` access; `--private-key` flags are findings of Low severity (argv exposure) unless the key comes from an env variable inside `vm.envUint`
- **G-12**
  - Rule: repo-wide secret scan, never printing values
  - Command: `rg -l --hidden -g '!.env*' -g '!node_modules' -g '!.next' -g '!lib' -g '!out' -g '!cache' -g '!pnpm-lock.yaml' -e '0x[0-9a-fA-F]{64}' .`
  - Pass: only files whose hits are transaction hashes or the public Anvil default key (`dev/fixture`); verify the Anvil hit with `rg -c 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' dev/fixture/script/Deploy.s.sol` (prints a count, not a key). Any other hit: stop and report without echoing it
- **G-13**
  - Rule: logging in scripts never prints secrets
  - Command: `rgn -i 'console2?\.log[^;]*(key|secret|private)' script src/ops scripts`
  - Pass: none
- **G-14**
  - Rule: `.gitignore` covers env files
  - Command: `rgn '^\.env' .gitignore`
  - Pass: `.env*` ignored
- **G-15**
  - Rule: no deployer-only back doors
  - Command: `rgn -i 'onlyOwner|onlyRole|DEFAULT_ADMIN_ROLE|guardian' $V`
  - Pass: every hit is in the privileged-function inventory (X-15)

## 3. Spec findings C-01 to C-36

Each row has: what to verify in code, the command, the named test, and the pass criterion. "Test" lines use the `ft` helper from section 0 and the names fixed in spec 4.4. If a named test is missing, the row fails until it exists.

### C-01 (H) NAV includes idle USDG; redeem is physical pro-rata
- Code: `rgn 'balanceOf\(address\(this\)\)' $VAULT` shows idle USDG read inside the NAV function; V1 payout shape is gone: `rgn -P 'usdgToken\.balanceOf\(address\(this\)\)\s*\*\s*\w+\s*/' $VAULT` prints none.
- Tests: `ft test_deposit_idleIncludedInNav`, `ft test_redeem_equalsQuoteWithinDust`, `ft test_redeem_lastHolderDrainsEverything`; invariant `invariant_previewSumEqualsNav` (I1).
- Pass: `previewRedeem(totalSupply()) == totalAssetsUSDG()` exactly; last holder leaves zero stranded value.

### C-02 (H) Delegated redeem uses the caller's allowance, never the vault's
- Code: `rgn 'burnFrom' $V`; `rgn '_spendAllowance' $TOK`; the vault must pass `msg.sender` as the spender: `rgn -B3 -A3 'burnFrom\(' $VAULT`; no V1 pattern: `rgn -P 'safeTransferFrom\([^)]*owner' $VAULT` prints none.
- Tests: `ft test_redeem_vaultApprovalDoesNotAuthorizeCaller`, `ft test_redeem_delegatedNeedsAllowanceOfCaller`.
- Pass: an owner who approved the vault (not the caller) is not redeemable by a stranger; an owner who approved the caller is, for exactly the allowance. Mutation M-02 must be killed.
- Evidence of the V1 defect: `docs/security/poc/V1Exploits.t.sol` `test_poc_delegatedRedeemHole`.

### C-03 (H) Decimals everywhere through `valueOf`/`tokensForValue`
- Code: `rgn '1e18|10 \*\* 18|10\*\*18' $VAULT $DESK` every hit is a price scale (18-decimal oracle price) or the share scale, never a USDG unit; `rgn 'usdgDecimals|USDG_UNIT' $VAULT`.
- Tests: `ft test_vector_roundTrip_d6`, `ft test_vector_roundTrip_d18` (exact integers of spec 1.8: shares, payout, `sharePrice()`); decimals matrix: `forge test --match-path "$T/**" --list 2>&1 | rg -i 'decimals|_d6|_d18|matrix'` must show the four cells (6/18, 18/18, 6/8, 18/8).
- Pass: exact vectors; no overflow at `1e12 * U` deposits.

### C-04 (H) Virtual shares per decimals
- Code: `rgn 'VIRTUAL_(SHARES|ASSETS)' $VAULT`; definition equals `1` and `10 ** max(18 - d, 12)` (`rgn -P 'max\(\s*18\s*-' $VAULT`, or an equivalent expression; compute by hand for `d` in {0, 6, 12, 18}).
- Tests: `ft test_inceptionSharePriceExact` for 6 and 18; `forge test --match-contract InflationAttackV2` (I11).
- Pass: inception price is exactly `1e6` units for `d <= 6` and `d = 18`. Independent model result in `threat-model.md` T-01.

### C-05 (M) V1 donation test superseded
- Code: `rgn 'rawUsdgDonation' $T` prints none; `rgn -il 'donat' $T` prints the V2 property files.
- Pass: V2 asserts "donation never profits the donor", not "NAV unchanged".

### C-06 (H) No `grantRole` on constituents
- Code: `rgn -i 'grantRole|IAccessControl|hasRole' $FACT $DEP $VAULT $ENG $REG` prints none (the registry grants its own `FACTORY_ROLE` through `AccessControl` internals only; flag any explicit call).
- Tests: `ft test_noGrantRoleCallsOnConstituents`, `ft test_realTokenWithoutMinterRoleAccepted`.

### C-07 (M) Factory bounds
- Code: `rgn 'MAX_CONSTITUENTS|MIN_WEIGHT_BPS|MAX_SLIPPAGE_BPS|MIN_REBALANCE_INTERVAL|MAX_REBALANCE_INTERVAL|MAX_DEPTH' $FACT` values 6, 100, 500, 1 hours, 365 days, 2; `rgn 'isSupported' $FACT` on oracle and venue for non-strategy tokens; name 1 to 48 bytes, symbol 2 to 10 bytes.
- Tests: every error of spec 2.7 is exercised: `for e in $(sed -n '/^interface IStrategyFactoryV2/,/^}/p' $SPEC | rg -o 'error (\w+)' -r '$1'); do rg -q "\b$e\b" $T/unit $T/invariant || echo "UNTESTED $e"; done` prints none.

### C-08 (M) Oracle V2 shape; V1 oracle frozen
- Code: `rgn 'function (isSupported|priceDecimals)' $ORA`; `sha256sum -c docs/handoffs/v1-sources.sha256 | rg oracle`.
- Tests: oracle V2 unit tests (`isSupported`, `priceDecimals`, `removeFeed`, `InvalidPrice`). Also see X-08 for the bounds I recommend.

### C-09 (H) Nested freshness through `priceStatus()`
- Code: `rgn 'priceStatus' $VAULT`; `_checkAllFresh` calls the child, `rgn 'StalePrice' $VAULT`; `priceStatus` never reverts (try/catch around oracle calls).
- Tests: `ft test_nested_staleChildBlocksParent`, `ft test_priceStatus_recursesIntoChild`.

### C-10 (M) `quoteRedeem` is venue-aware and recursive
- Code: `rgn 'function quoteRedeem' $VAULT $V/StrategyLens.sol`; child legs recurse into the child's quote. If the function lives in `StrategyLens` (spec 3.5 fallback 2, size gate) record it as an accepted deviation, check that the lens is stateless and view-only, and note that it is not protected by the vault's `nonReentrantView` (acceptable only because nothing on-chain consumes it).
- Tests: `ft test_redeem_equalsQuoteWithinDust`, `ft test_redeem_minUsdgOutEnforced`.

### C-11 (H) In-kind redeem includes idle USDG; skip mask
- Code: `rgn 'redeemInKindExcluding|skipMask|InvalidSkipMask' $VAULT`; returned arrays end with USDG; bits above `n` revert.
- Tests: `ft test_redeemInKind_returnsAllConstituentsAndIdle`, `ft test_redeemInKindExcluding_skipsFrozenToken`, `ft test_redeemInKindExcluding_invalidMask`, `ft test_redeemInKind_childSharesNotUnwound`.
- Pass: with `BlockableUSDG` or a `BlocklistToken` frozen, the exit with the frozen slot skipped succeeds and forfeited slices stay in the vault (remaining holders gain exactly that amount).

### C-12 (L) OZ `Pausable`, no custom `Paused` error
- Code: `rgn 'Pausable' $VAULT`; `rgn 'error Paused' $V` none; `rgn 'whenNotPaused' $VAULT` appears on exactly `deposit`, `depositInKind`, `executeRebalance` (inspect with `rgn -B2 -A4 'whenNotPaused' $VAULT`); never on `redeem*` or `checkpoint`.
- Tests: `ft test_redeem_neverPaused`, `ft test_deposit_revertsWhenPaused`, `ft test_pause_onlyGuardian`; `invariant_paused_redeemStillWorks`.

### C-13 (M) `NavCheckpoint` has an indexed timestamp
- Code: `rgn 'event NavCheckpoint' $V/interfaces` shows `(uint256 indexed timestamp, uint256 totalAssets, uint256 totalSupply)`.

### C-14 (L) Events and `LegTraded`
- Code: `sed -n '/^interface IStrategyVaultV2/,/^}/p' $SPEC | rg -o 'event (\w+)' -r '$1' | sort -u` equals `jq -r '.abi[]|select(.type=="event")|.name' "$FOUNDRY_OUT/StrategyVaultV2.sol/StrategyVaultV2.json" | sort -u` apart from OZ `Paused`/`Unpaused`.
- Tests: `ft test_rebalance_emitsCheckpointThenRebalanced`.

### C-15 (H) Effective threshold avoids the dust loop
- Code: `rgn 'effectiveMax|THRESHOLD_BAND_BPS' $VAULT` implements `min(10000, max(maxWeightBps, target + 10))`.
- Tests: `ft test_rebalance_thresholdUsesEffectiveMax`, `ft test_rebalance_thresholdFiresAboveMax`; seeds with `max == target` (STRM, EVMO, EQ5, CHIP, BLTZ, CLCM) do not refire after a rebalance.

### C-16 (L) Empty or paused vault is never "needed"
- Tests: `ft test_rebalance_emptyVaultNeverNeeded`, `ft test_rebalance_pausedNotNeeded`.

### C-17 (M) Strict two-pass rebalance
- Tests: `ft test_rebalance_sellsBeforeBuys` (event order), `ft test_rebalance_deploysIdle`, `ft test_rebalance_skipsLegsInsideTolerance`.

### C-18 (M) Nested redeem semantics
- Tests: `ft test_nested_redeemUsdg_unwindsChild`, `ft test_nested_redeemUsdg_childFailureWrapsReason`, `ft test_redeemInKind_childSharesNotUnwound`.
- Also X-07 for the returndata cap.

### C-19 (M) Engine resilience
- Code: `rgn 'try ' $ENG` (per-vault try/catch in `checkUpkeep`, `checkpoint`); `rgn 'MAX_SCAN|NotRegisteredVault|isRegistered' $ENG`.
- Tests: engine unit tests "failing vault skipped", "performRebalance registry gate", "checkpoint skips unregistered and reverting vaults"; locate with `forge test --match-path "$T/**" --list 2>&1 | rg -i 'engine|upkeep'`.

### C-20 (M) Registry V2
- Code: `rgn 'block\.number' $REG` none; `rgn 'function (isRegistered|getStrategies|strategyCount|updateMeta|getStrategyInfoV2)' $REG`; `registerStrategy` only `FACTORY_ROLE`; `updateMeta` only the stored creator; tag charset `[a-z0-9-]`, description at most 160 bytes, at most 3 tags of at most 16 bytes.
- Tests: registry unit tests (meta limits, creator-only update, pagination bounds).

### C-21 (M) `FengAggregator` is role-gated, bounded, non-back-datable
- Code: `rgn 'function updateRoundData' $V` prints none; `rgn -c 'onlyRole' $AGG` equals 6 (`updateAnswer`, `refresh`, `shockAnswer`, `forceAnswer`, `setParams`, `setShockEnabled`); `updatedAt` is only ever `block.timestamp`: `rgn '_updatedAt *=' $AGG`.
- Tests: aggregator unit tests (deviation against anchor, shock then restore, `refresh` moves `updatedAt` only, `forceAnswer` re-anchors, role gating, parameter caps). **Add reviewer probe X-01 (rate limit).**

### C-22 (L) USDG feed ignored by the vault
- Code: `rgn -i 'getPrice' $VAULT` shows calls only for constituents, never for `usdgToken`.

### C-23 (M) Approvals exact and reset
- Code: `rgn 'forceApprove' $VAULT $DESK $FACT`; every non-zero `forceApprove(x, a)` is followed by `forceApprove(x, 0)` on the same path (including the revert-free path after a failed `try`); the desk holds none: `rgn 'approve|forceApprove' $DESK` none.
- Tests: `ft test_approvalsAlwaysZeroAfterCalls`; invariant `invariant_noOpenApprovals`. Mutation M-06.

### C-24 (H) Size and stack depth
- Run P-05; `rgn 'via_ir' foundry.toml` shows `false`; constructors take `VaultParams memory`.

### C-25 (M) Decimals read and validated
- Code: `rgn 'decimals\(\)' $VAULT $FACT $DESK`; `rgn 'UnsupportedDecimals|DecimalsTooHigh|UnsupportedUsdgDecimals' $V`; all compare `<= 18`.
- Add decimals cells at `d` in {0, 2} for share math (X-12).

### C-26 (M) Pause and nested semantics
- Tests: child paused blocks parent deposit and rebalance but not parent redeem or `redeemInKind` (`forge test --match-path "$T/**" --list 2>&1 | rg -i 'pause'`).

### C-27 (M) In-kind weight guard
- Tests: `ft test_depositInKind_exceedsMaxWeightReverts`, `ft test_depositInKind_usdgReverts`, `ft test_depositInKind_worksWithEmptyDesk`, `ft test_depositInKind_valueAtOracle`.

### C-28 (L) Donation forcing a rebalance is accepted risk
- Test: a handler `donate` run shows NAV loss to holders at most the spread on the shifted notional (I4 bound) and the donor strictly loses.

### C-29 (H) Measured deltas for every pull and swap
- Code: `rgn 'balanceOf' $VAULT $DESK` shows before and after reads around each `safeTransferFrom` and `swapExactIn`; returned `amountOut` is used only for a sanity compare: `rgn 'amountOut' $VAULT`; pulls come only from `msg.sender`: `rgn -P 'safeTransferFrom\((?!msg\.sender)' $VAULT $DESK $FAU` prints none, or only a private helper that takes `from` (the desk has `_pull(token, from, amount)`): then `rgn '_pull\(' $DESK` must show every call site passing `msg.sender`.
- Tests: `ft test_deposit_feeOnTransferUsdgMintsFewerShares`; `HostileVenues` (lying `amountOut`, short delivery) tests; `forge test --match-path "$T/**" --list 2>&1 | rg -i 'feeOnTransfer|hostileVenue|lying|short'`. Mutation M-12.

### C-30 (M) Rounding direction
- Code: `rgn 'Rounding\.(Ceil|Floor)|mulDiv' $VAULT`; `nb` is computed with Ceil before the pull, `na` with Floor after; shares Floor.
- Tests: `ft test_deposit_*`, I6. Mutation M-01.

### C-31 (L) `Constituent` shape unchanged, ABI equals spec
- Code: `rgn 'struct Constituent' contracts` prints only `contracts/interfaces/IStrategyVault.sol`.
- ABI diff (P-13): `diff <(sed -n '/^interface IStrategyVaultV2/,/^}/p' $SPEC | rg -o 'function (\w+)' -r '$1' | sort -u) <(jq -r '.abi[]|select(.type=="function")|.name' "$FOUNDRY_OUT/StrategyVaultV2.sol/StrategyVaultV2.json" | sort -u)` prints nothing (extra OZ `Pausable` functions are acceptable only if listed in the report; `quoteRedeem` and `previewRedeemInKind` may legitimately move to `StrategyLens`, then repeat the diff against `StrategyLens` for those two names). Do the same for `error` names.

### C-32 (M) Desk gate
- Code: `rgn 'isRegistered|NotVault' $DESK`; `quoteExactIn` has no gate.
- Tests: desk registry-gate unit test (unregistered caller reverts `NotVault`, including a vault built by `VaultDeployerV2` outside the factory: `ft test_vaultCreatedByStrangerIsNotRegistered`).

### C-33 (L) Staleness constant
- Code: `rgn '43200|12 hours|21600|6 hours' script/DeployV2.s.sol $FACT $DESK`. Spec says 12 h, R2 says 6 h: record the final decision (F-05) in the report and check the desk and the factory use the same value.

### C-34 (L) Permissionless `executeRebalance` and `checkpoint`
- Code: `rgn -A2 'function (executeRebalance|checkpoint)\(' $VAULT` shows no access modifier besides `nonReentrant`/`whenNotPaused`.

### C-35 (L) Registry spam accepted; reads paged
- Code: `rgn -A14 'function getStrategies' $REG` clamps `limit` and returns empty when `offset >= count`.
- Ops: confirm the keeper pages (`checkUpkeepRange`) and filters (X-10).

### C-36 (L) Nested preview tolerance
- Test: `forge test --match-path "$T/**" --list 2>&1 | rg -i 'preview.*tolerance|previewWithinTolerance|nested.*preview'`; assert actual shares never exceed the preview by more than rounding and the preview overshoot respects the bound in C-36.

## 4. Invariants I1 to I11 (spec 4.3)

Run each at the default profile and at least once deep. Replace `Invariant6Dec` with `Invariant18Dec` for `d = 18`.

```bash
forge test --match-contract Invariant6Dec  -vv
forge test --match-contract Invariant18Dec -vv
FOUNDRY_PROFILE=deep forge test --match-path "$T/invariant/**" -vv
FOUNDRY_INVARIANT_SHOW_METRICS=true forge test --match-contract Invariant6Dec -vv   # per-handler call and revert table (V-01)
```

- **I1**
  - Statement: redeemable value equals NAV within rounding
  - Where to look and what to verify: `invariant_previewSumEqualsNav`: sum of actors' `previewRedeem` between `NAV - (actors + 1)` and `NAV`; `previewRedeem(totalSupply()) == totalAssetsUSDG()`; the expected NAV is recomputed by the test with its own `valueOf` (V-02)
  - Reviewer probe beyond the suite: raise `fuzz.runs` to 20000 on the stateless share-math suite: `forge test --match-path "$T/fuzz/**" --fuzz-runs 20000`
- **I2**
  - Statement: round trip returns at least input minus twice the spread, minus `2n + 3` units
  - Where to look and what to verify: handler `deposit` then `redeem` at constant prices; bound `in * (BPS - 2*spreadBps) / BPS - (2n + 3)`
  - Reviewer probe beyond the suite: add a trial with a 100 percent first-deposit and a 1 wei second deposit; expect revert or bound, never a loss above bound
- **I3**
  - Statement: share price does not fall beyond 1 unit plus 1e-6 relative
  - Where to look and what to verify: before and after each action with `S >= 1e18`; exact within 1 unit for `redeemInKind`
  - Reviewer probe beyond the suite: repeat with prices moving 10 percent between deposits
- **I4**
  - Statement: rebalance changes NAV by at most the spread cost
  - Where to look and what to verify: `LegTraded` logs give the notional; bound `navBefore - navAfter <= tradedNotional * spread / BPS * (1 + 1/BPS) + (n + 2)`; with a child leg twice that
  - Reviewer probe beyond the suite: include `donate` then rebalance (T-02 scenario C)
- **I5**
  - Statement: `redeemInKind` works with stale feeds, empty desk, paused vault
  - Where to look and what to verify: after each `chaos` mode: stale, desk `Unsupported`, reserve withdrawn, `removeFeed`; `previewRedeemInKind` too
  - Reviewer probe beyond the suite: also with `BlockableUSDG` frozen using `redeemInKindExcluding`
- **I6**
  - Statement: no path mints shares without equal measured value
  - Where to look and what to verify: `sharesMinted <= valueAddedIndependent * (S + vS) / (navBeforeIndependentCeil + 1)`; supply unchanged by rebalance, checkpoint and in-kind redeem except burns
  - Reviewer probe beyond the suite: check no `mint` call site other than `deposit` and `depositInKind`: `rgn '\.mint\(' $VAULT` shows exactly those two
- **I7**
  - Statement: depth at most 2, no cycles
  - Where to look and what to verify: `DepthCycleV2.t.sol`: depth 3 reverts `DepthExceeded`, unknown token reverts, duplicates revert, a strategy cannot contain itself or an ancestor
  - Reviewer probe beyond the suite: try to name the predicted CREATE address of the next vault token as a strategy-token constituent: must revert `UnknownStrategyToken`
- **I8**
  - Statement: desk accounting identity
  - Where to look and what to verify: `usdg.balanceOf(desk) >= funded + buyIn - sellOut - withdrawn`, equality without donations; per token in inventory mode
  - Reviewer probe beyond the suite: `sellOut` never exceeds `funded + buyIn - withdrawn` after a 1,000-step deep run
- **I9**
  - Statement: everything at `d = 6` and `d = 18`
  - Where to look and what to verify: `Invariant6Dec`, `Invariant18Dec` inherit one abstract base
  - Reviewer probe beyond the suite: add `d = 2` and `d = 8` smoke runs (X-12)
- **I10**
  - Statement: hostile reentrant token cannot extract value
  - Where to look and what to verify: `ReentrantToken` hook tries every entry point on vault and child; state-changing attempts revert with `ReentrancyGuardReentrantCall`, views revert; attacker's final value at most what it put in; `forge test --match-path "$T/**" --list 2>&1 | rg 'reentrancy_'` shows one test per entry point
  - Reviewer probe beyond the suite: also a hook that calls the registered sibling vault and a hook that calls the desk
- **I11**
  - Statement: first-depositor attack unprofitable at 6 and 18
  - Where to look and what to verify: `InflationAttackV2`: victim's redeem at least `V * (1 - 25 bps) - 3` or the deposit reverts (`ZeroShares`, `NoValueAdded`); attacker redeems at most `a + D` (1 unit slack)
  - Reviewer probe beyond the suite: `forge test --match-contract InflationAttackV2 --fuzz-runs 100000`; cross-check against the exact-integer model in the threat model (no profit found in about 2.4 million trials)

Suite-quality rows (a property test that asserts nothing is the main failure mode, see the `property-based-testing` skill):

- **V-01**
  - Check: no vacuity: every handler function runs and reverts only for expected reasons
  - Command: `FOUNDRY_INVARIANT_SHOW_METRICS=true forge test --match-contract Invariant6Dec -vv`
  - Pass: `deposit`, `depositInKind`, `redeem`, `redeemInKind`, `pushPrice`, `warp`, `rebalance`, `checkpoint`, `chaos`, `donate` all show calls greater than 0; `ghost_unexpectedRevert` is false; reverts of one handler are not above 90 percent of its calls
- **V-02**
  - Check: no tautology: expected values are independent of the code under test
  - Command: `rgn 'totalAssetsUSDG|previewRedeem|previewDeposit' $T/invariant/Handler.sol`
  - Pass: the handler recomputes `valueOf` from raw balances and oracle prices; expected NAV is never read from the vault
- **V-03**
  - Check: no filtered-out inputs
  - Command: `rgn 'vm\.assume' $T`
  - Pass: none, or each use is justified (prefer `bound`)
- **V-04**
  - Check: `fail_on_revert` honoured
  - Command: `forge config --json | jq .invariant.fail_on_revert`
  - Pass: `true`; handlers wrap targets in try/catch with the expected selector list of spec 4.2
- **V-05**
  - Check: invariants are registered on the right targets
  - Command: `rgn 'targetContract|targetSelector|excludeContract' $T/invariant`
  - Pass: handler is the only target; no function is excluded without a comment in the report

## 5. Extra checks from the threat model (X-xx)

- **X-01**
  - Threat: T-06, F-01
  - Check: relayer key cannot walk the price inside one block
  - Command or test: write and run `test_aggregator_walkWithinOneBlock`: loop `updateAnswer` 10 times in one block from `UPDATER_ROLE` at deviation 1500
  - Pass: if it passes (price moved 4x) the finding F-01 stays open; closed only when a minimum interval or cumulative bound rejects it
- **X-02**
  - Threat: T-06, T-08, T-09, F-02
  - Check: desk exposure per transaction and per window
  - Command or test: `rgn 'maxSwap|MAX_SWAP|outflow|window' $DESK`; probe: one vault redeem of 100 percent of reserve value at a moved price
  - Pass: either a cap exists with tests, or the README names the reserve as the maximum loss
- **X-03**
  - Threat: T-21, T-30
  - Check: role matrix equals spec 6.5 after `DeployV2`
  - Command or test: section 7 (D-01 to D-04) post-deploy; locally: `forge test --match-path "$T/**" --match-test 'roleMatrix|roles'`
  - Pass: no unexpected holder; vaults hold no mint role
- **X-04**
  - Threat: T-11, F-04
  - Check: faucet arithmetic
  - Command or test: `rgn 'FAUCET_ETH_FUND_WEI|ethPerClaim|dailyCap' script/DeployV2.s.sol`
  - Pass: funded ETH divided by `ethPerClaim` is at least `dailyCap`, or the mismatch is documented; test `FaucetEmpty` path
- **X-05**
  - Threat: T-03, T-16
  - Check: no function pulls tokens from an arbitrary `from`
  - Command or test: `rgn -P 'safeTransferFrom\((?!msg\.sender)' $V` and `rgn '_pull\(' $DESK`
  - Pass: no direct hit outside the private `_pull` helper, and every `_pull` call site passes `msg.sender`
- **X-06**
  - Threat: T-10
  - Check: lookalike vaults cannot register or trade
  - Command or test: `ft test_vaultCreatedByStrangerIsNotRegistered`; `rgn 'FACTORY_ROLE' $V script`
  - Pass: `FACTORY_ROLE` is granted to the factory only (and to the Live factory in `DeployLive`)
- **X-07**
  - Threat: T-25, F-06
  - Check: returndata copy is bounded
  - Command or test: `rgn 'catch \(bytes memory|catch Error|catch ' $VAULT`
  - Pass: the copied reason is capped or dropped, or accepted in the report
- **X-08**
  - Threat: T-18, F-13
  - Check: oracle input sanity
  - Command or test: `rgn 'updatedAt|decimals' $ORA`; probe with a mock feed returning `updatedAt = block.timestamp + 1` and `decimals = 30`
  - Pass: deterministic revert, never a silent zero price or an arithmetic panic inside a user path (`priceStatus` must return `(false, 0)`)
- **X-09**
  - Threat: T-02, T-23
  - Check: donation to a child does not profit the donor
  - Command or test: add `donateToChild` to the handler; assert donor value change at most 0
  - Pass: holds at depth 2
- **X-10**
  - Threat: T-13, F-08
  - Check: keeper resilience to spam vaults
  - Command or test: create 250 dust vaults in a test; `checkUpkeep()` returns at most the first 200, `checkUpkeepRange(200, 100)` reaches the rest; ops code filters by minimum NAV
  - Pass: no revert; documented in the runbook
- **X-11**
  - Threat: T-26
  - Check: no secret reaches logs, files or the repo
  - Command or test: G-11, G-12, G-13 plus `script/*.s.sol` writes only public addresses: `rgn 'writeFile|writeJson' script`
  - Pass: JSON schema 5.3 contains addresses and numbers only
- **X-12**
  - Threat: T-01, T-18
  - Check: decimals corners
  - Command or test: add share-math cells for `d = 0` and `d = 2`, constituents at 6 and 18
  - Pass: vectors and I11 hold; `MIN_LEG_USDG` degenerate case documented
- **X-13**
  - Threat: T-04, T-27
  - Check: Live deploy asserts
  - Command or test: `rgn 'uiMultiplier|decimals' script/DeployLive.s.sol`
  - Pass: asserts `uiMultiplier() == 1e18` per token and `decimals() == 6` for Paxos USDG before any broadcast
- **X-14**
  - Threat: T-26, T-30
  - Check: token constants and desk modes
  - Command or test: `rgn -c '0x7E955252E15c84f5768B83c41a71F9eba181802F' script`; `rgn -i '0x915Ef7c9|0x8F9231B0' script contracts src`
  - Pass: the Paxos address is the only USDG constant; the two decoys never appear; real tokens use `Inventory`, mocks use `Mint`
- **X-15**
  - Threat: T-21
  - Check: privileged-function inventory
  - Command or test: `rgn -B1 -A4 'onlyOwner|onlyRole|guardian' $V`
  - Pass: each privileged function appears in the table of the report with caller, effect and event; each emits an event (`rgn 'emit' ` in the body)
- **X-16**
  - Threat: T-12
  - Check: ops routes take no price or address input that reaches a signer
  - Command or test: `rgn -l 'RELAYER_PRIVATE_KEY|KEEPER_PRIVATE_KEY|FAUCET_PRIVATE_KEY' src` then read each route: parameters unused for signing; bearer check present on `/api/ops/tick`
  - Pass: 401 without `CRON_SECRET`; no echo of env values
- **X-17**
  - Threat: T-10, T-15
  - Check: frontend lists strategies from the registry only and escapes metadata
  - Command or test: `rgn 'dangerouslySetInnerHTML' src`
  - Pass: none; strategy lists come from `getStrategies`, history logs are filtered by registered vault address

## 6. Per-contract manual reads (after the greps)

Read in this order; for each file confirm the item and record file:line evidence in the report.

1. `StrategyTokenV2.sol`: only the vault mints, burns and spends; `burnFrom` ordering `_spendAllowance` then `_burn`; 18 decimals; immutable `vault`.
2. `StrategyVaultV2.sol`: constructor validation list (spec 2.6); the order inside `deposit` (`nb` before pull, delta after pull, delta after legs); `redeem` burns before any token leaves; idle read before any sale; `part_i` uses `S0` captured before the burn; all external calls have exact approvals reset; `executeRebalance` sets timestamps even when no leg trades; `priceStatus` try/catch; no storage writes in views; `lastCheckpointTimestamp` written on every emission point; no loop over unbounded input (n at most 6).
3. `StrategyFactoryV2.sol`: check order of spec 2.7; duplicates in O(n^2) with n at most 6; `vaultOf` written after deploy and before registry call; registry call reverts the whole creation if it fails.
4. `VaultDeployerV2.sol`: stateless; nothing but `new StrategyVaultV2`; consider F-07.
5. `OracleDesk.sol`: the pricing formulas of spec 2.3 round in the desk's favour (`priceBuy` ceil, `priceSell` floor, outputs floor); mint and burn paths; accounting counters updated with measured amounts; owner functions emit events; `Unsupported` stops swaps only; reentrancy guard; no approvals.
6. `FengAggregator.sol`: anchor semantics (deviation always against anchor; shock never moves the anchor; `forceAnswer` resets it); no `updateRoundData`; `latestRoundData` fields consistent; `decimals` fixed at deployment; parameter caps; roles.
7. `ChainlinkPriceOracleV2.sol`: see X-08.
8. `MarketplaceRegistryV2.sol`: `FACTORY_ROLE` only; `creator` argument comes from the factory's `msg.sender`; meta validation loops bounded (3 tags, 16 bytes).
9. `RebalanceEngineV2.sol`: no state; `try/catch` everywhere an external vault is called; unbounded loops capped by `MAX_SCAN`.
10. `FengFaucet.sol`: effects before interactions; EOA-only recipients; ETH sent with a bounded `call` and result checked; `receive()` open is intended; day counter arithmetic; roles.
11. `MockUSDGV2.sol` and mocks: flagged as sandbox; minter role only; no code path in production contracts depends on mock-only functions.
12. Scripts: `DeployV2.s.sol` order of spec 6.2; role grants of spec 6.5; `ENABLE_SHOCK` default off (F-03); `SeedV2.s.sol` never calls `updateAnswer`; `deploy-v2.sh` never echoes the key, never reads `.env*`, uses `--slow` and `--resume`.

## 7. Post-deploy read-only checks (no key, no transaction)

Run only after `DeployV2` is broadcast. The RPC is public; retry on TLS errors (the local ISP intercepts TLS intermittently).

```bash
RPC=https://rpc.testnet.chain.robinhood.com
A=deployments/robinhood-testnet-v2/addresses.json
r() { for i in 1 2 3 4 5; do cast "$@" --rpc-url "$RPC" 2>/dev/null && return; sleep 2; done; echo "FAILED: cast $*"; }
```

- **D-01**
  - Check: feed roles
  - Command: `r call "$(jq -r .priceOracles.TSLA $A)" 'hasRole(bytes32,address)(bool)' "$(cast keccak UPDATER_ROLE)" "$RELAYER_ADDRESS"` (address from the deploy output; do not read `.env*`)
  - Expected: `true` for the relayer; `false` for the deployer unless intended; `SHOCK_ROLE` `false` for everyone in the production deploy
- **D-02**
  - Check: desk
  - Command: `r call "$(jq -r .venue $A)" 'registry()(address)'`, `'spreadBps()(uint16)'`, `'reserveUsdg()(uint256)'`, `'owner()(address)'`
  - Expected: registry equals `.marketplaceRegistry`; spread 10; reserve 10,000,000e6; owner as planned
- **D-03**
  - Check: registry
  - Command: `r call "$(jq -r .marketplaceRegistry $A)" 'hasRole(bytes32,address)(bool)' "$(cast keccak FACTORY_ROLE)" "$(jq -r .strategyFactory $A)"`
  - Expected: `true` for the factory only
- **D-04**
  - Check: stock and USDG minters
  - Command: `r call <stock> 'hasRole(bytes32,address)(bool)' "$(cast keccak MINTER_ROLE)" <vault>` for every vault
  - Expected: `false` for vaults; `true` for the desk
- **D-05**
  - Check: freshness
  - Command: `r call "$(jq -r .priceOracles.TSLA $A)" 'latestRoundData()(uint80,int256,uint256,uint256,uint80)'`
  - Expected: `updatedAt` within the staleness window; answer positive
- **D-06**
  - Check: faucet
  - Command: `r call "$(jq -r .faucet $A)" 'ethPerClaim()(uint256)'`, `'dailyCap()(uint256)'`; `r balance "$(jq -r .faucet $A)"`
  - Expected: balance divided by `ethPerClaim` is documented (X-04)
- **D-07**
  - Check: guardian
  - Command: `r call <vault> 'guardian()(address)'`
  - Expected: not the zero address; equals the planned key
- **D-08**
  - Check: deployed code matches build
  - Command: `r code <vault>` hash equals the creation output of the standard-JSON verification on the explorer
  - Expected: verification status OK (O-4)

## 8. Mutation tests (do the suite and the tests catch bad code?)

Copy the repo to a scratch directory (no `.env*`, no `node_modules`), mutate one thing at a time, run the V2 suite, expect at least one named failure. A surviving mutant is a missing test and is reported as a Medium finding.

```bash
M="$SCR/mut"; mkdir -p "$M"
tar --exclude=node_modules --exclude=.next --exclude=out --exclude=cache --exclude='.env*' --exclude=.git -cf - . | tar -xf - -C "$M"
cd "$M"      # forge here uses the same FOUNDRY_OUT and FOUNDRY_CACHE_PATH
# edit one file (sed or an editor), then:
forge test --match-path "contracts/test/v2/**" -q 2>&1 | tail -15
```

- **M-01**
  - Change: `nb` rounded Floor instead of Ceil in `deposit` (C-30)
  - Must be killed by: share-math fuzz, I6, I2
- **M-02**
  - Change: pass `address(this)` (the vault) as spender to `burnFrom`, or delete `_spendAllowance` (C-02)
  - Must be killed by: `test_redeem_vaultApprovalDoesNotAuthorizeCaller`, `test_redeem_delegatedNeedsAllowanceOfCaller`
- **M-03**
  - Change: remove `nonReentrant` from `redeem`
  - Must be killed by: `test_reentrancy_redeem`, I10
- **M-04**
  - Change: remove `nonReentrantView` from `totalAssetsUSDG`
  - Must be killed by: reentrant-view test, I10
- **M-05**
  - Change: `VIRTUAL_SHARES = 1` for `d = 18` (C-04)
  - Must be killed by: `InflationAttackV2`
- **M-06**
  - Change: delete one `forceApprove(spender, 0)` reset (C-23)
  - Must be killed by: `invariant_noOpenApprovals`, `test_approvalsAlwaysZeroAfterCalls`
- **M-07**
  - Change: add `whenNotPaused` to `redeem`; remove it from `deposit` (C-12)
  - Must be killed by: `test_redeem_neverPaused`, `test_deposit_revertsWhenPaused`, `invariant_paused_redeemStillWorks`
- **M-08**
  - Change: remove the registry gate in `OracleDesk.swapExactIn` (C-32)
  - Must be killed by: desk gate test, `test_vaultCreatedByStrangerIsNotRegistered`
- **M-09**
  - Change: desk rounds in the user's favour (`priceBuy` floor) (spec 2.3)
  - Must be killed by: desk rounding test, I8
- **M-10**
  - Change: `MAX_DEPTH = 3`
  - Must be killed by: `DepthCycleV2`
- **M-11**
  - Change: aggregator bound uses `<` instead of `<=`, or drops `onlyRole(UPDATER_ROLE)`
  - Must be killed by: aggregator bound and role tests
- **M-12**
  - Change: credit the returned `amountOut` instead of the measured balance delta (C-29)
  - Must be killed by: `test_deposit_feeOnTransferUsdgMintsFewerShares`, `HostileVenues` tests
- **M-13**
  - Change: `_checkAllFresh` skips strategy-token constituents (C-09)
  - Must be killed by: `test_nested_staleChildBlocksParent`
- **M-14**
  - Change: `effectiveMax` returns `maxWeightBps` (C-15)
  - Must be killed by: `test_rebalance_thresholdUsesEffectiveMax`
- **M-15**
  - Change: swap pass 1 and pass 2 order (C-17)
  - Must be killed by: `test_rebalance_sellsBeforeBuys`
- **M-16**
  - Change: remove the EOA check in the faucet
  - Must be killed by: faucet contract-recipient test

## 9. Severity rubric, sign-off and report template

- **Critical**: loss or permanent lock of user funds, or theft of the desk reserve, by an unprivileged actor, with no unusual precondition.
- **High**: the same with a realistic precondition, or any path that blocks the exit (`redeemInKind` failing under stale feeds, empty desk or pause), or a mint of shares without matching value.
- **Medium**: bounded loss, privileged-key abuse that the spec claims to bound, griefing with real cost, a surviving mutant on a High row, a missing named test.
- **Low**: hygiene, UX hazards, documentation mismatches, cosmetic.
- **Info**: observations.

Sign-off (G1): zero open Critical or High; every Medium fixed or accepted with a written reason in the report; every row of sections 1 to 5 marked PASS, WAIVED (with reason) or FAIL; invariants green at default and deep profile; mutation survivors zero or justified; coverage thresholds met or `--ir-minimum` stated.

Requests to the coordinator (tools not installed, not to be installed by the reviewer): Slither (`pipx install slither-analyzer`), Aderyn, and Echidna or Medusa for a stateful fuzz run independent of Foundry. Until then the report states "static analysis not run".

`docs/security/review-v2.md` template:

```
# V2 review (E8-T3)
Scope: files and commit-less hashes (sha256sum of each reviewed file), date, reviewer.
Verdict: PASS / PASS WITH CONDITIONS / FAIL for G1.
## Findings
| ID | Sev | Row | File:line | Description | Proof (command or test) | Fix | Status |
## Checklist results
| Row | Result | Evidence |
## Not done / tooling gaps
## Open risks accepted
```

## Appendix A. Smoke run of the global gates on the in-progress tree (informational, not a review)

Run on 2026-10-03 while the authors were still writing `contracts/v2/` (about 2,000 lines present, tests partly compiling). It proves the commands work and gives the second pass a head start. Line numbers will move.

- G-02 (convention): two revert strings, `RebalanceEngineV2.sol:14` and `MarketplaceRegistryV2.sol:28` (`require(..., "zero ...")` in constructors). Low, hygiene; the convention says custom errors only.
- G-05: `assembly` in `VaultDeployerV2.deploy`: `create` over `type(StrategyVaultV2).creationCode` concatenated with `msg.data[4:]`. Pass 2 must check (a) the calldata tail of `deploy(VaultParams)` is byte-identical to the constructor argument encoding of one dynamic struct, (b) revert data is bubbled correctly, (c) a zero address result is impossible to miss, (d) the size and gas claims of spec 3.2 hold.
- G-08: `type(uint256).max` at `StrategyVaultV2.sol:249` is the initial value of a minimum tracker in `priceStatus`, not an approval. Benign.
- C-29/X-05: `OracleDesk._pull(token, from, amount)` takes `from`; all four call sites at the time pass `msg.sender`. Keep that invariant.
- C-10/C-31: `contracts/v2/StrategyLens.sol` exists and holds `quoteRedeem`, consistent with the size fallback in spec 3.5. It is a new contract outside the spec's file list: review it, add it to the ABI sync list, and note that `StrategyVaultV2` itself must no longer expose `quoteRedeem` or `previewRedeemInKind` unless the size gate allows.
- G-03, G-04, G-06, G-07, G-10: no hits.
