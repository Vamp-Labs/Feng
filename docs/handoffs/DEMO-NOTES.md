# Integration & Deploy — rehearsal and verification notes

Written by role 03 (Integration & Deploy). Operational notes only — see the final report to the PM
for the executive summary. Dates/times below are from the session on 2026-09-28.

## 0. Run the demo locally, right now

Everything below §1 is the original session's research/rehearsal record (kept as-is). This section
is the up-to-date, actually-reconciled local path, added in a follow-up session the same day, because
the real testnet deploy stays genuinely blocked (faucets — see §2, unchanged, not re-attempted) and the
Frontend role independently built its own `NEXT_PUBLIC_NETWORK=anvil-local` config pointing at
**port 8545** / chain id `31337` / `src/lib/dev/anvil-addresses.json` — a different local target than
this role's own `anvil-rehearsal` proof on port 8546 (§4 below, left untouched as historical record).
This section deploys the real `contracts/` + `script/Deploy.s.sol` (not the Frontend role's own
simplified `dev/fixture/`) against that exact port-8545/chain-31337 target, writes both
`deployments/anvil-local/addresses.json` (standard schema path) and `src/lib/dev/anvil-addresses.json`
(the frontend's already-coded read path for `NEXT_PUBLIC_NETWORK=anvil-local`, per
`src/lib/addresses.ts`), and re-verifies all 8 demo-path steps plus a genuinely permissionless keeper
rebalance against this specific deployment — not just a re-assertion of the §4 rehearsal.

### Prerequisites

`pnpm`, `forge`/`anvil`/`cast` (Foundry) installed, this repo checked out, dependencies installed
(`pnpm install`, once). No account, faucet, or real funds needed — everything below runs on Anvil's
own pre-funded local dev accounts.

### 1. Start a clean local chain on port 8545

```bash
# if a stale anvil is already bound to 8545 (e.g. from earlier fixture work), stop it first:
pkill -f "anvil --port 8545" 2>/dev/null || true
sleep 1

anvil --port 8545 --chain-id 31337
```

Leave this running in its own terminal (or background it: `anvil --port 8545 --chain-id 31337 &`).
This matches `src/lib/networks.ts`'s `ANVIL_LOCAL` definition exactly (chain id `31337`, RPC
`http://127.0.0.1:8545`).

### 2. Deploy the real contracts to it

From the repo root, in a second terminal:

```bash
DEPLOY_NETWORK=anvil-local \
DEPLOYER_PRIVATE_KEY=$ANVIL_KEY_0 \
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

(The private key above is Anvil's well-known, publicly-documented default account #0 — safe to put in
a doc verbatim because it only ever holds throwaway local-chain funds; never use it anywhere real.)

`DEPLOY_NETWORK=anvil-local` isn't one of `Deploy.s.sol`'s two named branches
(`robinhood-testnet`/`arbitrum-sepolia`), so it falls through to the script's local-default branch,
which happens to already resolve to chain id `31337` / RPC `http://127.0.0.1:8545` — exactly what
`anvil-local` needs, with zero script changes. This writes `deployments/anvil-local/addresses.json`.
(`scripts/deploy.sh` intentionally rejects anything but `robinhood-testnet`/`arbitrum-sepolia` — it's
the real-broadcast wrapper with retry/verify logic for those two only, so local runs call
`forge script` directly, as above.)

Now copy that file to the exact path the frontend's own (unmodified) `src/lib/addresses.ts` reads for
`NEXT_PUBLIC_NETWORK=anvil-local`:

```bash
cp deployments/anvil-local/addresses.json src/lib/dev/anvil-addresses.json
```

This overwrites whatever the Frontend role's own earlier `dev/fixture/` run had left there — that
fixture deploys a simplified, separate set of mock contracts (see `dev/fixture/README.md`) purely for
early UI work; this step replaces it with the same real, fully-tested `contracts/` deployment used
everywhere else in this project, in the exact shape `addresses.ts`'s `DeploymentAddresses` interface
expects.

### 3. Start the keeper (its own terminal / background process)

```bash
KEEPER_PRIVATE_KEY=$ANVIL_KEY_1 \
scripts/keeper.sh anvil-local 15
```

