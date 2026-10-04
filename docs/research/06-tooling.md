# 06 — Tooling

Scope: skills and MCP servers for the fixed stack in `05-synthesis.md` (Foundry + OpenZeppelin
Contracts v5.7.0 + custom ERC-4626-shaped vault on Robinhood Chain testnet, chain ID `46630`;
Next.js App Router + wagmi/viem frontend; no subgraph/indexer). Installed at **project scope only**
(`.claude/skills/` and `.mcp.json` inside this repo) — nothing global was touched. Search order
followed: (1) the vendor's own GitHub org, (2) `skills.sh`, (3) `registry.modelcontextprotocol.io`,
(4) Anthropic/vendor plugin marketplaces. Every `SKILL.md` below was read in full before install; none
instructs exfiltration, disabling safeguards, fetching/running unreviewed remote code, or acting
outside the project.

## Installed

| Name | Kind | Source | Version/commit | Role | For what |
|---|---|---|---|---|---|
| `setup-solidity-contracts` | skill | [OpenZeppelin/openzeppelin-skills](https://github.com/OpenZeppelin/openzeppelin-skills) | commit `6f215af6` (2026-07-15), 213★, official OZ org | Contracts engineer | `forge init`, pin `forge install OpenZeppelin/openzeppelin-contracts@v5.7.0`, write the correct `remappings.txt` — exactly the Foundry+OZ v5.7.0 setup `05-synthesis.md` §2/§9 decided on. |
| `develop-secure-contracts` | skill | [OpenZeppelin/openzeppelin-skills](https://github.com/OpenZeppelin/openzeppelin-skills) | commit `6f215af6` (2026-07-15), 213★, official OZ org | Contracts engineer | Library-first integration methodology: reads the installed OZ v5.7.0 source before writing security-critical logic. Used for `StrategyToken` (plain `ERC20`), `ReentrancyGuard`/`Pausable` on `StrategyVault`, and `Ownable`/`AccessControl` on `StrategyFactory`/`RebalanceEngine`/`MarketplaceRegistry` — steers away from hand-rolled reentrancy guards or access checks the library already provides. |
| `property-based-testing` | skill | [trailofbits/skills](https://github.com/trailofbits/skills) (`plugins/property-based-testing`) | commit `0cc1c73a` (2026-09-24), 7,278★, Trail of Bits (maintainers of Echidna/Medusa) | Contracts engineer | Foundry/Echidna/Medusa invariant-test methodology, explicitly covering "smart-contract state invariants." Targets the two hazards `01-tech-stack.md` §5 and `03-domain.md` flag as needing real invariant coverage, not example tests: the vault's virtual-shares/decimals-offset inflation-attack mitigation, and `StrategyFactory`'s `MAX_DEPTH=2` + cycle-detection enforcement. |
| `work:nextjs-app-router` | skill | pre-existing, global (`~/.claude/skills/work`), **reused, not reinstalled** | n/a | Frontend engineer | Server/client component boundary rules for the marketplace UI — wallet-connect and tx-signing components need `'use client'`, RPC-read views can stay server-rendered. Chain-agnostic; already covers the Next.js App Router side of this stack. |
| `work:react-components` | skill | pre-existing, global, **reused** | n/a | Frontend engineer | Props-API/composition discipline for deposit/redeem forms and the strategy-composition (nested Strategy Token) builder UI. |
| `work:typescript-types` | skill | pre-existing, global, **reused** | n/a | Frontend engineer | Deriving TypeScript types from `forge build`'s ABI JSON output instead of hand-writing contract-call types — matches `01-tech-stack.md`'s "no Hardhat, wagmi/viem reads ABI JSON directly" decision. |
| `work:reuse-first` | skill | pre-existing, global, **reused** | n/a | Frontend engineer | Inventory existing components/deps before adding new ones — relevant given the 6-day (not 10-day) budget from `05-synthesis.md`. |
| `me:stack-detect` (via `me:frontend`) | skill | pre-existing, global, **reused** | n/a | Frontend engineer | Detects the Next.js App Router + wagmi/viem stack at task start and routes to the `work:*` skills above automatically. |

**On the pre-existing `dapp` and `standards` skills** (checked per instructions before installing
anything else): both are **Stellar/Soroban-scoped** — `dapp`'s `SKILL.md` is built entirely around
`@stellar/stellar-sdk`, Freighter, Stellar Wallets Kit, and Soroban contract invocation; `standards`
covers Stellar SEPs/CAPs. Neither mentions EVM, Solidity, wagmi, viem, or any Ethereum-family concept.
**Verdict: poor fit, wrong chain ecosystem entirely** — not reused for this project. The gap they leave
(a dedicated "EVM dapp / wagmi-viem" skill) has no vendor-maintained equivalent that was found (see
Rejected); the frontend engineer works from wagmi/viem's own docs plus the chain-agnostic `work:*`
skills above, which is sufficient for a direct-RPC-read, no-indexer frontend.

## Rejected

- **OpenZeppelin Contracts MCP server** (`@openzeppelin/contracts-mcp`, official, npm, no API key) —
  considered, not installed. Its contract-generation capability is already reachable via
  `npx @openzeppelin/contracts-cli`, which the installed `develop-secure-contracts` skill invokes
  directly through Bash as part of its generate-compare-apply workflow — no MCP layer needed for that.
  The MCP's actual differentiator (an interactive "Wizard UI" rendered via the MCP Apps extension,
  with buttons/live preview) targets chat-style hosts like Claude Desktop/Cursor, not a CLI coding
  agent that already runs Bash directly. Redundant for this workflow.
- **Blockscout MCP server** (official, `blockscout/mcp-server`, hosted at `mcp.blockscout.com`) — not
  added to `.mcp.json`. Two real blockers, not installed by default: (1) requires a Blockscout **PRO
  API key** (secret); (2) its multi-chain coverage is driven entirely by Blockscout's own Chainscout
  registry (`get_chains_list`), and there is no confirmation Robinhood Chain testnet's self-hosted
  Blockscout instance (`explorer.testnet.chain.robinhood.com` — itself TLS-unreachable during
  `02-robinhood-testnet.md`'s research session) is registered there. Listed under **Needs the user**
  below rather than force-installed. **The actual need it was evaluated for — "checking deployed
  contract state, reading testnet data, verifying transactions" — is already covered with zero setup
  by `cast` (`cast call`, `cast receipt`, `cast logs`, `cast code`, `cast block`), part of the Foundry
  toolchain already fixed in `05-synthesis.md`, run directly via Bash against
  `https://rpc.testnet.chain.robinhood.com`.** This is the recommended path for both the Contracts and
  Integration/Deploy roles.
- **Community Foundry MCP servers** — `PraneshASP/foundry-mcp-server` (253★, but last pushed
  2026-01-17 and self-described "experimental") and `0xClandestine/foundry-mcp-rs` (7★, stale since
  2025-11-07). Both just proxy `forge`/`cast`/`anvil`/`chisel` calls — capability the agent already has
  directly via Bash in this environment, with no abstraction gap to close. Neither clears the "clearly
  established, actively maintained" bar strongly enough to justify the added indirection.
- **Generic EVM RPC MCP servers** — `mcpdotdirect/evm-mcp-server` (379★, but its chain list is
  hardcoded in `src/core/chains.ts` and does not include a brand-new Orbit testnet like Robinhood Chain
  testnet without a source edit), `JamesANZ/evm-mcp` (3★), `John0n1/chainrpc-mcp` (4★),
  `franckyo/evm-recon-mcp` — all either fail the adoption/activity bar or can't cleanly point at this
  project's specific RPC URL out of the box. `cast` and `viem` (already in the fixed stack) do this
  natively with zero setup.
- **Arbitrum/OffchainLabs-specific skill or MCP — none found, explicit gap.** Checked the OffchainLabs
  GitHub org directly (Nitro, Prysm, `arbitrum-sdk`, token-bridge-contracts, `arbitrum-docs`,
  `arbitrum-tutorials` — no MCP/skill/agent-tooling repo among them), `skills.sh` (an "arbitrum" search
  returns unrelated results — Playwright, Trail of Bits Solana/Rust skills, revenue-ops, etc., nothing
  Arbitrum-specific), and the MCP registry (an "arbitrum" search returns two unrelated paid
  trading/simulation tools — `arbitrum-transaction-preflight`, `ArbitrumOracle` — not vendor dev
  tooling). **Note for the handoffs:** the Contracts and Integration/Deploy roles should work from
  `docs.arbitrum.io` directly (already the primary source in `01-tech-stack.md` §6 and
  `02-robinhood-testnet.md`); this is a non-issue in practice since Orbit chains are plain
  EVM-compatible and need no chain-specific Foundry plugin.
- **Robinhood Chain-specific skill or MCP — none found, explicit gap.** Searched `skills.sh` and the
  MCP registry for "robinhood": only a 2-install unofficial skill
  (`jp4g/robinhood-chain-skill`) and several unrelated Robinhood *stock-trading*/DEX-intelligence MCP
  servers (a different Robinhood product entirely, not this chain's dev tooling) turned up. Consistent
  with `02-robinhood-testnet.md`'s own finding that no official starter repo or SDK exists yet — this
  confirms (rather than undercuts) the synthesis's mock-everything-behind-`addresses.json` approach;
  there is no tooling shortcut being missed here.
- **Other general Solidity/Web3 skills considered and passed over** as redundant with what's already
  installed, or out of scope for a 6-day build: `austintgriffith/ethskills@ethskills` (291★, broad
  "any Ethereum request" skill — overlaps with the OZ skills and Foundry's own docs, no capability
  specific to this project's actual hazards); `wshobson/agents@web3-testing` /
  `wshobson/agents@solidity-security` (part of a 40K★ general-purpose multi-domain plugin marketplace,
  not a blockchain vendor — overlaps with `property-based-testing` and the composability-hazard
  guidance `01-tech-stack.md` already worked out); `pashov/skills@solidity-auditor` and
  `trailofbits/skills@entry-point-analyzer` (audit-report-generation workflows suited to a pre-mainnet
  security audit, not a 6-day hackathon build path).

## Needs the user

- **Blockscout MCP server** (official — see Rejected above for why it wasn't installed by default). If
  the Integration/Deploy engineer later wants live block-explorer queries instead of raw `cast` calls:
  1. Register at `https://dev.blockscout.com` (free tier, no credit card) for a PRO API key
     (`proapi_...`).
  2. Confirm Robinhood Chain testnet (chain `46630`) is actually in Blockscout's Chainscout registry —
     call `get_chains_list` once connected; this was **not** confirmed during tooling research (its own
     explorer domain was TLS-unreachable in `02-robinhood-testnet.md`'s research session).
  3. Only then: `claude mcp add --transport http blockscout https://mcp.blockscout.com/mcp --header "Blockscout-MCP-Pro-Api-Key: ${BLOCKSCOUT_API_KEY}"`,
     supplying the key as an env var — never inline it into `.mcp.json`.
- No other MCP server was installed this session, so no other secret is pending.

## Sources

- `05-synthesis.md`, `01-tech-stack.md`, `02-robinhood-testnet.md` (this repo, read in full before
  searching)
- OpenZeppelin `openzeppelin-skills`: [github.com/OpenZeppelin/openzeppelin-skills](https://github.com/OpenZeppelin/openzeppelin-skills) (213★, official org, fetched 2026-09-28, HEAD `6f215af6` 2026-07-15)
  — skills read in full: `skills/setup-solidity-contracts/SKILL.md`, `skills/develop-secure-contracts/SKILL.md`
- Trail of Bits `skills`: [github.com/trailofbits/skills](https://github.com/trailofbits/skills) (7,278★, fetched 2026-09-28, HEAD `0cc1c73a` 2026-09-24)
  — skill read in full: `plugins/property-based-testing/skills/property-based-testing/SKILL.md`
- `skills.sh` searches: `foundry`, `solidity`, `arbitrum`, `robinhood` (fetched 2026-09-28 via `npx skills search`)
- OpenZeppelin Contracts MCP: [npmjs.com/package/@openzeppelin/contracts-mcp](https://www.npmjs.com/package/@openzeppelin/contracts-mcp), [github.com/OpenZeppelin/contracts-wizard](https://github.com/OpenZeppelin/contracts-wizard), [openzeppelin.com/news/introducing-contracts-mcp](https://www.openzeppelin.com/news/introducing-contracts-mcp) (fetched 2026-09-28)
- Blockscout MCP server: [github.com/blockscout/mcp-server](https://github.com/blockscout/mcp-server) (45★, official org, README fetched directly 2026-09-28)
- `registry.modelcontextprotocol.io` searches: `foundry`, `blockscout`, `openzeppelin`, `arbitrum`, `robinhood` (fetched 2026-09-28)
- Community MCP servers checked: [github.com/PraneshASP/foundry-mcp-server](https://github.com/PraneshASP/foundry-mcp-server), [github.com/0xClandestine/foundry-mcp-rs](https://github.com/0xClandestine/foundry-mcp-rs), [github.com/mcpdotdirect/evm-mcp-server](https://github.com/mcpdotdirect/evm-mcp-server), [github.com/JamesANZ/evm-mcp](https://github.com/JamesANZ/evm-mcp), [github.com/John0n1/chainrpc-mcp](https://github.com/John0n1/chainrpc-mcp) (all fetched/checked via GitHub API 2026-09-28 for star count and last-push date)
- OffchainLabs GitHub org: [github.com/OffchainLabs](https://github.com/OffchainLabs) (fetched 2026-09-28)
- foundry-rs GitHub org: [github.com/foundry-rs](https://github.com/foundry-rs) (fetched 2026-09-28)
- Pre-existing global skills read before deciding not to reinstall: `~/.claude/skills/dapp/SKILL.md`, `~/.claude/skills/standards/SKILL.md`, `~/.claude/skills/work/skills/{nextjs-app-router,react-components,typescript-types,reuse-first}/SKILL.md`, `~/.claude/skills/me/skills/stack-detect/SKILL.md`, `~/.claude/skills/me/agents/frontend.md`
