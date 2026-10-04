# 15. Mainnet path: Chainlink feeds, sequencer guard, 24/5 staleness, mainnet addresses, audit focus (R8)

Read and measured on **2026-10-03, about 14:40 to 15:00 UTC** (Saturday) from the user's machine. Track R8 of `docs/brainstorm/2026-10-03-feng-v2-plan.md`; feeds `README.md` (mainnet path section) and `docs/submission/judge-faq.md`. Methods: Chainlink's reference data directory JSON, Chainlink docs (HTML), Robinhood docs reached with `curl --resolve` and the DoH IP (13.35.238.76), Robinhood's public REST API (DoH IP 13.35.163.34), and read-only `cast call` / `eth_getCode` against the public mainnet RPC `https://rpc.mainnet.chain.robinhood.com` (retried until the intermittent TLS interception let it through). No transaction was sent, no key was used, no `.env*` file was read.

## Summary

1. **Mainnet price feeds exist for four of our five tickers plus USDG; NFLX is not in the directory.** Chainlink's `feeds-robinhood-mainnet.json` lists 58 feeds on chain 4663: Robinhood TSLA, AMZN, PLTR and AMD (all `8` decimals, `86400` s heartbeat, `0.5` percent deviation, `us_equities_24/5`) and `USDG / USD` (8 decimals, 86400 s, 0.5 percent, 24/7 "Crypto" hours). There is no NFLX entry. The testnet file (`feeds-robinhood-testnet.json`) is still a 404, so no Chainlink feed exists on testnet.
2. **No L2 Sequencer Uptime Feed is listed for Robinhood Chain.** Robinhood's oracle page recommends one, but neither Robinhood nor Chainlink publishes an address for chain 4663, Chainlink's sequencer page lists 11 networks without it, and it says "Chainlink is no longer expanding L2 Sequencer Uptime Feeds to additional networks". The Arbitrum One sequencer feed address has no code on Robinhood mainnet. Feng needs a guard that does not depend on that feed.
3. **The 24 hour heartbeat is the real constraint, not a weekend rule on its own.** The feeds are deviation plus heartbeat feeds and "do not have heartbeats during off-hours". Live proof from today: TSLA's feed was last updated Fri 2026-10-02 19:55 UTC, 19.0 hours before the read; AMD's 20.0 hours; USDG's 23.2 hours. Feng V1 uses a 24 hour limit and the V2 spec a 12 hour limit; both would reject real Chainlink prices after any quiet day, and every weekend. A mainnet adapter must treat staleness as `heartbeat + margin` in session and market-calendar aware when the market is closed (a market closed from Friday 20:00 ET to Sunday 20:00 ET is 48 hours before any holiday).
4. **Mainnet USDG and Stock Token addresses are published and checked on chain.** USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` (Robinhood's Token Contracts page; on chain: name "Global Dollar", symbol USDG, 6 decimals). The five Stock Tokens come from `GET https://api.robinhood.com/rhj/assets` (all chain 4663): TSLA `0x322F0929c4625eD5bAd873c95208D54E1c003b2d`, AMZN `0x12f190a9F9d7D37a250758b26824B97CE941bF54`, NFLX `0xE0444EF8BF4eD74f74FD73686e2ddF4C1c5591E8`, PLTR `0x894E1EC2D74FFE5AEF8Dc8A9e84686acCB964F2A`, AMD `0x86923f96303D656E4aa86D9d42D1e57ad2023fdC`. Robinhood's own docs page says the live token table is generated from the on-chain asset registry and that a token "with a matching name/ticker but a different contract address is not a Robinhood Stock Token".
5. **Real Stock Tokens change the vault design, not just the config.** Only Authorized Participants can mint and burn them (KYB onboarding), so a vault must hold them and trade through a venue (RFQ aggregators, Uniswap AMM pools, propAMMs such as Rialto) or accept them in kind. They carry a corporate-action multiplier (`uiMultiplier()`, ERC-8056) and an advisory `oraclePaused()` flag, and their transfers can be paused or blocked by the issuer.
6. **An audit of this design should focus on seven areas** (F6): oracle and staleness policy, execution and MEV on a permissionless rebalance, share math and decimals, nested valuation, token behaviour (pausable and blockable assets), access control and upgradeability of the dependencies, and exit liveness.

