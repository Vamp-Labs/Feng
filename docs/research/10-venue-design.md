# R3: venue design, OracleDesk versus Uniswap v4 on Robinhood Chain testnet

- **Date read and measured**: 2026-10-03, about 14:25 to 15:15 UTC (Saturday). Plan reference: `docs/brainstorm/2026-10-03-feng-v2-plan.md` section 7 R3, D2, D11, 5.1, E1-T3, E3-T2, E4-T5, 8.1. Baseline facts: `docs/research/07-testnet-reality-check.md` sections 2.4 and 5; V1 asset acquisition: `contracts/StrategyVault.sol:74-103` (deposit mints constituents) and `:105-145` (redeem burns them).
- **Method**: Blockscout `api?module=logs` for the PoolManager `Initialize` log scan; `cast`/JSON-RPC against `https://rpc.testnet.chain.robinhood.com` (every call retried up to 16 times because of the ISP TLS interception, which surfaced as `certificate expired` and `certificate not valid for name` errors); Uniswap docs and `Uniswap/contracts` deployments feed through DoH `--resolve`; raw GitHub source for v4-core and v4-periphery `main`; Rialto docs. **No transaction was sent and no key was used.** The adapter measurements are `eth_call` / `eth_estimateGas` runs with state overrides (code and storage injected at throw-away addresses), not on-chain executions. Scratch code lives outside the repo (agent scratchpad); this file is the only repo file written.
- **Read-only compliance**: no repo file other than this one was changed, nothing installed, no git.

## Summary

1. **Only one of the five stock tokens has a Uniswap v4 pool against Paxos USDG, and it is worth about 100 USD.** The scan found 34,690 `Initialize` events on the PoolManager. 69 involve USDG; exactly two of those involve a stock token, both TSLA/USDG (USDG is `currency0`): a dynamic-fee pool behind a `BellHook` with **zero liquidity**, and a plain 0.30 % pool (tick spacing 60, no hook, id `0x38f88da1...384b`) with active liquidity `3.16e12`, i.e. about **51 USDG and 0.196 TSLA** of virtual reserves, priced at **260.07 USDG per TSLA against the Robinhood API ask of 371.80**. AMZN, AMD, PLTR and NFLX have **no USDG pool at all** (they only pair with ETH, with each other and with junk tokens).
2. **A 500 USDG swap through the only liquid pool (V4Quoter, exact):** 0.177875 TSLA, an effective **2,811 USDG per TSLA, 7.56 times the API ask; 86.8 % value shortfall** versus the Robinhood price. For a 1 USDG swap the pool is 28 % cheaper than the API ask (a stale, low initial price), at 10 USDG about 16 % cheaper, and somewhere between 10 and 100 USDG it becomes more expensive than the API; the pool is exhausted at 0.196 TSLA. It is not a usable execution venue for a 500 USDG deposit leg, and it would fail the oracle-bound `minAmountOut` on every sell.
3. **The v4 plumbing is fully deployed and works from a contract.** On chain 46630 the PoolManager `0x8366...0951`, V4Quoter `0x8dc1...8f94`, StateView `0xf333...e673b`, PositionManager `0x58da...4fa7`, ReservesLens `0x0000001b...865B`, Universal Router `0x8876...0904` and Permit2 `0x0000...8BA3` all have code, and the three periphery contracts return the PoolManager from `poolManager()`. They are the same addresses Uniswap lists for Robinhood Chain **mainnet (4663)**; Uniswap's feed has **no testnet (46630) entry**, so these are verified by on-chain getters, not by an official listing. I built a 4.4 KB single-pair adapter that implements `unlockCallback` directly and simulated it against the live PoolManager with real USDG and real TSLA balances injected by state override: a 500 USDG swap returned exactly the V4Quoter figure (0.177874986065083241 TSLA), and the sell direction also works. Estimated gas 238k (direct) versus 339k (via Universal Router + Permit2). **A Universal Router path also works but the Uniswap docs example encoding fails on the deployed router** (empty revert); only the newer `ExactInputSingleParams` with `minHopPriceX36` works.
4. **OracleDesk is the right primary venue, with changes to the 8.1 interface** (section "Findings, Q3"): add `quoteToken()`, document `quoteExactIn` as non-binding (the v4 Quoter is not a `view` and Uniswap says not to call it on-chain), require the vault to measure its own balance deltas (fee-on-transfer, partial fills, recipient differences), add a vault allowlist and a coverage ratio to the desk, and add an optional `maxAmountIn` capacity hint.
5. **Rialto/propAMM**: the docs describe an API plus a mainnet-only Router Registry (`0x71a1...687E`, code size 0 on testnet); nothing on testnet. Its propAMM pair interface (`getAmountOut`, `swapExactIn`) is close to our `IVenue`, which makes OracleDesk easy to describe as "propAMM-shaped".
6. **Decision**: **E4-T5 (`UniswapV4Venue`) is not built as part of the submission path** (stay P2 and cut it; the verified 4.4 KB sketch proves the idea is feasible, and the unlock-callback route, not the Universal Router, is the one to use if it is ever built). **The Live universe should trade only through the OracleDesk in inventory mode, plus in-kind deposit and redeem for real faucet tokens.** A read-only "Uniswap v4 reference quote" panel costs about an hour and shows real venue integration without making vault safety depend on it.

## Findings

### Q1. Uniswap v4 pools for the five stock tokens versus Paxos USDG

**1.1 Deployment addresses (all with code on chain 46630, read 2026-10-03).**

