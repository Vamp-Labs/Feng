# Frontend sweep: decimals, addresses, read counts (E6-T0) and resilience result (E6-T2)

Date: 2026-10-03. Scope: `src/` excluding `src/lib/abi/`. Read-only sweep, line numbers are from the tree at the time of writing (before E6-T2 edits, which touch none of the lines below).

## 1. USDG decimals (everything assumes 18)

Single source: `src/lib/format.ts:3` `export const USDG_DECIMALS = 18;`. It is a constant, not read from the token. Paxos USDG is 6 decimals, so every row below breaks on a real-USDG universe.

| Site | What it does |
|---|---|
| `src/lib/format.ts:6` `formatUsdg` | `formatUnits(amount, USDG_DECIMALS)`, 2 fraction digits |
| `src/lib/format.ts:16` `formatUsdgCompact` | same, compact notation |
| `src/lib/format.ts:19-20` `parseUsdg` | `parseUnits(amount, USDG_DECIMALS)`; no caller in `src/` (dead export) |
| `src/lib/format.ts:25-27` `safeParseUsdg` | `parseUnits(amount, USDG_DECIMALS)` |
| `src/components/deposit-redeem-panel.tsx:65` | `parsedAmount = safeParseUsdg(amount)`; feeds `approve`, `deposit`, `previewDeposit`, `previewRedeem`. For redeem the typed amount is strategy-token shares but is parsed with USDG decimals; it only works because both are 18 |
| `src/components/deposit-redeem-panel.tsx:150,166` | `formatUsdg` for USDG balance and redeem preview |
| `src/components/strategy-detail.tsx:65` | `formatUsdg(detail.totalAssetsUSDG)` |
| `src/components/strategy-card.tsx:4,41` | `formatUsdgCompact(totalAssetsUSDG)` |
| `src/components/home/featured-card.tsx:12,137` | `formatUsdg(totalAssetsUSDG)` |
| `src/components/marketplace-stats.tsx:4,15` | `formatUsdgCompact(tvl)` |
| `src/lib/hooks/use-portfolio-stats.ts:5,36` | `formatUnits(tvlRaw, USDG_DECIMALS)` (re-implements `formatUsdgCompact` inline with its own `COMPACT` formatter, duplicate of `format.ts:13`) |
| `src/lib/demo-strategies.ts:2,6` | `usdg = (v) => parseUnits(v, USDG_DECIMALS)` for the three offline demo strategies (lines 17, 27, 37) |

`parseUnits(..., 18)` literal: none. The only literal `18` that is a decimals value outside `format.ts`:

- `src/components/positions-list.tsx:111` `formatTokenAmount(position.balance, 18)` (strategy token balance; the token decimals are already read in `use-strategy-detail.ts:46` but not in `use-positions.ts`).
- `src/components/strategy-detail.tsx:90` `tokenDecimals={detail.decimals ?? 18}` (falls back to 18 until the token `decimals()` read lands).

Correct-by-design: `formatTokenAmount(amount, decimals)` (`format.ts:51`) already takes decimals; `deposit-redeem-panel.tsx:153,163` pass `tokenDecimals`.

Fix shape for E6-T1/T3: read `decimals()` of `addresses.usdg` once (one entry in an existing multicall) and thread it through `formatUsdg`, `formatUsdgCompact`, `safeParseUsdg`, `use-portfolio-stats.ts`, and `demo-strategies.ts`; parse redeem shares with the strategy token decimals.

## 2. Hard-coded addresses

In `src/` (not counting the generated ABI folder and JSON deployment fixtures):

- `src/lib/demo-strategies.ts:10-12, 20-22, 30-32`: nine fake placeholder addresses (`0xd3a0...0001`, `...0011`, `0x7a3f...c0de`, etc.) for the offline demo cards shown on `/` when the registry is empty or unreadable. `isDemoStrategy` (line 43) keys on them.
- `src/app/providers.tsx:16` `PRIVY_ACCENT_COLOR = "#35f9a5"` (a colour, not an address; listed because it is the only token-bypassing hex in providers).
- `src/lib/networks.ts` (added by E6-T2): `MULTICALL3_ADDRESS`, the canonical `0xcA11bde05977b3631167028862bE2a173976CA11`.

Real contract addresses are never hard-coded: they come from `deployments/<network>/addresses.json` through `loadActiveNetworkConfig()` (`src/lib/addresses.ts`), shipped to the client by `Providers` and read through `useContracts()` (`src/lib/use-contracts.ts`). Stock-token tickers resolve from `addresses.stockTokens` (`use-constituent-options.ts`, `holding-tones.ts`). A fixture for anvil lives in `src/lib/dev/anvil-addresses.json`.

## 3. Read counts per page

Hooks and the multicalls they issue (each `useReadContracts` is one `eth_call` to Multicall3 once batching works; each `useReadContract` is one call, merged into the same Multicall3 call when issued within the same 16 ms window):