## Findings

### F1. Chainlink mainnet feed proxies for the five tickers and USDG

Source: `https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json`, HTTP 200, 84,653 bytes, 58 entries, fetched 2026-10-03 at about 14:40Z. Every entry has `contractVersion 6`, `multiply 100000000`, `maxSubmissionValue 95780971304118053647396689196894323976171195136475135` and the path suffix `-shared-svr`. For each entry the JSON carries `proxyAddress` (the address Robinhood's docs tell integrators to read), `contractAddress` (the underlying aggregator) and `secondaryProxyAddress` (see the SVR note below).

| Ticker | Feed name | `proxyAddress` (read this) | `contractAddress` (aggregator) | `secondaryProxyAddress` | Decimals | Heartbeat | Deviation | Market hours |
|---|---|---|---|---|---|---|---|---|
| TSLA | Robinhood TSLA / USD | `0x4A1166a659A55625345e9515b32adECea5547C38` | `0x7A6b81ba7FbCB90104d8C496158Cf383cD7233b1` | `0xE4479F01738B4e8C428CD8eB72D47AB9BC3c7de6` | 8 | 86400 s | 0.5 % | `us_equities_24/5` |
| AMZN | Robinhood AMZN / USD | `0xD5a1508ceD74c084eBf3cBe853e2C968fB2a651C` | `0x93503dFc97157cdB8aADcCaf70452621d598FDeb` | `0x9244830430bC7D9C9A48dd47603F24AD61f7c56e` | 8 | 86400 s | 0.5 % | `us_equities_24/5` |
| PLTR | Robinhood PLTR / USD | `0x820ABedFF239034956B7A9d2F0a331f9F075eB4c` | `0x315afd0f71D5407B99ad19ab001a67af40fbAAF4` | `0x8cd1DFC0fc61fcA55FA77b37e008A90f13364Fce` | 8 | 86400 s | 0.5 % | `us_equities_24/5` |
| AMD | Robinhood AMD / USD | `0x943A29E7ae51A4798823ca9eEd2ed533B2A22C72` | `0xdAD54b8Ee51Af258e5A6Faa9a84a3300f4775f7d` | `0xF6d57763DFa625F4A413485261Ab2E71Ff4304CF` | 8 | 86400 s | 0.5 % | `us_equities_24/5` |
| NFLX | not listed | none | none | none | n/a | n/a | n/a | n/a |
| USDG | USDG / USD | `0x61B7e5650328764B076A108EFF5fa7282a1B9aD2` | `0x8bEeE3503F6860D5dac4cE26b5eEe92982951c2e` | `0x901f56689360B89D7767a8acE28B7801e6348fa2` | 8 | 86400 s | 0.5 % | Crypto (24/7) |

Checks on chain (`cast call` on `https://rpc.mainnet.chain.robinhood.com`, chain ID 4663, head block 79,166,201 at 14:48Z):

| Proxy | `description()` | `decimals()` | `latestRoundData()` answer | `updatedAt` (UTC) | Age at 14:53:18Z |
|---|---|---|---|---|---|
| TSLA | `RHTSLA / USD` | 8 | 37044800000 (370.448) | Fri 2026-10-02 19:55:31 | 19.0 h |
| AMZN | `Robinhood AMZN / USD` | 8 | 25164999999 (251.65) | Fri 19:51:17 | 19.0 h |
| PLTR | `Robinhood PLTR / USD` | 8 | 18854600000 (188.546) | Fri 19:50:57 | 19.0 h |
| AMD | `RHAMD / USD` | 8 | 63282895000 (632.829) | Fri 18:51:35 | 20.0 h |
| USDG | not read | not read | 100005000 (1.00005) | Fri 15:39:34 | 23.2 h |
| TSLA `secondaryProxyAddress` | `RHTSLA / USD` | not read | 37044800000 | Fri 19:55:31 | same round data, a different `roundId` |

Notes:
- Per-ticker parameters in the directory are identical for the four stocks; "per-token" differences come from the asset, not the feed (see F3).
- The `description()` strings are not uniform (`RHTSLA / USD`, `RHAMD / USD`, `Robinhood AMZN / USD`), so never match feeds by description; map by proxy address in config.
- The two proxies per feed return the same price with different round ids. The directory labels the family "Shared SVR" (`svrDisplayLabel`), and Robinhood's Chainlink page says "Robinhood feeds have SVR enabled". Chainlink says SVR feeds "are read in the same manner as standard Chainlink Data Feeds ... and simply require that users specify an SVR-enabled feed address", and that SVR recaptures oracle extractable value for the protocol and Chainlink. **Which of the two proxies is the SVR-enabled one is not labelled in the JSON.** Robinhood's docs name the `proxyAddress`; Feng should use that one and ask Chainlink before using the secondary.
- The directory entries describe the tokens as "Tesla (Robinhood Tokenized Equity)" with `docs.productSubType: calculatedPrice`. The feed price is the per-token total-return value: underlying price times `uiMultiplier()`. Feng must not multiply again.
- NFLX: zero matches for `NFLX` or `Netflix` in the Robinhood mainnet JSON. Chainlink's Data Streams catalog has an `NFLX/USD` equity stream (name `NFLX/USD-Streams-EquityPrice-Timestamped-mainnet-production`), which is a different product and not a push feed on this chain. So a mainnet Feng with NFLX needs either a Data Streams integration (a verifier proxy, listed for mainnet only on Robinhood's Data Streams page), a feed Chainlink has not yet published, or NFLX left out.
- Testnet: `https://reference-data-directory.vercel.app/feeds-robinhood-testnet.json` returned HTTP 404 again (about 14:45Z). Chainlink has no Robinhood testnet feeds.