| Contract | Address | Codesize | Check |
|---|---|---|---|
| PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` | 24,009 | Blockscout: verified, solc 0.8.26, evm `cancun`, runs 44,444,444 |
| V4Quoter | `0x8Dc178eFB8111BB0973Dd9d722ebeFF267c98F94` | 6,118 | `poolManager()` returns the PoolManager; Blockscout shows `V4Quoter` metadata but `is_verified:false` |
| StateView | `0xF3334192D15450cdd385c8B70e03f9A6bD9E673b` | 3,531 | `poolManager()` returns the PoolManager; no Blockscout record |
| PositionManager | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` | 23,877 | `poolManager()` ok, `permit2()` = `0x0000...8BA3` |
| ReservesLens | `0x0000001b173C3bbF3984D417d8614E3eed34865B` | 14,142 | not used |
| Universal Router | `0x8876789976dEcBfCbBbe364623C63652db8C0904` | 24,546 | `poolManager()` ok; `V4_POSITION_MANAGER()` ok; `V3_POSITION_MANAGER()` points to a v3 NPM that has no code on testnet; no Blockscout record |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` | 9,152 | Robinhood docs list it for testnet |
| UR 2.1.2 `0x204FAca1...0498`, UR in Uniswap's JSON `0x06AfBA43...bf99`, v3 factory/SwapRouter02/QuoterV2/v2 factory | as listed by Uniswap for mainnet | **0** | not deployed on testnet at those addresses |

Source for the list: `https://developers.uniswap.org/docs/protocols/v4/deployments` (old docs path `https://docs.uniswap.org/contracts/v4/deployments`) and the unified feed `https://docs.uniswap.org/deployments.json` (generated 2026-09-22, commit `a677c0d4`): the only Robinhood chain id in either is **4663**. The testnet addresses are therefore an inference from identical addresses plus on-chain getters. Uniswap's docs warn integrators not to assume cross-chain address equality.

**1.2 The `Initialize` scan (extends doc 07 section 5).** Doc 07 filtered USDG as `topic2` only, which finds only pairs where USDG sorts first. Four of the five stock tokens sort *below* USDG (AMZN `0x5884`, AMD `0x7117`, PLTR `0x1FBE`, NFLX `0x3b82` are all < `0x7E95`), so they would be `currency0` and doc 07's filter could not see them. I therefore pulled **all** `Initialize` events (event `Initialize(bytes32,address,address,uint24,int24,address,uint160,int24)`, topic0 `0xdd466e67...6438`) by paging the Blockscout logs endpoint (1,000 rows per page, 35 pages) and filtered locally.

- Total `Initialize` events: **34,690** (block 91,000,224 .. 128,206,925, spam heavy).
- Pools with Paxos USDG on either side: **69**. Pools with at least one of the five stock tokens on either side: **556**. Union read through StateView: 623, of which 439 have non-zero active liquidity (mostly junk-token pools).
- **USDG pools involving one of our five stock tokens: 2, both TSLA.**

| Pool id | Pair (currency0/currency1) | Fee | Tick spacing | Hook | Initialised | Current tick | Active liquidity |
|---|---|---|---|---|---|---|---|
| `0x38f88da1f16ec1ddafcb2be5b3a0ee82ea9944da87a009e9b5e6fbfb94ba384b` | USDG / TSLA | 3000 (0.30 %) | 60 | none | block 127,188,201, 2026-10-01 15:08 UTC, tx `0x153afe06...9499` | 220,711 | `3,161,961,432,401` |
| `0xdb347ba0ee084cf36c3739f173ec202f3890eb3fbf57e1461d64c092234226ac` | USDG / TSLA | `0x800000` (dynamic) | 60 | `BellHook 0x25423e52c273d85925aa5c709d4bf4c99d5025c0` (verified) | block 115,699,621, 2026-09-08 17:21 UTC, tx `0x89752e48...a320` | 221,106 (never moved) | **0** |
| AMZN, AMD, PLTR, NFLX / USDG | **none** | | | | | | |

The TSLA tokens in these two pools are the faucet token `0xC9f9...bd4E`. The other 67 USDG pools pair USDG with unrelated tokens. Pools between the stock tokens and other assets exist (examples, all `getLiquidity` at 2026-10-03): ETH/TSLA 0.05 % `3.79e18`, AMD/TSLA 0.05 % `4.45e20` (tick -6,932, i.e. AMD at about 0.50 TSLA versus a real ratio of about 1.69), AMZN/ETH 0.01 % `4.82e20`, plus many `1e16 .. 1e19` pools. There is **no USDG/ETH pool with liquidity**, so no `USDG -> ETH -> stock` route exists either.

**1.3 Depth of the only liquid pool (StateView).** `getSlot0(0x38f8...)` returned `sqrtPriceX96 = 4912856805581430730047482149998150`, tick 220,711, protocol fee 0, LP fee 3,000; `getLiquidity` returned `3161961432401`. Virtual reserves `x = L / sqrtP`, `y = L * sqrtP`: **50.992 USDG and 0.19607 TSLA**. The V4Quoter output saturates at 0.19606 TSLA even for 1,000,000 USDG of input, which confirms the pool is a single, essentially full-range position of about 100 USD total. Spot price 260.07 USDG per TSLA, versus the Robinhood API at 2026-10-03T14:58:40Z: TSLA bid 371.43 / ask 371.80 (`https://api.robinhood.com/rhj/prices/TSLA`, via DoH `--resolve`). The pool was initialised near 260 and moved down from tick 221,106 to 220,711 by earlier trades, so it is also mispriced by about 30 %.

The empty dynamic-fee pool reverts the V4Quoter with `UnexpectedRevertBytes(0x7a5ed734 || poolId)`; `0x7a5ed734` is `NotEnoughLiquidity(bytes32)` (4byte lookup), i.e. no liquidity in range.

**1.4 Quote for 500 USDG (V4Quoter `quoteExactInputSingle`, `eth_call`, exact, not an approximation) versus the Robinhood API price (ask 371.80 for buys, bid 371.43 for sells).**

