# 03 — Domain

## Summary

The "Strategy Token as a composable primitive" pattern is **not novel** — it is a close variant of a
lineage that already ran its course once (Set Protocol/TokenSets, 2017–2023, deprecated) and is
currently live in several forms (Index Coop, Enzyme Finance, Sommelier Cellars). What would be novel
for this build is applying that pattern specifically to **tokenized equities** on **Robinhood Chain**,
not the composable-vault mechanic itself. The PRD's own risk table (§10) names "nested strategy
complexity" and gestures at "limit composition depth (e.g. max 2–3)" but does not ground that number
in anything, and it is silent on three failure modes the comparable-protocol evidence shows are the
ones that actually blow up nested/composable vault tokens: circular/recursive composition, redemption
illiquidity when a constituent is itself hard to redeem, and stale/hardcoded pricing of a nested
token's NAV. The November 2025 Stream Finance / Elixir deUSD / xUSD collapse is a live, well-documented
case of exactly this pattern (recursive vault-of-vault looping + a lending market reading the nested
token at a hardcoded price instead of its true value) and is the single most relevant precedent found.

The Arbitrum Open House Singapore Buildathon is real and verifiable: a three-week online Buildathon
(Sept 14 – Oct 4, 2026, $115K prize pool) feeding into an in-person, application-only Founder House
(Oct 23–25, 2026, Singapore, up to $300K more) run jointly by the Arbitrum Foundation and Robinhood
Chain. The Buildathon guarantees at least one of its top-three Open Category/Promising Products slots
to a Robinhood Chain project, but no separate "Robinhood Chain track" submission category, no numeric
judging rubric, and — most important for this project — **no explicit testnet-vs-mainnet submission
requirement** were found on any official page reached. This last point should be treated as an open
question, not an assumption, and cross-checked against Track B.

Robinhood Chain itself is confirmed as a real, operating Arbitrum Orbit L2: Robinhood's own permissionless
Layer-2, testnet live since Feb 10, 2026, mainnet live since July 1, 2026, purpose-built for tokenized
equities/ETFs/RWAs and 24/7 financial services, with 10% of its net profits contractually flowing back
to the Arbitrum ecosystem. This is a real market position ("bring Robinhood's tokenized-equities
distribution onchain"), which matters for how the demo should frame "not ETFs on blockchain" — the
comparison the PRD wants to win against is specifically traditional ETFs/managed portfolios, not other
DeFi index protocols, which the PRD does not mention as competition at all.

## Findings

### Comparable protocols

- **Set Protocol / TokenSets** (2017–2023). Pioneered the exact primitive this PRD proposes: an ERC-20
  "Set Token" representing a rules-based basket, with programmatic issuance/redemption and rebalancing
  modules. Set Protocol V2 and the TokenSets UI were formally deprecated in 2023, with Set Labs stepping
  back to let the protocol run without a company steward. The deprecation announcement does not cite a
  single security failure — the lesson is more that a rules-based basket token, on its own, without a
  strong distribution/discovery layer, did not sustain independent product-market fit; Index Coop
  effectively inherited and carried the model forward on the same underlying tech ("Index Protocol,"
  Set V2's successor). *(Sources: Set Labs Medium deprecation post; docs.tokensets.com)*
- **Index Coop** (live, 2026). Runs on "Index Protocol," a continuation of Set V2. Two rebalancing
  eras are documented: an early DEX/TWAP-based "taker" model where the protocol itself paid gas and
  absorbed slippage/MEV on every rebalance trade, and a 2023+ "Auction Rebalance Module" where the
  index sets a price-decay auction and third-party bidders compete to fill it — token holders pay no
  gas for rebalancing, and NAV decay/MEV exposure is reduced versus the taker model. Legacy products
  still on Set Protocol V2 (DPI, MVI, BED) cannot be upgraded to auction rebalancing because the base
  contracts are immutable — a direct illustration of how expensive it is to fix a rebalancing design
  after tokens are already live with value in them. Redemption is described as always permissionless
  and instant for underlying value. *(Sources: indexcoop.com/blog/introducing-auction-rebalancing,
  docs.indexcoop.com programmatic-redemptions page, docs.indexcoop.com auction-rebalance-module page)*
- **Enzyme Finance** (live, 2026). Vault manager pattern with a transferable ERC-20 vault-share token.
  Enzyme's own docs explicitly frame "vault of vaults" (fund-of-funds) as a supported, intended use
  case enabled by vault-share composability/transferability — i.e., nested vault tokens are a designed
  feature, not an accident, but Enzyme's model keeps redemption/valuation logic per-vault and lets each
  vault's manager control what it holds, rather than auto-composing arbitrary depth. *(Source:
  enzyme.finance/enzyme-vaults, enzyme.finance/use-cases/financial-instruments)*
- **Sommelier Cellars.** ERC-4626-based vaults ("Cellars") curated by strategists and approved through
  governance, with a Cosmos-based validator set executing the actual rebalancing transactions off the
  vault's own trust boundary — an explicit design choice to keep "rules-based automation" execution
  separated from the vault's custody contract. *(Source: search-aggregated description, no single
  canonical page fetched directly — treat this one item as lower-confidence pending a direct
  sommelier.finance docs read.)*