### F2. L2 sequencer uptime feed

- Robinhood, `https://docs.robinhood.com/chain/oracles-and-price-feeds/` ("Checking sequencer uptime (recommended on L2)"): "verify the sequencer is up before trusting a price ... Chainlink provides an L2 Sequencer Uptime Feed for this", with the standard snippet (`sequencerStatus == 0` means up; `block.timestamp - startedAt > GRACE_PERIOD`). **No address is given.**
- Chainlink, `https://docs.chain.link/data-feeds/l2-sequencer-feeds` (read 2026-10-03): "Chainlink is no longer expanding L2 Sequencer Uptime Feeds to additional networks." Listed networks: Arbitrum One `0xFdB631F5EE196F0ed6FAa767959853A9F217697D`, Base `0xBCF85224fc0756B9Fa45aA7892530B47e10b6433`, Celo, Mantle, MegaETH, Metis, OP, Scroll, Soneium, X Layer, ZKsync. **Robinhood Chain is not in the list**, and no feed with "sequencer" in its name is in the Robinhood mainnet JSON.
- On chain: `eth_getCode` of the Arbitrum One sequencer feed address on chain 4663 returned `0x` (no contract), so the Arbitrum One feed cannot be reused.
- Consequence: for Feng, "check the sequencer feed" is unavailable today. Outage handling must rely on (a) the `updatedAt` staleness check (feeds stop updating when the sequencer is down), (b) a grace period after the first fresh update following an outage, and (c) a guardian pause for deposits and rebalances with exits never paused (the V2 spec already has this guardian, `docs/handoffs/04-contracts-v2.md` S9). If Chainlink later publishes a feed for chain 4663, the adapter should accept an optional `sequencerFeed` address that is `address(0)` today.

### F3. Per-token staleness for a 24/5 market

Facts:
- Chainlink on Robinhood feeds: "Stock feeds update 24/5, following market hours" (Robinhood oracle page); "Robinhood tokenized equity feeds are configured as 24/5 ... Off-hours / closed sessions: When underlying equity markets are closed (weekends, holidays, thin overnight windows), the feed may hold the last published price ... These feeds do not have heartbeats during off-hours. Staleness checks: Integrators should read `updatedAt` and implement staleness bounds appropriate to their use case." (`https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood`).
- Heartbeat 86400 s and deviation 0.5 percent for all four stock feeds (F1). A feed therefore updates when the price moves by 0.5 percent or when 24 hours pass, and only while the market is open.
- Measured today (Saturday): the four stock feeds are 19 to 20 hours old, all with last updates between 18:51 and 19:55 UTC on Friday, i.e. inside Friday's extended session; USDG's feed is 23.2 hours old. A 12 hour limit would revert on all of them; a 24 hour limit reverts on USDG within an hour, and on the stocks around 19:50 UTC on Saturday, so a flat 24 hour limit would freeze every Feng vault each weekend.
- All five tickers report `tradingCapabilities` `TRADABLE` for market, extended and overnight sessions (`GET /rhj/assets`, 194 of 194 assets are tradable overnight), so the five behave alike; any ticker added later must be checked per asset.
- Robinhood's tokenization window (market makers mint and burn) is Monday 02:00 CET/CEST to Saturday 02:00 CET/CEST (Stock Tokens overview); end users can trade outside it.
- Corporate actions pause the oracle: "feeds are expected to stop publishing fresh prices while the token's terms or multiplier are being updated" and `oraclePaused()` on the token exposes it, but "the flag is advisory and not enforced on-chain, so a paused oracle may still return a value".