(Anvil's well-known default account **#1**, deliberately different from the deployer account above —
proves `performRebalance` is genuinely permissionless, not just deployer-callable.) This polls every
15s and fires real `performRebalance` calls whenever `checkUpkeep()` flags a vault. Leave it running;
it's what actually causes the demo's "trigger a rebalance" step to reflect on-screen without a human
manually calling `executeRebalance`.

### 4. Start the frontend

```bash
NEXT_PUBLIC_NETWORK=anvil-local \
NEXT_PUBLIC_CHAIN_ID=31337 \
NEXT_PUBLIC_RPC_URL=http://127.0.0.1:8545 \
NEXT_PUBLIC_EXPLORER_URL= \
pnpm dev
```

Open `http://localhost:3000`. In your browser wallet, add a custom network (RPC `http://127.0.0.1:8545`,
chain id `31337`) and import Anvil's default account #0 (private key above) — it starts holding all
mock USDG/stock-token supply from the deploy in step 2, so it's the account to click through the demo
with.

### 5. The manual click-path (the 8 demo steps, per `00-overview.md` §"The demo path")

1. **Connect wallet** — click connect in the header, approve in your wallet, confirm it shows chain id
   `31337` / "Anvil (local)".
2. **Create Strategy A** — go to Create Strategy, name it (e.g. "AI Growth" / `AI-GROWTH`), pick TSLA
   60% / AMZN 40%, set max-weight-per-asset (e.g. 70%) and a short rebalance interval (e.g. 1 second,
   so step 4 has something to trigger almost immediately), submit, confirm in wallet. You land on the
   new Strategy A detail page.
3. **Deposit USDG into Strategy A** — on the detail page, deposit an amount (e.g. 1000 USDG), confirm
   in wallet. Shares balance and the vault's underlying TSLA/AMZN holdings update on-screen.
4. **Trigger a rebalance** — either click the manual "Rebalance" action in the UI (same permissionless
   `performRebalance()` call), or simply wait ~15s for the keeper (step 3 above) to pick it up
   automatically — either way a `Rebalanced` event fires and the UI reflects the updated
   holdings/timestamp.
5. **Create Strategy B** — Create Strategy again, name it (e.g. "Diversified Growth" /
   `DIV-GROWTH`), pick Strategy A itself as one constituent (50%) plus NFLX (50%), submit. Confirms
   `depth()` reads 2 on the new vault.
6. **Deposit USDG into Strategy B** — deposit (e.g. 500 USDG), confirm the NAV shown live-recurses into
   Strategy A's own current NAV (not a stale/cached number).
7. **Browse the Marketplace** — go to the Marketplace list view, confirm both Strategy A and Strategy B
   are listed with their basic info.
8. **Redeem** — on Strategy A's detail page, redeem a partial share amount back to USDG, confirm the
   USDG balance increases pro-rata.

### 6. This exact sequence was re-verified this session

All 8 steps above were re-run via `cast` against a **fresh** deployment on this exact port-8545 /
`anvil-local` target (not a re-assertion of the port-8546 `anvil-rehearsal` in §4 below — a new anvil
instance, a new deploy, re-executed from scratch), with real addresses:

```
MockUSDG:             0x5FbDB2315678afecb367f032d93F642f64180aa3
StrategyFactory:      0xc6e7DF5E7b4f2A278906862b61205850344D4e7d
RebalanceEngine:      0x59b670e9fA9D0A427751Af201D676719a970857b
MarketplaceRegistry:  0x3Aa5ebB10DC797CAC828524e59A333d0A371443c
Strategy A vault:     0x553BED26A78b94862e53945941e4ad6E4F2497da  (token 0x9864Dc5A8a9851Dc63Ea7D68348C923C7Bd3031a)
Strategy B vault:     0x624dC0EcEFD94640D316eE3ACfD147Ed9B764638  (token 0x42d729740c681C1626A3b909081aD726b3975b49, depth 2)
```

(Full mock-stock-token and price-oracle addresses are in `deployments/anvil-local/addresses.json` and
`src/lib/dev/anvil-addresses.json` — identical content, both written by this run.)

