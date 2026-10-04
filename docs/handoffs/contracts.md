# Contracts — everything that crosses a role boundary

This is the interface every role builds against. Roles never read each other's source — they read
this file. If a role needs it to change, it reports back to the PM instead of diverging (see
`00-overview.md`).

Every decision below is fixed in `docs/research/05-synthesis.md`; this file translates those
decisions into concrete Solidity signatures, a deployment-address schema, and env var names.

## MVP asset-acquisition simplification — read this first

**PRD §8 says the vault "holds underlying assets" and §6.1 wants pro-rata redemption into
underlying.** Fully implementing that requires either (a) real DEX liquidity between USDG and each
mock/real stock token, or (b) the vault having mint/burn rights over the tokens it needs to
acquire/liquidate. `05-synthesis.md` decision 7 already commits to team-deployed mock USDG and mock
stock tokens for the demo (real testnet addresses are unconfirmed/unofficial per
`docs/research/02-robinhood-testnet.md` §5–6), and no DEX address on Robinhood Chain testnet is
confirmed either (`02-robinhood-testnet.md` §8 — a third-party directory claims Uniswap v2/v3 exists
but every address was "pending verification").

**Decision (binding for the Contracts role): mock stock tokens are deployed with a `MINTER_ROLE`
grantable to the `StrategyVault`.** On deposit, the vault mints itself the basket of mock stock
tokens it needs at the oracle-implied price and holds them for real (satisfying "vault holds
underlying assets" literally, not just in accounting). On redeem/rebalance-driven liquidation, the
vault burns the stock tokens it's shedding and returns USDG. This needs **no DEX, no AMM, no swap
routing** — it is a real, auditable custody model, just one where the "market" the vault trades
against is its own mint/burn authority over assets it deployed, priced by the oracle.

**This is explicitly out of scope beyond the mocks:** if/when real (non-mintable) testnet stock-token
addresses are confirmed and swapped into `addresses.json`, the vault's mint/burn acquisition path no
longer works — a DEX-swap acquisition path would be required instead. That is not part of this
build; note it in the demo narrative as the known post-hackathon path (consistent with PRD §6.2's
"multi-asset support" future scope) rather than hiding the limitation.

## Composability

- `MAX_DEPTH = 2` (constant, enforced on-chain in `StrategyFactory`). Depth 1 = a Strategy Token
  whose constituents are all raw assets (mock stock tokens / USDG). Depth 2 = a Strategy Token that
  includes at least one depth-1 Strategy Token as a constituent. Creation reverts above depth 2.
- Cycle detection: `StrategyFactory.createStrategy()` walks the constituent list and reverts if any
  proposed constituent is, directly or indirectly, an ancestor of the strategy being created (a
  strategy cannot contain itself, directly or nested).
- Nested NAV must always be computed live (`StrategyVault.totalAssetsUSDG()` recurses into any
  constituent Strategy Token's own live `totalAssetsUSDG()` at call time) — never cached, never a
  checkpoint. See `docs/research/03-domain.md` Recommendation 3 for why (Stream Finance precedent).
- Redemption of an outer Strategy Token that holds an inner Strategy Token as a constituent redeems
  pro-rata **in units of the inner Strategy Token**, not by force-unwinding the inner token's own
  underlying. See `docs/research/03-domain.md` Recommendation 4.
- Every rebalance/redeem entrypoint checks oracle freshness before executing (reverts if the relevant
  `IPriceOracle.getPrice()` `updatedAt` is older than `MAX_PRICE_STALENESS` — pick a value, e.g. 24h
  for equities given tokenized-stock market-hours behavior is unconfirmed on this testnet, document
  the choice in the deliverable notes, not in a code comment).

## Core contract interfaces

```solidity
// StrategyToken.sol — plain OZ ERC20, mint/burn restricted to its own StrategyVault
contract StrategyToken is ERC20 {
    address public immutable vault;
    modifier onlyVault() { require(msg.sender == vault, "not vault"); _; }
    function mint(address to, uint256 amount) external onlyVault;
    function burn(address from, uint256 amount) external onlyVault;
}

// IPriceOracle — Chainlink-AggregatorV3Interface-shaped, concrete adapter swappable via addresses.json
interface IPriceOracle {
    function getPrice(address token) external view returns (uint256 price, uint256 updatedAt);
}

// StrategyVault.sol — custom, ERC-4626-shaped, USDG-only settlement
struct Constituent {
    address token;          // mock stock token or a nested StrategyToken address
    uint16 targetWeightBps; // basis points, sums to 10_000 across all constituents
    bool isStrategyToken;   // true if `token` is itself a Strategy Token (nested)
}

interface IStrategyVault {
    function deposit(uint256 usdgAmount, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 usdgAmount);
    function previewDeposit(uint256 usdgAmount) external view returns (uint256 shares);
    function previewRedeem(uint256 shares) external view returns (uint256 usdgAmount);
    function totalAssetsUSDG() external view returns (uint256); // recurses into nested constituents live
    function getConstituents() external view returns (Constituent[] memory);
    function depth() external view returns (uint8);
    function rebalanceNeeded() external view returns (bool timeBased, bool thresholdBased);
    function executeRebalance() external; // callable only by RebalanceEngine or permissionlessly, see below

    // Auto-generated public-state getters also on the real deployed contract (not hand-listed above
    // originally — added here after the Frontend role flagged the gap; Contracts' actual
    // implementation already exposes these as `public immutable`/`public` state, confirmed against
    // `out/StrategyVault.sol/StrategyVault.json`, no contract change was needed):
    function maxWeightBps() external view returns (uint16);
    function rebalanceInterval() external view returns (uint256);
    function lastRebalanceTimestamp() external view returns (uint256);

    event Deposit(address indexed sender, address indexed receiver, uint256 usdgAmount, uint256 shares);
    event Redeem(address indexed sender, address indexed receiver, address indexed owner, uint256 shares, uint256 usdgAmount);
    event Rebalanced(uint256 indexed timestamp, bool timeBased, bool thresholdBased);
}

// StrategyFactory.sol
interface IStrategyFactory {
    function createStrategy(
        string calldata name,
        string calldata symbol,
        Constituent[] calldata constituents,
        uint16 maxWeightBps,        // per-asset cap constraint, PRD §3 example: "if any asset > 50% -> force rebalance"
        uint256 rebalanceInterval   // seconds, time-based trigger
    ) external returns (address vault, address token);

    event StrategyCreated(address indexed vault, address indexed token, address indexed creator, uint8 depth);
}

// RebalanceEngine.sol — permissionless keeper entrypoint, no third-party automation dependency
interface IRebalanceEngine {
    function checkUpkeep() external view returns (address[] memory vaultsNeedingRebalance);
    function performRebalance(address vault) external; // reverts if rebalanceNeeded() is false on that vault
}

// MarketplaceRegistry.sol — on-chain list, read directly by the frontend via RPC, no indexer
interface IMarketplaceRegistry {
    function registerStrategy(address vault, address token, address creator) external; // called by StrategyFactory only
    function getAllStrategies() external view returns (address[] memory vaults);
    function getStrategyInfo(address vault) external view returns (
        address token, address creator, uint8 depth, uint256 createdAt
    );

    event StrategyRegistered(address indexed vault, address indexed token, address indexed creator);
}
```

## Deployment address schema

One file per network, read identically by Foundry deploy scripts and the frontend. **No contract
address is ever hardcoded in a `.sol` file or a `.tsx` component — always read from this file.**

`deployments/<network>/addresses.json` (networks: `robinhood-testnet`, `arbitrum-sepolia`):

```json
{
  "chainId": 46630,
  "rpcUrl": "https://rpc.testnet.chain.robinhood.com",
  "explorerUrl": "https://explorer.testnet.chain.robinhood.com",
  "usdg": "0x...",
  "stockTokens": { "TSLA": "0x...", "AMZN": "0x...", "NFLX": "0x...", "PLTR": "0x...", "AMD": "0x..." },
  "priceOracles": { "USDG": "0x...", "TSLA": "0x...", "AMZN": "0x...", "NFLX": "0x...", "PLTR": "0x...", "AMD": "0x..." },
  "strategyFactory": "0x...",
  "rebalanceEngine": "0x...",
  "marketplaceRegistry": "0x..."
}
```

Owned by the **Contracts role** (it writes the values after each deploy); read-only for Frontend and
Integration/Deploy roles.

## Env vars (names only — no values, no secrets in any handoff or committed file)

| Var | Used by | Purpose |
|---|---|---|
| `DEPLOY_NETWORK` | Foundry deploy scripts | `robinhood-testnet` \| `arbitrum-sepolia`, selects which `foundry.toml` `[rpc_endpoints]` entry and which `addresses.json` to write |
| `DEPLOYER_PRIVATE_KEY` | Foundry deploy scripts | testnet-only deployer key, never committed, never logged |
| `NEXT_PUBLIC_CHAIN_ID` | Frontend | `46630` (robinhood-testnet) or `421614` (arbitrum-sepolia fallback) |
| `NEXT_PUBLIC_RPC_URL` | Frontend | matches `addresses.json.rpcUrl` for the active network |
| `NEXT_PUBLIC_EXPLORER_URL` | Frontend | matches `addresses.json.explorerUrl` |
| `NEXT_PUBLIC_NETWORK` | Frontend | `robinhood-testnet` \| `arbitrum-sepolia`, selects which `addresses.json` to import |

## Shared conventions

- All on-chain amounts are 18-decimal (`MockUSDG` and every mock stock token use 18 decimals to keep
  math uniform — do not assume 6-decimal USDG-style tokens for the mocks).
- Basis points (`uint16`, 0–10_000) for every weight/constraint field.
- Every event is indexed on the addresses a frontend will filter by (vault, token, creator) so the
  marketplace list and a user's own positions can be read via `eth_getLogs` without an indexer.
- ABI source of truth: `forge build`'s `out/*.json` — the frontend imports from there (or a copied
  subset), never hand-writes an ABI.