Design implications (a proposal, not a Robinhood or Chainlink statement):

| Case | Rule |
|---|---|
| Market open (Sun 20:00 ET to Fri 20:00 ET, minus holidays) | `now - updatedAt <= heartbeat + 1 h` (25 h) for deposit, rebalance and USDG redeem. |
| Market closed (weekend, holiday) | Accept `updatedAt >= lastCloseTime - heartbeat`, where the close time comes from a market-calendar value set by a guardian and bounded (maximum 4 days), or fall back to a flat 96 hour limit for NAV display only. Deposits and rebalances stay disabled while closed unless the venue quote is checked against the stale oracle with a tight band. |
| Corporate action | Treat `oraclePaused() == true` or a pending `newUIMultiplier()` as "no deposit, no rebalance"; in-kind redeem stays open. |
| Strategy tokens | Child vaults inherit their parents' worst constituent age (the V2 spec's `priceStatus()` recursion). |
| USDG | Do not read the USDG feed for NAV (the V2 spec already assumes 1.00 USD, C-22). If a depeg guard is wanted, use the 0.5 percent deviation band and the 24 hour heartbeat. |

Sandbox values (30 minute relayer heartbeat, 12 hour limit, `docs/research/09-price-source-and-feed.md`) must not be copied to mainnet.

### F4. Mainnet addresses from Robinhood's registry and docs

- **USDG**: `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`, and **WETH** `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` ("The following contracts are deployed on Robinhood Chain", `https://docs.robinhood.com/chain/contracts/`, read 2026-10-03; the page does not split mainnet and testnet). On chain (mainnet RPC, about 14:50Z): `name() = "Global Dollar"`, `symbol() = "USDG"`, `decimals() = 6`. The testnet USDG is a different contract (`0x7E955252E15c84f5768B83c41a71F9eba181802F`, Paxos docs).
- **Stock Tokens** (`GET https://api.robinhood.com/rhj/assets`, HTTP 200, 194 assets, every `deployments[].chainId` is 4663, fetched 2026-10-03 via `--resolve api.robinhood.com:443:13.35.163.34`):

| Ticker | Mainnet token (chain 4663) | `currentMultiplier` | Status |
|---|---|---|---|
| TSLA | `0x322F0929c4625eD5bAd873c95208D54E1c003b2d` | 1.000000000000000000 | `ASSET_STATUS_ACTIVE` |
| AMZN | `0x12f190a9F9d7D37a250758b26824B97CE941bF54` | 1.000000000000000000 | active |
| NFLX | `0xE0444EF8BF4eD74f74FD73686e2ddF4C1c5591E8` | 1.000000000000000000 | active |
| PLTR | `0x894E1EC2D74FFE5AEF8Dc8A9e84686acCB964F2A` | 1.000000000000000000 | active |
| AMD | `0x86923f96303D656E4aa86D9d42D1e57ad2023fdC` | 1.000000000000000000 | active |

  On chain: TSLA `0x322F...3b2d` reports `symbol "TSLA"`, `decimals 18`, `uiMultiplier 1e18`, `oraclePaused false`, `paused false`; NFLX `0xE044...91E8` reports `symbol "NFLX"` and `uiMultiplier 1e18`. These are not the testnet faucet tokens (07 section 2.1: testnet TSLA is `0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E`) and not Feng's mocks.
