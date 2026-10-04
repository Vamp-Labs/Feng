# 03 — Integration & Deploy Engineer

## Context — read first

- `docs/research/02-robinhood-testnet.md` — **full read, this is your primary source.** Chain
  identity, faucet, docs/SDK gaps, testnet asset/oracle gaps, bridging, and — critically — the
  operational finding that `docs.robinhood.com` and the Blockscout explorer were TLS-unreachable from
  the research environment all session. Your first task verifies whether that's still true.
- `docs/research/05-synthesis.md` — full read, especially "Unverified assumptions that still stand"
  (9 items) — this role's job is to close as many of those as possible before Day 6, and to execute
  the config-driven fallback plan (Arbitrum Sepolia) if Robinhood Chain testnet is genuinely blocked.
- `docs/research/01-tech-stack.md` §3 (keeper/automation), §4 (oracle), §6 (Solidity/ArbOS version) —
  what you're verifying against the real chain.
- `docs/handoffs/contracts.md` — the `addresses.json` schema you populate, the env var names you
  template (never fill with real values in a committed file).
- `docs/handoffs/00-overview.md` §"The demo path" — what your end-to-end rehearsal must prove works.

## Tools — skills and MCP

No skill or MCP server was installed specifically for this role (`docs/research/06-tooling.md`
§Rejected explicitly covers why: Blockscout's official MCP needs a user-supplied API key and
unconfirmed coverage of this testnet; several community Foundry/EVM RPC MCP servers were rejected as
redundant or stale). **Use `cast` directly via Bash** — `cast call`, `cast receipt`, `cast logs`,
`cast code`, `cast block` — against `https://rpc.testnet.chain.robinhood.com`, part of the Foundry
toolchain already in the fixed stack, with zero additional setup. If you later want Blockscout MCP for
convenience, the setup steps (user must supply the API key) are in `06-tooling.md` §"Needs the user"
— report the need to the PM rather than trying to obtain a key yourself.

## Owned paths