| Swap | Pool output | Effective price | Versus API |
|---|---|---|---|
| 1 USDG -> TSLA | 0.003760060 TSLA | 265.95 USDG/TSLA | 28.5 % below the ask (favourable, stale pool price) |
| 10 USDG -> TSLA | 0.032066166 TSLA | 311.86 | 16.1 % below the ask |
| 100 USDG -> TSLA | 0.129722721 TSLA | 770.87 | 2.07x the ask; 51.8 % value loss |
| **500 USDG -> TSLA** | **0.177874986 TSLA** | **2,810.96** | **7.56x the ask; 86.8 % value loss** (received value 66.13 USDG at the ask) |
| 0.01 TSLA -> USDG | 2.467434 USDG | 246.74 | 33.6 % below the bid |
| 0.1 TSLA -> USDG | 17.188703 USDG | 171.89 | 53.7 % below the bid |
| 1 TSLA -> USDG | 42.611936 USDG | 42.61 | 88.5 % below the bid |

The pool is cheaper than the API only for small buys (the 10 USDG quote is still 16 % below the ask, the 100 USDG quote is already 2x above it) and never favourable on sells. Command shape, reproducible: `cast call 0x8dc1...8f94 "quoteExactInputSingle(((address,address,uint24,int24,address),bool,uint128,bytes))(uint256,uint256)" "((USDG,TSLA,3000,60,0x0),true,500000000,0x)"` (returns `177874986065083241`, gas estimate 53,321). The sell-side figures come from the adapter simulation (section Q2), which matched the Quoter exactly for 10, 100 and 500 USDG.

**1.5 Side findings usable by other tracks (not verified by Robinhood).**
- `BellHook` (`0x2542...25c0`, verified Solidity, `https://explorer.testnet.chain.robinhood.com/api/v2/smart-contracts/0x25423e52c273d85925aa5c709d4bf4c99d5025c0`) is a third-party dynamic-fee hook for "official Robinhood Stock Tokens" against USDG or WETH. Its on-chain `StockVerifier` (`0xC0E4b366D22BF00816Dc88288644C06FACA312d8`) returns `isOfficial(TSLA 0xC9f9...)=true` and `isOfficial(AMZN 0x5884...)=true`, and `false` for our mock TSLA `0x37e4...`. That is a supporting data point for R1 question 5 (it is a third party's list, not Robinhood's). Its TSLA feed (`0x574cB847...114f`, `MockAggregator`, 8 decimals) is a static 250.00 set 2026-09-08, so it is no price source. The hook raises fees when its feed is stale, which on weekends would be most of the time.
- Pools with hooks that return deltas can change swap output; any production adapter must either reject pools with such hooks or measure the delta (see risks below).

### Q2. Can a contract call a v4 router, quoter or Permit2 flow, or must the adapter implement `unlockCallback`?

**2.1 What the docs say (read 2026-10-03).**
- "Although it's technically possible to interact directly with the PoolManager contract for swaps, this approach is not recommended due to its complexity" and the Universal Router is "the preferred method" (`https://developers.uniswap.org/docs/protocols/v4/guides/swapping/swapping`). Swap through the UR is `execute(commands=V4_SWAP(0x10), inputs=[abi.encode(actions, params)], deadline)` with actions `SWAP_EXACT_IN_SINGLE (0x06)`, `SETTLE_ALL (0x0c)`, `TAKE_ALL (0x0f)` (`v4-periphery/src/libraries/Actions.sol` lines 28, 40, 44); the router pulls the input through Permit2 (`token.approve(permit2)`, then `permit2.approve(token, router, amount, expiry)`).
- Direct integration: implement `unlockCallback(bytes) returns (bytes)` and call `poolManager.unlock(data)`; inside, `swap`, `sync`, transfer, `settle`, `take`; "any non-zero deltas ... the whole execution reverts" (`https://developers.uniswap.org/docs/protocols/v4/guides/unlock-callback-and-deltas`; interface `IUnlockCallback.sol`, `IPoolManager.sol` lines 114-194 on `main`).
- The V4Quoter "rel[ies] on state-changing calls designed to be reverted ... very expensive and **should not be called onchain**" (`https://developers.uniswap.org/docs/sdks/v4/guides/swapping/quoting`, source `V4Quoter.sol`: `try poolManager.unlock(...) {} catch (bytes reason)`). StateView is "for frontends and analytics", on-chain code should use `StateLibrary` (`.../guides/state-view`).
- Exact-in is `amountSpecified = -int256(amountIn)` and the router sqrtPrice limits are `MIN_SQRT_PRICE + 1` / `MAX_SQRT_PRICE - 1` (`V4Router.sol` lines 205-215; `TickMath.sol` constants 4295128739 and 1461446703485210103287273052203988822378723970342). `BalanceDelta` packs `amount0` in the upper 128 bits and `amount1` in the lower 128 (`BalanceDelta.sol` lines 12-17, 61-69).

**2.2 What works on the testnet (simulated, real contracts, injected balances).** I wrote two throw-away adapters (not committed) and ran them through `eth_call` / `eth_estimateGas` with state overrides at invented addresses: code override for the adapter, `stateDiff` for the USDG balance and allowance (USDG storage: `balanceData` mapping slot 1, `allowed` slot 3, verified against a real holder, `balanceOf` and `allowance` read back through the override) and the TSLA ERC-7201 balance/allowance slots (`openzeppelin.storage.ERC20` base `0x52c632...ce00`, `balanceOf` read back).

