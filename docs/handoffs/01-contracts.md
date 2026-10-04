# 01 — Contracts Engineer

## Context — read first

- `docs/research/05-synthesis.md` — full read. Every decision here (Foundry, custom vault, USDG-only
  settlement, MAX_DEPTH=2, permissionless keeper, Chainlink-shaped oracle interface, mock assets) is
  already made; do not re-decide any of it.
- `docs/research/01-tech-stack.md` — full read. Contains the concrete reasoning and version numbers
  (OZ v5.7.0, Foundry v1.8.3, `evm_version = "paris"`), the inflation-attack mitigation you must
  implement, and the read-only-reentrancy hazard your nested-NAV design must close.
- `docs/research/03-domain.md` §"Recommendations" and §"Implications per role" (contracts) — full
  read. This is where the depth cap, cycle-detection, nested-NAV-must-be-live, redemption-liquidity,
  and oracle-freshness rules come from, each grounded in a real incident (Stream Finance/Elixir, Nov
  2025). Implement all five as on-chain checks, not documentation.
- `docs/research/02-robinhood-testnet.md` §1–2, §9 — chain identity and quirks (chain ID 46630,
  Blockscout verification, PUSH0/ArbOS uncertainty).
- `docs/handoffs/contracts.md` — full read. This is the frozen interface you implement against, the
  MVP asset-acquisition simplification (mint/burn mocks, no DEX), the address-file schema you write
  to, and the env var names.

## Tools — skills and MCP

From `docs/research/06-tooling.md`:
- `setup-solidity-contracts` (`.claude/skills/setup-solidity-contracts/`) — use for `forge init`,
  pinning `openzeppelin-contracts@v5.7.0`, and `remappings.txt` setup. Invoke it before hand-rolling
  the Foundry project structure.
- `develop-secure-contracts` (`.claude/skills/develop-secure-contracts/`) — use for every
  security-relevant piece: `StrategyToken`'s access control, `StrategyVault`'s reentrancy guards,
  `StrategyFactory`/`RebalanceEngine`/`MarketplaceRegistry`'s access control. Its library-first
  methodology means reading the installed OZ v5.7.0 source before writing anything a library already
  provides (`ReentrancyGuard`, `Ownable`, `AccessControl`) — use it, don't hand-roll these.
- `property-based-testing` (`.claude/skills/property-based-testing/`) — use for invariant tests on
  (a) the vault's virtual-shares/decimals-offset inflation-attack mitigation and (b)
  `StrategyFactory`'s `MAX_DEPTH=2` + cycle-detection enforcement. These are exactly the two hazards
  the research flagged as needing real invariant coverage, not example-based tests.

No MCP server is installed for this role — use `cast` directly via Bash for any RPC inspection during
local development (`cast call`, `cast block`, etc. against `anvil` for local testing; Integration
owns real-testnet execution, but you should still be able to sanity-check against a local `anvil`
fork).

## Owned paths

`contracts/` (all `.sol` sources and Foundry tests), `foundry.toml`, `remappings.txt`,
`deployments/<network>/addresses.json` **schema and initial local-test values** (Integration writes
the final real-testnet values after running your deploy script — you own the file's existence,
structure, and a local/anvil-network entry for your own testing). Do not touch `app/`, `components/`,
or any frontend path. Do not execute a real testnet deploy yourself — write and locally test the
deploy script; Integration (role 03) runs it against Robinhood Chain testnet for real.

## Responsibilities

Build, locally test (via `forge test`, `anvil`), and hand off every contract in `contracts.md`'s
interface list: `StrategyToken`, `StrategyVault`, `StrategyFactory`, `RebalanceEngine`,
`MarketplaceRegistry`, plus `MockUSDG`, mock stock-token ERC-20s, and a `MockV3Aggregator`-shaped
`IPriceOracle` implementation — all wired to compile and pass tests before Integration deploys them
for real.

## Scope

### In scope