- **Chain facts** (`https://docs.robinhood.com/chain/connecting/`): mainnet chain ID 4663, public RPC `https://rpc.mainnet.chain.robinhood.com` (rate-limited, "not recommended for production"), explorer `robinhoodchain.blockscout.com`; Alchemy is the recommended provider.
- **Protocol contracts** (`/chain/protocol-contracts/`): L2 Multicall (mainnet) `0x2cAC2D899eCC914d704FeaAE33ac1bF36277DaD1`, Permit2 `0x000000000022D473030F116dDEE9F6B43aC78BA3`. The canonical Multicall3 `0xcA11bde05977b3631167028862bE2a173976CA11` should be checked on mainnet before the frontend config is reused.
- **Nature of the asset** (`/chain/stock-tokens/`): Stock Tokens are "tokenised debt securities issued by Robinhood Assets (Jersey) Limited", give "economic exposure" without legal or beneficial rights in the underlying, and may be subscribed directly only by Authorised Participants after KYB onboarding, "so developers build by composing with existing tokens rather than minting". Robinhood's brand guidelines (cited in `docs/research/09-price-source-and-feed.md`) ask for the term "Stock Tokens" and for "Robinhood Chain" in full.
- **Venues** (`/chain/building-with-stock-tokens/`): RFQ through aggregators (0x RFQ, 1inch Fusion, LiFi), AMM pools such as Uniswap, propAMM such as Rialto, and the Lighter order book. "Tokenized stocks trade via RFQ at launch."

### F5. Mainnet readiness gaps in Feng today

| Component | Mainnet gap | Source of the gap |
|---|---|---|
| `ChainlinkPriceOracle` | Reads `latestRoundData()` and `decimals()` and rejects `answer <= 0`; does not check `answeredInRound`, does not know heartbeats, a sequencer, `oraclePaused()` or `uiMultiplier()`. Per-token staleness lives only in the vault as one immutable. | `contracts/oracle/ChainlinkPriceOracle.sol`, `contracts/StrategyVault.sol` |
| Vault custody | Mints and burns constituents; real Stock Tokens cannot be minted by us. | `StrategyVault.deposit`, `StrategyFactory` (`grantRole(MINTER_ROLE)`) |
| USDG decimals | V1 assumes 18, mainnet USDG is 6. | `StrategyVault.sol:96`, 07 section 2.2 |
| NFLX | No Chainlink feed in the directory. | F1 |
| Sequencer guard | No feed exists for chain 4663. | F2 |
| Staleness policy | One flat limit for all tokens; wrong for 24/5 and for a 24 h heartbeat. | F3 |
| Venue | None in V1. V2's `OracleDesk` is a mock market maker. | `docs/handoffs/04-contracts-v2.md` |
| Keeper and relayer | The relayer is not needed on mainnet (Chainlink publishes); the keeper stays permissionless but needs MEV-aware execution. | F6 |

### F6. What an audit would focus on for this design

Ordered by the loss they could cause. Evidence is the repo's own findings table (`docs/handoffs/04-contracts-v2.md`, section 1.1, ids C-xx) and the Robinhood and Paxos facts above.

1. **Oracle and staleness policy.** Heartbeat versus deviation versus market hours (F3), `answeredInRound`, a zero or paused oracle, multiplier changes between the oracle read and the token balance read, the missing sequencer feed (F2), USDG treated as exactly 1.00 USD (C-22). A stale or wrong price is the cheapest way to mint shares at a wrong NAV (C-09: parents ignored child feed staleness in V1).
2. **Execution and MEV on a permissionless rebalance.** Anyone can trigger `performRebalance`, so with a real AMM or RFQ venue an attacker can choose the moment and sandwich the vault's legs. Per-leg bounds against the oracle (`maxSlippageBps`), the dust loop around thresholds (C-15), the order of sells before buys (C-17), a donation to force a rebalance (C-28), and a desk or venue that can be drained against a lagging oracle (C-32).
3. **Share math and decimals.** Virtual-share inflation protection at 6 and 18 decimals (C-04, C-05, C-30), rounding direction, minting on the measured value delta rather than the nominal amount (C-29, fee-on-transfer), and the donation property that raw USDG donations never profit the donor.
4. **Nested valuation and recursion.** Depth cap 2 and the leaf rule (`StrategyFactory`), gas of the recursive NAV, child NAV moving during a nested deposit (C-36), nested USDG redeem unwinding the child and reverting if it cannot (C-18), approval hygiene on child vaults (C-23).
5. **Token behaviour.** Stock Tokens are `onlyNotPaused` and `onlyNotBlocked` by registry (07 section 2.1) and USDG is a Paxos token with pause and blocklist; one frozen constituent must not trap the whole vault (C-11, `redeemInKind` with a skip mask), and the vault must tolerate a pausable or blockable USDG. `uiMultiplier()` changes and ERC-8056 semantics for balances.
6. **Access control and upgradeability of dependencies.** Guardian powers (pause deposits, rebalances; never exits), who can register strategies, delegated redeem allowance (C-02, fixed only in V2), `FACTORY_ROLE` on the registry, any owner-settable oracle or venue, the beacon-proxy upgradeability of the Stock Token (Robinhood can upgrade its implementation; 07 section 2.1), and Paxos' USDG proxy.
7. **Liveness and denial of service.** Unbounded loops in `checkUpkeep` (C-19), registry spam (C-35), a reverting constituent blinding the keeper, gas ceilings for six constituents at depth 2, exits that depend on an oracle or a venue (they must not).