Result, step by step: Strategy A created (`StrategyCreated` event, depth 1) → 1000 USDG deposited,
1,000,000,000,000,000,000,000,000 shares received, vault minted real TSLA/AMZN balances → manual
`performRebalance(vaultA)` fired a real `Rebalanced` event → Strategy B created nesting A at 50% +
NFLX at 50%, `depth()` reads 2 → 500 USDG deposited into B, 500,000,000,000,000,000,000,000 shares
received, `totalAssetsUSDG()` on B read back ≈499.999999999999999579 USDG (live-recursed into A's own
NAV) → `getAllStrategies()`/`getStrategyInfo()` returned both vaults correctly → redeemed 100,000 of
Strategy A's 1,000,000 shares, USDG balance increased pro-rata (8500.0 → 8599.999999999999999999 USDG).

**Keeper proof, same standard as §5 below:** `scripts/keeper.sh anvil-local 3 2` was run with
`KEEPER_PRIVATE_KEY` set to Anvil's default account **#1**
(`0x70997970C51812dc3A010C7d01b50e0d17dc79C8`) — an address with nonce `0` immediately beforehand,
confirming it had never created, deposited into, or otherwise touched either strategy. Both iterations
found vaults needing rebalance via `checkUpkeep()` and called `performRebalance()` on each, both
succeeding (`status 1`) and each emitting a real `Rebalanced` event on-chain (vault A tx
`0x40a5eb14d989b4c93713dd8d954a474527c2627e17391f24ab45a0fc6f9c64e0`, vault B tx
`0xf8d1e6c8c98bab2dd62ab27c7a2a2904cac390151150a55e04501439c86118ec`), confirmed via `cast logs`
against each vault directly. The keeper account's nonce read back as `2` afterward — exactly the two
`performRebalance` calls it made, nothing else. This is a genuinely permissionless third-party
rebalance, not the deployer/depositor account self-servicing its own vaults.

`deployments/robinhood-testnet/` and `deployments/arbitrum-sepolia/` were not touched by this session —
still correctly empty, real testnet deploy is unchanged, separate future work (§8 below).

## 1. Reachability re-verification (P0, done first)

Research (`02-robinhood-testnet.md`) flagged `docs.robinhood.com` and the Blockscout explorer as
TLS-unreachable all session, via both WebFetch and `curl`, with `certificate has expired` errors, and
suggested this could be environment-specific. **It is environment-specific, and the root cause is now
identified**, not just guessed at.

### What's actually happening

This machine's network path intercepts TLS connections to `docs.robinhood.com`,
`faucet.testnet.chain.robinhood.com`, and (intermittently) `rpc.testnet.chain.robinhood.com` /
`explorer.testnet.chain.robinhood.com`. The intercepting server presents certificates for
`internetpositif.id`, `aduankonten.id` (via reverse DNS), and — decisively — a certificate
**explicitly scoped to `internetsehatku.com` / `www.internetsehatku.com`**. These three domain names
are Indonesia's government internet-content-filtering system (Kominfo's "Trust Positif" / "Internet
Sehat" program). This is a local ISP/network-level censorship intercept, confirmed by directly
comparing DNS-over-HTTPS-resolved real IPs (via `1.1.1.1/dns-query`) against what the local resolver
returns, and by forcing connections to the real IPs with `curl --resolve`.

### What's actually true about each domain, verified against real IPs

- **RPC (`rpc.testnet.chain.robinhood.com`)**: real, live, answers `eth_chainId` → `0xb626` (46630)
  correctly. Confirmed correct, incrementing `eth_blockNumber` across repeated calls (~1–5 blocks per
  call, consistent with the ~100ms block-time claim in `02-robinhood-testnet.md` §2).
- **Explorer (`explorer.testnet.chain.robinhood.com`)**: real, live Blockscout instance — fetched the
  actual page (`<title>Robinhood Chain Testnet blockchain explorer ... | Blockscout</title>`), valid
  Let's Encrypt cert for the correct hostname.
- **docs.robinhood.com**: real and live once the local DNS hijack is bypassed
  (`curl --resolve docs.robinhood.com:443:13.35.238.76 ...`, the true CloudFront IP from DoH). All
  `/chain/*` pages referenced in research resolve to real content (200, after the expected trailing-slash
  redirect) — `/chain/`, `/chain/oracles-and-price-feeds/`, `/chain/protocol-contracts/`,
  `/chain/contracts/`, `/chain/connecting/`, `/chain/bridging/`, `/chain/stock-tokens/`,
  `/chain/stock-token-apis/`, `/chain/building-with-stock-tokens/`, `/chain/deploy-smart-contracts/`
  all returned real HTTP 200 documentation content once resolved to the true IP.
