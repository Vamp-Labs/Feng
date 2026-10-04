# R1: real faucet stock tokens and Paxos USDG on Robinhood Chain testnet

- **Date read and measured**: 2026-10-03, about 15:00 to 16:30 UTC (22:00 to 23:30 SGT, a Saturday, US markets closed).
- **Plan reference**: `docs/brainstorm/2026-10-03-feng-v2-plan.md` section 7 R1, D11, E1-T1, E4-T1.
- **Method**: Blockscout REST v2 and the Etherscan-style `/api` log endpoint on `https://explorer.testnet.chain.robinhood.com`; `cast` and raw JSON-RPC (`eth_call`, `eth_simulateV1`) against `https://rpc.testnet.chain.robinhood.com` with retries (the ISP intercepts TLS: about 1 in 3 `cast` calls failed with "certificate expired", all retried until success); `curl --resolve` with the DoH IP (1.1.1.1) for `faucet.paxos.com`, `docs.paxos.com`, `docs.robinhood.com`, `api.robinhood.com`, `blog.arbitrum.io`, `robinhood.com`. Verified sources downloaded from Blockscout and read in full.
- **Safety**: no transaction sent, no key used, no `.env*` file read, no faucet request submitted (see Findings 1: a faucet claim is a state change made by a third party; the coordinator forbade chain transactions, so claims are left to the user). Repository untouched except this file.
- **Evidence convention**: every claim cites a URL with the date read, or a command with its output. Helper scripts lived in the scratchpad only (not in the repo); the key commands are reproduced in the Sources section.

## Summary

