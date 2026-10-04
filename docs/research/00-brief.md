# 00 — Research Brief

## Project facts (from PRD.md)

**Product, one paragraph.** Composable Strategy Marketplace: a protocol where anyone can define a
rule-based investment strategy over tokenized stocks (asset weights, rebalancing rules, constraints
like max weight / max asset count), have the protocol mint that strategy as an ERC-20 "Strategy
Token" backed by an ERC-4626-inspired vault, deposit/redeem the underlying assets (or USDG) against
that token, have the vault auto-rebalance per the encoded rules, nest Strategy Tokens as constituents
of other Strategy Tokens (composability), and discover/mint strategies through a marketplace. The
pitch is "investment strategies as composable onchain primitives," not "ETFs on a blockchain."

**Target chain / network.** Robinhood Chain. PRD says "testnet/mainnet" (PRD §4 success metrics
table) but **this run's explicit scope is testnet only** — the demo, deployment, and every handoff
target Robinhood Chain's testnet, not mainnet.

**Sponsors / SDKs / APIs.** Robinhood Chain itself (an Arbitrum-ecosystem chain — Arbitrum Open
House Singapore Buildathon, Robinhood Chain track), Arbitrum tooling (Orbit stack is the working
assumption pending Track B confirmation), USDG (the PRD names USDG explicitly as a supported
deposit/redeem asset — issuer and testnet availability unconfirmed, Track B), tokenized-stock assets
on Robinhood Chain (unconfirmed which specific tickers/contracts exist on testnet, Track B), an
oracle for pricing tokenized stocks (unnamed in the PRD — Track B/A to find what is actually
available on the testnet).

**Required integrations.** ERC-20 (Strategy Tokens), ERC-4626-inspired vault, an oracle for stock
pricing, a keeper/automation mechanism for rebalancing, USDG deposit/redeem path.

**Frameworks the PRD already fixes.** Token standard ERC-20, vault pattern "ERC-4626 inspired (or
custom vault)" (PRD §8) — left open, Track A resolves it. No frontend framework is fixed by the PRD;
this PM's standing rule fixes Next.js for any frontend role regardless.

**Deadline.** Buildathon timeline in PRD §11 is a generic 10-day plan (Day 1–3 core contracts, Day
4–5 composability, Day 6–8 frontend, Day 9–10 polish/demo) with no absolute date attached. Treat as
directional, not a hard date; flag as an open question for the user at the gate if a real event date
is needed for pacing.

**Judging criteria.** PRD §12 "Success Definition for Hackathon": live on Robinhood Chain, rule-based
strategies (not static baskets) clearly demonstrated, true composability (strategy inside strategy)
shown, a polished understandable demo, the "composable primitives" narrative communicated. No
external/official judging rubric is in the repo — Track C searches for the buildathon's own public
judging criteria if published.

## Research tracks

### Track A — Tech stack — `docs/research/01-tech-stack.md`

Questions:
- Foundry vs Hardhat for this contract set (StrategyFactory, StrategyVault, RebalanceEngine/Keeper,
  Marketplace Registry) — which fits a fast-moving hackathon build better, current tooling maturity
  for each on Arbitrum Orbit chains.
