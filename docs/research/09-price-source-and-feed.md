# R2: price source and FengAggregator feed design

- **Date read/measured**: 2026-10-03, 14:23 to 14:36 UTC (a Saturday; 10:23 to 10:36 in New York, so a Saturday morning in US time, not evening; US equity markets were closed). Plan reference: `docs/brainstorm/2026-10-03-feng-v2-plan.md` section 7 R2, D7, E2-T1, E2-T6, E3-T1.
- **Method**: raw `curl --resolve` against the DoH IPs for `api.robinhood.com` and `docs.robinhood.com` (the local resolver returns a wrong host for `api.robinhood.com`, so a plain `curl` fails TLS); `cast` against the public RPC with retries; Chainlink and Pyth public docs and JSON. No transaction was sent, no key was used, no `.env*` file was read.

## Summary

1. **Robinhood's `/rhj/prices/{symbol}` is usable as the sandbox price source**, with caveats. It is unauthenticated, returns a JSON `quotes[0]` with bid/ask, 15 s cache (verified), no attribution requirement found in the docs or Terms of Service. It is not documented as having an SLA, and its live JSON already differs from the documented schema (it returns undocumented `tokenBid`, `tokenAsk`, `dailyHigh`, `dailyLow`, `mintBurnTokenVolume`, `mintBurnUsdVolume`), so the relayer must parse defensively.
2. **`tokenBid`/`tokenAsk` = `bid`/`ask` multiplied by the token's `currentMultiplier`** (verified exactly on CRWD at 4.0 and CCL, SPY, AAPL, NVDA at about 1.001 to 1.02). That is the same quantity the real Chainlink stock feeds publish ("underlying price times multiplier"). For our five tickers the multiplier is currently exactly 1.0, so `tokenBid == bid`. Use `tokenBid`/`tokenAsk`, never `bid`/`ask`.
3. **Weekend behaviour (real sample)**: quotes are frozen at the Friday value (byte-identical over 50 minutes in two samples, and identical to the 13:42Z sample in doc 07), `isTradingHalt` is `false` for all 194 assets, and `generatedAt` keeps advancing to the current second. So **`generatedAt` is a server clock, not a data-freshness signal**, and `isTradingHalt` does not mean "market closed". Weekend spreads are wide (our five: TSLA 10 bps, PLTR 29, AMZN 86, AMD 155, NFLX 228; median over all 194 assets 423 bps, max 19,818 bps).
4. **No safer live source exists.** Chainlink has no Robinhood Chain testnet data-feed file (404) and Robinhood's Data Streams page lists a mainnet verifier only. Pyth has no deployment on Robinhood Chain (not on Pyth's contract list; the canonical address on chain 46630 is an unrelated contract), its Hermes update endpoints now require an API key since 2026-08-26, and NFLX and AMD only have regular-hours feeds. Pyth is at best an optional off-chain cross-check, not worth the extra secret.
5. **FengAggregator design**: a role-gated aggregator with a per-update deviation bound of 1,000 bps, 30 minute heartbeat (re-publish same answer), relayer tick every 5 minutes, hold mode = same-answer push. A +18% demo shock is two stepped pushes of +8.63% each, signed by the relayer key (no contract special case), with an admin-only `setMaxDeviationBps` as a documented backup.
6. **Cost is negligible**: measured `cast estimate` of `updateAnswer` = 44,249 gas per feed (41,431 when re-publishing an unchanged value); at 0.01 gwei, 6 feeds every 30 minutes cost about 0.000127 ETH per day, about 0.0038 ETH per 30 days.
7. **Two urgent findings outside the R2 questions**: (a) the six V1 feeds are **50.1 hours old right now** (last update 2026-10-01 12:22 UTC), and the live V1 vault `0x9f6123c7...438B` **reverts `deposit` and `redeem` with `StalePrice`** (reproduced with `cast call`), because V1 enforces a 24 h limit on every deposit and redeem; (b) because V1 `redeem` itself is blocked by a stale feed, the V2 design must keep `redeemInKind` oracle-free, as the plan already requires.

## Findings

### 1. `https://api.robinhood.com/rhj/prices/{symbol}`

**1.1 Documented terms and limits** (`https://docs.robinhood.com/chain/stock-token-apis/`, read 2026-10-03):
- "read-only REST endpoints under https://api.robinhood.com/rhj/ ... All endpoints are rate-limited to 60 requests/second and cached; respect the per-endpoint cache window."
- `/prices` row: cache 15 s, 60 req/s, "Please use /{symbol} whenever applicable to prevent additional latency."
- Documented `/prices` fields: `tokenSymbol`, `deployments[]`, `bid`, `ask`, `currency` ("USD" at launch), `dailyTradingVolume` ("0" when unavailable), `isTradingHalt` ("true when the asset has an active trading halt"), `generatedAt` ("Server time the quote was generated").
- Documented semantics: "Prices are the raw underlying-equity bid/ask passed through as-is — they are not multiplier-adjusted. Apply `currentMultiplier` from `/assets` if you need the token-equivalent value." and "The REST /prices endpoint returns the raw underlying-equity bid/ask ... The onchain Chainlink feed returns the multiplier-adjusted value."
- `/corporate-actions` cache 1 hour, `/assets` carries `currentMultiplier`, `pendingMultiplier`, `pendingMultiplierEffectiveTime`.
- **Attribution/terms**: the docs page states no attribution, licence, or redistribution clause for the data. The Robinhood Chain Terms of Service (`https://docs.robinhood.com/chain/terms-of-service`, "Last Updated: August 24, 2026") covers the Sequencer, Public RPC, Full Node Snapshot, Testnet, and "SDKs, APIs, and related tools through docs.robinhood.com/chain" (section 2.1) with no data-licence clause. Section 2.3 "Network Abuse" prohibits "use of automated tools (such as bots, scrapers, or spiders)" that interfere with, disrupt or degrade the Services or bypass usage restrictions. Polling 5 symbols every few minutes is far under the published limit and not disruptive, but a relayer is an automated tool, so staying under the cache window and the rate limit is the compliance posture. Brand Guidelines (`https://docs.robinhood.com/chain/brand-guidelines`, v1.0 2026-08-20): refer to "Stock Tokens" in full and never "tokenized stocks"/"tokenized equities"; always write "Robinhood Chain" in full; any statistic must name its source with a link. Feng's own copy should follow that wording.
- **No SLA or stability promise** is stated anywhere I found. The 07 doc already noted the logo URL terms as unverified; that is unchanged.