Process items: an invariant suite for I1 to I11 (plan section 8.5), fork tests against mainnet Stock Tokens and USDG, a documented threat model, and a legal and compliance review of offering a pooled product over tokens issued as debt securities with restricted primary-market access (F4).

## Recommendations

1. For the README and the judge FAQ say exactly: Chainlink feeds exist on Robinhood Chain mainnet for TSLA, AMZN, PLTR, AMD and USDG, and not for NFLX; Feng's `ChainlinkPriceOracle` already reads `AggregatorV3Interface`; a mainnet deployment needs a per-asset staleness and market-hours policy, a sequencer-independent guard, a venue adapter, and an audit. Do not claim a mainnet deployment or a mainnet-ready oracle.
2. For the V2 contracts, keep the Sandbox 12 hour limit configurable per deployment and document that it must not be used on mainnet; make the staleness limit part of the oracle adapter (per feed `maxAge`, `marketHoursAware`) rather than a vault immutable if time allows, otherwise only document it.
3. Add the optional `sequencerFeed` (zero today) and a guardian pause to the mainnet roadmap; ask Chainlink (`chainlink_data_feeds@smartcontract.com` is the contact on their tokenized-equity page) whether an uptime feed or an alternative is planned for chain 4663 and for the NFLX feed.
4. Choose the mainnet venue after measuring depth: RFQ is off-chain and cannot be called from a vault; Uniswap AMM pools and propAMMs can. Re-run R3 on mainnet pools.
5. Do the audit scope in F6 before any mainnet value; start with items 1, 2 and 5.

## Implications per role

- **Contracts (lane A):** V2 stays testnet. Do not add mainnet-specific code before G2. If time remains, make `maxPriceStaleness` per feed, and add an `oraclePaused()` read as an optional guard only if a real Stock Token is wired in the Live universe; whether the testnet faucet tokens expose it has not been checked.
- **Frontend (lane C):** Nothing mainnet-specific. Keep the network switch limited to testnet and Arbitrum Sepolia; the copy should say "Stock Tokens" and "Robinhood Chain" in full.
- **Ops (lane B):** The relayer is a testnet substitute; on mainnet the job reduces to keeper plus health. Health should report feed age against the real heartbeat, not the Sandbox one.
- **Docs and submission (lane E):** Use F1, F2, F3 and F4 for the README mainnet section and the judge FAQ; every number there is cited above.
- **User:** If asked "what happens on mainnet", answer from F1 to F4 and name the audit; do not promise a date.

## Assumptions and open questions