- ERC-4626: is it directly usable as the StrategyVault base, or does the "composable, multi-asset,
  rule-constrained" requirement in PRD §3/§8 force a custom vault (PRD explicitly leaves this open:
  "ERC-4626 inspired (or custom vault)")? What do comparable multi-asset vault implementations
  (OpenZeppelin's ERC-4626 extensions, existing index-token protocols) do differently from
  single-asset ERC-4626, at current library versions.
- Keeper/automation options that work on an Arbitrum-Orbit-family chain today for the
  RebalanceEngine: Chainlink Automation, Gelato, OpenZeppelin Defender, or a manual/permissionless
  keeper pattern — current availability, cost, and setup effort on an Orbit testnet specifically.
- Oracle library/pattern options in the abstract (Chainlink, Pyth, RedStone) and what each requires
  to integrate — cross-reference against Track B's finding of what is actually deployed on Robinhood
  Chain testnet.
- Composability/nesting: known gas and re-entrancy hazards when a Strategy Token can hold other
  Strategy Tokens as vault constituents (PRD §10 risk: "Nested strategy complexity"); how existing
  index-token protocols cap composition depth.
- Current (2026) OpenZeppelin Contracts version compatible with Solidity/Foundry, and current
  Solidity compiler version recommended for Arbitrum Orbit chains.

Output: `docs/research/01-tech-stack.md`. PRD lines: §3 (Strategy Token concept), §6.1 (must-have
features), §8 (Technical Requirements — Blockchain, Core Components, Key Technical Considerations),
§10 (Risks).

### Track B — Robinhood Chain testnet — `docs/research/02-robinhood-testnet.md`

This is the track the user asked for explicitly and it gates whether the project can demo at all.
Every finding here either has a citable source (official docs, block explorer, faucet page, GitHub)
or is flagged as an open question — never guessed.

Questions:
- Robinhood Chain testnet identity: chain ID, RPC endpoint(s) (public and/or private/allowlisted),
  block explorer URL, native/gas token.
- Is Robinhood Chain built on the Arbitrum Orbit stack (as the buildathon track name implies)? If so,
  what does that fix (settlement layer, fraud proof / validity proof config, data availability
  choice) and does it change how contracts are deployed/verified versus plain Arbitrum.
- Faucet: how to get testnet gas token; any allowlist, KYC, or buildathon-specific faucet access.
- Docs/SDK: official developer docs, GitHub org/repo, any Foundry/Hardhat starter template Robinhood
  or Arbitrum provides for this chain specifically.
- Testnet tokenized-stock assets: which tokenized equities (if any) exist as deployed testnet
  contracts, their addresses/symbols, and how a builder mints/obtains test amounts of them.
- USDG on this testnet: is USDG (or a testnet-equivalent stablecoin) deployed, its contract address,
  and how to mint/obtain test amounts. If USDG itself is not available on this testnet, identify the
  closest testnet-equivalent stable asset and flag the gap explicitly.
- Price oracles live on this testnet: which oracle networks (Chainlink, Pyth, RedStone, a
  Robinhood/Arbitrum-run oracle) have feeds for the tokenized stocks on this testnet, feed addresses
  if published.
- Any known deployed contracts relevant to reuse or integration (DEXs, bridges, existing vault
  standards deployed by the chain team).
- Bridging: how assets get onto this testnet from Arbitrum Sepolia or Ethereum Sepolia, if relevant,
  and any known quirks/limits (block gas limit, contract size limit, rate limits, sequencer
  behavior).
- Buildathon submission requirements tied specifically to testnet deployment: does the Arbitrum Open
  House Singapore Buildathon (Robinhood Chain track) require a specific testnet, a specific
  submission format, a deployment addresses list, a demo video, verified contracts, etc. — search
  for the event's own public rules page.

Every item that cannot be found from an official/primary source must be written into
`## Assumptions and open questions` with the exact searches attempted, not silently left out.

Output: `docs/research/02-robinhood-testnet.md`. PRD lines: user's explicit testnet instruction
(this session), §4 (Live deployment metric), §6.1 (USDG Support), §8 (Blockchain: Primary Robinhood
Chain; Oracle integration).

### Track C — Domain — `docs/research/03-domain.md`

Questions:
- Comparable products: on-chain index/basket protocols with composable or nested tokens — Index
  Coop, TokenSets/Set Protocol, Enzyme Finance, Sommelier, Percentage Protocol, any tokenized-stock
  index primitive — what they got right/wrong on rebalancing, redemption, and composability, at
  current (2026) state.
- Check the PRD's core assumptions against evidence: is "Strategy Token as composable primitive"
  actually novel versus what exists today; are there known failure modes of nested/composable vault
  tokens (e.g., circular composition, redemption liquidity when a constituent is illiquid) that the
  PRD's §10 risks table doesn't cover.
- Arbitrum Open House Singapore Buildathon: official event page, Robinhood Chain track description,
  any published judging rubric or track-specific prizes, submission deadlines, and whether the event
  requires testnet vs mainnet deployment (cross-check against Track B).
- What "Robinhood Chain" is as a product/chain in the market (who runs it, its stated purpose,
  tokenized-equities focus) as far as it affects strategy/positioning, not just plumbing (plumbing is
  Track B).

Output: `docs/research/03-domain.md`. PRD lines: §1 (Positioning), §2 (Problem Statement), §5 (Target
Users), §12 (Success Definition), and the buildathon name in the header.

## Tracks skipped, and why

- **Design system** — skipped. The repository contains no HTML, frontend code, or design assets of
  any kind (only `PRD.md`); there is nothing to inventory. The frontend role's handoff will instead
  define a from-scratch minimal design direction, since there is no existing visual reference to
  follow.
- **Repo audit** — skipped as its own dispatched track. The repository was confirmed directly
  (`find` to depth 3) to contain only `PRD.md`; it is not a git repo and has no `package.json`, no
  source directories, no config. This is a greenfield build — recorded here instead of dispatching an
  agent to re-confirm it.