| Hook | Calls issued | Depends on |
|---|---|---|
| `useMarketplaceStrategies` (`use-marketplace.ts`) | wave 1: `useReadContract getAllStrategies` (1 call). wave 2: `useReadContracts` of `getStrategyInfo` x N. wave 3: `useReadContracts` of `totalAssetsUSDG`, `name`, `symbol` x N (3N calls) | wave 2 needs wave 1; wave 3 needs wave 2 |
| `useStrategyHoldings` (`use-strategy-holdings.ts`) | `useReadContracts` of `getConstituents` x N (retry 3, cached forever on success) | wave 1 |
| `usePositions` (`use-positions.ts`) | `useReadContracts` of `balanceOf(user)` x N, only when a wallet is connected | wave 2 |
| `usePortfolioStats` | no reads of its own (marketplace + positions) | |
| `useConstituentOptions` | no reads of its own (marketplace) | |
| `useStrategyDetail` (`use-strategy-detail.ts`) | `getStrategyInfo` (1), core `useReadContracts` x4 (`totalAssetsUSDG`, `getConstituents`, `depth`, `rebalanceNeeded`), token meta x3, constituent meta 3 x constituents | info -> token meta; core -> constituent meta |
| `DepositRedeemPanel` | 3 `useReadContract` when connected (`usdg.balanceOf`, `usdg.allowance`, token `balanceOf`), 1 preview when an amount is typed | |

Pages (N = number of strategies, 10 on the live registry):

| Page | Hooks | Logical contract reads | Per-contract `eth_call`s without Multicall3 | After E6-T2 (measured) |
|---|---|---|---|---|
| `/marketplace` | marketplace + holdings (+ stats component reuses marketplace) | 1 + N + 3N + N = 5N + 1 = 51 | 51 | 3 `eth_call`, all to Multicall3 |
| `/` | marketplace + holdings (featured carousel), `usePortfolioStats` (rank scene) | 51 | 51 | 3 |
| `/positions` | marketplace + positions (wallet) + stats | 4N + 1 (+ N when connected) | 41 (+10) | 3 |
| `/create` | marketplace (options) | 4N + 1 | 41 | 3 |
| `/strategy/[vault]` | detail (4 + 3 + 3C + 1 reads), panel reads when connected | about 20 | about 20 | 3 `eth_call` in 2 HTTP POSTs |

The marketplace reads were already collapsed into per-wave `useReadContracts`, so the hook code needed no change. The N+1 came from the chain definition: `src/lib/chains.ts` had no `contracts.multicall3`, so viem's `multicall` throws `ChainDoesNotSupportContract`, and `readContracts` in `@wagmi/core` catches that and falls back to one `readContract` per entry (`readContracts.ts`, catch branch). That is the 41+ calls.

Notes on dedup: wagmi/TanStack Query dedupes identical keys, so `MarketplaceList`, `MarketplaceStats`, `StrategyCard` etc. mounting the same hook does not multiply requests. `useStrategyHoldings` is mounted separately on `/` and `/marketplace` and caches forever on success.

## 4. E6-T2 result

Changes (all in the frontend lane):

- `src/lib/networks.ts`: `NetworkDefinition.multicall3?`, exported `MULTICALL3_ADDRESS`, set on Robinhood testnet and Arbitrum Sepolia (the fallback chain; same canonical address; viem ships it for that chain). Not set for anvil (the local fixture does not deploy Multicall3, so anvil keeps the per-call fallback).
- `src/lib/chains.ts`: `contracts: { multicall3: { address } }` on the viem chain.
- `src/lib/wagmi-config.ts`: `batch.multicall` set explicitly with a 16 ms `wait` (wagmi defaults to `{ multicall: true }`, which has `wait: 0`); `http()` transport with JSON-RPC batching (`batch.wait` 16 ms), `retryCount` 4, `retryDelay` 250 ms (viem backs off exponentially from it), `timeout` 12 s. The RPC accepts JSON-RPC batch arrays (checked with curl: `eth_chainId`, `eth_blockNumber`, `eth_getCode` in one POST, all answered).
- `src/lib/query-client.ts` (new) used by `src/app/providers.tsx`: `staleTime` 15 s, `gcTime` 5 min, up to 3 retries with 1 s, 2 s, 4 s (cap 8 s) delay, no retry when the failure is a contract revert (so `StalePrice`-style reverts surface immediately instead of after about 7 s).

Measurement method: production build served with `next start --port 3001`, headless Chrome (`chrome-headless-shell` 151, `--ignore-certificate-errors` because the ISP TLS interception otherwise fails every request), Chrome DevTools Protocol `Network.requestWillBeSent` filtered to `rpc.testnet.chain.robinhood.com`, request bodies parsed as JSON-RPC and each `eth_call` classified by target address. 20 s observation per page, no wallet connected.

| Page | HTTP POSTs with a body | JSON-RPC `eth_call` | of which to Multicall3 | failures |
|---|---|---|---|---|
| `/marketplace` | 3 | 3 | 3 | 0 |
| `/` | 3 | 3 | 3 | 0 |
| `/positions` | 3 | 3 | 3 | 0 |
| `/create` | 3 | 3 | 3 | 0 |
| `/strategy/0x9f61...B243B` | 2 | 3 | 3 | 0 |

An earlier run in the same harness without the certificate flag showed every request failing with `ERR_CERT_COMMON_NAME_INVALID` and exactly 5 attempts per request (1 + `retryCount` 4), confirming the transport retry is live.

The "before" figure (51 on `/marketplace`) is derived from the code path above, not measured: rebuilding the old chain definition was not worth a second build, and the fallback branch in `@wagmi/core` is unambiguous.

Not measured: a connected wallet (needs Privy login, so `usePositions`, panel reads and wallet-side calls were not exercised; they are `useReadContracts`/`useReadContract` and will ride the same batch), the `/strategy` page past the first 20 s, and a dev server (port 3000 was unresponsive when probed and was left alone).
