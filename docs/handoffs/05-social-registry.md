# 05 — SocialRegistry ABI sketch and seed data shape

Status: FINAL. Contract, scripts, tests and on-chain seeding are all done. Sections 2–4 below are now live addresses, not placeholders.

## 1. Contract

`contracts/v2/SocialRegistry.sol`, interface `contracts/v2/interfaces/ISocialRegistry.sol`.

Fully permissionless — no admin, no roles, no constructor args. Every function is called by `msg.sender` acting on their own state.

### Function signatures

```solidity
function follow(address target) external;
function unfollow(address target) external;
function followerCount(address target) external view returns (uint256);
function isFollowing(address user, address target) external view returns (bool);
function followedBy(address user) external view returns (address[] memory targets);

function setProfile(string calldata handle, string calldata bio) external;
function profileOf(address user) external view returns (string memory handle, string memory bio);
function ownerOfHandle(string calldata handle) external view returns (address owner);

uint256 public constant MIN_HANDLE_BYTES = 3;
uint256 public constant MAX_HANDLE_BYTES = 20;
uint256 public constant MAX_BIO_BYTES = 160;
```

`target` in `follow`/`unfollow` is any address — a strategy vault or a creator EOA. `followedBy(user)` returns every target that user currently follows (order not stable across unfollows: unfollow does a swap-and-pop).

Implementation note: storage is a hand-rolled swap-and-pop array per user, not OZ's `EnumerableSet` — this repo builds with `evm_version = "paris"` (see `foundry.toml`) for Robinhood Chain compatibility, and the installed OZ v5.7 `EnumerableSet`/`Arrays` uses the Cancun-only `mcopy` opcode, which fails to compile under `paris`. `MarketplaceRegistryV2` already avoids `EnumerableSet` for the same reason; `SocialRegistry` follows that precedent.

### Events

```solidity
event Followed(address indexed user, address indexed target);
event Unfollowed(address indexed user, address indexed target);
event ProfileSet(address indexed user, string handle, string bio);
```

### Errors

```solidity
error ZeroAddress();
error CannotFollowSelf();
error AlreadyFollowing();
error NotFollowing();
error InvalidHandleLength();
error InvalidHandleChar();
error HandleTaken();
error BioTooLong();
```

Handle charset mirrors the registry's tag charset: lowercase `a-z`, digits `0-9`, and `-`/`_`. Length 3–20 bytes. Bio max 160 bytes (same style as the registry's `description`), no charset restriction. Handles are globally unique; changing your handle frees your old one. Self-follow reverts with `CannotFollowSelf`. Double-follow and double-unfollow always revert (`AlreadyFollowing` / `NotFollowing`) rather than silently no-op.

## 2. `addresses.json` key

New top-level key in `deployments/robinhood-testnet-v2/addresses.json`, now live:

```json
"socialRegistry": "0xe0FaeeD02db34f98Da05bab08E01a1473f8dC6F1"
```

Added additively — all existing keys are untouched. ABI generated at `src/lib/abi/generated/socialRegistry.ts`, exported as `socialRegistryAbi` from the barrel.

## 3. New stock tokens (additive, `script/AddAssetsV2.s.sol`) — deployed