1. **Real USDG and real stock tokens are both usable by a contract vault. Verdict: GO for the Live universe at demo scale (E4-T1).** Using `eth_simulateV1` against the live chain, a real holder transferred each of USDG, TSLA, AMZN, AMD, PLTR, NFLX to a fresh contract address, approved a contract spender, and the contract spender ran `transferFrom` to another contract and then sent tokens out again. All returned `true` with exact balances and no fee. Neither implementation checks `code.length` or has a fee or transfer hook.
2. **The one structural risk is that all six tokens are admin-controlled and can freeze a vault.** USDG has `pause` and `freeze` (one EOA holds both roles) plus `wipeFrozenAddress`, which burns a frozen balance. The five Stock tokens have a registry-wide pause (affects all five at once), a token-level pause, a registry blocklist, and `adminBurn` that can burn any holder's balance with no pause or block check. Zero Pause, Freeze, Blocked, Paused events have ever been emitted on either system. Under any of these a vault is frozen entirely, including `redeemInKind` (it is a plain `transfer`). Document it as a disclosed limitation.
3. **Paxos faucet**: 100 USDG per request to any address, UI text "Limit 1 request per wallet per day", **no CAPTCHA, login, KYC or wallet connection in the shipped client code** (checked by searching the 541 KB bundle). Robinhood Chain Testnet is an option in the network dropdown. USDG comes from the on-chain faucet wallet `0xcc9644EC26A647de0B9b86f1560d5180232f70a3` (15,518 transactions, 2,194,746 USDG on hand). The cap is enforced off-chain; on-chain data shows it is not strict (27% of repeat-claim gaps were under 24 h).
4. **Robinhood stock faucet**: every claim sends **5 of each of the five tokens plus 0.01 ETH** (2,000 of 2,000 recent claims identical). The on-chain `Faucet` contract has an `onlyOwner` function and no per-address cooldown; `MINTING_LIMIT` is `2^128-1` (unlimited in practice). The cooldown is enforced off-chain and unpublished (a secondary source says 24 h). The site is behind a Vercel Security Checkpoint, so the UI could not be read; a browser handles it. The deployer has made exactly one claim (2026-09-05).
5. **Canonicity of the five addresses is strong but not officially documented.** The verified `Faucet` contract's `getFullTokenList()` returns exactly these five addresses, the Arbitrum blog (2026-02-11) and Robinhood newsroom (2026-02-10) name the faucet and the five companies, but no Robinhood doc lists testnet addresses. Say "the Robinhood testnet faucet's stock tokens", not "official".
6. **Sizing**: a 500 USDG swap needs 1.345 TSLA, 1.989 AMZN, 0.789 AMD, 2.647 PLTR, 7.371 NFLX at the 2026-10-03 asks. One faucet claim (5 each, about USD 7,567 of tokens) is a large inventory; **the real bottleneck is USDG (100 per wallet per day)**, not stock tokens.
7. **Minimum viable Live seed**: 10 of each stock token in the desk (deployer's existing 5 plus one more claim) and 100 to 200 USDG (one or two Paxos claims), with a per-swap cap of 25 to 50 USDG. Human time: about 15 minutes in a browser (list at the end of Recommendations).

## Findings

### 1. Paxos faucet (https://faucet.paxos.com), Robinhood Testnet

**What the page is.** `GET https://faucet.paxos.com/` (curl --resolve to 13.33.88.27, 2026-10-03) returns a React single-page app (`<title>Paxos Faucet</title>`, bundle `/assets/index-Cnwrg2YM.js`, 541,480 bytes, `meta version v1.51066.0`). I read the bundle.

| Question | Answer | Evidence |
|---|---|---|
| Is Robinhood Testnet supported? | Yes, `USDG: {networks: ETHEREUM, SOLANA, XLAYER, ARBITRUM_ONE, INK, ROBINHOOD, MANTLE}`; label "Robinhood Chain Testnet", explorer `https://explorer.testnet.chain.robinhood.com`; the "View USDG smart contract address" link for the network goes to `.../address/0x7E955252E15c84f5768B83c41a71F9eba181802F` | bundle, string `ROBINHOOD_USDG` |
| Amount per claim | **100 tokens** (button text `Send ${GT} Tokens`, constant `GT=100`) | bundle |
| Cooldown | UI text "Limit 1 request per wallet per day"; the client also blocks a second submit within 60 s; the server returns HTTP 429 mapped to "Too many requests, please try again later." | bundle |
| CAPTCHA, KYC, login | **None in the client.** The bundle contains zero occurrences of captcha, turnstile, recaptcha, hcaptcha, kyc, login, "sign in", "connect wallet", wagmi, WalletConnect. The only third-party scripts are Datadog and CookieYes. A server-side WAF could still challenge; I could not test it without sending a request. | grep counts |
| Request | `POST ${API_DOMAIN}/v2/treasury/faucet/transfers` with JSON `{token, network, address}`; the API domain is injected at runtime (`globalThis.config.API_DOMAIN`) and is not in the HTML. I did not call it. | bundle |
| Where USDG lands | The address typed in the field "Send to" (placeholder "Wallet Address", regex `^0x[a-fA-F0-9]{40}$`). Transfer is a plain ERC-20 `transfer` from the faucet wallet. | bundle and on-chain below |
| Confirmation | "Tokens sent successfully! Testnet tokens may take a few minutes to be broadcasted and confirmed on-chain." plus a link to the explorer address page. | bundle |
| Terms | Paxos "Testnet Faucet Terms": tokens have no value, availability not guaranteed, access may be revoked at Paxos's discretion, subject to resets. | bundle |

**On-chain evidence.** The faucet wallet is `0xcc9644EC26A647de0B9b86f1560d5180232f70a3` (EOA, 54,341,680,674,820,000 wei ETH, `transactions_count` 15,518, USDG balance 2,194,746.55). It is the main recipient of USDG mints (`SupplyIncreased` events: 1,000,000 on 2026-09-17, 6.2 M and 38 M on 2026-08/09-01, 100,000 and 1,000,000 on 2026-10-01). I paged the last 2,000 USDG transfers it sent (2026-09-20T08:31Z to 2026-10-03T14:19Z, about 150 per day): **1,985 were exactly 100,000,000 (100.000000 USDG)**; the other 15 were larger manual sends (10, 100, 1,000, 25,000, 40,000, 100,000 USDG). So the UI amount matches the chain.

**Cooldown evidence is weaker than the UI text.** Among 1,242 recipients of a 100 USDG claim, 555 got more than one; of 743 consecutive-claim gaps, 201 were under 23.9 h and 143 were under 1 h, including same-second pairs. So the "1 per wallet per day" limit is not strictly enforced (race or other keying), but do not plan on exceeding it: the planned human flow uses at most one claim per day per wallet.

**Where the claim is not tested.** I did not submit a request: a claim is a transaction made by a third party onto the chain, which the coordinator ruled out. The amount, limit and absence of a CAPTCHA come from the shipped code and from the chain history, not from a live claim.

**Exact human steps (Paxos USDG into the deployer wallet).** The deployer address is public: `0x47575C31c8146022FaB38dFF5ce883b5e55F6785`. No key is needed.
1. Open https://faucet.paxos.com in the user's normal browser (the user's ISP resolves it wrongly; if the page does not load, use a VPN or Cloudflare DNS 1.1.1.1). Expect the title "Testnet Faucet" and token icons USDG, PYUSD, USDP.
2. Click the **USDG** icon (it is selected by default). Expect the Network dropdown to show USDG's networks.
3. In **Network** choose **Robinhood Chain Testnet** (the link `?token=USDG&network=ROBINHOOD` preselects it, per the bundle's URL-parameter code). Expect a "View USDG smart contract address" button that opens `0x7E955252...181802F` on the Robinhood explorer; confirm that address before sending.
4. In the **Send to / Wallet Address** field paste `0x47575C31c8146022FaB38dFF5ce883b5e55F6785`. Expect no red error; the hint under it reads "Limit 1 request per wallet per day".
5. Click **Send 100 Tokens**. Expect a green box "Tokens sent successfully!" with a "Monitor your transaction here" link to the address page.
6. Wait a few minutes (UI text), then verify on `https://explorer.testnet.chain.robinhood.com/address/0x47575C31c8146022FaB38dFF5ce883b5e55F6785` the new USDG transfer of `100` from `0xcc9644EC...70a3`, or run `cast call 0x7E955252E15c84f5768B83c41a71F9eba181802F "balanceOf(address)(uint256)" 0x47575C31c8146022FaB38dFF5ce883b5e55F6785 --rpc-url https://rpc.testnet.chain.robinhood.com` and expect `100000000` (6 decimals).
7. If the page shows "Too many requests" or "Something went wrong", wait 60 seconds and retry once, then retry the next day. If a CAPTCHA or Cloudflare/WAF challenge appears (not seen in the code), solve it as a human; do not script it.

### 2. USDG implementation (`0x7E955252E15c84f5768B83c41a71F9eba181802F`)

**Structure** (Blockscout `/smart-contracts/`, read 2026-10-03):
- `0x7E95...802F` is a verified `ERC1967Proxy` (OpenZeppelin, solc 0.8.29, paris, 200 runs). EIP-1967 implementation slot `0x3608...2bbc` holds `0xF0863D7A29a55d0c4263c11bFac754312ff078DF` (verified `USDG`, `contracts/stablecoins/USDG.sol`, solc 0.8.28, paris). `USDG` is `PaxosTokenClaimableRewards, UUPSUpgradeable`; name "Global Dollar", symbol "USDG", decimals 6.
- It is a **diamond-like token**: the main contract holds `transfer`, `transferFrom`, `approve`, `increaseApproval`, `decreaseApproval`, mint and burn, and a `fallback()` that `delegatecall`s a facet chosen from `facets[msg.sig]`. `getFacet(bytes4)` shows `pause`, `unpause`, `paused`, `freeze`, `unfreeze`, `isFrozen` are served by the verified `TokenAdminFacet` `0x204d6B842f10F04B69cCd33a31cb1cFa788C5169`; `permit`, `nonces`, `transferWithAuthorization` (EIP-2612 and EIP-3009) by the verified `TokenExtensionsFacet` `0x08f560a85db40a7d4ac49b4F44f1D38e5B8aB811`.

**Transfer logic** (`ClaimableRewardsBase._transfer`, `PaxosTokenClaimableRewards.sol`):
- `transfer` and `transferFrom` carry `whenNotPaused`; `_transfer` reverts `ZeroAddress` if `to == 0`, `AddressFrozen` if `to` or `from` is frozen, `InsufficientFunds` if short. `transferFrom` also reverts `AddressFrozen` if **msg.sender** (the spender) is frozen, and `InsufficientAllowance` if `value > allowed`. `approve` reverts if the spender or the owner is frozen.
- **No fee, no burn on transfer, no `code.length` check, no recipient hook.** Balances are plain stored integers (`uint64` at 6 decimals, a cap of about 18.4 trillion USDG). The "claimable rewards" feature (payout groups, multipliers) only changes balances through explicit `claim` calls for addresses registered into a payout group by `PAYOUT_GROUP_REGISTRAR_ROLE`; a vault that is not registered is unaffected, and `balanceOf` "NEVER includes unclaimed rewards" per the source comment. So **USDG is not rebasing for us** and `balanceOf(vault)` is stable.
- Supply control: `mint` needs `supplyControl.canMintToAddress(...)` (`0x4549bb98c667aAb626627C118102c28065E8f54C`, ERC1967 proxy over `SupplyControl` `0xc804F2e8Ae84F6CFa01d9D33ef107323bf0F9A59`, proxy unverified). We cannot mint; our desk must be funded from the faucet.

**Who can do what** (RoleGranted logs, all at block 22,380,989 (`0x15581bd`, the initialisation) unless noted; `getLogs` from block 0):
| Power | Role | Holder (2026-10-03) | Evidence |
|---|---|---|---|
| `pause` / `unpause` (global freeze of `transfer`, `transferFrom`, `approve`) | `PAUSE_ROLE` | EOA `0xC7aa9798Be85Ad3b628EE71519B38d7057f8cd7e` | RoleGranted topic `0x139c28...e46d` |
| `freeze` / `unfreeze` / `wipeFrozenAddress` (burns a frozen balance) | `ASSET_PROTECTION_ROLE` | same EOA | topic `0xe3e4f9...9796` |
| upgrade implementation (`upgradeTo`, UUPS), `setFacet`/`batchSetFacet` (replace any function, including transfer hooks, by delegatecall), `setSupplyControl`, `reclaimToken` | `DEFAULT_ADMIN_ROLE` | contract `0x3a5B30D74e90E08F0E576CF9f6F2457E44AF38B3` (unverified, has code), `defaultAdminDelay` 300 s | `cast call ... owner()`, `defaultAdmin()` |
- On-chain history: `Pause()` events 0, `Unpause()` 0, `FreezeAddress` 0, `UnfreezeAddress` 0, `FrozenAddressWiped` 0 (log counts from block 0, 2026-10-03). `paused()` is `false`; `isFrozen(<fresh address>)` is `false`.

**Real holders include contracts.** Top holders (Blockscout `/tokens/<USDG>/holders`, 4,078 holders): `0xbb9b227DDCdaE7A5B01b9B737C8d9659e14a92BF` (contract, 7,197,734 USDG), `0x6dDaD34b15f1f9349acD788C56E68Fee33B145E3` (contract, 1,788,589), `SimbaVault` `0x8D66BA5293cA1D4d8eBAA74d245dcCc37a237cc1` (contract, 327,223), Uniswap v4 `PoolManager` `0x8366...0951` (contract, 65,529). The largest EOA holder used below is `0x545FA0D7993929FEf64158F68799E6fAdfbEb983` (29,199,500 USDG, no code, not frozen).

**Proof by `eth_simulateV1`** (`cast`-style one-shot `eth_call` cannot chain state, so I used `eth_simulateV1`, which runs a sequence of calls on one pending state; the chain accepted it). Setup: a **fresh address `0x...0F1001` with no code, no nonce** received a 45-byte forwarder as a state-override (it forwards its calldata to the token, so the token sees the fresh contract as `msg.sender`; hex `0x363d3d37...3d6000f3`) and `0x...0F1002` received a tiny contract. Results, USDG (6 decimals):

| # | Call (from) | Result |
|---|---|---|
| 1 | `transfer(F, 1000e6)` from holder `0x545F...b983` (EOA) to the fresh contract F | `true` |
| 2 | `balanceOf(F)` | `1000000000` (exact, no fee) |
| 3 | `approve(F, 500e6)` by the holder (contract spender) | `true` |
| 4 | `allowance(holder, F)` | `500000000` |
| 5 | `F.transferFrom(holder, G, 300e6)` (msg.sender at the token is the contract F; recipient G is a contract) | `true` |
| 6 | `balanceOf(G)` | `300000000` |
| 7 | `allowance(holder, F)` afterwards | `200000000` |
| 8 | `F.transfer(holder, 100e6)` (contract sends its own balance out) | `true` |
| 9 | `balanceOf(F)` | `900000000` |
| 10 | `F.approve(G, 50e6)` (contract as owner) | `true` |
| 11 | `isFrozen(F)`, `paused()` | `false`, `false` |
| 13 | `F.transferFrom(holder, G, 400e6)` over the remaining allowance | reverts `0x13be252b` = `InsufficientAllowance()` |

Failure-mode simulations (state overrides on the proxy; slots verified by reading the views back: `allowed` at slot 3, `globalTransferSettings.paused` at bit 160 of slot 4, `frozen` at slot **6** (the source comment says 7, it is 6, confirmed because `isFrozen` returned `true` only for slot 6), `balanceData` at slot 1):
- **Paused**: `transfer`, `approve`, `transferFrom` all revert `0xab35696f` = `ContractPaused()`. Exit and entry both blocked.
- **Vault address frozen** (with 1,000 USDG seeded): `F.transfer(holder)` reverts `0x1fd1cc44` = `AddressFrozen()`; `holder.transfer(F)` reverts; `approve` to or from F reverts. The vault cannot receive deposits or pay redeems; `wipeFrozenAddress` could burn the 1,000 USDG.
- Control (no allowance): `transferFrom` reverts `InsufficientAllowance`.

**Verdict for USDG**: a contract can hold, receive, approve, be a spender and send USDG. No fee. Admin pause, freeze and upgrade exist but have never fired.

### 3. `Stock` implementation and registry (`0xBd14156E05c6AF28ad39aA53a2AB8eB9CDf657DA`)

**Structure** (Blockscout, 2026-10-03):
- Each token (e.g. TSLA `0xC9f9...bd4E`) is an EIP-1967 `BeaconProxy`; the beacon is the **`AccessControlsRegistry` `0x1dF3cA0fD30ED5eeb09eB01938f4E9c5196E6Ca5`** (verified; it is also the beacon: `implementation()` returns the `Stock` implementation `0xBd14...57DA`, solc 0.8.33, evm osaka). The same registry is the immutable `ACCESS_CONTROLLED_REGISTRY` in `Stock`. All five tokens share beacon slot `0xa3f0ad...3d50` = the registry (checked on the five proxies).
- `Stock` (`src/Stock.sol`): `transfer` has `onlyNotPaused`, `onlyNotBlocked(to)`, `onlyNotBlocked(msg.sender)`; `transferFrom` has `onlyNotPaused`, `onlyNotBlocked(from)`, `onlyNotBlocked(to)`, `onlyNotBlocked(msg.sender)`; `approve` has `onlyNotPaused` and `onlyNotBlocked(msg.sender)`; `permit` (EIP-2612) exists. `paused()` is `tokenPaused || registry.paused()`. `onlyNotBlocked` calls `registry.isBlocked(account)`. `mint` needs `MINTER_ROLE`, `burn` needs `BURNER_ROLE` (both also need not paused and not blocked). **`adminBurn(from, amount)` needs only `ADMIN_BURNER_ROLE` and checks neither pause nor block.** Metadata (name, symbol) is changeable by `METADATA_UPDATER_ROLE`.
- Scaled UI: `uiMultiplier()` (18-decimal fixed point) only scales `balanceOfUI` and `totalSupplyUI`; raw `balanceOf` and `transfer` amounts are unaffected. All five report `uiMultiplier() = 1e18` today, `decimals = 18`, `totalSupply ~ 6.265M`, `paused() = false`, `tokenPaused() = false`. `uid()` values: TSLA `0xaa1fee9a...63f5` (07), AMZN `0x...99c33a4e...dda0`, AMD `0x...958cc238...734e`, PLTR `0x...52cd6b00...65e0`, NFLX `0x...41de1e6a...c784` (not equal to the mainnet registry uids).
- **No fee, no `code.length` check, no hook** in `Stock`, `ERC20ScaledUIUpgradeable` or the OpenZeppelin ERC-20 base.

**Who can pause or block** (registry `RoleGranted`/`RoleRevoked` logs from block 0; role hash = `keccak256(NAME)`):
| Power | Role | Holder | Notes |
|---|---|---|---|
| Registry pause: freezes **all five tokens at once** | `PAUSER_ROLE` | EOA `0x96732e2a999279015efc3aee77f35a289feebee5` | EOA, 0 txs |
| Token-level pause (one token) | `TOKEN_PAUSER_ROLE` | EOA `0xe44cd4f96e83a090ae70fe34c3ff2cc05c9e247a` | 0 txs |
| Blocklist (`blockAccounts`, any address, any time) | `BLOCKER_ROLE` | EOA `0x642236f4839821cdbbb1e0b47bee742f3997eee0` | 0 txs |
| `adminBurn` any holder | `ADMIN_BURNER_ROLE` | EOA `0x6177a6dba58da73c5baa97238b5a47f56588b804` | `hasRole` confirmed `true` |
| Upgrade the implementation of all five tokens (beacon `upgradeTo`) | `BEACON_UPGRADER_ROLE` | EOA `0x3a4187e2468727a3347bba84a99afcb4f1e02b73` (2 txs) | `Upgraded` events: 2026-02-10 (initial), 2026-03-13T23:10Z (current impl) |
| `mint` | `MINTER_ROLE` | EOA `0x490d3035...1fd0` and the verified `Faucet` contract `0x8762F93772c663c6a88Ba50900bd5381df2717Be` | see Finding 4 |
| `burn` | `BURNER_ROLE` | EOA `0xef55c48674114721f1dc09f423d6368fa8f0204c` | |
| Registry admin | `DEFAULT_ADMIN_ROLE` | EOAs `0x16132ea4e268f35e1755cdfaa5ac392c278107c6` and `0xa5d533d53dcfcbe9b91db5844982e080475cb69e` | the creator `0x7205...2d88` revoked itself at block 0x317 |
- History: registry `Blocked`, `Unblocked`, `Paused`, `Unpaused` events: **0 each**. `Upgraded`: 2. Today `registry.paused()` is `false`, `isBlocked(fresh contract)` is `false`, `isBlocked(deployer)` is `false`.
- Real roles are held by addresses with zero or few transactions; they may be multisigs on another chain or placeholders. I could not establish who stands behind them.

**Real holders include contracts.** Edel TSLA (aToken, `0xdCa54Ba5...32Cd`, 136,390 TSLA), Aave Stock TSLA (`0x5f145b9A...5139`, 27,948), the unnamed contract `0xFfEf1147...2dA9` (329,893 TSLA), and the same pattern for AMZN, AMD, PLTR, NFLX (Blockscout holders, 2026-10-03). Lending pools therefore already hold and move these tokens.

**Proof by `eth_simulateV1`** (holder `0x13aF0afcBf609928440d7285263EC872850faFFb`, an EOA with 18 to 32 tokens of each; fresh contract F per token, forwarder as above). For **each of the five tokens** the same eight calls succeeded: `holder.transfer(F, 5e18)` `true`; `balanceOf(F)` `5000000000000000000`; `holder.approve(F, 3e18)` `true`; `F.transferFrom(holder, G, 2e18)` (spender and recipient are contracts) `true`; `balanceOf(G)` `2000000000000000000`; `allowance(holder, F)` `1000000000000000000`; `F.transfer(holder, 1e18)` `true`; `balanceOf(F)` `4000000000000000000`. So a contract holds, receives, spends via `transferFrom` and pays out all five tokens with exact amounts.

**Failure-mode simulations on TSLA** (F seeded with 5 TSLA by overriding its balance slot in the ERC-7201 `ERC20` storage `0x52c63247...ce00`; registry slots verified: `implementation`+`paused` in slot 1, `isBlocked` in slot 2):
| Scenario | `F.transfer(Y)` (vault pays out) | `holder.transfer(F)` (deposit in) | other users |
|---|---|---|---|
| A: registry `paused` | reverts `0x1309a563` = `IsPaused()` | reverts `IsPaused()` | all transfers revert, **all five tokens** |
| B: registry blocks the vault F | reverts `0x75e91ce7` = `Blocked(F)` | reverts `Blocked(F)` | unaffected (`holder.transfer(Y)` works) |
| B2: registry blocks a user Y | reverts `Blocked(Y)` | works | the vault cannot pay Y; `redeem` and `redeemInKind` to Y revert as one transaction |
| C: TSLA token-level pause | reverts `IsPaused()` | reverts | TSLA only |
| D: `adminBurn(F, 2e18)` from `ADMIN_BURNER` holder `0x6177...b804` | succeeds: F's balance goes from 5 to 3 | | a random caller gets `AccessControlUnauthorizedAccount` (`0xe2517d3f`), also for `mint` |

**What happens to a vault if it fires (failure mode and the redeemInKind implication).**
1. Pause (registry or token): every `transfer` of the affected token(s) reverts, so `redeem`, `redeemInKind`, deposits and desk swaps involving them all revert. The vault is not insolvent; it is frozen until unpause. `redeemInKind` does **not** help (it is `transfer` of the same tokens) and the plan's rule "`redeemInKind` is never paused" (8.1) only holds for our own pause switch. A single-token pause blocks every vault that holds that token, because `redeemInKind` returns all constituents in one transaction and reverts if one transfer reverts. **Mitigation for E3**: add a per-token fallback `redeemInKindPartial(shares, receiver, owner, skipMask)` or a `claimStuck(token)` ledger that records an IOU for a token whose transfer reverts (use `try/catch` with a low-level call) so one frozen token does not lock the others. This is a design recommendation, not tested.
2. Blocklist on the vault address: the vault can neither receive nor send that token (`Blocked(vault)`). Funds are stuck unless the blocker unblocks. A blocked end user cannot redeem to their own address; allow `receiver != owner` so a blocked user can redeem to another address (their share token is a plain Feng ERC-20 we control).
3. `adminBurn` or `wipeFrozenAddress` can reduce the vault's balance without any call from us: `totalAssets` falls, `previewRedeem` and the real balance diverge, and a `redeemInKind` proportional to a stale internal ledger could revert on insufficient balance. Read balances with `balanceOf`, never a cached internal count, and make in-kind payouts `min(pro-rata share, balance)`.
4. Upgrade (`upgradeTo`, beacon upgrade): a new implementation can change any behaviour for all five tokens at once. Nothing on chain prevents it.
5. Probability: zero of these has fired since launch (Feb 2026), and these are testnet tokens; Robinhood's own tokens can be paused by compliance on mainnet. State this candidly in the submission rather than hide it.

### 4. Robinhood faucet: amounts, cooldown, repeat claims

**The on-chain faucet.** Blockscout name "Faucet", verified, `0x8762F93772c663c6a88Ba50900bd5381df2717Be`, 1,250,724 transactions (2026-10-03 counters), creator `0xb71f9759FB6416E952F314b5FB422c902F3D8613`, source `src/Faucet.sol`:
- `sendTokensAndEther(address payable recipient, uint256 tokenAmount) external payable onlyOwner`: for each address in `tokenList` it adds `tokenAmount` to `totalMinted[token]`, requires `totalMinted <= MINTING_LIMIT`, calls `mint(recipient, tokenAmount)`, then forwards `msg.value` ETH to the recipient. **No per-address cooldown, no per-address cap, no signature check; only the owner can call it.**
- `owner()` = `0xF691446e9386DEDF7364340fE35B09E8fE884d81` (EOA, 1,250,619 transactions). So the web app (faucet.testnet.chain.robinhood.com) holds that key and enforces any rate limit off chain.
- `MINTING_LIMIT()` = `340282366920938463463374607431768211455` (`2^128-1`). `getFullTokenList()` = `[TSLA 0xC9f9...bd4E, AMZN 0x5884...9E02, PLTR 0x1FBE...98d0, NFLX 0x3b82...8C93, AMD 0x7117...778d]`, `supportedTokensListLength()` = 5. `totalMinted` per token about 6,265,410 tokens (1.25 M claims x 5).
- The faucet contract's own ETH balance is 0; the owner EOA attaches the ETH as `msg.value` per call.

**Amount per claim (on chain).** I paged the last 2,000 Faucet transactions (2026-10-02T08:43Z to 2026-10-03T14:59Z, 30.3 h, about 1,580 per day): **2,000 of 2,000 are `sendTokensAndEther(recipient, 5000000000000000000)` with `value = 10000000000000000` (0.01 ETH), status ok, all from the owner EOA.** So one claim = **5 TSLA + 5 AMZN + 5 AMD + 5 PLTR + 5 NFLX + 0.01 ETH**. Worth about USD 7,567 at the 2026-10-03 asks (5 x 371.80 + 5 x 251.38 + 5 x 633.50 + 5 x 188.90 + 5 x 67.83).

**Cooldown.** Not published by Robinhood or Arbitrum (Arbitrum blog says only "Use the faucet to request testnet ETH (used for transaction fees) and test versions of Stock Tokens, including Tesla, Amazon, Palantir, Netflix, and AMD, with more to come"). A secondary source (datawallet.com, article dated 2026-09-05) says "no published cap" and "Not published" for the cooldown; a search snippet elsewhere says "every 24 hours" (not verified at the source). On chain: of the 1,904 distinct recipients in the 2,000-claim window, 69 claimed more than once; 96 gaps; 52 gaps are under 24 h and 44 are under 1 h; the minimum gap is 5 s; one address received 12 claims in 30 h. So **repeat claims from one address are technically possible but the rule is not documented, and the server may throttle by address, IP or session.** Treat a claim per day per wallet as the safe assumption.

**Can the deployer claim repeatedly to seed inventory?**
- Deployer `0x47575C31c8146022FaB38dFF5ce883b5e55F6785` holds exactly 5.000000 of each of the five tokens (`cast call ... balanceOf`, 2026-10-03), 0 USDG, 0.00818173 ETH. Its single claim was a mint at 2026-09-05T07:11:20Z (tx `0xa13a80f3022c9b62d79e44721eed041897521acb524741b9a72bf74afc032a3c`, `Transfer` from `0x0` of `5e18` TSLA). No other claim in 28 days.
- Each additional claim adds 5 of each token and 0.01 ETH, so n claims give 5n of each. Reaching 10 each needs 1 more claim; 25 each needs 4 more.
- UI facts could not be read: the faucet URL serves a **Vercel Security Checkpoint** page to non-browser clients (`<title>Vercel Security Checkpoint</title>`, 2026-10-03). A normal browser passes it automatically in a few seconds. I did not try to defeat it.

**Steps for the user (Robinhood stock tokens and ETH into the deployer).**
1. Open https://faucet.testnet.chain.robinhood.com in a normal browser. Expect a short "Vercel Security Checkpoint" spinner (a few seconds), then the faucet form. If a human check appears, complete it manually.
2. Per the Arbitrum blog (2026-02-11): use "Connect" to connect a wallet, or enter the address manually. Enter `0x47575C31c8146022FaB38dFF5ce883b5e55F6785` (no wallet connection needed). The labels of the other controls are unverified (the page could not be read); if an asset selector appears, choose all five stock tokens and ETH.
3. Submit. Expect, on chain within about a minute, a `sendTokensAndEther` transaction from `0xF691446e...4d81` into the Faucet and 5 of each token plus 0.01 ETH in the deployer.
4. Verify: `cast call <token> "balanceOf(address)(uint256)" 0x4757...6785 --rpc-url https://rpc.testnet.chain.robinhood.com` for the five tokens (expect `10000000000000000000` after the second claim).
5. If a second request is rejected, try again after 24 h. Do not run scripts against the faucet.

### 5. How strongly are these five "the" Robinhood testnet stock tokens?

Evidence for, strongest first:
1. The verified `Faucet` contract `0x8762...17Be` lists exactly these five addresses in `getFullTokenList()` (call 2026-10-03). It is a `MINTER_ROLE` holder on the registry, and it is the contract behind the faucet that the Arbitrum blog links.
2. The Arbitrum blog "Robinhood Chain Launches Testnet on Arbitrum" (https://blog.arbitrum.io/robinhood-chain-testnet/, dated Feb 11, 2026, read 2026-10-03) says: "Request testnet tokens: Use the faucet to request testnet ETH (used for transaction fees) and test versions of Stock Tokens, including Tesla, Amazon, Palantir, Netflix, and AMD, with more to come." and links `http://faucet.testnet.chain.robinhood.com/` ("Get test tokens from Robinhood Faucet"). The Robinhood newsroom post (https://robinhood.com/us/en/newsroom/robinhood-chain-launches-public-testnet, Feb 10, 2026) lists "Testnet-only assets, including Stock Tokens, to be used for integration testing".
3. The token names and tickers match the five (`name()` "Tesla", "Amazon", "AMD", "Palantir Technologies", "Netflix"), all are `BeaconProxy` of one registry-beacon whose `Stock` implementation (source `src/Stock.sol`) is the same family as Robinhood's Stock Token; the registry creator `0x7205...2d88` and the token factory creator `0x2DD5b0Ea7c29006bA9450B9a4f3ADc234409e5Da` are not Feng-controlled; 220k to 292k holders each (Blockscout), consistent with the 1.25 M faucet claims.
4. They are used by Edel, Aave-fork markets ("Aave Stock TSLA" etc.), 330k-balance contracts, and community code (`hummusonrails/robinhood-chain-dapp-example` README, per 07).

Evidence against or missing:
- **No Robinhood document lists a testnet address.** The docs "Token Contracts" page (`https://docs.robinhood.com/chain/contracts`, 2026-10-03) lists only mainnet WETH and USDG and says the stock-token table is "generated live from the on-chain asset registry" (mainnet, chain 4663); it warns "a token with a matching name/ticker but a different contract address is not a Robinhood Stock Token". The docs mention no faucet at all (0 occurrences across 16 `/chain/*` pages).
- `uid()` differs from mainnet uids (07).
- The faucet owner `0xF691...4d81` is itself a holder (9,752 TSLA) and the registry roles sit on unlabelled addresses; nothing on chain proves "Robinhood Markets" controls them.

**Conclusion**: confidence "high" that these are what the faucet mints and what the ecosystem treats as the testnet stock tokens; "medium-high" that they are Robinhood-issued; "not officially documented". Wording to use in the UI and the submission: "the stock tokens issued by the Robinhood Chain testnet faucet (5 tickers)". Do not write "official Robinhood tokens".

### 6. Edel and Aave-fork contracts (one paragraph)

On the testnet, "Edel" is an Aave-v3-style lending market with an aToken for each of the five stock tokens (`Edel TSLA` `0xdCa54Ba552dc8F7dD4296b8d2dF304d9918032Cd` is an unverified `AToken` proxy holding 136,390 TSLA) plus variable-debt tokens (`Edel Variable Debt TSLA` `0x1F29BB87...8CD6`, AMD, AMZN, NFLX, PLTR), and there is a separate "Aave Stock" fork (`Aave Stock TSLA` `0x5f145b9A...5139`, NFLX, AMD, PLTR, AMZN, plus "Aave Stock USDC"), all unverified. Per doc 07 Edel's TSLA/USD feed is owner-updated and last updated 2026-06-09, so those pools price off stale data; I did not audit them. For the roadmap's collateral idea (Feng strategy shares used as collateral) this means: the markets accept the same five tokens we use, so a Feng share token could later be listed only by their owners and priced only through a feed we would have to supply (our FengAggregator), so the idea is feasible in principle but depends on third-party governance and an unaudited fork. Nothing needs action for the current build; keep it as a post-hackathon roadmap line and do not interact with the pools.

### 7. Sizing: tokens a Live-universe OracleDesk must hold for 500 USDG swaps

Prices: `GET https://api.robinhood.com/rhj/prices/{TSLA,AMZN,AMD,PLTR,NFLX}` read 2026-10-03T15:03Z (a Saturday; quotes are Friday's close, `isTradingHalt=false`, `tokenBid == bid`, `tokenAsk == ask`, multiplier 1.0 per doc 09). A user depositing USDG makes the desk **sell** tokens at the ask; a user redeeming makes the desk **buy** tokens at the bid with USDG.

| Token | Ask | Bid | Tokens per 500 USDG buy-side (desk sells) | Faucet claims (5 tokens) for one 500-USDG single-asset swap | Tokens in an equal-weight 5-asset 500 USDG deposit (100 USDG each) |
|---|---|---|---|---|---|
| TSLA | 371.80 | 371.43 | 1.345 | 0.27 | 0.269 |
| AMZN | 251.38 | 249.22 | 1.989 | 0.40 | 0.398 |
| AMD | 633.50 | 623.73 | 0.789 | 0.16 | 0.158 |
| PLTR | 188.90 | 188.36 | 2.647 | 0.53 | 0.529 |
| NFLX | 67.83 | 66.30 | **7.371** | 1.47 | **1.474** |

- Serving N swaps of 500 USDG on one asset needs N x the per-swap number: 20 swaps = 26.9 TSLA, 39.8 AMZN, 15.8 AMD, 52.9 PLTR, **147.4 NFLX** (4, 6, 8, 11, **30** claims respectively).
- For equal-weight 5-asset vaults the binding token is NFLX (cheapest per token): one claim (5 NFLX) serves 3.4 deposits of 500 USDG; 10 NFLX serves 6.8.
- The **desk also needs USDG** to buy tokens back on redemptions. At 500 USDG per redemption, 20 redemptions need 10,000 USDG, which is 100 Paxos claims (100 per wallet per day). Deposits refill the desk's USDG one-for-one, so only net outflow needs a reserve; a price rise adds an outflow (the desk pays the higher bid).
- At demo scale (50 USDG deposits, equal-weight): 0.027 TSLA, 0.040 AMZN, 0.016 AMD, 0.053 PLTR, 0.147 NFLX per deposit. 10 NFLX would serve about 68 such deposits.
- **Tokens are plentiful, USDG is the bottleneck.** The asymmetry means the desk should cap a single swap (`maxSwapUsdg` 25 to 50) and cap net outflow; a swap above the cap should fall back to `redeemInKind`.

## Recommendations

**Recommendation (list).**
1. **E4-T1 decision: GO for the Live universe at demo scale**, conditional on the guardrails below. No technical blocker was found: USDG and all five stock tokens pass hold, receive, `approve`, contract-spender `transferFrom` and contract payout simulations from real holders, with no fee. The plan's acceptance clause ("if R1 says the real tokens or USDG block contract transfers, E4 stops") is not triggered.
2. **Live constituents**: TSLA, AMZN, AMD, PLTR, NFLX (the faucet tokens only; label them "Robinhood testnet faucet stock tokens", not "official").
3. **Minimum viable Live seed (MVS)**: desk inventory **10 of each stock token** (existing 5 + one more claim) and **at least 100 USDG** (one Paxos claim; 200 USDG with two claims). Demo plan: seed 3 Live strategies with 15 to 25 USDG each and leave 25 to 50 USDG as the desk reserve. Set `maxSwapUsdg` to 25 (MVS) and raise it to 50 only after 200 USDG is in the desk. Stretch seed: 25 of each token (4 more claims) and 300 USDG.
4. **Guardrails to build into E3 and E4** (each follows from a finding above):
   - Read USDG decimals (6) and use `balanceOf` for accounting; never cache balances (adminBurn and wipe can change them).
   - Make `redeemInKind` tolerant of one token reverting (try/catch with a per-token payable-later ledger), and permit `receiver != owner` so a blocked user can still exit.
   - Document in the UI and submission: "these tokens are admin-controlled (pause, blocklist, burn, upgrade); the vault cannot override them", and show the registry `paused()` flag and each token's `paused()` in the vault page (cheap view calls) so a freeze is visible.
   - Keep the Live universe separate from Sandbox (the plan's D11) so a freeze never breaks the default demo.
   - Do not rely on USDG `permit` or EIP-3009 for the first Live release (they exist on chain, `nonces` returns 0; not simulated); use `approve` then `deposit`. `Stock` also has `permit`. Permit2 is at `0x000000000022D473030F116dDEE9F6B43aC78BA3` (doc 07).
5. **E10 (judge onboarding)**: link the Paxos faucet with `?token=USDG&network=ROBINHOOD` (the bundle reads the `token` and `network` URL parameters) and the Robinhood faucet from the Live vault page. Each judge can self-serve 100 USDG per day; this solves desk refill without our key. Verify the deep link in a browser before shipping.
6. **Desk risk**: the desk quotes at the oracle with a spread; a stale relayer on a weekend invites an arbitrageur to drain tokens. Keep the Live desk small and the per-swap cap low, and tie the cap to doc 09's staleness limit.

**Exact human actions required from the user (with time estimates).** All use a normal browser. None needs a private key or a signature. No step may be automated.
| # | Action | Where | Time | Needed for |
|---|---|---|---|---|
| H1 | Claim 100 USDG to `0x47575C31c8146022FaB38dFF5ce883b5e55F6785` using the Paxos faucet steps in Finding 1; verify `balanceOf` = `100000000` | https://faucet.paxos.com | 3 min | E4-T3 desk reserve and seed deposits |
| H2 | Claim stock tokens plus 0.01 ETH to the same address using the steps in Finding 4; verify 10 of each token | https://faucet.testnet.chain.robinhood.com | 3 min (plus 3 min per extra claim) | E4-T3 desk inventory (MVS 10 each) |
| H3 | Repeat H1 after 24 h (about 2026-10-04 evening SGT) to reach 200 USDG; repeat H2 up to 2 more times if the faucet accepts it | both | 3 min each | stretch seed |
| H4 | Optional: tell the coordinator the faucet UI labels (asset selector, any cooldown message) so the steps can be tightened | | 2 min | accuracy of E10 copy |
| H5 | Optional, before the demo: from a second browser profile or phone, claim 100 USDG to a fresh judge-like wallet and run a Live deposit to prove the judge path | | 10 min | E10, E11 demo |
Total: about 6 minutes for the MVS (H1 and H2), about 20 minutes with the stretch and rehearsal items. If H1 or H2 is rejected, the Live universe falls back to a smaller seed (deployer's existing 5 of each, no USDG: only an in-kind deposit demo) and Sandbox stays the product.

## Implications per role

- **E4 Live-universe contract agent (`general-purpose/contracts`)**: no special-casing needed to hold the tokens. Use `IERC20Metadata.decimals()` for USDG (6) and stock tokens (18); never assume a fee. Desk inventory mode must handle `transferFrom` reverting with `IsPaused`, `Blocked`, `ContractPaused`, `AddressFrozen`; wrap token calls so a revert turns into `InsufficientLiquidity` or the in-kind fallback rather than a stuck state. Per-token constants: TSLA `0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E`, AMZN `0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02`, AMD `0x71178BAc73cBeb415514eB542a8995b82669778d`, PLTR `0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0`, NFLX `0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93`; USDG `0x7E955252E15c84f5768B83c41a71F9eba181802F`. Stock `mint`/`burn` are impossible for us, so the desk cannot run in mint mode for Live.
- **E3 vault V2 agent**: per-token tolerant `redeemInKind`, `receiver != owner`, balance-based accounting (this is the main lesson from the adminBurn and block scenarios); keep the "redeemInKind never paused" rule limited to Feng's own switch and state in NatSpec/docs that token-level freezes can still block it.
- **E2 ops (relayer and keeper)**: Live feeds use the same relayer; add a monitor that reads `registry.paused()`, each `token.paused()` and `isBlocked(vault)` and the USDG `paused()` and `isFrozen(vault)` on the `/api/health` response, so a freeze is flagged before a user hits it. Faucet-wallet USDG balance (`0xcc9644...70a3`, 2.19 M) is not our concern.
- **E6 and E10 frontend (`work:frontend`)**: show the Live badge; present USDG with 6 decimals; link both faucets (deep link above); show the "admin-controlled tokens" disclosure; allow `receiver` input in the Live redeem form. Labels: "Robinhood testnet faucet stock tokens", not "official".
- **E7 deploy and E11 submission**: the Paxos USDG address and the five token addresses go in the address block; include the five-token provenance sentence from Finding 5 and the freeze disclosure. Contracts that hold real tokens should be verified on Blockscout (R4).
- **E8 tests**: add fork-or-mock tests for the four revert selectors (`IsPaused 0x1309a563`, `Blocked 0x75e91ce7`, `ContractPaused 0xab35696f`, `AddressFrozen 0x1fd1cc44`) in a mock token that reproduces them; keep `invariant`: vault balance >= claims on it unless a token-level burn occurred.
- **The user**: do H1 and H2 now (about 6 minutes); do H3 after about 24 h. Nothing here needs a key.
- **Coordinator**: E4-T1 is GO with the MVS above; the E4-T3 "needs the user" note is accurate and small.

## Assumptions and open questions

- A: Blockscout and the RPC reflect the live chain at read time (2026-10-03 ~15:00 to 16:30 UTC); `eth_simulateV1` results hold only for the state at that moment and with the stated overrides. Failure-mode simulations use state overrides on storage slots that I verified by reading the views back; they prove the revert behaviour, not that an admin will ever act.
- A: the faucet bundle (v1.51066.0) is what production serves; the API domain and any server-side WAF were not inspected.
- A: the Paxos "1 per wallet per day" and amount (100) are what the code says; the chain history confirms the amount and not the limit.
- A: Robinhood faucet amounts are as on chain (5 of each + 0.01 ETH per claim), not as documented by Robinhood.
- A: the `Stock` tokens' `uiMultiplier` stays 1.0 for these five until a corporate action; a change of the multiplier alters UI balances only, but our price conversion (`tokenBid`, `tokenAsk`, doc 09) must track it.
- Q: is a repeat Robinhood-faucet claim from the deployer accepted, and after how long? (unknown until the user tries H2 twice; 52 of 96 repeat gaps in the chain history were under 24 h, so probably yes at some cost of throttling).
- Q: does the Paxos API challenge non-browser or repeated requests (WAF)? Unknown; the user will find out in the browser.
- Q: who stands behind `PAUSE_ROLE`, `BLOCKER_ROLE`, `ADMIN_BURNER_ROLE`, `BEACON_UPGRADER_ROLE`, `DEFAULT_ADMIN_ROLE` (zero-transaction EOAs)? Probably Robinhood/Paxos multisigs or placeholders; unknown.
- Q: depth of USDG/stock Uniswap v4 pools (R3) which could serve as a USDG source for the desk by selling tokens; not measured here.

**Still unknown (list).**
1. Whether the Paxos faucet shows any challenge for a real browser and how long a payout takes (UI says "a few minutes").
2. The exact UI of faucet.testnet.chain.robinhood.com (a Vercel checkpoint blocked non-browser fetches) and its real cooldown.
3. Whether the Robinhood faucet keeps the same `5 + 0.01 ETH` tuple; changeable by the owner at any time.
4. Whether `permit` and `transferWithAuthorization` on USDG work with our deposit flow (selectors present; no signature simulated).
5. Who controls the admin roles on USDG and the Stock registry.
6. Whether Robinhood or Arbitrum will confirm the five addresses officially (an email or Discord question to the Robinhood Chain developer channel would close it).
7. Logo and brand usage terms for Robinhood and Paxos assets (carried over from doc 07).
8. Behaviour of the Stock tokens across a corporate action (multiplier change) on testnet; no such event has been emitted for these five (all `uiMultiplier` are 1e18).

## Sources

URLs read 2026-10-03 unless noted; hosts reached with `curl --resolve host:443:<DoH IP>` where the local resolver is wrong.

- Paxos faucet app and bundle: https://faucet.paxos.com/ and https://faucet.paxos.com/assets/index-Cnwrg2YM.js (541,480 bytes, v1.51066.0; strings `GT=100`, "Limit 1 request per wallet per day", `ROBINHOOD` network, `/v2/treasury/faucet/transfers`).
- Paxos docs, USDG on Test Networks: https://docs.paxos.com/guides/stablecoin/usdg/testnet (Robinhood Testnet `0x7E955252E15c84f5768B83c41a71F9eba181802F`; navigation entry "Faucet").
- Robinhood faucet (Vercel Security Checkpoint seen via curl): https://faucet.testnet.chain.robinhood.com
- Arbitrum blog (Feb 11, 2026): https://blog.arbitrum.io/robinhood-chain-testnet/ ; Robinhood newsroom (Feb 10, 2026): https://robinhood.com/us/en/newsroom/robinhood-chain-launches-public-testnet ; Arbitrum Foundation build guide (Jul 21, 2026): https://blog.arbitrum.foundation/build-your-first-dapp-on-robinhood-chain/ ; secondary faucet comparison (Sep 5, 2026): https://www.datawallet.com/crypto/get-robinhood-chain-testnet-tokens
- Robinhood docs: https://docs.robinhood.com/chain/ (16 pages under `/chain/` searched for "faucet": 0 hits), https://docs.robinhood.com/chain/contracts (mainnet-only token table, canonicality sentence), https://docs.robinhood.com/chain/connecting (testnet RPC and explorer), https://docs.robinhood.com/chain/protocol-contracts (Permit2, L2 Multicall).
- Robinhood prices: `GET https://api.robinhood.com/rhj/prices/{TSLA,AMZN,AMD,PLTR,NFLX}` at 2026-10-03T15:03Z: TSLA 371.43/371.80, AMZN 249.22/251.38, AMD 623.73/633.50, PLTR 188.36/188.90, NFLX 66.30/67.83.
- Blockscout REST (base `https://explorer.testnet.chain.robinhood.com/api/v2`): `/smart-contracts/0x7E955252E15c84f5768B83c41a71F9eba181802F`, `/smart-contracts/0xF0863D7A29a55d0c4263c11bFac754312ff078DF` (USDG, 38 sources, `PaxosTokenClaimableRewards.sol`, `ClaimableRewardsBase.sol`, `BaseStorageV3.sol`), `/smart-contracts/0x204d6B842f10F04B69cCd33a31cb1cFa788C5169` (`TokenAdminFacet`), `/smart-contracts/0x08f560a85db40a7d4ac49b4F44f1D38e5B8aB811` (`TokenExtensionsFacet`), `/smart-contracts/0xBd14156E05c6AF28ad39aA53a2AB8eB9CDf657DA` (`Stock`, `AccessControlled.sol`, `ERC20ScaledUIUpgradeable.sol`, `Roles.sol`), `/smart-contracts/0x1dF3cA0fD30ED5eeb09eB01938f4E9c5196E6Ca5` (`AccessControlsRegistry`), `/smart-contracts/0x8762f93772c663c6a88ba50900bd5381df2717be` (`Faucet`), `/tokens/<addr>/holders`, `/tokens/<addr>/transfers`, `/addresses/<addr>`, `/addresses/<addr>/counters`, `/addresses/<addr>/token-transfers?type=ERC-20&filter=from&token=<USDG>` (40 pages = 2,000 transfers), `/addresses/0x8762...17be/transactions` (40 pages = 2,000 transactions), `/search?q=Edel`, `/search?q=Aave%20Stock`.
- Blockscout log API: `https://explorer.testnet.chain.robinhood.com/api?module=logs&action=getLogs&fromBlock=0&toBlock=latest&address=<addr>&topic0=<hash>` for `RoleGranted` `0x2f878811...f0d`, `RoleRevoked` `0xf6391f5c...171b`, `SupplyIncreased` `0xf5c174d5...8797`, `FreezeAddress` `0x1aa66049...c392`, `UnfreezeAddress` `0x150465b0...9bbe`, `Pause()` `0x6985a022...f625`, `Unpause()` `0x7805862f...5b33`, `FrozenAddressWiped` `0xfc5960f1...aede`, registry `Blocked`, `Unblocked`, `Paused`, `Unpaused`, `Upgraded`.
- RPC commands (all via `https://rpc.testnet.chain.robinhood.com`, retried): `cast call 0x7E95...802F "name()(string)"` "Global Dollar"; `"decimals()(uint8)"` 6; `"paused()(bool)"` false; `"totalSupply()(uint256)"` 57301240000000; `"owner()(address)"` `0x3a5B30D74e90E08F0E576CF9f6F2457E44AF38B3`; `"supplyControl()(address)"` `0x4549bb98...f54C`; `"getFacet(bytes4)(address)"` for `pause()` `0x8456cb59`, `freeze(address)` `0x8d1fdf2f`, `isFrozen(address)` `0xe5839836`, `permit` `0xd505accf`; `cast storage 0x7E95...802F 4` = `0x...01518000699cea00`; `cast call 0x8762...17Be "owner()(address)"` `0xF691446e9386DEDF7364340fE35B09E8fE884d81`, `"MINTING_LIMIT()(uint256)"` `340282366920938463463374607431768211455`, `"getFullTokenList()(address[])"` the five tokens; `cast call 0x1dF3...E6Ca5 "implementation()(address)"`, `"paused()(bool)"` false, `"isBlocked(address)(bool)"` false; `cast call <stock> "uiMultiplier()(uint256)"` 1e18 and `"uid()(bytes32)"`, `"paused()(bool)"` false for the five tokens; `cast balance 0x4757...6785` 8181727130000000 wei.
- Simulation method: `eth_simulateV1` via JSON-RPC (`blockStateCalls` with `stateOverrides` for the fresh forwarder code and storage slots; `validation:false`). Calldata built with `cast calldata`; slots with `cast index`. Forwarder runtime for token T: `0x363d3d37 3d3d363d3d73 <T> 5af1 3d600060003e 602d57 3d6000fd 5b 3d6000f3`. Fresh test addresses `0x...0F1001`, `0x...0F1002` (USDG) and `0x...0F2001..` (Stock): code `0x`, nonce 0 verified. Selectors checked with `cast sig`: `InsufficientAllowance()` `0x13be252b`, `ContractPaused()` `0xab35696f`, `AddressFrozen()` `0x1fd1cc44`, `IsPaused()` `0x1309a563`, `Blocked(address)` `0x75e91ce7`, `ZeroAddress()` `0xd92e233d`.
- Repo evidence read: `docs/research/07-testnet-reality-check.md` (sections 2.1 to 2.4), `docs/research/09-price-source-and-feed.md` (tokenBid/tokenAsk, multiplier 1.0, weekend quotes), `docs/brainstorm/2026-10-03-feng-v2-plan.md` sections 0, 4 D11, 6 E1 and E4, 7 R1, 8.1.