- **ERC-4626 nested-vault mechanics (protocol-agnostic).** OpenZeppelin and Euler have both published
  on the "inflation attack": an attacker donates directly to an empty/near-empty vault to distort the
  share price before another depositor's first deposit, causing that depositor's shares to round to
  zero. OpenZeppelin's own GitHub issue thread and Euler's writeup state explicitly that **this problem
  compounds with vault nesting** — "if vaults would be nested (vaults holding shares of other vaults as
  assets), the decimals or initial exchange rate would compound with every nesting level." This is a
  documented, standard-level (not protocol-specific) hazard that applies directly to "Strategy Token
  holds Strategy Token." *(Sources: github.com/OpenZeppelin/openzeppelin-contracts issue #3706,
  openzeppelin.com/news/erc-4626-tokens-in-defi-exchange-rate-manipulation-risks,
  euler.finance/blog/exchange-rate-manipulation-in-erc4626-vaults)*
- **Stream Finance / Elixir deUSD / xUSD collapse (Oct–Nov 2025).** The clearest recent real-money case
  of nested/composable-token failure modes materializing together. Third-party curators built vaults
  where users supplied USDC against xUSD collateral, and the borrowed USDC was looped back into minting
  more xUSD — a recursive, self-referential structure that inflated the token's apparent backing.
  Critically, the lending markets pricing this collateral (on Euler and Morpho) did not mark xUSD to
  its actual traded value — they read a **hardcoded price of $1** — so when the real value collapsed,
  the liquidation machinery that should have unwound the position never triggered. Stream disclosed
  ~$93M in losses and froze withdrawals on Nov 4, 2025; Elixir's deUSD (65% backed by Stream exposure)
  fell ~98% to ~$0.015 and was wound down; contagion reached a third stablecoin (Stables Labs' USDX).
  Elixir's recovery effort reported ~80% redemption processed for deUSD holders as of the writeup.
  *(Sources: blockeden.xyz/blog/2025/11/08 "Anatomy of a $285M DeFi Contagion," theblock.co/post/377961,
  pharos.watch/learn/case-studies/stream-elixir-contagion-2025)*
- **Gas cost of deep/nested composition (general DeFi exploit pattern, 2026).** A documented Aave-
  adjacent exploit chain involved over 160 nested transactions and 8.6M gas to extract $2.7M, illustrating
  that deep recursive/nested call structures are both a cost problem (gas) and an attack-surface problem
  (harder to reason about, harder to audit) even outside strict vault-of-vault designs. *(Source:
  aggregated from "Q1 2026 DeFi Exploit Pattern Analysis" search result, dev.to/ohmygod)*

### Arbitrum Open House Singapore Buildathon

- **Format & dates.** Online Buildathon: Sept 14 – Oct 4, 2026 (3 weeks), $115K in prizes + grants.
  Founder House: Oct 23–25, 2026, in-person, Singapore, application-only, for teams with an existing
  product/prototype, up to $300K in prizes/grants. Total program: $415K across both phases.
  *(Sources: blog.arbitrum.foundation/builders-block-023-415k-in-prizes-at-open-house-singapore-apply-now/,
  blog.arbitrum.foundation/open-house-singapore-applications-are-now-open/, luma.com/openhouse-singapore,
  openhouse.arbitrum.io — read via search snippet, direct fetch returned 403)*
- **Buildathon prize structure.** Open Category: $70K ($40K/$20K/$10K for 1st/2nd/3rd). Promising
  Products Track (AI agents, new financial primitives, frontier categories): $15K ($7K/$5K/$3K).
  Arbitrum Foundation grants: additional $30K. **A minimum of one of the top three spots (across Open
  Category and Promising Products Track) is reserved for a project building on Robinhood Chain** — this
  is a guarantee, not a separate track/category with its own submission form, based on everything
  fetched. *(Source: blog.arbitrum.foundation/open-house-singapore-applications-are-now-open/)*
- **Founder House / Robinhood Chain-specific prizes.** Separately, Founder House (the later, in-person,
  application-only phase) lists a "Robinhood Chain Founder-in-Residence Award" (~$60K) and a "Robinhood
  Chain Innovation Award" (~$30K) inside its up-to-$300K pool, alongside a $120K General Builder Track.
  These are Founder House figures, not Buildathon figures — do not conflate the two phases when citing
  prize numbers. *(Sources: egamers.io "Arbitrum Launches $115K Buildathon...", en.coin-turk.com
  "Arbitrum and Robinhood Chain launch $300,000 grant program," tronweekly.com Founder House article —
  these are secondary/press sources; the Arbitrum Foundation's own blog posts confirm the Founder House
  total and General Builder Track figure but were less explicit on the exact per-award Robinhood Chain
  breakdown, so treat those two specific dollar figures as medium- rather than high-confidence.)*
- **Judging criteria.** No numeric/scored rubric was found on any page reached. The closest statements:
  Founder House selection is "based on product quality, execution potential, and ecosystem alignment"
  (Builder's Block #025); the Buildathon overall is described as evaluating whether projects are
  "solving real-world problems while leveraging unique advantages of onchain systems" (openhouse.arbitrum.io,
  read via search-engine snippet since direct fetch was blocked). Tech stack accepted: Solidity, Rust.
  Format: fully online for the Buildathon phase. *(Source: arbitrum-singapore.hackquest.io)*
- **Testnet vs mainnet requirement.** **Not found.** Every page fetched (openhouse.arbitrum.io [via
  search, direct fetch 403], luma.com/openhouse-singapore, arbitrum-singapore.hackquest.io,
  blog.arbitrum.foundation Builder's Block #023 and #025) was silent on whether Buildathon submissions
  must deploy to a specific network. This is logged under Assumptions/open questions below, per the
  task's explicit instruction not to invent this.

### Robinhood Chain — market positioning

- Robinhood Chain is Robinhood's own permissionless Ethereum Layer-2, built on the Arbitrum Orbit
  stack, purpose-built for tokenized real-world assets (equities, ETFs, private equity) and 24/7
  financial services, with 100ms block times and settlement back to Ethereum. Public testnet launched
  Feb 10, 2026 (reportedly processing 4M transactions in its first week); public mainnet launched
  July 1, 2026. Uniswap and Chainlink were integrated "from day one." Under the Arbitrum/Robinhood
  technology agreement, 10% of Robinhood Chain's net profits flow back to the Arbitrum ecosystem — a
  real, disclosed commercial relationship, not just a co-marketing label, which is worth using in demo
  narrative as evidence this isn't a throwaway hackathon chain. *(Sources: blog.arbitrum.io/robinhood-chain-mainnet/,
  eco.com/support articles "What Is Robinhood Chain," finance.yahoo.com "Robinhood's New Arbitrum Chain
  Bridges the Gap Between DeFi and Traditional Finance," coindesk.com "Arbitrum (ARB) price jumps 30%
  after revenue surge from its partnership with Robinhood," robinhood.com/us/en/newsroom "Robinhood
  Chain Launches Public Testnet")*
- Positioning implication: Robinhood Chain's own stated purpose is literally "bring Robinhood's
  tokenized-equities product onchain, 24/7, DeFi-composable." The PRD's "we do not build ETFs on
  blockchain" line is well-aimed at this — the natural competitive contrast for a Robinhood Chain judge
  is not other index-token DeFi protocols, it's Robinhood's own existing (TradFi) managed-portfolio /
  ETF products and simple static tokenized-stock baskets. The comparable-protocol research above should
  be read as "prior art to learn from and avoid repeating," not as "the competition to beat" in the demo
  narrative.

## Recommendations

Concrete guardrails to add to PRD §10 (Risks & Mitigations), each grounded in a specific incident or
documented pattern above:

1. **Hard-cap composition depth at 2, not "2–3."** Depth 1 = Strategy Token holding only underlying
   assets (stocks/USDG). Depth 2 = Strategy Token holding other depth-1 Strategy Tokens as constituents.
   No depth-3 (a Strategy Token composed of Strategy Tokens that themselves hold other Strategy Tokens).
   Rationale: the Aave-adjacent nested-transaction exploit (160 nested calls, 8.6M gas, $2.7M loss) and
   the general ERC-4626 nesting-compounds-inflation-risk finding both show cost and attack surface grow
   with depth, while depth 2 is already sufficient to demonstrate "true composability" for PRD §12's
   success definition ("Strategy inside Strategy"). Enforce this as a `require()` in `StrategyFactory`
   at creation time, not a UI-level suggestion.
2. **Reject circular composition at creation time, on-chain.** Walk the proposed constituent graph when
   a new Strategy Token is created and revert if the new token would appear, directly or indirectly, as
   its own constituent. This is precisely the missing control in the Stream Finance/xUSD case — borrowed
   collateral was looped back into minting more of the same synthetic asset with no check preventing it.
   Add this to §10 as its own risk line ("Circular composition inflating apparent backing") distinct
   from the existing generic "Nested strategy complexity" row.
3. **Never let a nested Strategy Token's NAV be read from a stale or hardcoded value.** Require that
   NAV computation for a composed Strategy Token recurse into its constituent Strategy Tokens' live,
   freshly computed NAV at redemption/rebalance time — not a cached checkpoint. This is the direct
   mechanical cause of the Stream Finance contagion (lending markets read xUSD at a hardcoded $1
   instead of its real, collapsing value, so the liquidation logic never fired). Add to §10 as
   "Nested NAV staleness / hardcoded pricing," separate from the existing generic "Oracle / pricing
   issues" row, since this is specifically about internally-composed price, not external oracle feeds.
4. **Add an explicit redemption-liquidity rule for composed strategies.** When a Strategy Token holds
   another Strategy Token as a constituent, redemption of the outer token must not force redemption of
   the inner Strategy Token into its own underlying assets (which may be slow/illiquid/rate-limited);
   it should instead redeem pro-rata in units of the constituent Strategy Token itself. This avoids
   promising instant/full redemption against an asset that cannot actually be unwound instantly — the
   general liquidity-mismatch pattern documented across 2025–2026 vault incidents (Stream, and the
   broader pattern of "vault offers instant withdrawals but the underlying is illiquid"). Add to §10 as
   its own row: "Redemption liquidity mismatch on nested constituents."
5. **Gate rebalance/redemption execution on oracle freshness, specifically because the underlying is
   tokenized equities.** Traditional equities trade on market hours; a tokenized-stock wrapper may be
   transferable 24/7 on Robinhood Chain, but its price oracle may not update, or may update on stale
   TradFi-hours data, outside market hours. A rebalance or large redemption executed against a stale
   feed misprices the trade. Add an explicit staleness bound (e.g. reject rebalance/redemption actions
   if the relevant oracle update is older than N minutes) as a new §10 row — this is not covered by the
   existing generic "Oracle / pricing issues → use reliable price feeds" mitigation, which doesn't
   address the equities-market-hours-specific staleness problem.
6. **Note the "taker vs maker" rebalancing cost tradeoff explicitly, even if the MVP stays simple.**
   Index Coop's own history shows their original DEX/TWAP "taker" rebalancing (protocol pays gas, eats
   slippage/MEV on every trade) was expensive enough that they built a whole new "maker"/auction module
   to escape it — and that legacy products on the old model *couldn't be upgraded* because the contracts
   were immutable. For this hackathon MVP, a simple keeper-driven taker-model rebalance is fine and
   should stay in scope, but §10's "Rebalancing gas costs" row should say explicitly *why* (bounded
   trade size / slippage cap, not full DEX-taker rebalancing at arbitrary size) and should flag
   auction-style rebalancing as the known post-hackathon upgrade path, consistent with PRD §6.2.

## Implications per role

**For whoever designs the StrategyVault / RebalanceEngine contracts:**
- Depth-2 cap and cycle-detection must live in `StrategyFactory` at strategy-creation time (revert
  before mint), not be a soft UI validation — this is the cheapest place to enforce it and matches how
  the failure actually originates (a bad graph gets created, not a bad graph gets exploited later).
- NAV computation for any composed Strategy Token must recurse into live constituent NAV, and that
  recursion is exactly where the depth cap earns its keep (bounded recursion, bounded gas).
- Build the oracle-staleness check as a shared modifier/guard used by both the rebalance entrypoint and
  the redeem entrypoint, since both are exposed to the same equities-market-hours staleness risk.
- Treat "constituent is itself a Strategy Token" as a distinct redemption code path from "constituent
  is a raw tokenized-stock/USDG," per Recommendation 4 — don't let the generic pro-rata redemption
  function silently try to unwind a nested Strategy Token's own underlying.

**For whoever writes the marketplace/demo narrative:**
- Do not pitch "Strategy Token nested inside Strategy Token" as *technically* unprecedented — judges
  familiar with DeFi (plausible at an Arbitrum event) will recognize Set Protocol, Index Coop, and
  Enzyme's vault-of-vaults as prior art. The credible differentiators are (a) applying this pattern to
  tokenized equities specifically, natively on Robinhood Chain, and (b) building the depth cap, cycle
  check, and redemption-liquidity rule in from day one as *safety features*, turning a well-known DeFi
  failure class (cite Stream Finance/Elixir, Nov 2025, ~$93M loss with contagion) into an explicit,
  demonstrable design decision — "here's the incident this would have prevented" is a strong, concrete
  demo beat for a 3-minute walkthrough.
- Position against Robinhood's own existing tokenized-stock/ETF product and static baskets, not against
  other DeFi index protocols — that is what Robinhood Chain's own stated purpose (bringing tokenized
  equities onchain, 24/7, composable) makes the natural contrast, and it's a contrast the PRD's own
  "not ETFs on blockchain" line is already reaching for.