| Path | Runtime size | 500 USDG -> TSLA output | `eth_estimateGas` | Notes |
|---|---|---|---|---|
| Direct `unlockCallback` adapter (`swapExactIn(tokenIn, tokenOut, amountIn, minOut, recipient)`, one pair, reentrancy lock, measures balance deltas, refunds unspent input, `take` straight to `recipient`) | **4,374 bytes** | **0.177874986065083241** (identical to V4Quoter) | **237,686** | also works TSLA -> USDG (0.01 / 0.1 / 1 TSLA gave 2.467434 / 17.188703 / 42.611936 USDG) |
| Universal Router path (Permit2 approve, `execute`, forward output) | 2,581 bytes | 0.177874986065083241 | 338,970 | **only works with the newer `ExactInputSingleParams` including `minHopPriceX36`**; the docs page example (5-field struct) reverted with empty data; main-branch `IV4Router.sol` has the 6-field struct |

Gas at the measured 0.01 gwei: about 2.4e-6 ETH (direct) and 3.4e-6 ETH (UR) per swap, negligible. The simulation also shows that a *contract* holding USDG and TSLA can transfer them to and from the PoolManager: Paxos USDG's `transfer`/`transferFrom` only check `whenNotPaused` and the frozen list, not contract status, and balances of non-enrolled wallets are plain (`payoutGroupId == 0` takes the exact-balance path in `ClaimableRewardsBase._transfer`); the Stock token's `onlyNotBlocked` registry check passed for a fresh address. A frozen or blocked vault would still fail, and pause on either token halts everything (R1 territory).

**2.3 Estimate for a production `swapExactIn(tokenIn, tokenOut, amountIn, minAmountOut, recipient)` adapter.**

