# Judge FAQ

Short, honest answers to the questions a reviewer is most likely to ask. Each answer is two lines. Facts come from the repo and the cited research files.

**Skeleton pass.** Each V2-PENDING marker flags an answer that changes depending on whether the V2 redeploy (Gate G1, 2026-10-04 10:21 SGT) shipped; the text outside the marker is true for the V1 deployment on chain today. The coordinator resolves each marker.

## Why a mock desk?

The real Robinhood Stock Tokens on testnet cannot be minted by us (only the issuer's authorized participants mint and burn), and their testnet liquidity is unverified, so a demo that must run on demand cannot depend on them.
In V1 the vault simply mints and burns our mock tokens at the oracle price, with no spread; `[V2-PENDING: in V2 the vault holds the tokens and trades through an IVenue market maker (the OracleDesk) with a spread and per-leg slippage bounds, so the vault code is the production shape and only the venue is a stand-in]`.

## Why a relayer?

Chainlink has no Robinhood Chain testnet feeds (its testnet directory file returns 404), so something has to publish prices; Robinhood's public REST price endpoint is the best live source (`docs/research/09-price-source-and-feed.md`).
Today the testnet feeds are mock aggregators holding constant prices that anyone can update; `[V2-PENDING: in V2 a role-gated, deviation-bounded relayer pushes real prices every few minutes]`. The oracle adapter reads Chainlink's `AggregatorV3Interface`, so mainnet is a feed-address change, not a rewrite.

## What is live?

Live on Robinhood Chain testnet (chain ID 46630): the factory, registry, rebalance engine and oracle adapter, ten strategies including two nested ones, Privy wallets, and a keeper path that anyone can call; 16 `Rebalanced` events were on chain as of 2026-10-03, all from our keeper.
Mocked: the stock tokens, USDG, the price feeds and, in V1, custody (mint and burn instead of swaps). `[V2-PENDING: update with the V2 contracts, the Live universe with real Paxos USDG if it shipped, the always-on keeper, and the contract verification status]`.

## What happens on mainnet?

Chainlink publishes 8-decimal, 24-hour-heartbeat feeds on Robinhood Chain mainnet for TSLA, AMZN, PLTR, AMD and USDG; there is no NFLX feed and no listed sequencer uptime feed (`docs/research/15-mainnet-path.md`).
Mainnet also needs per-asset staleness for a 24/5 market, a venue adapter because real Stock Tokens cannot be minted by a vault, and an independent audit; we have deployed nothing to mainnet.

## What if the oracle stalls?

In V1 every deposit, redeem and rebalance reverts with `StalePrice` once a feed is older than 24 hours, which means exits are blocked too; we observed exactly this on 2026-10-03 when all six mock feeds were about 50 hours old.
`[V2-PENDING: in V2 redeemInKind needs no oracle and no venue and is never paused, deposits and rebalances stop on stale prices, a guardian can pause them, and ops raises an alarm when a feed is older than 35 minutes]`.

## Why not ERC-4626?

ERC-4626 models one underlying asset; a Feng strategy is a multi-asset basket with USDG as the entry asset, a NAV that sums constituents (including other strategies), in-kind exits and rebalancing, which a literal 4626 vault cannot express (`docs/research/01-tech-stack.md`).
We kept the familiar surface (`deposit`, `redeem`, `previewDeposit`, `previewRedeem`, virtual-share inflation protection) so a 4626-style wrapper for USDG deposit and redeem remains possible.

## How is composability bounded?

The factory enforces `MAX_DEPTH = 2`: a constituent that is a Strategy Token must be a registered strategy that already exists and must itself be a leaf (no nested constituents); because vaults are immutable and a child must exist first, cycles cannot be created, and the app locks depth-2 tokens in the composer.
Valuation recurses at most one level (the parent calls the child's `previewRedeem`), so NAV cost and failure modes are bounded; this is the response to the nested-vault collapse of Stream Finance described in `docs/research/03-domain.md`.
