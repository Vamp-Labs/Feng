# 02 — Robinhood Chain Testnet

Read date for every source below: **2026-09-28** unless otherwise noted.

## Summary

Robinhood Chain testnet is real, public, and permissionless today. It is an **Arbitrum Orbit**
chain (Nitro client, settles to Ethereum), **chain ID 46630**, RPC
`https://rpc.testnet.chain.robinhood.com`, Blockscout explorer at
`https://explorer.testnet.chain.robinhood.com`, gas token **ETH**. It launched publicly on
2026‑02‑10 and is still live after mainnet (chain ID 4663) launched 2026‑07‑01. Standard Foundry /
Hardhat / viem / ethers tooling works unmodified — there is an official Foundry deploy tutorial, but
no official Robinhood-branded starter repo. A faucet exists at
`faucet.testnet.chain.robinhood.com` (test ETH + sample Stock Tokens for TSLA/AMZN/PLTR/NFLX/AMD),
plus third-party faucets (QuickNode, Chainstack, Alchemy, Chainlink) — none show a hard KYC/allowlist
gate, though the official faucet has an unspecified "verify yourself" step.

Chainlink is the announced oracle partner. **Chainlink CCIP is confirmed live on the testnet** with a
concrete router address, chain selector, and lanes to Arbitrum Sepolia / Ethereum Sepolia. Chainlink
**Data Feeds for tokenized-equity prices are documented only for Robinhood Chain Mainnet** in
Chainlink's own docs — no testnet price-feed address table was found despite a dedicated search. This
is the single most important open gap for this project (Track B question 7 / PRD's oracle
requirement).

USDG (Paxos's Global Dollar) is confirmed deployed on Robinhood Chain generally, and a Paxos testnet
faucet endpoint exists (`faucet.paxos.com?network=robinhood`), but **no testnet USDG contract address
was found in any source**, and the faucet page itself could not be fetched (TLS error, see below).
Testnet Stock Token contract addresses exist but the only ones found are **community-sourced, not
from official docs** (extracted from faucet on-chain activity by a third-party GitHub README) — they
must be re-verified against the explorer before use.

**Operational finding worth flagging on its own**: `docs.robinhood.com` (the official docs domain)
was **unreachable from this research environment for the entire session** — every fetch attempt (via
both the WebFetch tool and direct `curl`) failed with `certificate has expired` /
`SSLV3_ALERT_HANDSHAKE_FAILURE`. This could be an environment-local TLS trust-store issue rather than
a problem with Robinhood's actual certificate (their site is presumably reachable from normal
browsers), but it means every "official docs say X" claim below is relayed through secondary sources
that quote or mirror those pages, not read first-hand. The team should personally verify
`docs.robinhood.com/chain/*` from a normal browser before relying on anything sourced only that way.

The Arbitrum Open House Singapore Buildathon (the event this project targets) is real and running
now: online Buildathon **2026‑09‑14 → 2026‑10‑04**, in-person Founder House (application-only)
**2026‑10‑23 → 10‑25** in Singapore. $70K Open Category prize pool with **at least one of the top 3
spots reserved for a Robinhood Chain project**. No primary source found states a hard rule that
testnet deployment (vs. mainnet) is required or sufficient, nor a concrete deliverables checklist
(contract addresses / verified source / demo video) — this is an open question the team should
resolve directly on the HackQuest submission page, which requires registration to view in full.

## Findings