Assumptions:
- The Chainlink directory JSON is current (`fetched 2026-10-03`); Chainlink may add NFLX or a sequencer feed later. The JSON does not label which of the two proxies per feed is the SVR variant.
- The mainnet token addresses in the Robinhood assets API are canonical (the Robinhood docs say the on-chain registry is the source and that the API documents `/rhj/assets`; the docs' own live table could not be read because it is rendered client-side).
- "24/5" means the equity market sessions Sunday 20:00 ET to Friday 20:00 ET (my reading of 24/5 and of Chainlink's "regular, pre-market, post-market, and overnight sessions"); the exact session boundaries per feed were not published. The weekend rule in F3 is therefore a proposal.

Open questions:
1. Is a sequencer uptime feed planned for Robinhood Chain, or should integrators use another mechanism?
2. Will Chainlink publish an NFLX Robinhood feed, or is NFLX a Data Streams-only asset on this chain?
3. Which proxy per feed is the SVR-enabled one and does it matter for a read-only consumer?
4. What are the exact market-open timestamps per session that drive the feed's off-hours behaviour (holidays, early closes)?
5. Do the five mainnet Stock Tokens expose `oraclePaused()`, `newUIMultiplier()` and `effectiveAt()` with the documented semantics? TSLA's `oraclePaused()` read `false` and `paused()` read `false` today; the others were not read.
6. Does mainnet USDG (Paxos) pause or blocklist contract holders (not read; the testnet USDG implementation was not read either, that is R1's question)?
7. Is Multicall3 `0xcA11...CA11` deployed on mainnet (the docs list a different L2 Multicall)?

## Sources

All read on 2026-10-03.

- Chainlink reference data directory, Robinhood mainnet: `https://reference-data-directory.vercel.app/feeds-robinhood-mainnet.json` (HTTP 200, 84,653 bytes); testnet: `.../feeds-robinhood-testnet.json` (HTTP 404).
- Chainlink docs: `https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood`; `https://docs.chain.link/data-feeds/l2-sequencer-feeds`; `https://docs.chain.link/data-feeds/svr-feeds`; `https://docs.chain.link/data-feeds/price-feeds/addresses` (Robinhood Chain Mainnet section and the NFLX Data Streams entry).
- Robinhood Chain docs (via `curl --resolve docs.robinhood.com:443:13.35.238.76`): `/chain/oracles-and-price-feeds/`, `/chain/contracts/`, `/chain/stock-tokens/`, `/chain/building-with-stock-tokens/`, `/chain/protocol-contracts/`, `/chain/connecting/`, `/chain/stock-token-apis/`.
- Robinhood public API: `https://api.robinhood.com/rhj/assets` (194 assets, HTTP 200, via `--resolve api.robinhood.com:443:13.35.163.34`).
- On-chain reads, Robinhood Chain mainnet public RPC `https://rpc.mainnet.chain.robinhood.com` (chain ID 4663, block 79,166,201 at 14:48Z, `date -u` 2026-10-03T14:53:18Z for the age figures): `latestRoundData()`, `decimals()` and `description()` on the TSLA, AMZN, PLTR, AMD and USDG proxies; `latestRoundData()` on the TSLA secondary proxy; `name()`, `symbol()` and `decimals()` on USDG `0x5fc5...d168`; `symbol()`, `decimals()`, `uiMultiplier()`, `oraclePaused()`, `paused()` on TSLA `0x322F...3b2d` and `symbol()`, `uiMultiplier()` on NFLX `0xE044...91E8`; `eth_getCode` of the Arbitrum One sequencer feed address (empty). Script outputs are reproducible with `cast call <addr> "<sig>" --rpc-url https://rpc.mainnet.chain.robinhood.com`, retrying on TLS errors.
- Repo evidence: `docs/research/07-testnet-reality-check.md`, `docs/research/09-price-source-and-feed.md`, `docs/handoffs/04-contracts-v2.md` (section 1.1 findings C-01 to C-36), `contracts/oracle/ChainlinkPriceOracle.sol`, `contracts/StrategyVault.sol`, `contracts/StrategyFactory.sol`.

### Recommendation

1. Describe mainnet in the README and FAQ as a documented, researched path with four concrete requirements (feeds with per-asset staleness, a sequencer-independent guard, a venue adapter, an audit), citing F1 to F4; claim nothing deployed.
2. Keep the Sandbox staleness values out of any mainnet text and note that real feeds only update on 0.5 percent moves or 24 hour heartbeats.
3. Ask Chainlink about the sequencer feed and NFLX before promising either.

### Still unknown

1. A sequencer uptime feed address for chain 4663 (none published).
2. An NFLX push feed on Robinhood mainnet (none in the directory).
3. Which proxy per feed is the SVR variant and what it means for a read-only consumer.
4. Exact 24/5 session boundaries and holiday behaviour of each feed.
5. Whether mainnet USDG and the Stock Tokens block contract holders, and the full set of issuer pause and blocklist powers.
6. Liquidity depth of mainnet Stock Token pools versus USDG.