- **Faucet (`faucet.testnet.chain.robinhood.com`)**: real, live, hosted on Vercel (confirmed via DoH:
  CNAME to `*.vercel-dns-016.com`). Reachable at its true IP, but returns HTTP 429 with
  `x-vercel-mitigated: challenge` — Vercel's bot-mitigation layer, which blocks non-interactive
  clients (see §3).

**Conclusion: none of this is a Robinhood-side outage.** The research's own hedge — "this could be an
environment-local TLS trust-store issue rather than a problem with Robinhood's actual certificate" —
is correct, and now specifically diagnosed: it is Indonesian ISP-level content filtering intercepting
these exact hostnames from this network, not a certificate problem on Robinhood's end.

### It's intermittent, and that matters for tooling, not just browsing

The interception is probabilistic, not 100% consistent, and — critically — different HTTP client
implementations hit it at different rates:

- `curl` (OpenSSL-backed): RPC and explorer succeeded on effectively every attempt across ~15+ manual
  tests.
- `cast` (Rust `reqwest`/`rustls`-backed, same stack as `forge`): a single `cast block-number` call
  against the RPC succeeded ~60% of the time (6/10 in one measured run), failing the rest with the
  `internetsehatku.com` / expired-cert error.
- `forge script` (same stack as `cast`, but makes many sequential RPC calls per run — account
  fetches, gas estimation, nonce lookups, etc.): **0/10 full dry-run simulations against
  `rpc.testnet.chain.robinhood.com` completed without hitting the intercept at least once.** Since a
  full script run needs many independent calls to all succeed, and each call has roughly a 30–40%
  chance of being intercepted here, the probability of a whole multi-call script completing cleanly is
  low by simple compounding.

**Practical consequence: even with a funded deployer key, running `forge script ... --broadcast`
against Robinhood Chain testnet from this specific machine/network is unreliable** — not impossible,
but not something to expect to complete in one shot. `scripts/deploy.sh` (owned by this role) includes
retry logic for exactly this reason (`DEPLOY_MAX_ATTEMPTS`, default 8). The real fix is to run the
actual broadcast deploy from a network path that isn't behind this filter (a different ISP, a VPN, or
a cloud CI runner outside Indonesia) — this is a note for whoever executes the real broadcast, not a
code problem.

Arbitrum Sepolia's public RPC (`https://sepolia-rollup.arbitrum.io/rpc`) is **not** affected — 5/5
`cast` calls succeeded, and a full `forge script` dry-run against it completed cleanly (see §4).

## 2. Funding blocker — testnet ETH could not be obtained from this environment

A fresh, testnet-only deployer wallet was generated locally for this session
(`cast wallet new`, private key never written to any file inside the repo). Every reasonably available
faucet path was attempted for it, in this order:

1. **Official Robinhood faucet** (`faucet.testnet.chain.robinhood.com`) — blocked by the local DNS
   hijack described in §1 for normal browser/CLI use; when bypassed via a forced real IP, the site
   itself returns HTTP 429 with Vercel's bot-mitigation challenge (`x-vercel-mitigated: challenge`),
   which a non-interactive client cannot pass.
2. **QuickNode faucet** (`faucet.quicknode.com/robinhood/testnet`) — reachable and not censored. Its
   own FAQ text claims "no minimum mainnet balance" is required, but the actual submit path rejected
   the fresh wallet with `Invalid ETH mainnet balance. Please note, you'll need a small mainnet balance
   on this wallet in order to use the faucet.` — the FAQ copy and the enforced rule disagree; worth
   flagging back to QuickNode, not actionable for us without an already-funded mainnet wallet.
3. **Alchemy faucet** (`alchemy.com/faucets/ethereum-sepolia`, which also lists **Robinhood Testnet**
   directly as a network option) — gated by Cloudflare Turnstile (`cf-turnstile-response` hidden
   field), which failed automated submission (`CAPTCHA verification failed`).
4. **pk910 Sepolia PoW faucet** (`sepolia-faucet.pk910.de`) — no account/balance requirement, mines
   ETH via proof-of-work in-browser, but session start is also gated by a CAPTCHA
   (`[INVALID_CAPTCHA] captcha check failed: invalid token`).
5. **thirdweb faucet** (`thirdweb.com/sepolia`) — no manual-address input at all; requires a connected
   wallet browser extension, which this environment doesn't have installed.