- Because the Buildathon's own testnet-vs-mainnet requirement could not be confirmed (see Open
  questions), the demo narrative should not assert "we deployed to mainnet" or "we deployed to testnet"
  as a badge of compliance without Track B's confirmation — frame deployment target as a deliberate
  choice made for the demo, not as satisfying an unverified rule.

## Assumptions and open questions

- **No official numeric judging rubric was found.** The most specific language located is "selection is
  based on product quality, execution potential, and ecosystem alignment" (Builder's Block #025) and
  "solving real-world problems while leveraging unique advantages of onchain systems" (openhouse.arbitrum.io,
  via search snippet). Do not treat any more specific rubric as real without a direct citation — none
  was found despite searching "judging criteria," "rubric," and fetching the Buildathon's own site,
  the Luma page, and the HackQuest registration page.
- **Testnet vs mainnet submission requirement: not found, explicitly flagged per task instructions.**
  Searched/fetched: `openhouse.arbitrum.io` (direct WebFetch returned HTTP 403 Forbidden — only a
  search-engine-cached snippet was available, which did not mention network requirements),
  `luma.com/openhouse-singapore`, `arbitrum-singapore.hackquest.io`, and Arbitrum Foundation blog posts
  Builder's Block #023 and #025. None state a required network for Buildathon submissions. This must be
  cross-checked against Track B's testnet research and, if still unresolved, raised to the user before
  the team commits to a deployment target.
