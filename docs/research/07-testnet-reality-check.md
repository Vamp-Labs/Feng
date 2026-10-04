# 07 — Robinhood Chain testnet reality check (re-verification of 02-robinhood-testnet.md)

Read and measured on **2026-10-03** (about 21:30-22:30 SGT), from the user's machine, using the public
Blockscout REST API, raw JSON-RPC, Robinhood/Paxos docs reached with a DNS bypass (`curl --resolve`
with the real IP from DoH, because the local ISP intercepts TLS), and Robinhood's public REST API.
Purpose: several conclusions in `02-robinhood-testnet.md` and `DEMO-NOTES.md` section 7 were wrong or
incomplete. This file supersedes them where they conflict. Everything marked **UNVERIFIED** still needs
the agent in epic E1 to confirm.

Reproduce: every command is in the "How to reproduce" section at the bottom.

## 1. What changed versus the earlier research

| Earlier conclusion | Now | Confidence |
|---|---|---|
| "No testnet stock-token addresses exist" (DEMO-NOTES section 7 item 3, from `/rhj/assets` having only chain 4663) | **Real testnet stock tokens exist** and are the ones the Robinhood faucet hands out. The registry API simply does not list testnet. | High (Blockscout token list, 220k-290k holders each, verified proxy, matches the community README for TSLA/AMZN/NFLX) |
| "No testnet USDG address found" | **Paxos' own docs list the Robinhood Testnet USDG address.** | High (primary source: Paxos docs, plus on-chain checks) |
| "No live price feed" | Still true for Chainlink. A third-party Aave-fork ("Edel") has a TSLA/USD feed, but it is owner-updated and last updated 2026-06-09. Unusable. | High |
| "Faucet is CAPTCHA-gated so no way to get tokens" | Still gated for ETH, but the deployer wallet **already holds 5 TSLA/AMZN/AMD/PLTR/NFLX** from a faucet claim, so real stock tokens are obtainable by the user in a browser. | High |

## 2. Facts

### 2.1 Real stock tokens on testnet (chain 46630)

Blockscout `GET /api/v2/tokens?type=ERC-20` (top by holders). All 18 decimals, total supply
6,264,870 tokens each, `uiMultiplier() = 1e18` (checked on TSLA).

| Ticker | Address | Holders (2026-10-03) |
|---|---|---|
| AMZN | `0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02` | 291,879 |
| TSLA | `0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E` | 228,377 |
| AMD | `0x71178BAc73cBeb415514eB542a8995b82669778d` | 227,926 |
| PLTR | `0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0` | 225,438 |
| NFLX | `0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93` | 223,891 |

- TSLA is an EIP-1967 **BeaconProxy** (verified) over the verified `Stock` implementation
  `0xBd14156E05c6AF28ad39aA53a2AB8eB9CDf657DA` (source `src/Stock.sol`, solc 0.8.33). Same family as
  mainnet Stock Tokens.
- `Stock.mint`/`burn` need `MINTER_ROLE`/`BURNER_ROLE` held by Robinhood-side accounts. **Our vault can
  never mint or burn these.** `transfer`, `transferFrom`, `approve` are `onlyNotPaused` and
  `onlyNotBlocked` (a registry-level pause or blocklist can freeze a holder, including a vault).
- The faucet claim is 5 tokens per ticker (deployer `0x47575C31c8146022FaB38dFF5ce883b5e55F6785` holds
  exactly 5e18 of each). Top holders include faucet-like contracts (330k TSLA), Edel (lending), Aave
  fork (`Aave Stock TSLA`) — so the tokens already circulate in DeFi on testnet.
- `uid()` on the five testnet tokens (e.g. TSLA `0xaa1fee9a...63f5`) does **not** equal the mainnet
  registry ids from `/rhj/assets` (e.g. TSLA `0xcfece324...2d9f`), so testnet tokens are separately
  issued; canonicity rests on faucet reach, the Arbitrum testnet-launch blog naming these five
  tickers, and the community README. Treat as "very likely the faucet tokens", not proven by Robinhood.
- Our deployed mocks (`deployments/robinhood-testnet/addresses.json`, e.g. TSLA `0x37e2...3732`) are
  **different, unrelated contracts**.