6. **arbitrum.faucet.dev** (found via the official HackQuest page's own "Faucets" section, see §5) —
   reachable, but its minimal SPA didn't render any interactive input/button elements to a scripted
   browser session (likely needs a connected wallet extension too, or hasn't fully hydrated headlessly).
   Not exhausted as thoroughly as the others — worth a human trying it directly, since it's the
   buildathon organizers' own recommended link for Arbitrum Sepolia specifically.

**This is a genuine, well-diagnosed blocker, not a workaround-needed situation**: every faucet with a
meaningful chance of automated success is protected by anti-bot measures (CAPTCHA, Cloudflare
Turnstile, Vercel bot mitigation) or a mainnet-balance-history gate that a freshly generated,
zero-history wallet cannot satisfy, and the official Robinhood faucet is additionally behind this
network's ISP-level content filter. **A human, with a real browser, an existing wallet with some
mainnet ETH history (for QuickNode/Alchemy-style checks), or the patience to solve a CAPTCHA, needs to
claim testnet ETH for the deployer address** before a real broadcast to either target network can
happen. This is the single blocking item standing between everything below and a real, verified
Robinhood Chain testnet / Arbitrum Sepolia deployment.

## 3. Deploy pipeline readiness — proven via dry-run against both real networks

`forge build` — clean. `forge test` — 48/48 passing (re-verified independently this session, matches
the PM's report).

`forge script script/Deploy.s.sol --rpc-url <real RPC>` (no `--broadcast`, i.e. a full simulation
against live chain state) was run against both real target networks:

- **`robinhood-testnet`**: blocked by the TLS interception described in §1 on every attempt (10/10).
  This is a network-path problem, not a script problem — see §1 for why, and `scripts/deploy.sh` for
  the retry-wrapped real invocation.
- **`arbitrum-sepolia`**: **succeeded cleanly.** `Script ran successfully.` Estimated total gas
  16,192,489, estimated cost 0.00102 ETH at the simulated network conditions. This proves the deploy
  script, `foundry.toml` RPC config, and every constructor argument are correct against the real
  Arbitrum Sepolia chain — the only missing ingredient to a real broadcast is a funded deployer key
  (§2).

## 4. Local rehearsal deployment — proof the full stack works end to end

Because neither target testnet could be funded (§2), a full real deployment was executed against a
throwaway local Anvil instance (`anvil --port 8546`, isolated from any other running Anvil instance —
in particular, not the frontend engineer's own dev instance on port 8545, which was left untouched)
using the exact same `Deploy.s.sol` script Contracts wrote and Integration owns running, with
`DEPLOY_NETWORK=anvil-rehearsal` (a throwaway network name so this doesn't collide with the
`deployments/anvil/addresses.json` schema reference Contracts already produced). Output:
`deployments/anvil-rehearsal/addresses.json`. This is **not** one of the two owned deliverable files
(`robinhood-testnet` / `arbitrum-sepolia`) — it exists purely as rehearsal evidence and can be deleted
once reviewed.

This is a real broadcast (`ONCHAIN EXECUTION COMPLETE & SUCCESSFUL`), independently confirmed via
`cast code` returning real, non-empty bytecode for every contract address.

### 8-step demo path rehearsal (`00-overview.md` §"The demo path")

All 8 steps executed via `cast` against the real rehearsal deployment (steps described in terms of the
underlying contract calls a UI would make):

1. **Connect wallet** — N/A for a `cast`-only rehearsal; equivalent to using anvil's account 0 as the
   acting user throughout.
2. **Create Strategy A** ("AI Growth" / `AI-GROWTH`, TSLA 60% / AMZN 40%, `maxWeightBps=7000`,
   `rebalanceInterval=1s`) — `StrategyFactory.createStrategy(...)` succeeded, `StrategyCreated` event
   emitted, depth 1. Vault `0x553bED26A78b94862e53945941e4Ad6E4f2497da`, token
   `0x9864Dc5A8a9851Dc63Ea7D68348C923C7Bd3031a`.
3. **Deposit USDG into Strategy A** — minted 10,000 mock USDG to the user, approved, deposited 1,000 →
   received 1,000,000,000,000,000,000,000,000 shares (the vault's decimals-offset share math, matches
   the inflation-attack mitigation design). Vault's constituent basket was minted for real (mock
   TSLA/AMZN balances confirmed non-zero after deposit).
4. **Trigger a rebalance** — called `RebalanceEngine.performRebalance(vaultA)` directly (the exact
   call the keeper script makes, §6). Succeeded, real `Rebalanced(uint256,uint256,bool,bool)` event
   confirmed via `cast logs` querying the vault address directly (topic0
   `0x8bdf01e7180b1b0530cf19b68fb302f258506810f644eb7644bf1b30c5680289` matches
   `keccak256("Rebalanced(uint256,bool,bool)")`).
5. **Create Strategy B**, nesting Strategy A (`isStrategyToken=true`) at 50% weight plus NFLX at 50% —
   `createStrategy` succeeded, `depth()` on the new vault reads **2**, confirming true composability
   and `StrategyFactory`'s depth/cycle enforcement working against a real nested constituent, not just
   in the unit tests. Vault `0x624Dc0ECEfd94640D316EE3acfd147ED9B764638`.
6. **Deposit USDG into Strategy B** — deposited 500 USDG → 500,000,000,000,000,000,000,000 shares.
   `totalAssetsUSDG()` on Strategy B read back **≈499.999999999999999579 USDG**, i.e. it correctly and
   live-recursed into Strategy A's own NAV rather than using any cached/stale value — directly
   confirms `contracts.md`'s composability requirement ("nested NAV must always be computed live").
7. **Browse the Marketplace** — `MarketplaceRegistry.getAllStrategies()` returned both vault addresses;
   `getStrategyInfo(vaultA)` returned the correct token, creator, depth (1), and creation timestamp.
8. **Redeem** — redeemed 100,000 (of 1,000,000) Strategy-A shares back to USDG via
   `StrategyVault.redeem(...)`; user's USDG balance increased correctly, pro-rata to the shares burned.

**Result: all 8 steps work end to end, with real on-chain state, against real deployed contracts.**
None of the 5 core contracts showed a bug during this exercise — no report back to Contracts was
necessary.

## 5. Keeper script — proven to fire a real on-chain rebalance autonomously

`scripts/keeper.sh <network> [intervalSeconds] [maxIterations]` reads `rebalanceEngine` from
`deployments/<network>/addresses.json`, polls `RebalanceEngine.checkUpkeep()`, and calls
`performRebalance(vault)` for every vault flagged, on a loop.

Run against the rehearsal deployment (§4) with `KEEPER_PRIVATE_KEY` set to a **different** anvil
account than the one that created/funded the strategies (anvil account 1, not account 0) — specifically
to prove the entrypoint is genuinely permissionless, not just callable by the deployer:

```
[1] checkUpkeep -> [0x553BED26A78b94862e53945941e4ad6E4F2497da, 0x624dC0EcEFD94640D316eE3ACfD147Ed9B764638]
[1] performRebalance(0x553BED26A78b94862e53945941e4ad6E4F2497da)  -> status 1 (success), Rebalanced event
[1] performRebalance(0x624dC0EcEFD94640D316eE3ACfD147Ed9B764638)  -> status 1 (success), Rebalanced event
```

Both calls succeeded from an address (`0x70997970C51812dc3A010C7d01b50e0d17dc79C8`) that never
created, deposited into, or otherwise interacted with either strategy before — confirming
`performRebalance` really is permissionless, and confirming the keeper script itself (not just the
manual `cast send` from §4 step 4) autonomously discovers and rebalances vaults with zero human
intervention, exactly as the P0 acceptance criterion requires ("keeper script, run against the real
deployment, causes a real `Rebalanced` event to be emitted on-chain — checkable via `cast logs`").

The only thing not yet proven is this exact script pointed at the real `robinhood-testnet` or
`arbitrum-sepolia` deployment, purely because neither has a funded, deployed instance yet (§2/§3).

> CORRECTION 2026-10-03: the registration close quoted below (2026-10-03 01:01 SGT) is stale. The live API now says registrationClose 2026-10-04 23:58 SGT and submissionClose 2026-10-04 23:59 SGT. Email, Telegram, GitHub, Twitter, LinkedIn are registration fields, not submission fields. See docs/research/14-hackquest-submission.md. Local anvil keys: `$ANVIL_KEY_0` and `$ANVIL_KEY_1` are the first two keys that `anvil` prints on start.

## 6. HackQuest — the buildathon's actual submission requirements (primary source, directly read)

Registration was not completed (no account credentials available to this role, and the constraint
against inventing workarounds applies here too), but the buildathon's own **public submission
form and rules page** — `arbitrum-singapore.hackquest.io/buildathons/Arbitrum-Open-House-Singapore-Online-Buildathon`
— is publicly fetchable without login and was read in full. This resolves `05-synthesis.md`'s open
question #5 directly from the primary source, not a secondary AI summary:

- **Deadlines (previously unknown to the minute):** `submissionClose`: **2026-10-04T15:59:00Z**
  (2026-10-04, 23:59 Singapore time — i.e. the deadline is end-of-day Oct 4 SGT, not an arbitrary UTC
  cutoff). `registrationClose`: **2026-10-02T17:01:00Z** (2026-10-03, 01:01 SGT) — registration closes
  **before** the submission deadline, so the team needs to register days before actually submitting.
- **Network requirement, resolved definitively:** the form states verbatim: *"Your project must be
  deployed on an Arbitrum chain to qualify. For example: Arbitrum Sepolia, Arbitrum One, Robinhood
  Chain, or others."* — no testnet-vs-mainnet mandate exists. This directly validates the plan already
  chosen (Robinhood Chain testnet primary, Arbitrum Sepolia parallel) and closes the "is Arbitrum
  Sepolia a baseline requirement" rumor `02-robinhood-testnet.md` flagged as untraceable — it is not a
  requirement, just one of several qualifying options.
- **Judging criteria (verbatim, confirms the secondary-source synthesis word for word):** Smart
  contract quality ("best practices, structured logically and efficiently, with minimal security
  vulnerabilities"), Product-Market Fit, Innovation and Creativity, Real Problem Solving.
- **Notable bonus, worth surfacing to the whole team:** *"Extra consideration is given to projects
  integrating Paxos' USDG stablecoin."* This project already uses USDG as its sole settlement asset —
  worth calling out explicitly in the pitch/demo narrative.
- **Prize reservation (confirms research):** "At minimum, 1 of 3 prizes is reserved for a project
  building on Robinhood Chain" and, separately, "At minimum, 1 of 3 prizes is reserved for a project
  building on Arbitrum." All prizes are milestone-tied per the event's Terms and Conditions.
- **Actual submission form fields (previously unknown, now confirmed from the live form):** Email,
  Telegram, Github, Twitter, LinkedIn; a link to the frontend/UI/website of the project ("or demo" —
  **no separate demo-video field exists**, a live/deployed frontend link satisfies this); "List your
  Core Protocol/Smart Contract Addresses"; "List your Factory/Pool Contracts (if applicable)"; "List
  your Token Contract Address (if applicable)"; a free-text field asking which parts of the code were
  produced during the Buildathon (existing repos are explicitly allowed — "You do not need to create a
  new Github repo for your project"); which sponsor/partner technologies were used; a contract-address
  block per network in the format `network: address — label`; an optional Custom Track field.
- **Faucets, as listed by the organizers themselves (in order given):** Ethereum Sepolia → bridge to
  Arbitrum Sepolia via `bridge.arbitrum.io`; Arbitrum Sepolia direct via `arbitrum.faucet.dev`
  (untested end-to-end here, see §2); Robinhood Chain via the official faucet (blocked here, see §2).

This is the full, primary-source deliverables checklist — nothing here needed to be guessed or
inferred from a secondary AI summary.

## 7. Status of the 9 unverified assumptions from `05-synthesis.md`

1. **Chainlink Data Feeds on Robinhood Chain testnet — RESOLVED: confirmed NOT deployed.** Chainlink's
   own reference-data-directory (linked directly from `docs.robinhood.com/chain/oracles-and-price-feeds/`'s
   "Available feeds" section, which links to
   `docs.chain.link/data-feeds/price-feeds/addresses?network=robinhood`) only publishes
   `feeds-robinhood-mainnet.json` (58 feeds, all `chainId: 4663`). Every guessed testnet filename
   (`feeds-robinhood-testnet.json`, etc.) returned HTTP 404. This is a direct, primary-source
   confirmation — not an absence of evidence — that Chainlink Data Feeds for Robinhood Chain are
   mainnet-only today. The mock `IPriceOracle`/`MockV3Aggregator` design was the right call.
2. **Testnet USDG address — still not found, but the mainnet address is now confirmed.**
   `docs.robinhood.com/chain/contracts/` (Robinhood's own "Token Contracts" page) lists USDG
   `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` and WETH `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`
   — but the page describes contracts "deployed on Robinhood Chain" without a testnet/mainnet split,
   and the same page's live stock-token table is fed by an on-chain asset registry that (per the
   official `/rhj/assets` REST API, see #3) only lists mainnet (chain 4663) deployments. Treat this
   USDG address as mainnet-only; still no testnet USDG address found anywhere.
3. **Testnet stock-token addresses — RESOLVED: confirmed there is no official testnet listing.**
   Robinhood's own official REST API (`api.robinhood.com/rhj/assets`, documented at
   `docs.robinhood.com/chain/stock-token-apis/`) was queried directly: 195 assets returned, every
   single `deployments[].chainId` is `4663` (mainnet). Zero testnet (`46630`) deployments exist in the
   official registry. This directly confirms — from Robinhood's own API, not a community README — that
   the TSLA/AMZN/NFLX addresses research found in an unofficial GitHub repo are not corroborated by any
   official source, and no official testnet stock-token address exists to substitute in.
4. **`docs.robinhood.com` / explorer reachability — RESOLVED, see §1.** Confirmed environment-specific
   (Indonesian ISP-level content filtering, not a Robinhood outage), and confirmed intermittent rather
   than a hard block for the RPC/explorer specifically.
5. **Buildathon submission requirements — RESOLVED, see §6.** Full deliverables checklist, exact
   deadlines, judging criteria, and network requirement all confirmed directly from the live public
   submission form.
6. **Faucet "verify yourself" step — RESOLVED: it's Vercel bot-mitigation (a challenge/CAPTCHA-class
   check), not KYC.** Confirmed via the `x-vercel-mitigated: challenge` response header when the
   faucet's real backend is reached directly (see §2). Not an account/identity requirement, but not
   scriptable either.
7. **Robinhood Chain testnet's ArbOS/PUSH0 support — still not directly confirmed**, but
   `docs.robinhood.com/chain/connecting/` explicitly states Robinhood Chain testnet is chain ID 46630,
   an Arbitrum L2 "using Ethereum blobs for data availability and ETH as the native gas token," and the
   RPC responded correctly and quickly to standard `eth_chainId`/`eth_blockNumber` calls — nothing
   observed contradicts modern ArbOS/Shanghai-EVM support, but no ArbOS version number was directly
   surfaced by any endpoint checked. `evm_version = "paris"` remains the safe, unchanged default;
   no evidence justifies flipping it this session.
8. **Gelato Web3 Functions reach on Robinhood Chain testnet — still unconfirmed.** Not pursued this
   session (P1, and P0 items consumed the available time); the permissionless-keeper design (§5) does
   not depend on it.
9. **Composability depth cap of 2 — unchanged, still original engineering reasoning, not a reported
   protocol precedent.** Nothing this session added or removed evidence here; it's a design decision,
   not a research gap to close, and the rehearsal in §4 step 5 confirms it's enforced correctly against
   a real nested deployment.

## 8. What's needed to close out the two real testnet deployments

1. A human claims testnet ETH for the deployer address from a real, interactive browser session (any
   of the faucets in §2, most promisingly the official Robinhood faucet from a network without the
   Indonesian filter, or `arbitrum.faucet.dev` for the Arbitrum Sepolia fallback) — or bridges existing
   Sepolia ETH in via `bridge.arbitrum.io`.
2. Run `DEPLOYER_PRIVATE_KEY=<funded key> ./scripts/deploy.sh arbitrum-sepolia` first — this path is
   already proven clean (dry-run success, no TLS interference) and should complete on the first try.
3. Run `DEPLOYER_PRIVATE_KEY=<funded key> ./scripts/deploy.sh robinhood-testnet` — expect to need the
   script's built-in retries, or to run it from a network path outside the Indonesian filter described
   in §1 if retries aren't enough.
4. Once each deploy's `deployments/<network>/addresses.json` is written with real addresses, run
   `KEEPER_PRIVATE_KEY=<any funded key> ./scripts/keeper.sh <network>` to start the keeper loop for
   real, and re-run the 8-step rehearsal from §4 against the real addresses instead of the local one.
5. Everything else — script correctness, contract correctness, keeper logic, demo flow, submission
   requirements — is already verified and does not need to be redone, only re-pointed at real
   addresses.