| | Direct `unlockCallback` (recommended if ever built) | Via Universal Router |
|---|---|---|
| Solidity size | about 200 to 260 lines with a pool registry (mapping pair to `PoolKey`), owner or factory-set config, events, `quoteExactIn` approximation via `extsload`; runtime about 7 to 9 KB | about 100 to 140 lines; runtime about 4 KB |
| External trust | PoolManager only (`msg.sender` check in the callback) | UR (unowned, non-upgradeable per Uniswap) plus Permit2; address not in Uniswap's testnet list |
| Struct/ABI drift risk | low (PoolManager interface is stable) | **demonstrated**: docs example fails on the deployed UR |
| Gas | about 238k | about 339k |
| Test effort | a mock PoolManager is not enough; needs a forked test against the live RPC (flaky TLS) or a copy of v4-core in `lib/` | same, plus Permit2 |
| Build plus review estimate | about 3 h build, 3 h tests, 1 h review (matches the plan's 6 h for E4-T5) | about 2 h build, 3 h tests |

Core of the direct callback (this is the part that carries the risk; shown because the exact accounting order is load-bearing):

```solidity
function unlockCallback(bytes calldata data) external returns (bytes memory) {
    if (msg.sender != address(poolManager)) revert NotPoolManager();
    (PoolKey memory key, bool zeroForOne, uint256 amountIn, address tokenIn, address tokenOut, address recipient) =
        abi.decode(data, (PoolKey, bool, uint256, address, address, address));
    int256 d = poolManager.swap(key, SwapParams(zeroForOne, -int256(amountIn),
        zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1), "");
    int128 a0 = int128(d >> 128);  int128 a1 = int128(d);
    (int128 inD, int128 outD) = zeroForOne ? (a0, a1) : (a1, a0);
    poolManager.sync(tokenIn);
    IERC20(tokenIn).transfer(address(poolManager), uint256(uint128(-inD)));
    poolManager.settle();
    poolManager.take(tokenOut, recipient, uint256(uint128(outD)));
    return "";
}
```

**Risks specific to a v4 adapter** (none is hypothetical; each follows from the sources above):
1. *Partial fills.* An exact-in swap that reaches the price limit with liquidity exhausted spends less than `amountIn`; the delta reports what was spent. The adapter must pay only `-inD` and refund the rest (the sketch does). On the current pool (full range) a 500 USDG input is fully consumed; on a concentrated pool it would not be.
2. *Hooks.* `beforeSwapReturnDelta`/`afterSwapReturnDelta` hooks can alter amounts (`IPoolManager.swap` natspec says integrators must check the delta). Restrict the registry to hookless pools or an audited hook.
3. *Pool identity and trust.* Pool config must be immutable per factory (plan 8.1) and must never come from the caller; 34,690 pools exist, most of them junk, and several have the same token pair with different fees.
4. *Oracle-bound `minAmountOut`.* The adapter's slippage check is the only MEV and manipulation guard; with the vault computing it from the oracle, the TSLA/USDG pool's 28 to 30 % mispricing would revert every sell leg (cap 500 bps) and accept every small buy leg at a discount.
5. *Fee-on-transfer or rebasing input.* `settle` measures the PoolManager's own balance change after `sync`; an input token that delivers less than owed leaves a negative delta and the whole call reverts `CurrencyNotSettled` (safe failure). FOT *output* means the recipient receives less than `take`; hence the vault must measure its own balance delta.
6. *Cancun dependency of the manager, not of the adapter.* The PoolManager is compiled for `cancun` (transient storage). The adapter itself compiled with `solc 0.8.24 --evm-version paris` and ran, so the repo's `evm_version = paris` is fine if v4 types are redeclared locally as in the sketch; importing `v4-core` sources would need `cancun` for those files.
7. *Reentrancy.* The callback is entered from the PoolManager; the adapter needs its own lock, and the vault must not hold state-changing assumptions across the venue call.
8. *Native ETH.* `address(0)` currencies are out of scope; reject.

### Q3. OracleDesk design check

**3.1 What exists to build on.** V1 prices every constituent with `priceOracle.getPrice(token)` returning an 18-decimal USD price and a timestamp, uses `1e18` in `(slice * 1e18) / price` (`StrategyVault.sol:96`) and `(balance * price) / 1e18` (`:239`), mints/burns mock stock via `IMintableStockToken` (`:97`, `:136`) and has a 24 h staleness check `_checkAllFresh` (`:210-221`). The plan's USDG has 6 decimals (Paxos USDG decimals = 6, doc 07 section 2.2) and stock tokens 18.

**3.2 Mode semantics.**

| | Mint mode (Sandbox) | Inventory mode (Live and any ERC-20) |
|---|---|---|
| Stock side | desk holds `MINTER_ROLE` (and burns tokens it receives); infinite | desk holds real tokens; finite, bounded by what the faucet gave |
| USDG side | finite reserve held by the desk | finite reserve held by the desk |
| Vault buys token (USDG in) | desk receives USDG, mints token to `recipient` | desk receives USDG, transfers token from inventory; reverts `InsufficientLiquidity(token)` if the inventory is short |
| Vault sells token | desk pulls token from the vault, burns it, pays USDG from reserve; reverts if the reserve is short | desk pulls token (inventory grows), pays USDG from reserve |
| Failure when price rises | reserve drains on sells (liability = outstanding minted supply times price) | inventory drains on buys, reserve drains on sells |
| Who can fund | deployer: `MockUSDG` is mintable, so effectively unlimited | deployer wallet via faucet claims (5 tokens per ticker per claim per doc 07; USDG claim amount UNVERIFIED, R1) |

**3.3 Pricing and spread.** With oracle price `P` (USD per token, 1e18 scale), token decimals 18 and USDG decimals `d`:
- buy: `tokenOut = usdgIn * 10^(36-d) * 10_000 / (P * (10_000 + s))`
- sell: `usdgOut = tokenIn * P * (10_000 - s) / (10^(36-d) * 10_000)`
- both round in the desk's favour (floor on what it pays), `s` is a half-spread in bps. Recommended Sandbox default **25 bps per side** (about 50 bps round trip), per-token override allowed, hard cap 200 bps. The vault's per-leg bound `maxSlippageBps` (default 100, cap 500 in 8.1) must always exceed `s` plus the maximum oracle move between two relayer updates (R2: 5-minute cadence, 1,000 bps per-update deviation bound), otherwise legs revert in volatile minutes.
- Do not make the quote depend on a different oracle path than the vault (the Rialto docs give the same rule for oracle-driven propAMMs: "quote from the same oracle you settle against", `https://docs.rialto.xyz/developers/quoting.md`).

**3.4 Reserve accounting.**
- **Truth = balances, not shadow counters.** USDG is a yield-capable Paxos token (payout-group wallets compound via a multiplier); our contracts are not enrolled so their balance is exact, but the desk should still read `balanceOf` instead of keeping an internal reserve variable that could drift from reality.
- Keep one counter that cannot be derived: `netMinted[token]` (mint mode: minted minus burned), because it is the desk's liability base. Expose `reserveUsdg()`, `liabilityUsdg()` (sum of `netMinted[token] * bid(token)` over mint tokens), and `coverageBps() = reserve * 10_000 / liability` (max when liability is 0). Ops (E2-T7) reads it into `/api/ops/health`; below a threshold (suggest 150 %) the keeper tops up in Sandbox.
- **Funding sizing (Sandbox).** Seeded vault NAV is about 6.5k USDG per strategy (plan section 1), so about 65k USDG notional across 10 strategies. A uniform +25 % rally costs the desk about 16k USDG on a full exit; fund **30,000 mock USDG** at deploy (mintable by the deployer, so this is free) and refill from the keeper if `coverageBps < 15000`. Live: the desk holds whatever the faucets gave; size trades to inventory, and use per-swap caps.
- **Who funds**: deployer (`owner`) calls `fund(amount)` or simply transfers; withdrawal only by `owner` and only down to a `minReserve` unless the desk is paused (prevents an accidental drain during a demo).

**3.5 Failure modes and mitigations.**

| # | Failure | Effect | Mitigation |
|---|---|---|---|
| 1 | Reserve exhausted on a sell | `redeem` reverts `InsufficientLiquidity` | `redeemInKind` (D3) never uses the desk; coverage metric and keeper top-up |
| 2 | Inventory exhausted on a buy (inventory mode) | deposit leg reverts | per-swap `maxAmountIn`, Live deposits capped to demo scale, in-kind deposit path |
| 3 | Stale, zero or paused oracle | desk quotes garbage | revert if `updatedAt` older than `maxPriceStaleness`, zero price reverts; vault already checks freshness |
| 4 | Relayer lag gives an arbitrage (buy at the old price just before a push, sell after) | desk P&L bleeds | spread at least the typical 5-minute move; **allowlist of callers** (only vaults registered by the factory); per-block notional cap |
| 5 | Decimals mistake (6 vs 18) | 1e12 error | read `usdg.decimals()` once at construction; unit tests at 6 and 18 decimals (also required by E3) |
| 6 | Output rounds to 0 | silent dust trade | revert on `amountOut == 0` |
| 7 | Mint role removed or token paused/blocked | mint mode bricks, inventory is frozen | `isSupported(token)` returns false when `paused()` is detected (Stock tokens expose `paused()` through the registry, R1); fall back to in-kind |
| 8 | Reentrancy through a hostile ERC-20 | drain | `nonReentrant`; only registered tokens; checks-effects-interactions |
| 9 | Owner key compromise | reserve theft | owner is the deployer on testnet; surplus-only withdrawal; `transferOwnership` two-step; documented in the README |
| 10 | Venue immutable per factory (8.1) but a bad fill rate discovered later | stuck | deploy a new factory plus desk; V1 pattern |

**3.6 Is the `IVenue` shape in section 8.1 enough for both desk and v4 adapter?** `swapExactIn(tokenIn, tokenOut, amountIn, minAmountOut, recipient) returns amountOut`, `quoteExactIn(...) view returns amountOut`, `isSupported(token)` covers the two venues' call shapes and both can be exact-in only (deposit legs spend an exact USDG slice; sell legs sell an exact token balance, so exact-out is not needed). It is **not sufficient on semantics**, for five reasons:
1. **`quoteExactIn` cannot be a real on-chain `view` for v4.** The V4Quoter is not `view` and Uniswap says not to call it on-chain; a `view` implementation would have to re-implement the swap loop (tick crossing) over `extsload`. Make `quoteExactIn` non-binding ("approximate, 0 means cannot fill, never used for settlement"), and make the oracle-derived `minAmountOut` the only settlement guard. The desk's quote can be exact.
2. **Recipient handling, fee-on-transfer, partial fills.** The venue can only report what it sent. The vault must measure its own balance before and after and enforce `minAmountOut` on that delta; the venue must pull exactly `amountIn` (or price on the amount it actually received) and refund unspent input to `msg.sender`. v4 `take(token, recipient, x)` can pay the vault directly (tested in the sketch); the Rialto propAMM standard pays the router and lets the router verify the delta (`https://docs.rialto.xyz/developers/settlement.md`). Same lesson: verify the delta, do not trust the return value.
3. **`isSupported(token)` has no counterparty.** Add `quoteToken()` so the factory can reject a venue whose numeraire is not the vault's USDG (a v4 adapter registered for TSLA/ETH would otherwise pass).
4. **No capacity signal.** A rebalance needs to know when a leg will not fit (finite reserve, thin pool). Add an optional `maxAmountIn(tokenIn, tokenOut)` view; the keeper and the vault can then skip or clamp a leg instead of reverting the whole rebalance.
5. **Access control and token whitelisting are not in the interface** but matter (failure mode 4): the desk should only serve vaults registered by the factory; the v4 adapter must only serve its own configured pools.

Proposed refinement of 8.1 (sketch only, names follow the plan):

```solidity
// SKETCH (refines section 8.1)
interface IVenue {
    function quoteToken() external view returns (address);                    // numeraire, must equal the vault's USDG
    function isSupported(address token) external view returns (bool);          // false when paused, blocked or unconfigured
    function quoteExactIn(address tokenIn, address tokenOut, uint256 amountIn)
        external view returns (uint256 amountOut);                              // non-binding; 0 = cannot fill
    function maxAmountIn(address tokenIn, address tokenOut) external view returns (uint256); // optional capacity hint
    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external returns (uint256 amountOut);   // pulls amountIn via transferFrom(msg.sender), refunds unspent input,
                                                // callers must measure their own balance delta
    error NotAuthorized(); error UnsupportedPair(address tokenIn, address tokenOut);
    error InsufficientLiquidity(address token); error SlippageExceeded(uint256 got, uint256 min);
}
```

Vault-side rules that go with it (E3-T3): exact approval to the venue for `amountIn` then reset to 0 (already in the plan); compute `minAmountOut` from the oracle (`P * (1 -/+ maxSlippageBps)`), never from `quoteExactIn`; measure balance deltas; handle `InsufficientLiquidity` in the rebalance loop by clamping or skipping.

**3.7 Can OracleDesk look like a propAMM?** Rialto's standard pair interface is `getAmountOut(bool zeroForOne, uint256 amountIn) view` and `swapExactIn(bool zeroForOne, uint256 amountIn, uint256 amountOutMin, address to, uint256 deadline) payable` (`https://docs.rialto.xyz/developers/standard-interface.md`). A thin per-pair adapter would make OracleDesk listable on a Rialto-like router; the interface is not worth contorting ours (fixed pair order, `deadline`, `payable`). It is a story point, not a requirement.

### Q4. RFQ and propAMM entry points on testnet

Robinhood's docs say Stock Tokens trade through RFQ aggregators (0x RFQ, 1inch Fusion, LiFi), AMM pools such as Uniswap, and propAMMs like Rialto, and describe a propAMM as on-chain and composable "unlike RFQ, which relies on off-chain signed quotes" (`https://docs.robinhood.com/chain/building-with-stock-tokens/`, read 2026-10-03). RFQ therefore has no contract entry point a vault could call (signed off-chain quotes). Rialto launched an on-chain spot exchange on **mainnet** (`https://x.com/arbitrum/status/2072697641863921930` via search result, `https://www.offchain.io/blog/partners/supporting-rialtos-launch-on-robinhood-chain`); its developer docs (`https://docs.rialto.xyz/llms.txt` and the `/developers/*` pages, read 2026-10-03) describe a Quote API at `https://rialto-trade-api.rialto.xyz` with bearer keys, a Router Registry at `0x71a120CbBf3Ce7cD910a3c50fF77aFc62735687E` listed for chain **4663 only**, and a propAMM listing flow. The registry has **code size 0 on chain 46630**, and none of the pages I grepped (onboarding checklist, propAMM overview, authentication, supported tokens, reference implementation, FAQ) mention testnet. There is no on-chain testnet entry point for Rialto or any RFQ/propAMM that I could find; the mainnet tokens also differ from the testnet faucet tokens (doc 07 section 2.1).

## Recommendations

**Decision on E4-T5 (`UniswapV4Venue`): do not build it in the submission window.** Keep it as P2 and mark it "deferred, feasibility proven (4.4 KB direct adapter simulated against the live PoolManager, 238k gas)". Reasons, with evidence: (1) four of five tickers have no USDG pool, the fifth has about 100 USD of liquidity at a price 30 % off the API (Q1); (2) a 500 USDG deposit leg would lose 86.8 % of its value or revert on the oracle bound; (3) creating our own pools needs faucet tokens we cannot mint (5 per ticker per claim) and LP plumbing through PositionManager and Permit2 that adds hours without adding depth worth demoing; (4) the effort (6 h in the plan) buys a venue the vault cannot safely route through. If a spike is still wanted after G1, build the **direct `unlockCallback` adapter, not the Universal Router one**, and gate it behind a configuration that only lists pools whose `getLiquidity` and price band pass a check.

**Decision on the Live universe: trade only through the OracleDesk in inventory mode, plus in-kind deposit and in-kind redeem of the real faucet tokens.** Real USDG deposits into Live strategies are served from the desk's finite real inventory at oracle price plus spread, at demo scale (hundreds of USDG, not thousands), labelled as such in the UI and README ("real tokens, mock market maker"). No Live strategy should claim v4 execution.

**Concrete actions**
1. **R3 interface**: update section 8.1 with the refined `IVenue` above (E3-T0), and add `maxAmountIn` as optional in the first cut.
2. **OracleDesk (E3-T2)**: build both modes in one contract with per-token mode flag; formulas and rounding per 3.3; `reserveUsdg()`, `liabilityUsdg()`, `coverageBps()`; caller allowlist (factory-registered vaults); `owner` funding and surplus-only withdrawal; events `Swap(token, isBuy, amountIn, amountOut, price)`; revert on zero output; read `usdg.decimals()`; Sandbox half-spread 25 bps default, cap 200.
3. **Vault (E3-T3)**: measured balance deltas, oracle-bound `minAmountOut`, clamp or skip a leg on `InsufficientLiquidity`.
4. **Ops (E2)**: add desk reserve, coverage, and Live inventory to `/api/ops/health`; top-up job in Sandbox only.
5. **Frontend**: optional read-only "Uniswap v4 reference" row on Live strategy pages (about 1 h): TSLA/USDG spot from StateView and a 500 USDG V4Quoter quote next to the oracle price, to show the real venue and why execution goes through the desk. Never call the V4Quoter from a contract.
6. **Docs**: put the "v4 pools are too thin" finding into the README "real versus mocked" table (E11-T2).

**Recommendation** (list form, as required by the plan):
- Build OracleDesk, mint plus inventory modes, with the 8.1 refinements.
- Do not build `UniswapV4Venue` for the submission; P2 and cut by default.
- Live universe = inventory-mode desk plus in-kind paths; Sandbox = mint-mode desk.
- If a v4 adapter is ever built, use the direct callback and a pool allowlist.

## Implications per role

- **Plan (E3-T0 design review)**: freeze the refined `IVenue` (adds `quoteToken`, optional `maxAmountIn`, non-binding quote, delta-measurement rule, refund of unspent input, exact approvals). Remove any dependency of vault logic on `quoteExactIn`.
- **GP/contracts (E3-T2, E3-T3, E4-T2)**: OracleDesk as specified in 3.2 to 3.5; Sandbox desk funded with 30,000 mock USDG; Live desk deployed in inventory mode via `DeployLive.s.sol`. Do not start E4-T5. If it is started later, the direct callback core above is verified; the Universal Router example in the docs does not work on the deployed router, use the 6-field `ExactInputSingleParams`.
- **GP/tests (E8)**: desk invariants (reserve plus inventory conservation, `coverageBps` monotone with price, no value created by round trips beyond spread, `amountOut > 0`), decimals 6 and 18, allowlist, stale-oracle revert, partial fill and FOT venue mocks for the vault (a mock venue that pays less than reported), `redeemInKind` with an empty desk. No fork test is needed unless E4-T5 is revived.
- **Ops (E2)**: monitor desk reserve and coverage and Live inventory; the relayer cadence (R2) bounds the arbitrage window of failure mode 4.
- **Frontend (E5/E6/E4-T6)**: surface `InsufficientLiquidity` and `SlippageExceeded` from deposit and redeem, show a "capacity" hint from `maxAmountIn`, show the Live badge with the honest wording; optional v4 reference panel (StateView and V4Quoter via `eth_call`, never on-chain).
- **Submission (E11)**: describe the desk as a market maker backed by an oracle with finite real inventory in Live; cite the Uniswap v4 finding (one TSLA pool, about 100 USD) as the reason; do not claim DEX execution.
- **User (human steps)**: for the Live desk, claim faucet tokens (E4-T3); nothing is needed for Sandbox.

## Assumptions and open questions

**Assumptions**
- The five token addresses in the brief are the faucet tokens (doc 07 section 2.1 caveat stands; the third-party `StockVerifier` in 1.5 agrees for TSLA and AMZN but is not Robinhood's).
- The Robinhood API price (TSLA 371.43/371.80 at 14:58:40Z, Saturday, markets closed; the value is frozen at Friday's close per `docs/research/09-price-source-and-feed.md`) is the reference. The conclusions do not depend on which weekday value is used (the pool is off by 28 % to 8x).
- State-override simulations match on-chain behaviour for these contracts. The balances were injected, so real first-touch storage and approval costs may differ; gas figures are estimates (they include cold-slot costs of the overridden state and the Arbitrum L1 component as the node estimates it).
- Pool state is a snapshot: any testnet user can add liquidity or trade at any time; the depth could change.
- Uniswap's addresses on testnet are assumed to be the same code as on mainnet (only getters were checked; the UR and StateView are not verified on Blockscout).

**Open questions**
1. Does the user want the optional read-only v4 reference panel (about 1 h), or is it out of scope?
2. Minimum acceptable Live desk inventory: what USDG amount does the Paxos faucet give (R1 question 1)? It determines the Live deposit cap.
3. Should Sandbox desk spread be visible to users (a "spread 0.25 %" label on deposit previews), or hidden? The refined `previewDeposit` should show it.

**Still unknown**
- The Paxos faucet claim size and whether USDG or stock tokens can be claimed repeatedly (R1).
- Who created the 0.30 % TSLA/USDG pool and whether it will be topped up or arbitraged; its 2026-10-01 creation hints at another builder's test.
- Whether the Universal Router `0x8876...` and StateView are the official Uniswap deployments (not verified on Blockscout, absent from Uniswap's testnet list).
- The exact revert path for a too-high `minAmountOut` in the direct adapter (the simulation was launched but its output was not captured; the Quoter output of 0.196 TSLA at saturation implies a revert for 0.2 TSLA, so I leave it as unverified).
- Whether pausing, freezing or blocklisting of a vault address can occur on USDG or the Stock registry on testnet in practice (R1).
- Rialto's testnet plans, if any (no document says; `https://docs.rialto.xyz/` read 2026-10-03).
- Whether any other v4 hook (outside the five tokens) wraps the stock tokens in a way that changes `transfer` semantics (not checked).

## Sources

All read on 2026-10-03 unless noted.

- Uniswap v4 deployments (mainnet 4663 only): `https://developers.uniswap.org/docs/protocols/v4/deployments` and `https://docs.uniswap.org/contracts/v4/deployments`; unified feed `https://docs.uniswap.org/deployments.json` (generated 2026-09-22, repo `https://github.com/Uniswap/contracts` commit `a677c0d4`); `https://docs.uniswap.org/llms.txt`.
- Uniswap v4 docs: `https://developers.uniswap.org/docs/protocols/v4/guides/unlock-callback-and-deltas.md`, `.../guides/swapping/swapping.md`, `.../guides/swapping/routing.md`, `.../guides/state-view.md`, `.../guides/read-pool-state.md`, `.../concepts/poolmanager.md`, `https://developers.uniswap.org/docs/sdks/v4/guides/swapping/quoting.md`, `https://developers.uniswap.org/docs/protocols/universal-router/overview.md`, `.../concepts/commands.md`, `https://developers.uniswap.org/docs/protocols/uniswap-labs-hooks/permissioned-pools/overview.md`.
- v4 source (GitHub `main`, raw): `Uniswap/v4-core/src/interfaces/IPoolManager.sol`, `src/PoolManager.sol`, `src/interfaces/callback/IUnlockCallback.sol`, `src/types/BalanceDelta.sol`, `src/types/PoolOperation.sol`, `src/libraries/TickMath.sol`; `Uniswap/v4-periphery/src/lens/V4Quoter.sol`, `src/lens/StateView.sol`, `src/interfaces/IV4Quoter.sol`, `src/V4Router.sol`, `src/interfaces/IV4Router.sol`, `src/libraries/Actions.sol`, `src/base/DeltaResolver.sol`; `Uniswap/permit2/src/interfaces/IAllowanceTransfer.sol`.
- Robinhood docs: `https://docs.robinhood.com/chain/protocol-contracts/` (Permit2 and Multicall on testnet; no Uniswap listing), `https://docs.robinhood.com/chain/building-with-stock-tokens/` (RFQ, AMM, propAMM), via DoH `--resolve`.
- Robinhood price API: `https://api.robinhood.com/rhj/prices/{TSLA,AMZN,AMD,PLTR,NFLX}` read 2026-10-03T14:58Z (TSLA 371.43/371.80, AMZN 249.22/251.38, AMD 623.73/633.50, PLTR 188.36/188.90, NFLX 66.30/67.83).
- Blockscout: `https://explorer.testnet.chain.robinhood.com/api?module=logs&action=getLogs&...` (PoolManager `Initialize` pages), `.../api/v2/smart-contracts/{0x8366...0951, 0x8dc1...8f94, 0x2542...25c0 (BellHook), 0xF0863D7A... (USDG implementation), 0xBd14156E... (Stock implementation), 0xC0E4b366... verifier}`, `.../api/v2/tokens/0x7E955252.../holders`.
- On-chain commands run against `https://rpc.testnet.chain.robinhood.com` (block about 128.2M): `cast codesize` on the 13 addresses in 1.1; `cast call <Quoter> quoteExactInputSingle(...)` (quotes in 1.4); `cast call <StateView> getSlot0/getLiquidity`; batched `eth_call` `getLiquidity`/`getSlot0` for 623 pools (rate limited with HTTP 429 once; resumed); `eth_call` with state overrides (adapter code, USDG slot 1 / 3, TSLA ERC-7201 slots) and `eth_estimateGas` for the gas figures; `cast call <hook> verifier()`, `isOfficial(...)`, `feedOf(...)`.
- Rialto: `https://docs.rialto.xyz/llms.txt`, `.../developers/standard-interface.md`, `.../settlement.md`, `.../quoting.md`, `.../router-registries.md`, `.../swap-api-overview.md`, `.../security-model.md`, `https://www.offchain.io/blog/partners/supporting-rialtos-launch-on-robinhood-chain`, web search results for the Rialto launch (Arbitrum post, Phemex).
- Paxos USDG implementation source via Blockscout: `contracts/PaxosTokenClaimableRewards.sol`, `ClaimableRewardsBase.sol`, `BaseStorageV3.sol` (transfer checks, storage layout, payout groups).
- Repo: `docs/brainstorm/2026-10-03-feng-v2-plan.md` sections 0, 4 (D2, D11), 5.1, E1, E3-T2, E4-T5, 7 R3, 8.1; `docs/research/07-testnet-reality-check.md` sections 2.4 and 5; `docs/research/09-price-source-and-feed.md` (weekend price behaviour, relayer cadence); `contracts/StrategyVault.sol` lines 74-145, 190-285.