### 1. Chain identity (testnet)
- **Chain ID:** `46630` (hex `0xb626`) — confirmed independently by ChainList, Chainstack docs,
  TrustSwap, and Datawallet.
  [ChainList — Robinhood Chain Testnet](https://chainlist.org/chain/46630) (2026-09-28)
  [Chainstack — Robinhood getting started](https://docs.chainstack.com/reference/robinhood-getting-started) (2026-09-28)
- **RPC URL:** `https://rpc.testnet.chain.robinhood.com`.
  [TrustSwap — Robinhood Chain Testnet](https://trustswap.com/robinhood/testnet) (2026-09-28)
- **Block explorer:** `https://explorer.testnet.chain.robinhood.com` (Blockscout instance). Note:
  this explorer domain also returned `certificate has expired` on every direct fetch attempt from
  this environment during the session — same caveat as the docs domain applies.
  [ChainList — Robinhood Chain Testnet](https://chainlist.org/chain/46630) (2026-09-28)
- **Native/gas token:** ETH (test ETH, "has no value and never will").
  [TrustSwap — Robinhood Chain Testnet](https://trustswap.com/robinhood/testnet) (2026-09-28)
- **Mainnet chain ID (for contrast, not to use):** `4663`, launched 2026‑07‑01.
  [Dwellir — Robinhood Chain RPC](https://www.dwellir.com/networks/robinhood) (2026-09-28)
  One secondary source (TrustSwap's Chainlink page) stated mainnet chain ID as `5042` in an
  AI-generated summary — this conflicts with every other source and a targeted follow-up search
  confirmed `5042` actually belongs to an unrelated chain ("Arc"), so it is a summarization error, not
  a genuine conflict. Treat `4663` as correct for mainnet.
  [GitHub thirdweb-dev/js issue #8971 — "Add Robinhood Chain mainnet (4663)"](https://github.com/thirdweb-dev/js/issues/8971) (2026-09-28)

### 2. Arbitrum Orbit confirmation and what it fixes
Confirmed: "Robinhood Chain is a layer-2 network built with the Arbitrum platform (Arbitrum Orbit,
Nitro client)." This fixes: settlement to Ethereum (inherits Ethereum's security without Robinhood
running its own L1), full EVM + Ethereum JSON-RPC compatibility, standard Solidity/Foundry/Hardhat
tooling and standard audit assumptions, and ETH as the native gas token rather than a
chain-proprietary token. Reported block time target is ~100ms via preconfirmations, framed explicitly
as "trading-grade latency." One summary also stated the chain uses Ethereum blobs (EIP-4844) for data
availability, consistent with an Orbit rollup posting to Ethereum rather than an AnyTrust/DAC
configuration, but this specific DA-mode detail was not independently corroborated by a second
source — flagged as lower-confidence.
[Chainstack — What is Robinhood Chain?](https://chainstack.com/what-is-robinhood-chain/) (2026-09-28)
[Chainstack — Robinhood getting started](https://docs.chainstack.com/reference/robinhood-getting-started) (2026-09-28)
[Arbitrum blog — Robinhood Chain Launches Testnet on Arbitrum](https://blog.arbitrum.io/robinhood-chain-testnet/) (2026-09-28)

Practically, this means deployment/verification on Robinhood Chain testnet should work exactly like
deploying to any other Arbitrum Orbit / Nitro testnet: `forge create` with `--rpc-url` +
`--chain-id 46630`, then verify against the Blockscout explorer's verification API (Blockscout, not
Etherscan-style — verification flow differs slightly, e.g. Sourcify/Blockscout "smart-contract
verification" endpoints rather than Etherscan API keys).

### 3. Faucet
- **Official faucet:** `https://faucet.testnet.chain.robinhood.com` — connect wallet or paste an
  address, a "verify yourself" step (likely a captcha; no source specified KYC), then claim. Gives
  test ETH plus sample Stock Tokens (TSLA, AMZN, PLTR, NFLX, AMD mentioned).
  [Arbitrum blog — Robinhood Chain Launches Testnet on Arbitrum](https://blog.arbitrum.io/robinhood-chain-testnet/) (2026-09-28)
  [BitBlog — How to Interact with the Robinhood Public Testnet](https://www.bitblog.io/tutorials/how-to-interact-with-the-robinhood-public-testnet) (2026-09-28)
- **No allowlist/KYC requirement was found** in any source for the official faucet specifically.
  Third-party faucets impose their own unrelated eligibility gates (see below) — those are the
  third party's rules, not Robinhood's.
- **Third-party faucets and their own gates:**
  - QuickNode: `faucet.quicknode.com/robinhood/testnet` — 12h cooldown per network, requires 0.001
    mainnet ETH in the requesting wallet.
  - Chainstack: `faucet.chainstack.com/robinhood-chain-testnet-faucet` — up to 1 test ETH / 24h,
    requires 0.08 mainnet ETH holding history — largest single allocation found.
  - Alchemy: 0.1 test ETH / 24h, requires mainnet ETH + tx history.
  - Chainlink: `faucets.chain.link/robinhood-testnet` — 25 test LINK only, no ETH.
  [Datawallet — How to Get Robinhood Chain Testnet Tokens](https://www.datawallet.com/crypto/get-robinhood-chain-testnet-tokens) (2026-09-28)
- **Bridge as an alternative gas source:** existing Sepolia ETH can be moved in via the canonical
  Arbitrum bridge, which has a direct route for this chain:
  `https://portal.arbitrum.io/bridge?sourceChain=sepolia&destinationChain=robinhood-chain-testnet`.
  [Arbitrum Portal bridge URL](https://portal.arbitrum.io/bridge?sourceChain=sepolia&destinationChain=robinhood-chain-testnet&sanitized=true) (2026-09-28)

### 4. Docs / SDK / starter templates
- Official docs live under `docs.robinhood.com/chain/` — pages found by URL/title in search results:
  `/connecting`, `/deploy-smart-contracts` (Foundry contract deployment tutorial), `/contracts`,
  `/protocol-contracts/`, `/oracles-and-price-feeds/`, `/stock-token-apis/`, `/bridging/`,
  `/add-network-to-wallet`. **None of these were directly fetchable this session** (TLS cert error on
  every attempt, both WebFetch and raw `curl`) — content below is relayed via secondary sources that
  quote them.
- **No official Foundry/Hardhat starter template repo for Robinhood Chain specifically** was found.
  The official docs offer a deployment *tutorial* (prose steps), not a scaffolded template repo.
  Generic Foundry+Hardhat combo templates exist (e.g.
  [telekom-mms/hardhat-foundry-starter-kit](https://github.com/telekom-mms/hardhat-foundry-starter-kit))
  but are not Robinhood-specific.
- **Community example repo:** [hummusonrails/robinhood-chain-dapp-example](https://github.com/hummusonrails/robinhood-chain-dapp-example)
  (2026-09-28) — unofficial, references chain ID 46630, the RPC/explorer URLs above, and a small set
  of testnet contract addresses (see §5). Also a community demo dapp,
  [robinhood-chain-dapp.vercel.app](https://robinhood-chain-dapp.vercel.app/) ("Index Baskets") —
  interesting prior art for this exact PRD's shape (basket/index tokens on this chain) but not
  affiliated with Robinhood.
- **Infra providers with dedicated Robinhood Chain support/docs:** Alchemy
  ([alchemy.com/rpc/robinhood-testnet](https://www.alchemy.com/rpc/robinhood-testnet)), Chainstack
  ([docs.chainstack.com/reference/robinhood-getting-started](https://docs.chainstack.com/reference/robinhood-getting-started),
  [docs.chainstack.com/docs/robinhood-tooling](https://docs.chainstack.com/docs/robinhood-tooling)),
  QuickNode (guides at quicknode.com/guides/robinhood/*). All confirm chain ID 46630 / testnet RPC
  independently, which cross-validates §1.

### 5. Testnet tokenized-stock assets
- Officially, the faucet distributes sample Stock Tokens for **TSLA, AMZN, PLTR, NFLX, AMD** (per
  Arbitrum's own testnet-launch blog post — the closest thing to a primary source found for "which
  tickers exist on testnet").
  [Arbitrum blog — Robinhood Chain Launches Testnet on Arbitrum](https://blog.arbitrum.io/robinhood-chain-testnet/) (2026-09-28)
- **Community-sourced testnet addresses** (from the unofficial example repo's README, which states
  these were "identified from the faucet's onchain activity," NOT copied from official docs — treat
  as unverified until re-checked on the explorer):
  - TSLA: `0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E`
  - AMZN: `0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02`
  - NFLX: `0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93`
  - (community demo, not a Robinhood contract) BasketFactory: `0xC1940D5fd58ce735A44a53f910852B12250F6a14`,
    BasketToken: `0x7633e0920Ea46A8Ec54F61C95adECD391c01Edd4`
  [hummusonrails/robinhood-chain-dapp-example](https://github.com/hummusonrails/robinhood-chain-dapp-example) (2026-09-28)
- A search result also surfaced an explorer URL titled "Robinhood Chain Testnet RH-AAPL token
  details" at `https://explorer.testnet.chain.robinhood.com/token/0xe21690b40D8b8838743eF588DD0f7499Edfaf703`,
  implying an RH-AAPL testnet token exists at that address — **this could not be independently
  confirmed** because the explorer itself was unreachable (TLS error) every time it was fetched
  directly this session. Flagged as unverified.
- Mainnet addresses (do **not** use on testnet, listed only to avoid confusion): TSLA
  `0x322F0929c4625eD5bAd873c95208D54E1c003b2d`, AAPL `0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9`,
  NVDA `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC`, AMZN `0x12f190a9F9d7D37a250758b26824B97CE941bF54`.
  [QuickNode — How to Read Stock Tokens Data on Robinhood Chain](https://www.quicknode.com/guides/robinhood/read-stock-tokens-data-onchain) (2026-09-28)
- Each Stock Token is a standard ERC-20 with an additional `uiMultiplier()` function; display price =
  underlying equity market price × multiplier, per Chainlink's own docs for this integration (see §7).
  [Chainlink docs — Robinhood Tokenized Equities](https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood) (2026-09-28)
- **How to obtain test amounts:** the official faucet is the only documented path found; no
  documented "swap into a stock token" or mint-on-demand mechanism was found for testnet.

### 6. USDG on this testnet
- USDG (Paxos's Global Dollar) is confirmed deployed on Robinhood Chain as one of its supported
  networks generally (alongside Ethereum, Ink, Mantle, Solana, X Layer).
  [globaldollar.com — Build with USDG](https://globaldollar.com/build-with-usdg) (2026-09-28)
- **No testnet-specific USDG contract address was found** despite multiple targeted searches and
  fetch attempts. The mainnet Ethereum USDG address (`0xe343167631d89B6Ffc58B88d6b7fB0228795491D`,
  for reference/contrast only, not for use on Robinhood testnet) was found, but no Robinhood-chain
  address (testnet or mainnet) was surfaced in any fetchable source.
- **Test USDG faucet:** `https://faucet.paxos.com/?network=robinhood` is referenced as "a testnet
  faucet... no fees, permissionless and easy to use, available for all Paxos-issued stablecoins," but
  the page itself returned a TLS handshake failure on every direct fetch attempt this session and so
  could not be independently confirmed to actually serve USDG for the Robinhood network parameter.
  [globaldollar.com — Build with USDG](https://globaldollar.com/build-with-usdg) (2026-09-28)
- Robinhood Earn (≈7% APY lending against USDG) is a **mainnet** product feature, not directly
  relevant to a testnet build.
  [Robinhood Earn](https://robinhood.com/us/en/crypto/earn/) (2026-09-28)
- The Across bridge integration that delivers USDG on Robinhood Chain (bridging USDC in from other
  chains, relayer pays out USDG) is described as a **mainnet** flow; no equivalent testnet flow was
  found.
  [Across blog — Bridge to Robinhood Chain with Across](https://across.to/blog/bridge-to-robinhood-chain-with-across) (2026-09-28)

### 7. Price oracles on this testnet
- **Chainlink is the announced/confirmed oracle partner for Robinhood Chain**, stated at testnet
  launch: "Robinhood launches public testnet and partners with Chainlink as the oracle platform for
  Robinhood Chain."
  [Chainlink on X, quoted via search](https://x.com/chainlink/status/2021399623563178207) (2026-09-28)
- **Chainlink Data Feeds (tokenized-equity price feeds) are documented by Chainlink explicitly for
  "Robinhood Chain Mainnet"** — the dedicated docs page
  (`docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood`) states the mainnet deployment date
  (2026‑07‑01) and ~95 supported tokenized equities, uses the standard `AggregatorV3Interface` /
  `latestRoundData()` pattern, but **does not publish a parallel testnet feed-address table**, and no
  such table was found elsewhere.
  [Chainlink docs — Robinhood Tokenized Equities](https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood) (2026-09-28)
- **Chainlink CCIP (a different Chainlink product — cross-chain messaging/token transfer, not price
  data) is confirmed live on the testnet with concrete addresses:**
  - Chain selector: `2032988798112970440`
  - Router: `0x30D197C6F5bE050D5525dD94d01760FaCdB67e7C`
  - Fee tokens: LINK `0x6a11698F9dA09d1aA0Ee060E949086D50A3c2F70`, WETH
    `0x7943e237c7F95DA44E0301572D358911207852Fa`, native ETH
  - Outbound lanes confirmed to Arbitrum Sepolia and Ethereum Sepolia (OnRamp
    `0xFdf08F0e789682b00046837C424187d893d15083`, CCIP v2.0.0)
  [Chainlink docs — Robinhood Chain Testnet CCIP directory](https://docs.chain.link/ccip/directory/testnet/chain/robinhood-testnet) (2026-09-28)
- **Conclusion / gap:** CCIP (bridging/messaging) is provably live on testnet with real addresses.
  Data Feeds (price oracles for stock tokens, which is what this PRD actually needs) are only
  documented for mainnet in every source checked. Whether Chainlink Data Feeds are *also* live on
  Robinhood Chain testnet — just undocumented publicly — versus genuinely mainnet-only, could not be
  determined. This is the single biggest technical unknown for this project (see Assumptions/open
  questions and Recommendations).

### 8. Other known deployed contracts
- A third-party "verified contract address" directory
  ([trustswap.com/robinhood/contract-addresses](https://trustswap.com/robinhood/contract-addresses))
  *claims* Robinhood Chain has WETH, USDG, USDC, USDT, a Uniswap v2/v3 router+factory, a canonical
  Arbitrum bridge contract, and a "stock-token registry" — but **every address field on that page was
  "Pending verification"** at read time, i.e. it asserts these contracts exist without giving usable
  addresses. Not independently corroborated elsewhere for testnet. Treat as an unconfirmed lead, not
  a fact.
  [TrustSwap — Robinhood Chain Contract Addresses](https://trustswap.com/robinhood/contract-addresses) (2026-09-28)
- Robinhood's own docs (per secondary citation) name canonical Arbitrum bridge plus partner bridges
  LI.FI/Jumper, Relay, Across, Stargate, and Chainlink CCIP as officially supported bridge routes.
  [Datawallet — How to Bridge to Robinhood Chain](https://www.datawallet.com/crypto/bridge-to-robinhood-chain) (2026-09-28)

### 9. Bridging and testnet quirks/limits
- Canonical route from Arbitrum's own bridge portal:
  `portal.arbitrum.io/bridge?sourceChain=sepolia&destinationChain=robinhood-chain-testnet` — i.e.
  Robinhood Chain testnet settles against **Ethereum Sepolia** (not directly against Arbitrum
  Sepolia), consistent with an Orbit chain's standard parent-chain relationship for a testnet
  deployment.
  [Arbitrum Portal](https://portal.arbitrum.io/bridge?sourceChain=sepolia&destinationChain=robinhood-chain-testnet&sanitized=true) (2026-09-28)
- Chainlink CCIP additionally provides lanes directly to both Arbitrum Sepolia and Ethereum Sepolia
  (see §7) as an alternative cross-chain path, separate from the canonical Orbit bridge.
- **No explicit block gas limit or contract-size-limit figures for Robinhood Chain were found** in
  any source. As a standard Arbitrum Nitro/Orbit chain, the default EVM 24KB contract-size limit
  (EIP-170) almost certainly applies unless Robinhood customized it, but this was not directly stated
  anywhere found — flagged as an assumption, not a confirmed fact.
- One secondary source noted "mainnet gas is cheap on Robinhood Chain, but launch-hour congestion is
  real," implying deploy scripts should tolerate delayed confirmations around high-traffic periods —
  this was stated about mainnet, relevance to testnet unconfirmed.
  [TrustSwap — Robinhood Chain Testnet](https://trustswap.com/robinhood/testnet) (2026-09-28)
- Block time: ~100ms target (see §2), framed as trading-grade latency, consistently repeated across
  Chainstack, the Arbitrum blog, and CoinDesk coverage of mainnet launch.

### 10. Buildathon's own public submission rules
- **Event and dates:** Arbitrum Open House Singapore — online Buildathon **2026‑09‑14 → 2026‑10‑04**,
  in-person Founder House (application-only, selected teams) **2026‑10‑23 → 10‑25**, Singapore.
  [Luma — Arbitrum Open House Singapore](https://luma.com/openhouse-singapore) (2026-09-28)
  [Arbitrum Foundation blog — Open House Singapore: Applications Are Now Open](https://blog.arbitrum.foundation/open-house-singapore-applications-are-now-open/) (2026-09-28)
- **Prize structure (Buildathon stage, from the Foundation's own blog):**
  - Open Category: $70K total ($40K / $20K / $10K for 1st/2nd/3rd); **"a minimum of one of the top
    three spots will be reserved for a project building on the Robinhood Chain."**
  - Promising Products Track (AI agents, new financial primitives, frontier products): $15K total
    ($7K / $5K / $3K); same Robinhood Chain reservation language applies.
  - $30K USDC in discretionary Arbitrum Foundation grants.
  - Payment structure: except for Promising Products, prizes are split 50% upfront / 50%
    milestone-based payouts.
  [Arbitrum Foundation blog — Open House Singapore: Applications Are Now Open](https://blog.arbitrum.foundation/open-house-singapore-applications-are-now-open/) (2026-09-28)
- **Founder House-stage awards** (separate, application-only, later stage — not the Buildathon itself):
  a Luma page fetch surfaced a "Robinhood Chain Founder-in-Residence Award ($60K)" and "Robinhood
  Chain Innovation Award ($30K)" plus milestone-based funding, as part of the broader $300K Founder
  House prize/grant pool. This is a **different, later program stage** than the Buildathon this
  project is in; do not conflate the two when reading prize numbers elsewhere.
  [Luma — Arbitrum Open House Singapore](https://luma.com/openhouse-singapore) (2026-09-28)
- **Submission platform:** registration and (apparently) submission go through HackQuest at
  `arbitrum-singapore.hackquest.io`; the Foundation's blog posts route readers there via "Register
  Today" rather than stating requirements inline. Fetching the HackQuest page directly returned only
  high-level info (prize pool $115K total across the program, "Solidity and Rust" as supported tech
  stacks, participant count) — **no deliverables checklist or deployment-network requirement was
  visible without an account/registration**.
  [HackQuest — Arbitrum Open House](https://arbitrum-singapore.hackquest.io/) (2026-09-28)
- **Judging criteria:** one AI-search synthesis (not independently confirmed by directly reading a
  Singapore-specific primary page — `openhouse.arbitrum.io` returned HTTP 403 to this tool, and no
  other primary page with a rubric was found) reported four criteria used consistently across
  Arbitrum's Open House cities (India, NYC, Singapore all use the same HackQuest template): smart
  contract quality (best practices, minimal vulnerabilities), product-market fit, innovation and
  creativity, and whether the project solves a real problem. This is **secondhand, not directly
  verified from a primary Singapore-specific page** — flag accordingly.
- **No primary source found stating a hard testnet-vs-mainnet deployment requirement**, nor a
  concrete deliverables list (contract addresses / verified source / demo video). An earlier AI
  search summary asserted "Deployment on Arbitrum Sepolia is the baseline requirement, with Arbitrum
  One preferred" — this claim could **not** be traced to any primary source after three follow-up
  fetch attempts (`openhouse.arbitrum.io` 403, HackQuest page had no such text, both Builder's Block
  blog posts fetched had no such text) and may be a hallucinated generalization from a different
  Arbitrum hackathon's rules. **Do not rely on it.** Treat the actual submission requirements as an
  open question to be resolved by registering on HackQuest directly.

## Recommendations

1. **Build against Robinhood Chain testnet (chain ID 46630) as the primary target** — it is public,
   permissionless, EVM-standard, and matches the buildathon's explicit Robinhood Chain track
   incentive (at least one of three Open Category / Promising Products slots reserved for it). Use
   RPC `https://rpc.testnet.chain.robinhood.com`, verify contracts on
   `https://explorer.testnet.chain.robinhood.com` (Blockscout).

2. **Do not block development on finding official testnet stock-token or USDG addresses.** Deploy
   your own mock ERC-20s (`MockUSDG`, `MockTSLA`, `MockNVDA`, etc.) with 18 decimals and a
   `uiMultiplier()`-shaped interface matching the real Stock Token pattern found in Chainlink's docs,
   behind a single config file (`deployments.<network>.json` or a Foundry `.env` per network) so
   swapping in real testnet addresses later is a one-line change per token, not a contract rewrite.
   This directly addresses the PRD's risk that "Oracle / pricing issues" (PRD §10) could stall Day
   1–3 core-contract work.

3. **Build the oracle integration against a Chainlink `AggregatorV3Interface`-shaped abstraction from
   day one**, since that is the confirmed pattern for Robinhood Chain's real feeds (mainnet-confirmed,
   testnet-unconfirmed). Write a `MockV3Aggregator` (OpenZeppelin/Chainlink's own test mock pattern)
   implementing `latestRoundData()` for the demo, and keep the vault/oracle-consumer contracts coded
   against the interface, not a concrete mock address. The moment real testnet Data Feed addresses are
   confirmed (ask in the buildathon's Discord/Telegram, or re-check
   `docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood` and `docs.robinhood.com/chain/oracles-and-price-feeds/`
   closer to demo day), swap the address in config — no contract change needed.

4. **Concrete fallback plan if full public testnet access to Robinhood Chain turns out to be
   unavailable/gated for the team** (e.g. faucet rate-limits block the whole team, or a needed asset
   genuinely doesn't exist on testnet): build and demo on **Arbitrum Sepolia** instead, using the same
   mock-USDG / mock-stock-token / mock-oracle contracts described above. Structure this as a single
   network config swap:
   - One `networks.json`/`foundry.toml` `[rpc_endpoints]` block per target chain (arbitrum-sepolia,
     robinhood-testnet), selected by an env var (`DEPLOY_NETWORK`).
   - One `deployments/<network>/addresses.json` per network holding USDG/stock-token/oracle
     addresses, loaded by both the Foundry deploy scripts and the frontend's config — never hardcode
     an address in a contract or a component.
   - Because Robinhood Chain testnet bridges cleanly to/from Ethereum Sepolia via the canonical
     Arbitrum bridge (§9), and CCIP lanes exist to both Arbitrum Sepolia and Ethereum Sepolia,
     Arbitrum Sepolia is a coherent "practice chain" that shares tooling and bridge topology with the
     real target — not a disconnected fallback.
   - This also satisfies any (unconfirmed, see §10) baseline "must deploy on an Arbitrum Sepolia-class
     testnet" submission rule, if that turns out to be real, while still letting the team point the
     same deploy scripts at Robinhood Chain testnet as the headline deployment.

5. **Verify `docs.robinhood.com` and the Blockscout explorer from a normal browser (not this
   environment) before the team commits to specific addresses or docs-derived claims in this file.**
   This session's TLS failures against those two domains could be environment-specific; do not assume
   the domains are actually down.

6. **Resolve the buildathon submission requirements directly on HackQuest before Day 9–10 polish
   work.** Register at `arbitrum-singapore.hackquest.io`, read the actual submission form fields
   (they typically state required deliverables explicitly), and do not rely on this document's §10
   for anything beyond dates and prize structure.

## Implications per role

**Contracts engineer needs:**
- Network config: chain ID `46630` (testnet) / `4663` (mainnet, do not target for this project), RPC
  `https://rpc.testnet.chain.robinhood.com`, standard Foundry `forge create --rpc-url <url> --chain
  46630`.
- A mock-token deployment script (`MockUSDG`, mock stock ERC-20s with `uiMultiplier()`) and a
  `MockV3Aggregator`-style oracle mock, both swappable via a `deployments/<network>/addresses.json`
  file rather than hardcoded constants — this is the concrete artifact that makes the
  Robinhood-testnet ↔ Arbitrum-Sepolia fallback (Recommendation 4) actually work.
- Contract verification target: Blockscout at `https://explorer.testnet.chain.robinhood.com`
  (Blockscout's own verification flow/API, not Etherscan's).
- Before writing the RebalanceEngine/oracle-consumer contract: confirm (via team's own browser check
  of `docs.robinhood.com/chain/oracles-and-price-feeds/` or by asking in the buildathon's dev channel)
  whether Chainlink Data Feeds are actually live on testnet with real addresses — this file could not
  confirm it either way.

**Frontend engineer needs:**
- `NEXT_PUBLIC_CHAIN_ID=46630`, `NEXT_PUBLIC_RPC_URL=https://rpc.testnet.chain.robinhood.com`,
  `NEXT_PUBLIC_EXPLORER_URL=https://explorer.testnet.chain.robinhood.com` as env vars, with a second
  parallel set for an Arbitrum Sepolia fallback profile (chain ID `421614`) selected by a single
  `NEXT_PUBLIC_NETWORK` toggle.
- Standard EVM wallet connection (MetaMask/RainbowKit/wagmi) — no custom auth needed, chain is
  permissionless and standard-EVM per §2.
- Contract addresses and ABIs consumed from the same `deployments/<network>/addresses.json` the
  contracts engineer produces — never hardcode an address string in a component.
- A visible "network" indicator in the demo UI (which chain the app is currently pointed at) is
  cheap insurance given the real possibility of needing the Arbitrum Sepolia fallback mid-build.

## Assumptions and open questions

- **Chainlink Data Feeds (tokenized-equity price data) on Robinhood Chain testnet: existence and
  addresses unconfirmed.** Chainlink's own docs page for this integration names mainnet explicitly
  and does not publish a testnet table. Searches tried: `Robinhood Chain testnet Chainlink oracle
  Pyth price feed`, `"Robinhood Chain" testnet Chainlink price feed live "testnet" data feeds
  available`, direct fetch of `docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood`. Chainlink
  CCIP (a different product) is confirmed live on testnet — do not conflate the two when reading
  "Chainlink is live on testnet" claims elsewhere.
- **USDG testnet contract address on Robinhood Chain: not found.** Searches tried: `Robinhood Chain
  testnet USDG contract address tokenized stock token address`, direct fetch of
  `globaldollar.com/build-with-usdg`, `faucet.paxos.com/?network=robinhood` (TLS error both attempts).
  Nearest fallback found: a Paxos testnet faucet URL that could not be independently verified to
  actually dispense USDG on Robinhood Chain testnet specifically.
- **Official testnet Stock Token contract addresses: not published in any fetchable official source.**
  The only addresses found (TSLA/AMZN/NFLX) come from an unofficial GitHub README that explicitly
  says they were reverse-engineered from faucet transaction activity, not copied from docs — re-verify
  on the Blockscout explorer before using them in a demo. Searches tried: `Robinhood Chain testnet
  tokenized stock token address`, `Robinhood Chain testnet RH-AAPL token details`, direct fetch of
  `explorer.testnet.chain.robinhood.com/tokens` and the specific RH-AAPL token page (both TLS errors).
- **`docs.robinhood.com` and `explorer.testnet.chain.robinhood.com` were unreachable from this research
  environment all session** (`certificate has expired` / TLS handshake failure via both WebFetch and
  raw `curl`). Every claim in this file attributed to those domains is relayed secondhand through
  sources that quote them (Chainstack, TrustSwap, QuickNode, Datawallet, Chainlink docs, the
  unofficial GitHub repo). The team should re-check these two domains from an ordinary browser as a
  first step before relying on any address or claim sourced only this way — it is plausible this is
  purely an artifact of this environment's CA trust store or network path, not a real outage.
- **Buildathon deliverables checklist (contract addresses list, verified-source requirement, demo
  video requirement, submission deadline time-of-day) — not found in any primary source.** Searches
  tried: `Arbitrum Open House Singapore Buildathon submission rules judging criteria devpost`, direct
  fetch of `openhouse.arbitrum.io` (403 Forbidden), `arbitrum-singapore.hackquest.io` (fetched, no
  such detail present without registration), both `blog.arbitrum.foundation` Builder's Block posts
  found (fetched, no such detail present), `luma.com/openhouse-singapore` (TLS error). Resolve by
  registering on HackQuest directly.
- **Whether the Buildathon requires testnet vs. mainnet deployment, or accepts either: not found in
  any primary source.** An AI-search synthesis claimed "Arbitrum Sepolia is the baseline requirement"
  but this could not be traced to a citable primary page after three follow-up attempts and should be
  treated as unverified, possibly hallucinated from a different Arbitrum event's rules.
- **Whether the official faucet's "verify yourself" step is a captcha or something stricter (email,
  Robinhood account, KYC): not found.** Searches tried: `"faucet.testnet.chain.robinhood.com"
  allowlist signup requirement KYC` — no source described the step beyond its name.
- **Exact EVM contract-size / block gas limits for Robinhood Chain: not found**, assumed to be
  standard Nitro/EIP-170 defaults absent evidence of customization, but not confirmed.
- **Whether the "Founder-in-Residence" / "Innovation Award" Robinhood-specific prizes (§10) apply to
  the Buildathon stage this project is in, or only to the later Founder House stage: ambiguous.** The
  Foundation's own blog post ties the $70K/$15K prize structure explicitly to the Buildathon; the
  Luma page's $60K/$30K Robinhood-specific awards appeared alongside Founder House's $300K figure.
  Treat the Buildathon-stage numbers ($70K Open + $15K Promising Products, with 1-of-3 reserved for
  Robinhood Chain) as the ones relevant to this project's near-term deadline.

## Sources

- [ChainList — Robinhood Chain Testnet (chain 46630)](https://chainlist.org/chain/46630) — 2026-09-28
- [Robinhood Chain Testnet Faucet — add-chain page](https://faucet.testnet.chain.robinhood.com/add-chain) — 2026-09-28 (fetch failed: TLS cert error; cited via search snippet only)
- [Robinhood Chain Testnet RPC — Alchemy](https://www.alchemy.com/rpc/robinhood-testnet) — 2026-09-28
- [Robinhood Chain Testnet: RPC, Faucets, Deploy Guide — TrustSwap](https://trustswap.com/robinhood/testnet) — 2026-09-28
- [Robinhood Chain RPC, Chain ID 4663 & Official Links — TrustSwap](https://trustswap.com/robinhood/network-details) — 2026-09-28
- [Robinhood Chain Contract Addresses — TrustSwap](https://trustswap.com/robinhood/contract-addresses) — 2026-09-28
- [Chainlink on Robinhood Chain: Oracles & Price Feeds — TrustSwap](https://trustswap.com/robinhood/chainlink) — 2026-09-28
- [Robinhood Chain API reference: Arbitrum Orbit JSON-RPC quickstart — Chainstack](https://docs.chainstack.com/reference/robinhood-getting-started) — 2026-09-28
- [What is Robinhood Chain? — Chainstack blog](https://chainstack.com/what-is-robinhood-chain/) — 2026-09-28
- [Robinhood Chain tooling — Chainstack docs](https://docs.chainstack.com/docs/robinhood-tooling) — 2026-09-28
- [Robinhood Chain Faucet — Chainstack](https://faucet.chainstack.com/robinhood-chain-testnet-faucet) — 2026-09-28 (URL cited via search, not directly fetched)
- [Robinhood Chain Launches Testnet on Arbitrum — Arbitrum blog](https://blog.arbitrum.io/robinhood-chain-testnet/) — 2026-09-28
- [Robinhood Chain mainnet is live — Arbitrum blog](https://blog.arbitrum.io/robinhood-chain-mainnet/) — 2026-09-28
- [Robinhood Chain: Built for onchain finance](https://robinhood.com/us/en/chain/) — 2026-09-28 (cited via search snippet)
- [Robinhood Chain | Robinhood support article](https://robinhood.com/us/en/support/articles/robinhood-chain-mainnet/) — 2026-09-28 (cited via search snippet)
- [Robinhood Chain Testnet advanced filter — Blockscout explorer](https://explorer.testnet.chain.robinhood.com/advanced-filter) — 2026-09-28 (fetch failed: TLS cert error)
- [Robinhood Chain Testnet RH-AAPL token page — Blockscout explorer](https://explorer.testnet.chain.robinhood.com/token/0xe21690b40D8b8838743eF588DD0f7499Edfaf703) — 2026-09-28 (fetch failed: TLS cert error; unverified)
- [How to Get Robinhood Chain Testnet Tokens: Faucets & Limits — Datawallet](https://www.datawallet.com/crypto/get-robinhood-chain-testnet-tokens) — 2026-09-28
- [How to Bridge to Robinhood Chain — Datawallet](https://www.datawallet.com/crypto/bridge-to-robinhood-chain) — 2026-09-28
- [How to Interact with the Robinhood Public Testnet — BitBlog](https://www.bitblog.io/tutorials/how-to-interact-with-the-robinhood-public-testnet) — 2026-09-28
- [hummusonrails/robinhood-chain-dapp-example — GitHub](https://github.com/hummusonrails/robinhood-chain-dapp-example) — 2026-09-28
- [Index Baskets demo dapp](https://robinhood-chain-dapp.vercel.app/) — 2026-09-28 (existence noted via search, not independently fetched)
- [How to Read Stock Tokens Data on Robinhood Chain — QuickNode Guides](https://www.quicknode.com/guides/robinhood/read-stock-tokens-data-onchain) — 2026-09-28
- [Robinhood Tokenized Equities — Chainlink docs](https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood) — 2026-09-28
- [Robinhood Chain Testnet CCIP directory — Chainlink docs](https://docs.chain.link/ccip/directory/testnet/chain/robinhood-testnet) — 2026-09-28
- [Chainlink on X — testnet + Chainlink oracle partnership announcement](https://x.com/chainlink/status/2021399623563178207) — 2026-09-28
- [Build with USDG — Developer Tools, Integrations & Supported Networks — globaldollar.com](https://globaldollar.com/build-with-usdg) — 2026-09-28
- [USDG on Main Networks — Paxos Documentation](https://docs.paxos.com/guides/stablecoin/usdg/mainnet) — 2026-09-28 (cited via search snippet)
- [Robinhood Earn](https://robinhood.com/us/en/crypto/earn/) — 2026-09-28
- [Bridge to Robinhood Chain with Across — Across blog](https://across.to/blog/bridge-to-robinhood-chain-with-across) — 2026-09-28
- [Arbitrum Portal bridge — Sepolia to Robinhood Chain Testnet](https://portal.arbitrum.io/bridge?sourceChain=sepolia&destinationChain=robinhood-chain-testnet&sanitized=true) — 2026-09-28
- [Robinhood Chain RPC — Dwellir](https://www.dwellir.com/networks/robinhood) — 2026-09-28
- [Add Robinhood Chain mainnet (4663) to chainlist — thirdweb-dev/js GitHub issue #8971](https://github.com/thirdweb-dev/js/issues/8971) — 2026-09-28
- [Robinhood Chain Launches Public Testnet — Robinhood newsroom](https://robinhood.com/us/en/newsroom/robinhood-chain-launches-public-testnet) — 2026-09-28 (cited via search snippet, launch date Feb 10 2026)
- [Robinhood launches test version of its own blockchain — Yahoo Finance](https://finance.yahoo.com/news/robinhood-launches-test-version-own-013845371.html) — 2026-09-28
- [Arbitrum Open House Singapore — Luma](https://luma.com/openhouse-singapore) — 2026-09-28 (fetch failed on retry: TLS cert error; first successful fetch retained)
- [Open House Singapore: Applications Are Now Open — Arbitrum Foundation blog](https://blog.arbitrum.foundation/open-house-singapore-applications-are-now-open/) — 2026-09-28
- [Builder's Block #025 — Arbitrum Foundation blog](https://blog.arbitrum.foundation/builders-block-025-arbitrums-buildathon-starts-next-week-heres-how-to-stand-out-in-open-house/) — 2026-09-28
- [Builder's Block #023 — Arbitrum Foundation blog](https://blog.arbitrum.foundation/builders-block-023-415k-in-prizes-at-open-house-singapore-apply-now/) — 2026-09-28 (cited via search snippet)
- [Founder House Singapore: Apply Now — Arbitrum Foundation blog](https://blog.arbitrum.foundation/founder-house-singapore-apply-now-to-launch-products-on-arbitrum-one-robinhood-chain/) — 2026-09-28 (cited via search snippet)
- [Arbitrum Open House — One Program, Two Phases](https://openhouse.arbitrum.io/) — 2026-09-28 (fetch failed: HTTP 403)
- [Arbitrum Open House Singapore Online Buildathon — HackQuest](https://arbitrum-singapore.hackquest.io/) — 2026-09-28
- [Singapore Is Next For Arbitrum's Open House — EGamers.io](https://egamers.io/singapore-is-next-for-arbitrums-open-house-115k-buildathon-kicks-off-sept-14/) — 2026-09-28 (cited via search snippet)