| Ticker | Theme | Token | Feed (FengAggregator) |
|---|---|---|---|
| NVDA | AI / Semiconductors | `0xD0c81c063D7F5B9A9D64735dc9ed44D53DCBf160` | `0xBB61aaE284954d8871c449dBD5008e974517039b` |
| TSMC | Semiconductors | `0xA5E5662951D9D4ED2ce91E2Ea48348022fC29207` | `0x111eCBE2bA11D9fD1AfDC49265d755B17EDcC0dA` |
| MSFT | Technology | `0xC2eEcF5C0928b950e6274ffbb32579250a775a72` | `0x39302A361f1B6f07912407dA50E7FAb2b1816F6F` |
| GOOGL | Technology / AI | `0x90D4deD5f9a09Dc0c6f551E2f2E9102D35a9287b` | `0xDb52187861D08B55AEb6B5b85EFe06355E669736` |
| RKLB | Space | `0x85b84597D57f8561be7702fDced8431eCE369B8a` | `0x9C323f8bb795EC1b33afC573c1a6A0Bb1Dc2ED1D` |
| ISRG | Robotics | `0xb19E0f1276d9c561158F676eE71D82eC22D5a600` | `0x6A006eFE8d165788D18139FE3C3Ebc5609547832` |
| XOM | Energy | `0x9D354460f59348F286FaE84c4C3679c890dD0038` | `0x9c263812aE0b05C3a0dcDf6BF79972b4f3D303a3` |
| ENPH | Energy | `0x408921d41b292c220c127b80FE7082CBF11f4955` | `0xd157C1EB497ec40666739C41ed4E5B8B70004324` |

Each got a `MockStockToken` + a `FengAggregator` feed, registered on `ChainlinkPriceOracleV2.setFeed` and `OracleDesk.setToken(token, Mode.Mint)`, with `MINTER_ROLE` on the token granted to the desk — same pattern as the five original tickers in `DeployV2.s.sol`. Entries land in `addresses.json` under `.stockTokens.<TICKER>` and `.priceOracles.<TICKER>`, additively; the five original tickers are untouched. `scripts/refresh-feeds.sh`'s `PRICES` map now includes these 8 tickers with matching seed prices.

Known limitation: `src/ops/relayer.ts` uses the `addresses.json` ticker key verbatim as the Robinhood public price API symbol (`${priceApiBase}/${ticker}`). This works unmodified for the 5 original tickers and for NVDA, MSFT, GOOGL (real, matching symbols). `TSMC` as a key may not match Robinhood's real feed (Taiwan Semiconductor's ADR trades as `TSM` there), and `RKLB`/`ISRG`/`XOM`/`ENPH` may or may not be present on Robinhood's retail price API at all — if so, those feeds will simply show up as `skipped` with reason `price error` in tick summaries (graceful degradation, not a crash), and `scripts/refresh-feeds.sh` remains the fallback manual price source for them. Flagging this now in case Plan 1's ops agent wants to alias the API symbol separately from the display ticker.

## 4. Seed data (creators, strategies, follows) — on chain

4 deterministic demo wallets (private key = `keccak256("feng-seed-creator-<n>")`, never a real secret, funded with 0.0003 ETH each from the deployer — see `script/SeedSocialV2.s.sol`):

| # | Address | Handle | Bio |
|---|---|---|---|
| 1 | `0xf11d5a3bcfb1B3C2dA164C15d5eb3AEe3Ba62670` | `alex` | "AI & Technology Research" |
| 2 | `0x125747Aa358E9dc1D378c2ae913De1Df8a7AF681` | `nova` | "Space, robotics and frontier tech ideas." |
| 3 | `0x1d326d6a6C828333CaB6e77022fE48ED7A5d82A6` | `maya` | "Energy transition and grid infrastructure theses." |
| 4 | `0x00cF418f2f9a8172BA0aA6e0f44bd7c73A1b6514` | `kai` | "Semiconductors and big tech systems." |

12 strategies, registered via `StrategyFactoryV2.createStrategy` (thesis in registry `description`, category as `tags[0]`), each with a small first deposit from its own creator wallet:

| Creator | Name | Symbol | Category | Vault | Constituents (weight bps) |
|---|---|---|---|---|---|
| alex | AI Will Win | AIWIN | ai | `0x47D76795F6802361b92b03A57929c0282F9Cfdf9` | NVDA 4000, AMD 2500, TSMC 2000, MSFT 1500 |
| alex | Semiconductor Boom | CHIPS | semiconductors | `0xA53CdbDAaA291db15932c76a1c37B79112608B9a` | TSMC 3500, AMD 3500, NVDA 3000 |
| alex | Cloud Titans | CLOUD | technology | `0x5bE77433B5a8EAFb0f3d78DBC612CCbea8aADcd1` | MSFT 4000, GOOGL 3500, AMZN 2500 |
| nova | Robotics Future | ROBOT | robotics | `0x1b71617491C953aa640b26d590D7e670a749a890` | ISRG 4000, NVDA 3000, RKLB 3000 |
| nova | Space Race | ORBIT | space | `0xD7063a9799dbAFC2BBF784Bf796D5240e5eCB5aD` | RKLB 5000, ISRG 2500, GOOGL 2500 |
| nova | Deep Space Capital | COSMOS | space | `0xe525b37Dec76c38764842AdA165c4F02c3643723` | RKLB 6000, XOM 2000, ENPH 2000 |
| maya | Clean Energy Shift | GREEN | energy | `0xF9dd3d2EFC0E9F533344071c9E4817A1C7bB1Af5` | ENPH 4500, XOM 2500, TSLA 3000 |
| maya | Energy Barbell | BARBL | energy | `0x14E157f899024ab42FDc088bb774495F162e7FAB` | XOM 5000, ENPH 5000 |
| maya | Grid Future | VOLT | energy | `0xC52Fe235e31A0b8F486A3d8F36cA9432d592B523` | ENPH 4000, XOM 3000, MSFT 3000 |
| kai | Chip Supercycle | SUPER | semiconductors | `0x7223dEC2709dF8D1a40f09E12b8B320cd09B314b` | TSMC 4500, NVDA 3500, AMD 2000 |
| kai | Big Tech Core | BIGT | technology | `0x28268D95921cBD6d00fB1F7BC7d40CDA46d7DEa2` | MSFT 3500, GOOGL 3500, AMZN 3000 |
| kai | Humanoid Robotics | ANDRO | robotics | `0xDB573c22176e162efb7EF96fb67f6DfE5DaaF1Df` | ISRG 5000, RKLB 2500, NVDA 2500 |

Full vault/token/symbol/name list is in `deployments/robinhood-testnet-v2/addresses.json` under `.vaults` (appended additively; the key was empty before this run).

Follows (creator -> target), confirmed on chain via `followerCount`:

- alex follows nova, maya, kai (creator addresses)
- nova follows AIWIN vault, GREEN vault
- maya follows CHIPS vault, SUPER vault
- kai follows ORBIT vault, AIWIN vault

On-chain `followerCount` result: AIWIN=2, CHIPS=1, ORBIT=1, GREEN=1, SUPER=1, all others=0 — 5 vaults with a non-zero count, matching the acceptance bar.

## 5. Open items for Plan 3 / Plan 4

- Frontend ABI will land at `src/lib/abi/generated/socialRegistry.ts`, exported from the `index.ts` barrel, same shape as the other generated ABI modules.
- `followedBy(user)` is unbounded — fine for a client read, but don't assume stable ordering across renders if the user unfollows mid-session.
- No pagination on `followedBy`; if a "who follows this creator" list view turns out to be needed beyond the raw count, that would be a separate read path (e.g. derived from `Followed`/`Unfollowed` event logs client-side), not a new contract function — flag it here if you need it so it can be added before freeze.

## 6. Test and on-chain summary

- `forge test`: 609/609 passed (full repo suite, including 27 `SocialRegistry` unit tests and a `SocialRegistry` invariant suite with 7 invariants over 256 runs / 16,384 calls, 0 unexpected reverts).
- Deployer ETH: 0.00388799835 ETH before this plan's sends, 0.00068901538 ETH after (`AddAssetsV2.s.sol` + `SeedSocialV2.s.sol` combined) — stayed above the 0.0005 floor throughout, never hit zero.
- Tx records: `SocialRegistry` deploy and new asset wiring in `broadcast/AddAssetsV2.s.sol/46630/run-latest.json`; strategy creation/deposit/follow/profile calls in `broadcast/SeedSocialV2.s.sol/46630/run-latest.json`.