- **`openhouse.arbitrum.io` could not be directly read.** WebFetch returned 403 Forbidden on the
  official site. All information attributed to it in this report came from search-engine result
  snippets of that domain, which is lower-confidence than a direct page read — a human with browser
  access (or a differently configured fetch) should verify the live page directly, especially for any
  submission-mechanics detail (required fields, video requirement, deployment proof format) not
  captured by a search snippet.
- **Robinhood Chain Founder-in-Residence Award ($60K) and Innovation Award ($30K) figures are
  medium-confidence.** They came from secondary press coverage (EGamers.io, coin-turk.com, TronWeekly)
  rather than being directly and explicitly itemized on an Arbitrum Foundation first-party page in the
  content actually returned by the fetch tool. The $300K Founder House total and $120K General Builder
  Track figure are corroborated by the Foundation's own blog, but the specific Robinhood-Chain-only
  award split should be treated as "reported, not verified first-party" until a primary source is read
  directly.
- **Whether "Robinhood Chain track" is a separate submission category in the online Buildathon (vs. a
  guaranteed-placement rule applied within the existing Open Category / Promising Products Track) is
  inferred, not explicitly stated.** All fetched sources describe it as "a minimum of one of the top
  three spots reserved for a project building on Robinhood Chain" within the existing categories, not
  as a distinct third track with its own submission form. If a distinct Robinhood Chain track/form does
  exist, it was not surfaced by any search or fetch performed.