**1.2 Live responses** (curl through `--resolve`, HTTP 200, `content-type: application/json`, `server: envoy`, served by CloudFront with `x-cache: Miss from cloudfront`, `grpc-status: 0` header, so it is a gRPC-gateway behind CloudFront; no `cache-control` or rate-limit headers are returned).

Exact JSON for TSLA at 2026-10-03T14:23Z:

```json
{"quotes":[{"tokenSymbol":"TSLA",
 "deployments":[{"contractAddress":"0x322F0929c4625eD5bAd873c95208D54E1c003b2d","chainId":4663,"networkName":"Robinhood Chain","itnEnabled":false,"atomicEnabled":false}],
 "bid":"371.43","ask":"371.8","currency":"USD","dailyTradingVolume":"55329941","isTradingHalt":false,
 "generatedAt":"2026-10-03T14:23:10.223339303Z","dailyHigh":"374.6","dailyLow":"354.9",
 "mintBurnTokenVolume":"1557.82426","mintBurnUsdVolume":"578910.8623799",
 "tokenBid":"371.430000000000000000","tokenAsk":"371.800000000000000000"}]}
```

Field list returned (14 keys): `ask, bid, currency, dailyHigh, dailyLow, dailyTradingVolume, deployments, generatedAt, isTradingHalt, mintBurnTokenVolume, mintBurnUsdVolume, tokenAsk, tokenBid, tokenSymbol`. `deployments[]` keys: `atomicEnabled, chainId, contractAddress, itnEnabled, networkName`. Note that `deployments` lists only the **mainnet** deployment (chainId 4663), never the testnet addresses; map by `tokenSymbol` (TSLA's mainnet address `0x322F...` differs from the testnet faucet token `0xC9f9...` in the plan).

Field meanings (observed, cross-checked against the docs):

| Field | Type | Meaning (evidence) |
|---|---|---|
| `tokenSymbol` | string | Ticker, upper case only (`/rhj/prices/tsla` returns 404 `no whitelisted asset with symbol "tsla"`). |
| `bid`, `ask` | decimal string | Raw underlying-equity bid/ask in USD, not multiplier-adjusted (docs; CRWD bid 269.87 versus tokenBid 1079.48). |
| `tokenBid`, `tokenAsk` | decimal string, 18 dp | **`bid`/`ask` times `currentMultiplier`**. Verified: CRWD multiplier 4.0 gives ratio 4.0 exactly; CCL 1.021486444855206408 gives 1.0214864448552063; SPY 1.001717991187472003, AAPL 1.000566080061092436, NVDA 1.000775159164630595 all match. Not in the published schema (undocumented but stable across 194 assets). |
| `currency` | string | "USD". |
| `dailyTradingVolume` | string | Underlying-equity volume. |
| `dailyHigh`, `dailyLow` | decimal string | Undocumented; **raw underlying** (CRWD 273.54/266.50 versus tokenBid 1079.48), so multiply by the multiplier before using them as a sanity band. |
| `mintBurnTokenVolume`, `mintBurnUsdVolume` | decimal string | Undocumented; primary-market mint/burn volume. Not needed. |
| `isTradingHalt` | bool | True only for an active halt (docs). It was `false` for all 194 assets on a Saturday, so it is **not** a "market closed" flag. |
| `generatedAt` | RFC 3339 with ns | Server time of quote generation. Verified to be a server clock (see 1.4). |

**1.3 Cache and rate**: five symbols fetched at 8 s intervals three times. TSLA `generatedAt` was `14:23:10.2`, then `14:23:25.5` (round 2), and the **identical** `14:23:25.505598680Z` in round 3 (8 s later); AMZN, NFLX, PLTR, AMD behaved the same, so the 15 s cache window is real and per symbol. I deliberately did not load-test the 60 req/s limit. Without a symbol, `GET /rhj/prices` returns all 194 quotes in one 98,472-byte response with a single shared `generatedAt` (14:25:11.05Z, equal to the request time); the docs advise per-symbol calls to avoid latency, 5 small requests per tick is the clean option.

**1.4 The five tickers, three rounds plus a final sample** (all values identical in every round):

| Symbol | bid | ask | mid | spread (bps) | mid scaled to 8 dp | `isTradingHalt` |
|---|---|---|---|---|---|---|
| TSLA | 371.43 | 371.80 | 371.615 | 10 | 37161500000 | false |
| AMZN | 249.22 | 251.38 | 250.30 | 86 | 25030000000 | false |
| NFLX | 66.30 | 67.83 | 67.065 | 228 | 6706500000 | false |
| PLTR | 188.36 | 188.90 | 188.63 | 29 | 18863000000 | false |
| AMD | 623.73 | 633.50 | 628.615 | 155 | 62861500000 | false |

Multiplier for all five (`/rhj/assets`): `currentMultiplier` "1.000000000000000000", `pendingMultiplier` "". No corporate-action rows exist for them in `/rhj/corporate-actions` (the list is processDate-ordered, 1 h cache; the first rows are CRM, MPWR, TSM cash dividends in October).

**1.5 Weekend behaviour (this is a real weekend sample)**:
- 13:42Z (doc 07 section 2.3), 14:23Z, and 14:35Z give the **same** bid and ask for all five (for example TSLA 371.43/371.80), while `generatedAt` advanced by the wall clock (TSLA `14:23:10`, `14:34:10`, `14:35:40`). So the endpoint serves the last quote and stamps it with the current time.
- Pyth's market-hours field agrees the market is closed: `next_open` 1791207000 = 2026-10-05 13:30 UTC (09:30 ET Monday) for the TSLA equity feed (`https://hermes.pyth.network/v2/price_feeds?query=TSLA&asset_type=equity`, 2026-10-03).
- Spreads are wide and noisy while closed (see table; AMD's 155 bps and NFLX's 228 bps are an order of magnitude above a normal spread). All five mids lie inside the Friday `dailyLow`/`dailyHigh` band (for example NFLX mid 67.065 within 66.76 to 68.23), which gives a usable plausibility check. Some other assets quote absurd weekend spreads (CRM 229.4/270.0 = 16%; the worst of 194 is 19,818 bps), so a spread guard is needed.
- **Not sampled**: a weekday session, an overnight session, an actual trading halt, a corporate-action window, and any Monday gap. Those behaviours are taken from the docs only (see Assumptions).

**1.6 Corporate actions and `uiMultiplier`** (`https://docs.robinhood.com/chain/building-with-stock-tokens`, `.../oracles-price-feeds/`, `https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood`, 2026-10-03):
- Stock tokens implement ERC-8056; `uiMultiplier()` has 18 decimals (1e18 = 1.0), balances and supply stay raw (not rebasing). Dividends are reinvested through the multiplier (a token tracks total return), splits scale it (example in the Chainlink doc: 1.0 to 10.0, token price continuous at $20 x 10 = $200). Pending changes are visible via `newUIMultiplier()` and `effectiveAt()`.
- The Chainlink feed returns the multiplier-adjusted per-token price ("don't apply the multiplier yourself"), so **`tokenBid`/`tokenAsk` is the REST equivalent of the Chainlink answer; `bid`/`ask` is not**. 42 of 194 assets currently have a multiplier other than 1.0 (CRWD 4.0, CCL 1.0215, SGOV 1.0072, SCHD 1.0055 and so on), so mixing the two would be visibly wrong for those.
- During a corporate action Robinhood pauses the oracle (`oraclePaused()` on the token); the Chainlink feed "holds the last known good value" and stops updating; the flag is advisory. A relayer should mirror that: do not push while `/assets` shows `pendingMultiplier != ""` or a matching `/corporate-actions` row has status `IN_PROGRESS` with a `processDate` within a day, keep the last answer, and alert.
- The live `/rhj/assets` already differs from the docs example (adds `tokenDecimals`, `isin`, `tradingCapabilities.market/extended/overnight`; the docs page shows an older `fractionalTradability`/`allDayTradability` shape), another sign that fields evolve without notice.

**1.7 Stability/risk summary**: unauthenticated and CDN-fronted (good); schema drift between docs and live (parse defensively, ignore unknown fields, require the 5 fields we use); the mid is noisy in closed sessions; no stated SLA; the local resolver in the user's network returns a wrong host for this domain, and ISP interception hits TLS intermittently, so the relayer host must be outside that network (consistent with R5) and retry with backoff.

### 2. Other live sources

**2.1 Chainlink on Robinhood Chain testnet**
- `https://reference-data-directory.vercel.app/feeds-robinhood-testnet.json` returns **404** (79 bytes); also 404 for `feeds-robinhood-chain-testnet.json` and `...-chain-mainnet.json`; `feeds-robinhood-mainnet.json` returns 200 (84,653 bytes, 58 feeds). Read 2026-10-03. This is the same result as doc 07.
- Mainnet entries for our tickers (for R8/E11 only, not usable on testnet): TSLA `0x4A1166a659A55625345e9515b32adECea5547C38`, AMZN `0xD5a1508ceD74c084eBf3cBe853e2C968fB2a651C`, PLTR `0x820ABedFF239034956B7A9d2F0a331f9F075eB4c`, AMD `0x943A29E7ae51A4798823ca9eEd2ed533B2A22C72`, USDG/USD `0x61B7e5650328764B076A108EFF5fa7282a1B9aD2`; all 8 decimals, heartbeat 86400 s, threshold 0.5%. No NFLX row appeared in my name filter (R8 should confirm).
- Chainlink's own page for Robinhood tokenized equity feeds states: the feed price is underlying market price times the on-chain multiplier; 24/5 coverage; "When underlying equity markets are closed (weekends, holidays, thin overnight windows), the feed may hold the last published price ... **These feeds do not have heartbeats during off-hours**"; read `updatedAt` and apply your own staleness bound (`https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood`, 2026-10-03).
- **Data Streams**: `https://docs.robinhood.com/chain/data-streams` lists a Verifier Proxy only for "Robinhood Chain Mainnet (chain ID 4663)" `0xcE73c8ad08CBDEaCa6078BF0627C8fe0a9a536E7`. Chainlink's `data-streams/crypto-streams` page (16 MB, scanned) contains Robinhood only as the HOOD equity and xStock assets, never a Robinhood Chain network. A web-search summary claimed Data Streams exist for the Robinhood testnet; I could not confirm it from any primary page, so I treat it as unconfirmed.
- Conclusion: **there is no live Chainlink data feed for the testnet that I can find**; "confirmed with high but not absolute confidence" (I could not ask an official channel; see Still unknown).

**2.2 Pyth**
- Pyth's EVM contract list (`https://docs.pyth.network/price-feeds/core/contract-addresses/evm`, 549 KB HTML parsed 2026-10-03) lists no Robinhood chain (only unrelated "Ethereum Hoodi", "Morph Hoodi", "Taiko Hoodi").
- On chain 46630, address `0x2880aB155794e7179c9eE2e38200202908C17B43` (Pyth's usual address on many EVM chains) has 2,137 hex chars of code, is verified on Blockscout as `ReceiverSetup`, with an empty EIP-1967 implementation slot, and `getValidTimePeriod()` fails, so it is **not** Pyth. `0x4305FB66...` has no code.
- Hermes: `GET /v2/price_feeds?query=TSLA&asset_type=equity` still answers 200 without a key, but `/v2/updates/price/latest` returns `unauthorized`. Pyth's docs (`https://docs.pyth.network/price-feeds/core/upgrade/preparing`): "hermes.pyth.network now requires authentication ... every Hermes user needs a Pyth API Key"; free trial, paid after; effective 2026-08-26 16:00 UTC.
- Coverage: TSLA, AMZN, PLTR have both `Equity.US.X/USD` (schedule `America/New_York;0930-1600` Monday to Friday, closed weekends) and an `Equity.Index.X/USD` "24/7" variant; NFLX and AMD have only the regular-hours `Equity.US` feed. So Pyth is worse on session coverage than Robinhood's own 24/5-based quote and needs a secret. It cannot be pulled on chain because no Pyth contract is deployed here.

**2.3 Others**: Edel's owner-updated TSLA feed (doc 07 section 2.3) is stale and owner-controlled. No RedStone, API3 or Switchboard deployment on 46630 turned up in a web search; not verified further.

### 3. Evidence for the design (current repo and chain)

- `MockV3Aggregator.updateAnswer(int256)` is **ungated** and sets `updatedAt` to `block.timestamp` and increments the round (`contracts/mocks/MockV3Aggregator.sol:29-30, 45-48`); `latestRoundData` returns `startedAt == updatedAt == _latestTimestamp` and `answeredInRound == roundId` (`:42`). `updateRoundData(answer, updatedAt)` is also ungated and lets anyone set any timestamp (`:33-34`). So anyone can set any price today.
- `ChainlinkPriceOracle.getPrice` reverts only for a zero feed or `answer <= 0` and scales to 18 decimals (`contracts/oracle/ChainlinkPriceOracle.sol:24-32`); it returns `updatedAt` and leaves the staleness decision to the vault.
- V1 staleness policy: `MAX_PRICE_STALENESS = 24 hours` (`script/Deploy.s.sol:16`, passed at `:78`). `_checkAllFresh()` (`contracts/StrategyVault.sol:229-238`) is called in `deposit` (`:77`), `redeem` (`:112`) and `executeRebalance` (`:178`). A strategy-token constituent is skipped, only stock constituents are checked.
- Current on-chain state, read via `cast call latestRoundData()` at 2026-10-03T14:31Z: all six feeds have `roundId` 3 and `updatedAt` between 1790857356 and 1790857370 (2026-10-01 12:22 to 12:23 UTC), so about 180,500 s = 50.1 h old. TSLA 260.00, AMZN 183.00, NFLX 581.00, PLTR 26.00, AMD 138.00, USDG 1.00 (these equal the hard-coded prices in `scripts/refresh-feeds.sh:22-29`).
- Reproduced on vault `0x9f6123c775B62a88b7403ca8CaF41B0Ea6B2438B` (AIGR: constituents PLTR 35%, AMD 35%, AMZN 30%; `rebalanceInterval` read on chain as 604800 s; `maxWeightBps` 4000 per `script/SeedStrategies.s.sol:73`, not read on chain): `cast call ... deposit(uint256,address)` and `... redeem(uint256,address,address)` both revert with `StalePrice(0x3B05...d764, 1790857366)`. `executeRebalance` reverts `RebalanceNotNeeded` because that check runs before `_checkAllFresh` (`StrategyVault.sol:176-178`); a due rebalance would hit `StalePrice` too. **Today the V1 app cannot take a deposit or process a redeem** until feeds are refreshed.
- Seed config relevant to the shock demo (`script/SeedStrategies.s.sol:72-89`): EVMO is TSLA 40 / AMD 30 / PLTR 30 with `maxWeightBps` 4000 and a 1 day interval; BLTZ is PLTR 50 / TSLA 50 with `maxWeightBps` 5000 and a 1 h interval. A threshold rebalance triggers when a weight exceeds `maxWeightBps` (`StrategyVault.sol:242-258`, strict `>` at `:251`). In EVMO, TSLA +18% moves its weight from 40.0% to 44.0%, which fires; note that any TSLA outperformance at all fires EVMO (target equals the cap), so under live prices that vault will rebalance often.

### 4. Gas and cost (measured)

- `cast gas-price --rpc-url https://rpc.testnet.chain.robinhood.com` = **10,000,000 wei (0.01 gwei)** at block 128,199,211 (raw `eth_gasPrice` `0x989680`, `eth_maxPriorityFeePerGas` `0x0`). Unchanged from doc 07.
- `cast estimate <feed> 'updateAnswer(int256)' 37143000000 --from 0x...dEaD` against each current V1 feed (TSLA, AMZN, NFLX, PLTR, AMD, USDG): **44,249 gas each**. Re-publishing the unchanged answer (the `hold` case) on TSLA: **41,431 gas**. A zero-value transfer estimates 26,910 gas, so the estimate includes an L1 data component of about 5.9k on top of the 21,000 base.

| Scenario | Gas per round (6 feeds) | ETH per round | per day | per 30 days |
|---|---|---|---|---|
| Push every 30 min, 44,249 gas, 6 feeds | 265,494 | 0.00000265 | 0.000127 (48 rounds) | 0.00382 |
| Push every 15 min | 265,494 | 0.00000265 | 0.000255 | 0.00765 |
| Push every 60 min | 265,494 | 0.00000265 | 0.0000637 | 0.00191 |
| Hold every 30 min (41,431 gas each) | 248,586 | 0.00000249 | 0.000119 | 0.00358 |
| 30 min at 10x the gas price (0.1 gwei) | 265,494 | 0.0000265 | 0.00127 | 0.0382 |

The relayer wallet therefore needs about 0.004 ETH for a month at the baseline; the deployer's 0.0082 ETH (doc 07, not re-measured) is ample. These estimates are for the existing mock; a FengAggregator costs more per call (role check, bound check, event) and less if its state is packed into one slot (not measured; see Assumptions).

### 5. Answers to the "hold mode" question

`MockV3Aggregator.updateAnswer(int256)` **does** update `updatedAt`: it calls `_pushRound(answer, block.timestamp)` (`MockV3Aggregator.sol:29-30`), which increments `_latestRound`, writes the answer and sets `_latestTimestamp = block.timestamp` (`:45-48`), and `latestRoundData` returns that timestamp as both `startedAt` and `updatedAt` (`:42`). Re-publishing the same answer is therefore a valid keep-alive, costs 41,431 gas, and there is no revert for an unchanged value.

## Recommendations

### R-A. Price source and relayer parsing rules (for E2-T1)

1. Fetch `GET https://api.robinhood.com/rhj/prices/{SYMBOL}` per symbol, upper case, at most once per symbol per 15 s (one tick every 5 minutes is far below the limit). Require HTTP 200, a non-empty `quotes[0]` whose `tokenSymbol` equals the request, and parse only `tokenBid`, `tokenAsk`, `isTradingHalt`, `generatedAt`, plus optional `bid`, `ask`, `dailyHigh`, `dailyLow` for sanity. Ignore unknown fields. Treat any missing field as a failed fetch.
2. Parse decimals as strings, never `Number`: split on `.`, pad/truncate to 18 dp into a bigint.
3. **Scaling rule (8 decimals)**: `bid18 = parse18(tokenBid)`, `ask18 = parse18(tokenAsk)`, `mid18 = (bid18 + ask18 + 1) / 2`, `answer8 = (mid18 + 5e9) / 1e10` (round half up). Reject if `bid <= 0`, `ask < bid`, or `answer8 <= 0`.
   - TSLA 371.43 / 371.80: `mid18 = 371.615e18`, `answer8 = 37161500000` (371.615 x 1e8).
   - CRWD (multiplier 4): tokenBid 1079.48, tokenAsk 1080.60, mid 1080.04, `answer8 = 108004000000`; the raw `bid`/`ask` would have given 270.01 and is wrong for a token feed.
   - CCL (non-terminating): tokenBid 25.996830021565003084, tokenAsk 26.711870532963647569, `answer8 = 2635435028`.
   - USDG: constant `100000000` (no API for it); push only as heartbeat.
4. Reject (hold the last answer and report) when: `isTradingHalt` is true; spread `(ask - bid) / mid` is above 500 bps (the five tickers measured 10 to 228 bps on a closed weekend; CRM-like outliers are 1,600 bps and more); mid falls outside `[dailyLow x 0.9, dailyHigh x 1.1] x currentMultiplier` (needs `/assets`, cached 15 min); or `/assets` shows a pending multiplier or `/corporate-actions` shows an in-progress row for the symbol.
5. Do not use `generatedAt` as freshness. Use it only for logging and to detect a clock jump (reject if it is more than 120 s from the relayer clock, a cheap check for a broken CDN or a bad host clock).
6. A move larger than the on-chain bound (see R-B) is allowed only after two fetches at least 16 s apart agree within 50 bps; then step (R-D).
7. Cross-check and attribution: README line "Prices: Robinhood Chain Stock Token API (https://docs.robinhood.com/chain/stock-token-apis/), polled every 5 minutes, used as testnet reference prices". Say "Stock Tokens", not "tokenized stocks".
8. Pyth stays out of the build. If a second source is ever wanted for a sanity check, use it only off-chain and only with a key held in an environment variable.

### R-B. `FengAggregator` (for E3-T1)

Interface and behaviour (sketch, not an implementation):

```solidity
// SKETCH
contract FengAggregator is AggregatorV3Interface, AccessControl {
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    uint8 private immutable _decimals;                    // 8
    string private _description;                          // "TSLA / USD (Feng sandbox)"
    uint16 public maxDeviationBps;                        // default 1000, admin-settable, hard cap 5000
    // one packed slot: uint80 roundId, uint48 updatedAt, int128 answer
    function pushAnswer(int256 answer) external onlyRole(UPDATER_ROLE);   // answer > 0; |answer - last| * 1e4 <= last * maxDeviationBps
    function setMaxDeviationBps(uint16 bps) external onlyRole(DEFAULT_ADMIN_ROLE);  // no timelock in sandbox
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80); // startedAt = updatedAt, answeredInRound = roundId
    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);  // Chainlink-shaped
    event MaxDeviationUpdated(uint16 bps);
}
```

- A same-answer push (deviation 0) is always allowed: it is the heartbeat and the `hold` mode.
- `updatedAt` is `block.timestamp` of the push (as the mock). Do **not** expose `updateRoundData` (the mock's ungated timestamp setter is the worst part of the mock).
- Keep it consumable by the unchanged `ChainlinkPriceOracle` (it reads only `latestRoundData` and `decimals`, `ChainlinkPriceOracle.sol:27-29`). The repo's `AggregatorV3Interface` has no `getRoundData`; leave it out (storing history costs an extra SSTORE per push).
- Role holders: relayer key gets `UPDATER_ROLE`; the deployer or a safer admin holds `DEFAULT_ADMIN_ROLE`. `UPDATER_ROLE` can be revoked if the relayer key leaks; the per-update bound only limits the damage of a bad API value or code bug, not of a stolen key (a stolen key can walk the price in stepped pushes inside one block), so say that plainly in docs/security.
- Optional UI helper view `lastChangeAt()` (timestamp of the last push whose answer differed from the previous). It lets the UI say "market closed, price unchanged since Friday" even while the heartbeat keeps `updatedAt` fresh. The vault must keep using `updatedAt` only.
- Sandbox only. The mainnet path stays `ChainlinkPriceOracle` pointed at Chainlink's real proxies (D7).

### R-C. Cadence, heartbeat, weekend

- Tick every **5 minutes** (any host in R5 that can do it; if only 15 or 30 minute ticks are possible, the rules still hold, the keeper just reacts later).
- Push when the new `answer8` differs from the on-chain answer by at least **10 bps**, or when the on-chain `updatedAt` is at least **30 minutes** old (heartbeat), whichever comes first. Hard floor stays: never let a feed pass 12 h.
- Weekend and closed sessions: no special calendar logic. The API returns the frozen Friday quote, the 10 bps rule produces no price pushes, and the 30 minute heartbeat re-publishes the same answer (about 0.00012 ETH per day for all six). The UI label comes from `lastChangeAt()` or from a client-side "US market closed" calendar, not from the oracle. If the relayer is down at the weekend, nothing changes for users until staleness (R-E) expires.
- Daily cost at this setup: at most 0.00013 ETH for heartbeats, plus price pushes (a few per symbol per hour in market hours); even 20 extra pushes per symbol per day add only 0.0005 ETH.
- Optional cost optimisation (P2): a `FengFeedBatcher` holding `UPDATER_ROLE` on all six aggregators with `batchPush(feeds[], answers[])` to avoid 5 of 6 transaction base costs; the saving is estimated, not measured (Assumptions).

### R-D. Deviation bound and the demo shock

- Per-update bound **1,000 bps (10%)**. Rationale: a single-name overnight gap beyond 10% is rare but does happen (earnings); a relayer that detects a target move above the bound steps toward it with repeated pushes, each at most 90% of the bound, sent back to back (same block is fine, nonces managed by the relayer). Thus legitimate gaps still land within one tick, while a wrong-decimals value (100x), a zero, or a 5x API glitch is rejected on chain.
- **Bounded shock (+18%) for `scripts/demo-shock.sh` (E2-T6)**: two pushes by the relayer key, each `x 1.0863` (1.0863^2 = 1.18; each step is +8.63%, under the 10% bound); for example TSLA 371.615 to 403.68 to 438.51 (8 dp: 37161500000, 40368000000, 43851000000 are approximate; compute from the on-chain answer at run time). Then run the permissionless keeper (the vault's `maxWeightBps` check fires; EVMO moves from 40.0% to 44.0%), then restore with two pushes of about -7.95% each (1/1.0863), or let the market-mode tick restore it (it also steps). Total cost: 2 + 2 pushes x about 44k gas.
- **The relayer must not fight the shock**: while the script runs, the 5 minute tick would walk the answer back to live. The script sets a pause the tick honours (an env var `RELAYER_PAUSED=1` for a worker, or a pause file/flag in the host's key-value store), and clears it after restore. Without that, the on-camera rebalance can lose a race.
- **Backup if a larger or instant shock is needed (demo mode)**: `setMaxDeviationBps(5000)` by the admin key (not the relayer), shock in one push, restore, then `setMaxDeviationBps(1000)`. No timelock in the sandbox; it emits an event so it is visible and auditable. Prefer the stepped path: it demonstrates that the bound exists and needs no privileged call.
- The stepped path is a realistic mimic of how a real feed would deliver a violent move (a chain of rounds), and it keeps `AnswerUpdated` history consistent for the history UI.

### R-E. Vault behaviour when `updatedAt` is old, and `maxPriceStaleness`

- V2 behaviour (matches the plan's 8.1 error list): `deposit`, `depositInKind` valuation and `executeRebalance` revert `StalePrice(token, updatedAt)`; `redeem` to USDG also reverts when a feed is stale (it values at the oracle); **`redeemInKind` never checks any feed**. `previewRedeem`, `previewDeposit`, `sharePrice`, `weights` are views and must not revert on staleness (return the last-priced value) so the UI can render, with a stale badge from the health endpoint. The V1 behaviour is worse: `redeem` is blocked by a stale feed (`StrategyVault.sol:112`) with no in-kind escape, and that is happening on the live site now.
- **Sandbox `maxPriceStaleness` = 6 hours** (set on the new V2 factory; it is immutable per factory, `StrategyFactory.sol:19`). That is 12 heartbeats, long enough to survive a host restart or a missed cron, short enough to mean something; the plan's alert threshold stays 35 min and the hard floor 12 h in the relayer. If the host cannot hold 6 h reliably (R5), lengthen to 12 h rather than going back to 24 h; in V1 even 24 h was exceeded by 26 h.
- **Mainnet Chainlink path (market 24/5)**: do not reuse one global 24 h limit. Chainlink says its Robinhood stock feeds have "no heartbeats during off-hours" and a 0.5% deviation threshold with a 86,400 s heartbeat (`feeds-robinhood-mainnet.json`); a weekend can pass without any update, and a holiday weekend longer. Recommended shape for the mainnet-path doc and any future factory: per-feed `maxStaleness` stored in `ChainlinkPriceOracle` (not the vault), about 4 days (96 h) for stock tokens to cover Friday night to Monday plus a holiday, 26 h for USDG (heartbeat 24 h plus margin), plus (a) the L2 Sequencer Uptime Feed check with a grace period (Robinhood docs "Checking sequencer uptime"), (b) `oraclePaused()` on the token, (c) a per-update sanity check against the last observed price in the vault for deposits. These numbers are a proposal derived from the heartbeat and session facts above, not tested on mainnet (R8 owns the final values).

### R-F. V1 `hold` mode behaviour (for E2-T1, one paragraph)

In `hold` mode the relayer never calls the price API. Each tick it reads `latestRoundData()` from every V1 feed, and if `block.timestamp - updatedAt` is at least 30 minutes (and always before 12 h), it calls `updateAnswer(answer)` with the **same** `answer` it just read. `MockV3Aggregator.updateAnswer` writes `updatedAt = block.timestamp` and bumps the round (`MockV3Aggregator.sol:29-30, 45-48`), so the staleness clock restarts; the call costs 41,431 gas per feed (measured) and never reverts for an unchanged value. Because the answers never change, `hold` produces no threshold rebalances and keeps the seed prices (TSLA 260 and so on, versus real 371) which must be labelled as such on the site. Read the answer from chain rather than from `scripts/refresh-feeds.sh:22-29`, so that a later `market` run is not rolled back to the seed constants. Because the V1 `updateAnswer` is open to anyone, a hold relayer can use any funded key. For FengAggregator the same behaviour is `pushAnswer(lastAnswer)`.

### Recommendation

1. **Immediately (E0/E2, before anything else)**: refresh the six V1 feeds (the existing `scripts/refresh-feeds.sh` does it with the same seed values, one funded key, no code change) and keep them fresh at least every 6 h until the relayer ships; the live V1 deposit and redeem are broken now (50.1 h old, 24 h limit).
2. Use `https://api.robinhood.com/rhj/prices/{SYMBOL}` per symbol as the single sandbox price source; take `tokenBid`/`tokenAsk` (never `bid`/`ask`); `answer8 = round((tokenBid + tokenAsk) / 2 x 1e8)` using integer math; ignore `generatedAt` for freshness; skip on `isTradingHalt`, spread above 500 bps, band violations, or a pending corporate action.
3. Build `FengAggregator` with `UPDATER_ROLE`, per-update `maxDeviationBps` 1,000 (admin-settable, hard cap 5,000), same-answer heartbeat allowed, no `updateRoundData`, `AnswerUpdated` event, optional `lastChangeAt()`.
4. Relayer: tick every 5 min; push at 10 bps move or 30 min age; weekend needs no special case; step moves larger than 90% of the bound; `hold` mode re-publishes the on-chain answer.
5. `demo-shock.sh`: two stepped relayer pushes of +8.63% (about +18% total), pause the relayer tick during the demo, run the keeper, restore; keep admin `setMaxDeviationBps` as a documented fallback.
6. Sandbox `maxPriceStaleness` 6 h on the V2 factory; `redeemInKind` oracle-free; views never revert on staleness. Mainnet path: per-feed staleness near 96 h for stock tokens, 26 h for USDG, plus sequencer-uptime and `oraclePaused` checks.
7. Budget 0.005 ETH for a dedicated `RELAYER_PRIVATE_KEY` wallet (about 0.0038 ETH per 30 days at the baseline); alert at 0.001 ETH.
8. Do not integrate Pyth or Data Streams; do not wait for a Chainlink testnet feed.

## Implications per role

- **Contracts (E3-T1, E3-T3, E3-T4)**: implement `FengAggregator` per R-B (roles, bound, packed slot, no `updateRoundData`); make `maxPriceStaleness` a V2-factory constructor value of 6 h for the sandbox; keep `redeem(USDG)` staleness-checked, `redeemInKind` never checked; make preview and `sharePrice` views stale-tolerant; keep `ChainlinkPriceOracle` unchanged. Add a test for the deviation bound (accept 10%, reject 10.01%, accept same-answer heartbeat, reject zero and negative) and for stale-feed paths. The seed config note: EVMO (target equals cap) will rebalance on any outperformance under live prices; consider a cap above target in the V2 seed so the keeper does not churn.
- **Ops (E2-T1, E2-T3, E2-T6, E2-T8)**: parse per R-A; run on a host outside the user's network (the local resolver returns a wrong host for `api.robinhood.com`); retry with backoff and rotate IPs on TLS failures; `hold` and `market` modes per R-F and R-C; `RELAYER_PAUSED` flag for the demo; health endpoint should expose per-feed `ageSec` plus `lastChangeAt` (market-closed hint) and the relayer balance; alert on balance below 0.001 ETH or any feed age above 35 min.
- **Frontend (E6, E9)**: a "price age" badge from `/api/ops/health`; a "US market closed, prices frozen at Friday close" label from a client calendar (the oracle's `updatedAt` will look fresh because of the heartbeat); label sandbox prices as reference prices from Robinhood's Stock Token API; use "Stock Tokens" wording. Do not read `bid`/`ask` from the REST API in the browser for display, call the chain (or the health endpoint).
- **Tests/Security (E8)**: invariants: answer always within bound of the previous answer; only `UPDATER_ROLE` can push; `redeemInKind` succeeds with stale feeds; relayer parsing unit tests with the exact JSON above (including the CRWD multiplier 4 case and a 19,818 bps spread outlier). Document that the relayer key can steer sandbox prices inside the bound, and that a stolen key can step prices; revoke path is `revokeRole`.
- **Submission (E11)**: say plainly that sandbox prices are real Robinhood Stock Token quotes relayed by a bounded, role-gated updater, that the testnet has no Chainlink feed, and that the mainnet path uses Chainlink proxies via `ChainlinkPriceOracle` with per-feed staleness (R8). Include the data-source link and the Brand Guidelines wording.
- **R1/R8 researchers**: R1 maps mainnet-address-keyed API data to testnet faucet addresses by symbol. R8 should confirm NFLX's mainnet feed (absent in my name filter), decimals/heartbeats and the sequencer uptime feed.
- **Coordinator**: the V1 outage (item 1 of the Recommendation) is the most urgent action found by this track.

## Assumptions and open questions

Assumptions (stated without a measured source):

1. **Weekday and overnight behaviour is from docs, not sampled.** "Stock feeds update 24/5, following market hours" (`https://docs.robinhood.com/chain/oracles-and-price-feeds/`) and the Chainlink statement about off-hours are used for the mainnet-path staleness proposal; I only sampled a Saturday.
2. The 10% bound, 500 bps spread guard, 5 minute tick, 30 minute heartbeat, 6 h sandbox staleness, and the 96 h mainnet figure are design choices from the evidence above, not values taken from a source. The 96 h figure assumes a Friday-evening-to-Monday-open gap of about 60 h plus a one-day holiday and a margin.
3. A packed-slot `FengAggregator` push should cost less than the mock's 44k gas, and role and bound checks add some; I did not compile or estimate it (the repo is read-only for this task). A batcher is estimated to save about 5 x 27k gas (the transaction base of 21k plus about 5.9k L1 data component per saved transaction); not measured.
4. The deployer balance of 0.0082 ETH comes from doc 07 and was not re-read (reading it needs the deployer address, which is not in `deployments/robinhood-testnet/addresses.json`).
5. The statement that `dailyHigh`/`dailyLow` are raw underlying values is based on CRWD (4.0x) and CCL; the band check should be applied with the multiplier and tested on weekdays.
6. The five testnet faucet tokens are mapped to the API by ticker; the API only returns mainnet addresses.
7. I treat a web-search summary that "Data Streams is available for the Robinhood Chain testnet" as unconfirmed; the primary pages show mainnet only.
8. The local resolver issue (wrong host for `api.robinhood.com`, certificate mismatches and an expired certificate on the RPC) are interception artefacts of the user's ISP, consistent with the preamble; they are not API faults.

Open questions:

1. Does Robinhood intend the `/rhj/` endpoints for third-party testnet apps? The docs say "for offchain access to Stock Token data" and nothing about usage terms; a short email or Discord question to the Robinhood Chain team would settle attribution.
2. Is `isTradingHalt` raised for a single-name halt only, or also for market-wide pauses? What do `bid`/`ask` contain during a halt (last, zero, empty)?
3. Is there any gated Chainlink testnet feed or Data Streams testnet verifier for Robinhood Chain (ask the Chainlink or Robinhood developer channels)?

### Still unknown

- Actual `/rhj/prices` behaviour on a weekday, in the overnight session, at the Sunday 8 pm ET reopen, on a Monday gap, during a real trading halt, and during a corporate-action pause (only a Saturday was sampled).
- Whether the undocumented fields `tokenBid`, `tokenAsk`, `dailyHigh`, `dailyLow`, `mintBurn*` are a stable part of the contract or may disappear (the docs page does not list them).
- The real rate-limit response (status code and body at 60 req/s); not load-tested on purpose.
- Whether any official Robinhood or Chainlink channel has a testnet Chainlink feed or Data Streams verifier (not asked; no reachable channel).
- The exact gas cost of a packed-slot `FengAggregator.pushAnswer` and of a batcher (needs a compiled prototype).
- Whether the vault's seed strategies should be reconfigured so that targets are below caps (EVMO, BLTZ, others) to avoid keeper churn at live prices.
- Mainnet feed behaviour at weekends and holidays (is `updatedAt` really untouched; R8).
- Pyth's Hermes key pricing and whether the free trial would be enough for an optional cross-check (not pursued).

## Sources

All read or measured on 2026-10-03 unless stated.

- Robinhood Stock Token APIs: https://docs.robinhood.com/chain/stock-token-apis/ (fetched with `curl --resolve`)
- Robinhood Stock Tokens (trading hours, tokenization window, multiplier): https://docs.robinhood.com/chain/stock-tokens/
- Robinhood Building with Stock Tokens (uiMultiplier, ERC-8056): https://docs.robinhood.com/chain/building-with-stock-tokens
- Robinhood Oracles & Price Feeds (24/5, oracle pauses, sequencer uptime): https://docs.robinhood.com/chain/oracles-and-price-feeds/
- Robinhood Data Streams (mainnet verifier only): https://docs.robinhood.com/chain/data-streams
- Robinhood Chain Terms of Service (Last Updated August 24, 2026): https://docs.robinhood.com/chain/terms-of-service
- Robinhood Chain Brand Guidelines (v1.0, 2026-08-20): https://docs.robinhood.com/chain/brand-guidelines
- Robinhood live API responses: https://api.robinhood.com/rhj/prices/{TSLA,AMZN,NFLX,PLTR,AMD,CRWD,CCL,SPY,AAPL,NVDA}, https://api.robinhood.com/rhj/prices, https://api.robinhood.com/rhj/assets, https://api.robinhood.com/rhj/corporate-actions
- DoH (IPs for the `--resolve` calls): https://1.1.1.1/dns-query?name=api.robinhood.com&type=A
- Chainlink feed directory: https://reference-data-directory.vercel.app/feeds-robinhood-testnet.json (404), https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json (200)
- Chainlink tokenized equity feeds, Robinhood: https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood
- Chainlink Data Streams stream list: https://docs.chain.link/data-streams/crypto-streams
- Pyth EVM contract addresses: https://docs.pyth.network/price-feeds/core/contract-addresses/evm
- Pyth Hermes API key requirement: https://docs.pyth.network/price-feeds/core/upgrade/preparing
- Pyth Hermes feed listing and market hours: https://hermes.pyth.network/v2/price_feeds?query=TSLA&asset_type=equity
- Robinhood Chain testnet explorer (address `0x2880aB...B43` = `ReceiverSetup`): https://explorer.testnet.chain.robinhood.com/api/v2/addresses/0x2880aB155794e7179c9eE2e38200202908C17B43
- RPC (cast calls): https://rpc.testnet.chain.robinhood.com (`cast gas-price`, `cast estimate`, `cast call latestRoundData`, `cast call deposit/redeem`, block 128,199,211)
- Repo: `contracts/mocks/MockV3Aggregator.sol:8-10,29-34,42,45-48`; `contracts/oracle/ChainlinkPriceOracle.sol:24-32`; `contracts/StrategyVault.sol:74-77,105-112,175-178,229-238`; `contracts/StrategyFactory.sol:19,32-37`; `script/Deploy.s.sol:16,36,64-78`; `script/SeedStrategies.s.sol:72-89`; `scripts/refresh-feeds.sh:16,22-29,34`; `deployments/robinhood-testnet/addresses.json`; `docs/research/07-testnet-reality-check.md` sections 2.3 and 2.4; `docs/brainstorm/2026-10-03-feng-v2-plan.md` sections 0, 4 (D7), 6 (E1, E2-T1, E2-T6, E3-T1), 7 (R2), 8.1.