- **P0:** `StrategyToken` (plain OZ ERC20, `mint`/`burn` restricted to its `vault` via `onlyVault`).
- **P0:** `StrategyVault` implementing the full `IStrategyVault` interface from `contracts.md`:
  `deposit`/`redeem` in USDG only, `previewDeposit`/`previewRedeem`, `totalAssetsUSDG()` (must
  recurse live into any nested Strategy Token constituent's own `totalAssetsUSDG()` — never cache),
  `getConstituents()`, `depth()`, `rebalanceNeeded()` (time-based and threshold-based per PRD §3's
  example: "Rebalance every 7 days," "If any asset > 50% -> force rebalance"), `executeRebalance()`.
  Virtual-shares/decimals-offset inflation-attack mitigation on the USDG↔share exchange rate, ported
  from OpenZeppelin's documented technique (`01-tech-stack.md` §2). Redemption of a nested constituent
  Strategy Token redeems pro-rata in units of that inner token, never force-unwinding its underlying
  (`03-domain.md` Recommendation 4).
- **P0:** `StrategyFactory` implementing `IStrategyFactory`: enforces `MAX_DEPTH = 2` and on-chain
  ancestor-cycle rejection at creation time (`03-domain.md` Recommendation 1–2), deploys a new
  `StrategyToken` + `StrategyVault` pair, auto-registers the pair in `MarketplaceRegistry`.
- **P0:** `RebalanceEngine` implementing `IRebalanceEngine`: `checkUpkeep()` view (for an off-chain
  cron bot to poll cheaply across all registered vaults) and permissionless `performRebalance(vault)`
  that reverts if `rebalanceNeeded()` is false, otherwise calls the vault's `executeRebalance()`. No
  dependency on Chainlink Automation, Gelato, or OpenZeppelin Defender (`01-tech-stack.md` §3 — all
  three rejected).
- **P0:** `MarketplaceRegistry` implementing `IMarketplaceRegistry`: `registerStrategy` (callable only
  by `StrategyFactory`), `getAllStrategies()`, `getStrategyInfo()`.
- **P0:** `IPriceOracle` interface + a `ChainlinkPriceOracle` adapter (wraps
  `AggregatorV3Interface.latestRoundData()`) + a `MockV3Aggregator`-shaped mock feed deployable per
  asset, so the concrete oracle can be swapped for a real Robinhood Chain testnet feed later via
  `addresses.json` alone, with zero contract change (`05-synthesis.md` decision 6).
- **P0:** oracle-freshness gate (`MAX_PRICE_STALENESS`) checked by both the rebalance and redeem
  entrypoints (`03-domain.md` Recommendation 5) — pick and document a concrete value (this is your
  call; write the reasoning into your deliverable notes, not a code comment).
- **P0:** `MockUSDG` (18-decimal ERC20) and mock stock-token ERC-20s for the exact ticker set the real
  faucet distributes — TSLA, AMZN, NFLX, PLTR, AMD (`02-robinhood-testnet.md` §5) — each with a
  `uiMultiplier()` function matching the real Stock Token interface shape, and a `MINTER_ROLE`
  grantable to a `StrategyVault` per `contracts.md`'s MVP acquisition simplification.
- **P0:** Foundry unit tests for every contract above, plus the `property-based-testing`-driven
  invariant tests for the inflation-attack mitigation and the depth/cycle enforcement.
- **P0:** a Foundry deploy script (`script/Deploy.s.sol` or similar) parameterized by
  `DEPLOY_NETWORK`, that deploys everything above in the right order (mocks → oracles → factory/engine/
  registry) and writes `deployments/<network>/addresses.json` in the schema `contracts.md` defines.
  You write and locally test this script against `anvil`; Integration executes it for real.
- **P1:** a second mock stock-token set or additional constituents if time remains, to make the
  marketplace demo feel less like a two-token toy.
- **P2:** any additional constraint types beyond max-weight-per-asset and rebalance-interval (PRD
  §6.2's "advanced rule engine" is explicitly future scope, not this build).

### Out of scope

- Any DEX/AMM integration for asset acquisition — the mint/burn mock model in `contracts.md` replaces
  it entirely for this build. Do not add Uniswap-router calls "just in case" — no DEX address on
  Robinhood Chain testnet is confirmed to even exist (`02-robinhood-testnet.md` §8).
- Direct multi-asset deposit (depositing stock tokens directly instead of USDG) — USDG-only in/out is
  the fixed P0 flow (`05-synthesis.md` decision 3).
- Depth-3+ composition — hard-capped at 2, not "2 for now, extend later."
- Chainlink Automation, Gelato Web3 Functions, or OpenZeppelin Defender integration — the
  permissionless entrypoint is the entire P0 keeper design.
- Real testnet deployment execution — you write and locally test the script; you do not run
  `--broadcast` against Robinhood Chain testnet yourself (Integration role 03 does).
- Anything touching `app/`, `components/`, or other frontend paths.

## Objectives

Ship five contracts (`StrategyToken`, `StrategyVault`, `StrategyFactory`, `RebalanceEngine`,
`MarketplaceRegistry`) plus mocks and an oracle adapter, all compiling under `evm_version = "paris"`,
`pragma ^0.8.24`, passing `forge test` including invariant tests, with a deploy script Integration can
run unmodified against Robinhood Chain testnet.

## Requirements

All tagged per `docs/handoffs/00-overview.md`'s priority scheme; see Scope above for the full list
with P0/P1/P2 already assigned per item.

## Dependencies

None to start — this role is first in the dispatch order (`00-overview.md`). Integration (03) depends
on this role's contracts passing `forge test` before it deploys for real. Frontend (02) depends on
`contracts.md`'s frozen interface (already written, does not require this role's code to exist first)
but needs this role's final ABI output (`forge build`'s `out/*.json`) for its last mile of real
integration.