- **Sommelier Cellars description is lower-confidence** — no single canonical Sommelier documentation
  page was directly fetched; the description above is aggregated from search-result snippets only and
  should be verified directly (e.g. against sommelier.finance docs) before being cited as authoritative
  in any handoff document.
- **USDG issuer/availability details were intentionally not pursued here** — that is explicitly Track
  B's remit per the brief; this report only establishes that Robinhood Chain's stated purpose includes
  tokenized real-world assets and that Founder House prizes are denominated in "USDG," which at least
  confirms USDG is a currency Robinhood Chain's own ecosystem actively uses, not evidence of its testnet
  deployment status (Track B question).

## Sources

- [Arbitrum Open House Singapore · Luma](https://luma.com/openhouse-singapore) — read 2026-09-28
- [Open House Singapore: Applications Are Now Open — Arbitrum Foundation blog](https://blog.arbitrum.foundation/open-house-singapore-applications-are-now-open/) — read 2026-09-28
- [Builder's Block #023: $415k in Prizes at Open House Singapore](https://blog.arbitrum.foundation/builders-block-023-415k-in-prizes-at-open-house-singapore-apply-now/) — read 2026-09-28 (via search snippet)
- [Builder's Block #025: Arbitrum's Buildathon Starts Next Week](https://blog.arbitrum.foundation/builders-block-025-arbitrums-buildathon-starts-next-week-heres-how-to-stand-out-in-open-house/) — read 2026-09-28
- [Builder's Block #026: $300K Awaits at Founder House Singapore](https://blog.arbitrum.foundation/builders-block-026-300k-awaits-at-founder-house-singapore-what-great-startups-have-in-common/) — read 2026-09-28 (via search snippet)
- [Arbitrum Open House — openhouse.arbitrum.io](https://openhouse.arbitrum.io/) — attempted 2026-09-28, direct fetch returned HTTP 403; info sourced via search-engine snippet only
- [Arbitrum Open House Singapore — HackQuest registration page](https://arbitrum-singapore.hackquest.io/) — read 2026-09-28
- [Arbitrum Launches $115K Buildathon, Reserving a Podium Spot for Robinhood Chain Builders — EGamers.io](https://egamers.io/arbitrum-launches-115k-buildathon-reserving-a-podium-spot-for-robinhood-chain-builders/) — read 2026-09-28 (secondary source)
- [Singapore Is Next For Arbitrum's Open House: $115K Buildathon Kicks Off Sept. 14 — EGamers.io](https://egamers.io/singapore-is-next-for-arbitrums-open-house-115k-buildathon-kicks-off-sept-14/) — read 2026-09-28 (secondary source)
- [Arbitrum and Robinhood Chain launch $300,000 grant program for founders in Singapore — coin-turk](https://en.coin-turk.com/arbitrum-and-robinhood-chain-launch-300000-grant-program-for-founders-in-singapore/) — read 2026-09-28 (secondary source)
- [Arbitrum Launches Founder House Singapore With $300K Fund — TronWeekly](https://www.tronweekly.com/arbitrum-founder-house-singapore-300k-builder/) — read 2026-09-28 (secondary source)
- [Robinhood Chain mainnet is live, built with the Arbitrum Platform — Arbitrum blog](https://blog.arbitrum.io/robinhood-chain-mainnet/) — read 2026-09-28
- [Robinhood's New Arbitrum Chain Bridges the Gap Between DeFi and Traditional Finance — Yahoo Finance](https://finance.yahoo.com/news/robinhood-arbitrum-chain-bridges-gap-100215924.html) — read 2026-09-28
- [Robinhood Arbitrum L2 Chain Launches With a Bang: Hits 4 Million Testnet Transactions — Yahoo Finance](https://finance.yahoo.com/news/robinhood-arbitrum-l2-chain-launches-124715466.html) — read 2026-09-28
- [What Is Robinhood Chain? Inside Robinhood's Arbitrum L2 — Eco support](https://eco.com/support/en/articles/15859739-what-is-robinhood-chain-inside-robinhood-s-arbitrum-l2) — read 2026-09-28
- [Robinhood Tokenized Stocks: What's Live and How It Works — Eco support](https://eco.com/support/en/articles/15083160-robinhood-tokenized-stocks-what-s-live-and-how-it-works) — read 2026-09-28
- [Robinhood Chain Launches Public Testnet — Robinhood Newsroom](https://robinhood.com/us/en/newsroom/robinhood-chain-launches-public-testnet/) — read 2026-09-28
- [Arbitrum (ARB) price jumps 30% after revenue surge from its partnership with Robinhood — CoinDesk](https://www.coindesk.com/markets/2026/09/01/robinhood-s-new-crypto-network-is-printing-cash-and-it-s-sending-arbitrum-s-token-soaring) — read 2026-09-28
- [Robinhood (HOOD) starts testing its own blockchain — CoinDesk](https://www.coindesk.com/business/2026/02/11/robinhood-starts-testing-its-own-blockchain-as-crypto-and-tokenization-push-deepens) — read 2026-09-28
- [Index Coop: Introducing Auction Rebalancing](https://www.indexcoop.com/blog/introducing-auction-rebalancing) — read 2026-09-28
- [Programmatic Redemptions — Index Coop Resource Center](https://docs.indexcoop.com/index-coop-community-handbook/protocol/programmatic-redemptions) — read 2026-09-28
- [Auction Rebalance Module — Index Coop Resource Center](https://docs.indexcoop.com/index-coop-community-handbook/protocol/index-protocol/modules/auction-rebalance-module) — read 2026-09-28
- [Set Token — Index Coop Resource Center](https://docs.indexcoop.com/index-coop-community-handbook/protocol/index-protocol/core-contracts/set-token) — read 2026-09-28
- [Announcing the deprecation of Set Protocol V2 and TokenSets — Set Labs Medium](https://medium.com/set-protocol/announcing-the-deprecation-of-set-protocol-v2-and-tokensets-f019410f2d2a) — read 2026-09-28
- [Overview — Set (TokenSets) Documentation](https://docs.tokensets.com/) — read 2026-09-28
- [Enzyme Vaults — the industry standard](https://enzyme.finance/enzyme-vaults) — read 2026-09-28
- [Financial Instruments — Enzyme Finance](https://enzyme.finance/use-cases/financial-instruments) — read 2026-09-28
- [Implement or recommend mitigations for ERC4626 inflation attacks — OpenZeppelin GitHub issue #3706](https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706) — read 2026-09-28
- [ERC-4626 Tokens in DeFi: Exchange Rate Manipulation Risks — OpenZeppelin](https://www.openzeppelin.com/news/erc-4626-tokens-in-defi-exchange-rate-manipulation-risks) — read 2026-09-28
- [A Novel Defense Against ERC4626 Inflation Attacks — OpenZeppelin](https://www.openzeppelin.com/news/a-novel-defense-against-erc4626-inflation-attacks) — read 2026-09-28
- [Exchange Rate Manipulation in ERC4626 Vaults — Euler Finance blog](https://www.euler.finance/blog/exchange-rate-manipulation-in-erc4626-vaults) — read 2026-09-28
- [Anatomy of a $285M DeFi Contagion: The Stream Finance xUSD Collapse — BlockEden.xyz](https://blockeden.xyz/blog/2025/11/08/m-defi-contagion/) — read 2026-09-28
- [Elixir sunsets deUSD synthetic stablecoin following Stream Finance unwinding — The Block](https://www.theblock.co/post/377961/elixir-sunsets-deusd-synthetic-stablecoin-following-stream-finance-unwinding-aims-full-redemptions) — read 2026-09-28
- [Stream Finance: loss broke three stablecoins — Pharos case study](https://pharos.watch/learn/case-studies/stream-elixir-contagion-2025/) — read 2026-09-28
- [Q1 2026 DeFi Exploit Pattern Analysis: $137M Lost, 5 Attack Patterns Every Auditor Must Know — DEV Community](https://dev.to/ohmygod/q1-2026-defi-exploit-pattern-analysis-137m-lost-5-attack-patterns-every-auditor-must-know-2mh) — read 2026-09-28