`scripts/` (deploy orchestration beyond Contracts' own `forge script`, the keeper cron script),
`.env.example` templates (var **names** only, per `contracts.md`'s table — never a real value),
`deployments/<network>/addresses.json` **final real-testnet values** (Contracts owns the schema and a
local/anvil entry; you own filling in the real `robinhood-testnet` and `arbitrum-sepolia` entries
after executing the actual deploy), and a short `docs/handoffs/DEMO-NOTES.md` you may create for your
own rehearsal notes/findings (this is the one exception to "PM writes all markdown" — operational
runbook notes for your own role are yours to write; do not use it to redefine scope, report scope
changes to the PM instead).

## Responsibilities

You are the bridge between the research's open questions and a working, demoable deployment. Three
jobs: (1) verify what the research flagged as unconfirmed, directly against the real chain, (2)
execute the actual testnet deployment once Contracts' code passes local tests, (3) rehearse the full
demo path end to end and be ready to flip to the Arbitrum Sepolia fallback if Robinhood Chain testnet
is genuinely blocked.

## Scope

### In scope

- **P0, do this first:** re-verify `docs.robinhood.com/chain/*` and
  `https://explorer.testnet.chain.robinhood.com` are actually reachable (the research session hit TLS
  certificate errors on both, all session, via two different fetch methods — `02-robinhood-testnet.md`
  flags this as plausibly environment-specific, not a real outage, but it must be confirmed, not
  assumed). Report back to the PM immediately if it's still unreachable from this environment too —
  that changes the plan.
- **P0:** obtain testnet ETH via the official faucet (`faucet.testnet.chain.robinhood.com`) or the
  Arbitrum bridge from Sepolia (`02-robinhood-testnet.md` §3) for the deployer address. Do not use or
  request any real funds — testnet only.
- **P0:** once role 01 (Contracts) reports `forge test` green, run its deploy script for real against
  `robinhood-testnet` (`forge script ... --rpc-url https://rpc.testnet.chain.robinhood.com --broadcast`),
  capture every deployed address, and write the final `deployments/robinhood-testnet/addresses.json`
  per `contracts.md`'s schema.
- **P0:** verify every deployed contract on the Blockscout explorer (Blockscout's own verification
  flow, not Etherscan's — `02-robinhood-testnet.md` §2).
- **P0:** run the same deploy against `arbitrum-sepolia` too, producing
  `deployments/arbitrum-sepolia/addresses.json` — this is the fallback network, prepared in parallel,
  not only if Robinhood Chain testnet fails (cheap insurance, `05-synthesis.md` decision 1).
- **P0:** stand up the keeper cron script (a simple interval-driven script calling
  `RebalanceEngine.performRebalance()` for any vault `checkUpkeep()` flags) and confirm it actually
  fires a rebalance end to end on the deployed contracts.
- **P0:** end-to-end demo rehearsal — walk all 8 steps of `00-overview.md`'s demo path yourself
  against the real deployed testnet contracts (via `cast` or the frontend once role 02 has it wired),
  and report any step that doesn't work back to whichever role owns it.
- **P0:** attempt to resolve, and report findings on, as many of `05-synthesis.md`'s 9 unverified
  assumptions as possible before Day 6 — specifically: whether Chainlink Data Feeds exist on this
  testnet with real addresses (ask in the buildathon's own dev channel if docs don't resolve it,
  re-check `docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood`), whether a real USDG testnet
  address exists, whether the community-sourced stock-token addresses
  (`02-robinhood-testnet.md` §5) are genuine (check them on the now-hopefully-reachable Blockscout
  explorer). If any resolve, report to the PM so `addresses.json` can be updated to use them instead
  of mocks — but do not block the P0 deploy-with-mocks path waiting on this.
- **P0:** register on HackQuest (`arbitrum-singapore.hackquest.io`) and read the actual submission
  form — resolve `05-synthesis.md`'s open question about a testnet-vs-mainnet deployment mandate and
  any deliverables checklist (contract addresses, verified source, demo video), report findings to the
  PM immediately since this could change the deployment target.
- **P1:** if Gelato Web3 Functions is confirmed reachable on Robinhood Chain testnet
  (`01-tech-stack.md` §3's open question), layer it on top of the same permissionless
  `performRebalance()` entrypoint as a polish item — not required for the demo to work.

### Out of scope

- Writing or modifying any `.sol` contract source — that's role 01's owned path; if a contract needs a
  change during deployment (a bug found at deploy time), report it back to role 01, do not patch it
  yourself.
- Writing or modifying any frontend code — that's role 02's owned path; if the UI needs a different
  address-file shape or an additional field, report it to the PM (who updates `contracts.md`), not a
  silent fix.
- Any real-money transaction of any kind — testnet only, always.
- Committing a real `.env` file or a real private key anywhere.

## Objectives

Real, verified contract deployments on Robinhood Chain testnet (and, in parallel, Arbitrum Sepolia as
insurance), a working keeper loop, a rehearsed end-to-end demo, and as many of the research's open
questions closed with a primary-source answer as the 6-day budget allows.

## Requirements

See Scope above — every item already P0/P1 tagged.

## Dependencies

Depends on role 01 (Contracts) reporting `forge test` green before executing a real deploy. Runs
largely in parallel with role 02 (Frontend) — your `addresses.json` output is what role 02 does its
final integration against, but your own verification/faucet/HackQuest work can start immediately,
independent of both other roles.

## Constraints

- Testnet-only funds and transactions, always.
- Never commit a real private key or `.env` file — `.env.example` gets variable **names** only.
- No code comments except `// TEMPORARY —` on genuinely temporary scaffolding, if you write any
  scripts of your own.

## Deliverables

- **P0:** a written verification report (to the PM, and/or `docs/handoffs/DEMO-NOTES.md`) on whether
  `docs.robinhood.com` and the Blockscout explorer are reachable from this environment, done first.
- **P0:** `deployments/robinhood-testnet/addresses.json` and `deployments/arbitrum-sepolia/addresses.json`,
  both fully populated with real, verified contract addresses.
- **P0:** a working keeper cron script, demonstrated firing at least one real rebalance on the
  deployed contracts.
- **P0:** a completed, timed, end-to-end rehearsal of the 8-step demo path, with a written note of
  which step (if any) failed and why.
- **P0:** a report on the buildathon's actual submission requirements (from HackQuest, directly), and
  on which of `05-synthesis.md`'s 9 unverified assumptions got resolved and how.

## Acceptance criteria

- `deployments/robinhood-testnet/addresses.json` matches `contracts.md`'s schema and every address in
  it resolves to real, verified, non-empty bytecode on `https://explorer.testnet.chain.robinhood.com`
  (checkable via `cast code <address> --rpc-url https://rpc.testnet.chain.robinhood.com`).
- The keeper script, run against the real deployment, causes a real `Rebalanced` event to be emitted
  on-chain (checkable via `cast logs`).
- The 8-step demo path from `00-overview.md` completes end to end against the real Robinhood Chain
  testnet deployment (or, if genuinely blocked, against the Arbitrum Sepolia deployment, with a clear
  written reason why the fallback was needed).
- A written answer — sourced, not guessed — to whether the Buildathon requires a specific network for
  submission, delivered before any role starts P1 work that could be invalidated by the answer.