## Constraints

- Solidity `^0.8.24`, OpenZeppelin Contracts `v5.7.0`, Foundry `v1.8.3`, `forge-std` `v1.16.2`,
  `evm_version = "paris"` in `foundry.toml` (defensive, until Robinhood Chain testnet's ArbOS/PUSH0
  support is confirmed — see `02-robinhood-testnet.md` unresolved item).
- No code comments (standing rule) — document the staleness-window and any other judgment call in
  your final deliverable notes to the PM, not inline.
- No new dependency beyond what `05-synthesis.md`/`06-tooling.md` already fixed without asking the PM.

## Deliverables

- **P0:** `contracts/` with all five core contracts + mocks + oracle adapter, compiling clean.
- **P0:** `forge test` green, including invariant tests for inflation-attack mitigation and
  depth/cycle enforcement.
- **P0:** `script/Deploy.s.sol` (or equivalent), locally verified against `anvil`, parameterized by
  `DEPLOY_NETWORK`, producing a correctly-shaped `deployments/<network>/addresses.json`.
- **P0:** ABI output available at `out/` for the Frontend role to consume.
- A short written note (in your final report to the PM, not a committed file unless the PM asks) on
  the staleness-window value chosen and any other judgment call made where this file didn't specify
  an exact number.

## Acceptance criteria

- `forge build` succeeds with `evm_version = "paris"`, `pragma ^0.8.24`.
- `forge test` passes, including at least one invariant test per: (a) inflation-attack mitigation
  holds under a donate-then-deposit attack scenario, (b) `StrategyFactory` rejects any attempt to
  create a strategy exceeding `MAX_DEPTH = 2` or containing a cycle.
- Depositing USDG into a depth-1 strategy mints the correct StrategyToken amount and the vault
  actually holds (via mint) the underlying mock stock-token basket at the deposit-time oracle price.
- Creating a depth-2 strategy that nests a depth-1 Strategy Token succeeds; creating a depth-3
  strategy (nesting a depth-2 strategy) reverts.
- `totalAssetsUSDG()` on a depth-2 vault reflects live changes to its nested constituent's own NAV
  (e.g. after the nested vault rebalances) without any manual sync step.
- `performRebalance()` reverts when `rebalanceNeeded()` is false and succeeds (emits `Rebalanced`)
  when a time or threshold trigger condition is met.
- Redeeming a depth-2 Strategy Token that holds a nested Strategy Token returns the inner Strategy
  Token's units pro-rata, not the inner token's own underlying assets directly.
- Rebalance and redeem both revert if the relevant oracle price is older than the chosen
  `MAX_PRICE_STALENESS`.
- `deployments/<network>/addresses.json` matches the schema in `contracts.md` exactly.