- Decoys exist: another "USDG" `0x915Ef7c9F9f80a69e3BE47A38EE0Bb47607103ec` (6 decimals, unverified,
  10k holders, `claim()` of 1000) and a "Mock USDG" `0x8F9231B0F448bA9AD045348437458721676c23BC`. Docs
  warn that a token with a matching name at a different address is not canonical.

### 2.2 Paxos USDG on testnet

- Paxos docs, "USDG on Test Networks" (https://docs.paxos.com/guides/stablecoin/usdg/testnet): **Robinhood
  Testnet token `0x7E955252E15c84f5768B83c41a71F9eba181802F`**, supply control
  `0x4549bb98c667aAb626627C118102c28065E8f54C`. Arbitrum Sepolia USDG
  `0xFFC95faa3d63Cde504a05B567C600B78C0b41892` (useful fallback network).
- On-chain: name "Global Dollar", symbol USDG, **decimals 6**, ERC1967 proxy (verified) over a verified
  `USDG` implementation, 4,072 holders, supply 57,301,240 USDG. Deployer wallet balance is 0.
- Our `MockUSDG` is 18 decimals and `StrategyVault` assumes it (`slice * 1e18 / price`, `StrategyVault.sol:96`;
  `src/lib/format.ts` `USDG_DECIMALS = 18`). Real USDG would silently break V1 math by 1e12.
- Faucet: Paxos faucet at https://faucet.paxos.com (listed in Paxos docs navigation). Claim size and
  gating are **UNVERIFIED** (a human must try it; likely CAPTCHA).
- Mainnet USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` is in Robinhood's token-contracts page (not
  for this build).

### 2.3 Prices

- Chainlink Data Feeds for Robinhood Chain: **mainnet only**. `feeds-robinhood-testnet.json` returns 404,
  `feeds-robinhood-mainnet.json` returns 200 (re-checked). Data Streams verifier proxy is listed for
  mainnet only.
- Edel's TSLA feed `0x518C0E2860c3E4BEB06FCa4fF30259Fb3E91EfBd` ("TSLA / USD", 8 decimals, 408.91) is
  owner-updated by `0x556088ff...`, last `update` tx 2026-06-09. Stale and not ours to rely on.
- **Robinhood publishes live, unauthenticated prices**: `GET https://api.robinhood.com/rhj/prices/{symbol}`
  (docs: https://docs.robinhood.com/chain/stock-token-apis/, 15 s cache, 60 req/s). Fields include
  `bid`, `ask`, `tokenBid`, `tokenAsk`, `isTradingHalt`, `generatedAt`. Sample at 2026-10-03T13:42Z:
  TSLA 371.43/371.80, AMZN 249.22/251.38, NFLX 66.30/67.83, PLTR 188.36/188.90, AMD 623.73/633.50.
  Our mock seed prices (250/180/600/25/140) are far from reality.
- `GET /rhj/assets` (194 assets, all `chainId 4663`) returns a `logoUrl`
  (`https://cdn.robinhood.com/ncw_assets/logos/<mainnet-address-lowercase>.png`). Logo usage terms
  UNVERIFIED.
- Docs say stock feeds update 24/5; with a 24 h staleness limit, real Chainlink feeds would trip every
  weekend. A per-token heartbeat/staleness is needed on the mainnet path.

### 2.4 Infrastructure facts that shape the design

- **Gas is ~0.01 gwei** (`cast gas-price` = 10,000,000 wei). Creating a vault (2.76M gas) cost
  0.0000276 ETH (tx `0x337a6bc2...`, block 127,134,572, 2026-10-01T12:21Z). Deployer balance
  0.00818 ETH covers a full redeploy and weeks of keeper/relayer pushes (about 0.0001 ETH/day at
  one 6-feed push per 30 min).
- **Canonical Multicall3 exists** at `0xcA11bde05977b3631167028862bE2a173976CA11` (code present) and
  Robinhood lists a testnet L2 Multicall `0xa432504b6F04Cafe775b09D8AA92e8dbe41Ec7a8`. Our
  `src/lib/chains.ts` does not set `contracts.multicall3`, so wagmi sends one `eth_call` per read.
- **Historical state is not available**: `eth_call` at 100k blocks back fails with "historical state ...
  is not available". So NAV history cannot be read retroactively; it must be recorded (events or a store).
- **`eth_getLogs` works over huge ranges**: a 50M-block range for the registry returned all 12 logs. So
  event-sourced history is viable with no indexer.
- Block time about 0.16 s (864,000 blocks = 140,342 s); about 532k blocks/day.
- **Uniswap v4 `PoolManager`** at `0x8366a39CC670B4001A1121B8F6A443A643e40951` (verified). `Initialize`
  logs show many pools with the Paxos USDG as `currency0`, including **at least two USDG/TSLA pools**
  (ids `0xdb347ba0ee...`, `0x38f88da1f1...`); liquidity depth UNVERIFIED. Uniswap v3 position NFTs also
  exist. Robinhood docs say stock tokens trade via RFQ aggregators, Uniswap AMM pools and propAMMs.
- Robinhood docs list Permit2 at `0x000000000022D473030F116dDEE9F6B43aC78BA3` on testnet.

## 3. Implications (inputs to the v2 plan)

1. A "real asset" mode is feasible: real faucet stock tokens + Paxos USDG are on chain. The vault must
   **hold** them (no mint/burn) and trade through a venue or accept them in kind.
2. USDG decimals must be handled (6, not 18). This alone makes V1 unusable with real USDG.
3. Prices still have to come from us on testnet; the live Robinhood price API is the best source.
4. NAV history must be event-sourced or stored; there is no archive state.
5. The keeper/relayer must run outside Indonesia; the frontend should batch reads via Multicall3.

## 4. Still UNVERIFIED (assigned to E1)

Paxos faucet claim size and gating; whether any USDG/stock Uniswap v4 pool has usable depth (and which
hooks); whether Robinhood has a testnet Chainlink Data Streams or any other live feed; whether the real
USDG implementation blocks transfers to contracts (it has blocklist/pause features per Paxos design);
logo usage terms; ArbOS version / `PUSH0` support (still `evm_version = paris`).

## 5. How to reproduce

```bash
B=https://explorer.testnet.chain.robinhood.com/api/v2
curl -s "$B/tokens?type=ERC-20"                                   # token list with holders
curl -s "$B/smart-contracts/0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E"   # TSLA beacon proxy
cast call 0x7E955252E15c84f5768B83c41a71F9eba181802F "decimals()(uint8)" --rpc-url https://rpc.testnet.chain.robinhood.com
cast gas-price --rpc-url https://rpc.testnet.chain.robinhood.com
# Initialize events of the v4 PoolManager with USDG as currency0 (topic2):
curl -s "https://explorer.testnet.chain.robinhood.com/api?module=logs&action=getLogs&fromBlock=0&toBlock=latest&address=0x8366a39CC670B4001A1121B8F6A443A643e40951&topic0=0xdd466e674ea557f56295e2d0218a125ea4b4f0f6f3307b95f85e6110838d6438&topic0_2_opr=and&topic2=0x0000000000000000000000007e955252e15c84f5768b83c41a71f9eba181802f"
# Robinhood live prices (use --resolve with the DoH IP if your ISP intercepts TLS):
curl -s https://api.robinhood.com/rhj/prices/TSLA
```

The RPC and explorer fail intermittently from Indonesia (ISP TLS interception, see
`docs/handoffs/DEMO-NOTES.md` section 1): always retry; for `forge script` use `--resume`.

## Sources

- Paxos, USDG on Test Networks: https://docs.paxos.com/guides/stablecoin/usdg/testnet (read 2026-10-03 via DNS bypass)
- Robinhood Chain docs: `/chain/oracles-and-price-feeds/`, `/chain/building-with-stock-tokens/`, `/chain/stock-token-apis/`, `/chain/protocol-contracts/`, `/chain/contracts/`, `/chain/data-streams/` (read 2026-10-03 via DNS bypass)
- Blockscout REST API on https://explorer.testnet.chain.robinhood.com (queried 2026-10-03)
- Chainlink reference data directory (404 for testnet): https://reference-data-directory.vercel.app/feeds-robinhood-testnet.json
- `hummusonrails/robinhood-chain-dapp-example` README (community, cross-checks TSLA/AMZN/NFLX addresses)
