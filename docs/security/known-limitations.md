# Known limitations (draft for the README)

- **Status**: draft 1.0, 2026-10-03, by the independent security reviewer. E8-T5 asked for it "if G1 fails"; it is written so it is true in both outcomes.
- **How to use**: every entry carries a scenario tag. `[V1]` is true only while the V1 contracts are the production deployment. `[V2]` is true only if V2 passes G1 and becomes production. `[BOTH]` is true either way. **If V1 ships**: delete every `[V2]` entry and section "B", keep sections "A" and "C", paste block P1. **If V2 ships**: delete every `[V1]` entry and section "A", keep "B" and "C", paste block P2, and optionally keep entry KL-HIST-01 as a one-line history note. Entries marked `{{...}}` depend on a decision or a number that must be confirmed at ship time (list in section D).
- **Wording rules** (from `docs/research/09-price-source-and-feed.md` and the Robinhood Brand Guidelines): write "Robinhood Chain" in full, say "Stock Tokens" for Robinhood's tokens, call ours "mock stock tokens", and never claim an audit.
- **Evidence**: `docs/security/threat-model.md` (threats T-xx, findings F-xx), `docs/security/poc/V1Exploits.t.sol` (local proofs of concept for the V1 entries), `docs/security/review-checklist-v2.md`, and later `docs/security/review-v2.md`.

## P1. Paste-ready block if V1 ships

> **Known limitations (read before depositing).** Feng runs on Robinhood Chain testnet with mock USDG and mock stock tokens; nothing here has real value and nothing has been audited by a third party. The V1 contracts have two known design flaws that we chose to disclose rather than hide. First, a vault keeps deposited USDG as a cash pot and mints mock stock tokens next to it; redemption pays a pro-rata share of the cash pot, not the net asset value, so after a price move the payout can differ from the previewed value and value moves between early and late depositors. Second, the testnet price feeds are open mock aggregators that anyone can update, so anyone can set any price; combined with the first flaw, a proof of concept on a local copy of the contracts took the entire USDG balance of a vault using 1 USDG. We also found that an owner who approves a vault on a strategy token lets anyone redeem that position. V1 uses 18-decimal mock USDG and cannot use Paxos USDG. These issues are fixed by design in the V2 contracts (`docs/handoffs/04-contracts-v2.md`), which are not the deployed ones. Details: `docs/security/known-limitations.md`.

## P2. Paste-ready block if V2 ships

> **Known limitations (read before depositing).** Feng runs on Robinhood Chain testnet. Strategies are custodied by vaults that hold real token balances and trade through a venue; in the Sandbox universe that venue is a mock market maker (an oracle-priced desk with a 10 bps spread and a finite USDG reserve) and the stock tokens are our mocks, priced by a role-gated relayer that republishes Robinhood Stock Token API quotes every few minutes. Consequences you should know: prices lag the real market by up to one relayer tick and are frozen at the Friday close over the weekend; the relayer, the desk owner, the guardian and the deployer are trusted roles held by the team on testnet (the guardian can pause deposits and rebalances but never exits); USDG redemptions depend on the desk reserve, while `redeemInKind` always works and needs no oracle or desk; if a real token or USDG is paused or blocklisted by its issuer the affected slice cannot be moved. The contracts are immutable, were tested with unit, fuzz and invariant tests and reviewed by an independent pass, and have not had a third-party audit. {{Live universe: real Stock Tokens and Paxos USDG at demo scale only}}. Details: `docs/security/known-limitations.md`.

---

## A. V1 limitations

### KL-V1-01 [V1] Redemption pays a cash pot, not net asset value
- **What happens**: `deposit` keeps the USDG as idle cash and also mints mock stock tokens at the oracle price. Net asset value counts only the stock tokens (`StrategyVault._totalAssetsUSDG`, `contracts/StrategyVault.sol:258-263`) and share minting uses it (`:278-280`). `redeem` pays `usdg.balanceOf(vault) * shares / supply` (`:116`) and burns the stock tokens without paying for them.
- **Measured** (local proof of concept, `test_poc_payoutDoesNotFollowNav`): Alice deposits 100 USDG at price 250; the price doubles; Bob deposits 100 USDG. `previewRedeem` shows Alice 200 and Bob 100. Actual payouts: Alice 133.33, Bob 66.67. Bob loses 33.33 to Alice without any trade.
- **Why it ships**: it is the V1 design from `docs/handoffs/contracts.md` ("asset-acquisition simplification"); fixing it needs the custody model of V2.
- **What would fix it**: V2 (venue-based custody, idle USDG in NAV, pro-rata physical redemption, spec C-01).

### KL-V1-02 [V1] Anyone can set any price, and with KL-V1-01 can take a vault's USDG
- **What happens**: the six feeds behind the V1 vaults are `MockV3Aggregator` with ungated `updateAnswer` and `updateRoundData` (`contracts/mocks/MockV3Aggregator.sol:29-34`). Shares are minted at NAV, so an attacker sets every constituent price to 1 (8 decimals), deposits 1 USDG and receives about a million times the existing supply, restores the price and redeems the cash pot pro-rata.
- **Measured** (local proof of concept, `test_poc_openFeedDrainsCashPot`): a vault holding 20,000 USDG of other depositors' money; the attacker put in 1 USDG and took out 20,000.98 USDG. Everything is mock USDG, so no real value is at risk, but a judge or a bot can do this to every V1 vault today. The deployed contracts have the same source (checksums in `docs/handoffs/v1-sources.sha256`); this was not run against the chain.
- **Why it ships**: the feeds are open on purpose so the keeper and the demo can refresh prices without keys (`scripts/refresh-feeds.sh` uses any funded key).
- **What would fix it**: V2 `FengAggregator` (role-gated, bounded, no back-dating) plus pro-rata physical redemption. A partial V1 mitigation, if V1 must stay live, is to stop promoting the V1 vaults and to hold the deployed feeds fresh with one key; it does not remove the hole.

### KL-V1-03 [V1] An approval to the vault lets anyone redeem the owner's shares
- **What happens**: `redeem(shares, receiver, owner)` with `msg.sender != owner` pulls the owner's shares using the owner's allowance to the vault and never checks the caller (`contracts/StrategyVault.sol:118-123`). If an owner ever approves the vault on the share token, any address can redeem that position to any receiver.
- **Measured**: local proof of concept `test_poc_delegatedRedeemHole`: an unrelated address received Alice's 1,000 USDG position after she approved the vault.
- **Exposure today**: no Feng screen asks for that approval; the risk is third-party tools and users who approve manually.
- **What would fix it**: V2 `StrategyTokenV2.burnFrom(owner, spender, amount)` spends the caller's allowance (spec C-02).

### KL-V1-04 [V1] 18-decimal mock USDG only; Paxos USDG and real Stock Tokens are not supported
- **What happens**: the share math assumes 18-decimal USDG (`contracts/StrategyVault.sol:96`, `src/lib/format.ts`); Paxos USDG on Robinhood Chain testnet has 6 decimals, so using it would be wrong by a factor of 10^12. The factory also calls `grantRole` on every constituent (`contracts/StrategyFactory.sol:93`), which reverts for tokens we do not administer, and the vault mints and burns its constituents, which real Stock Tokens do not allow.
- **Consequence**: there is no Live universe in V1; every asset is a mock.

### KL-V1-05 [V1] Redeem and deposit stop when any price is older than 24 hours; there is no in-kind exit
- **What happens**: `_checkAllFresh` runs on `deposit`, `redeem` and `executeRebalance` (`contracts/StrategyVault.sol:77, 112, 178`). Measured on 2026-10-03 14:31 UTC (`docs/research/09-price-source-and-feed.md` section 3): all six feeds were 50.1 hours old and a `cast call` of `deposit` and `redeem` on the AIGR vault reverted `StalePrice`. {{Update with the state at ship time and with the ops soak result.}}
- **Why it ships**: the keeper and a price heartbeat are what keep V1 usable; they depend on a host being up (E2).
- **What would fix it**: V2 `redeemInKind` needs no oracle and no venue.

### KL-V1-06 [V1] Mint and burn at the oracle price: no spread, no slippage controls, no min-out
- **What happens**: V1 "buys" assets by minting mock stock tokens at the oracle price with no spread and no `minShares` or `minUsdgOut` parameter. It is a simulation of a market, not a market.
- **What would fix it**: V2 venue interface, 10 bps desk spread, `minShares` and `minUsdgOut`.

### KL-V1-07 [V1] Nested redeem returns child strategy tokens
- **What happens**: redeeming a depth-2 strategy pays the USDG pot share and transfers the inner strategy tokens (`contracts/StrategyVault.sol:133-135`); the user must redeem the child separately. This is documented behaviour (test `test_depth2_redeem_returnsInnerStrategyTokenUnits`), kept for completeness.

### KL-V1-08 [V1] Keeper, registry and factory are minimal
- `RebalanceEngine.checkUpkeep` is unbounded and one reverting vault blinds it; `performRebalance` accepts any address; `rebalanceNeeded` reports `timeBased` for an empty vault; the factory accepts any address as a constituent with no cap on count, no minimum weight and no interval limits; the registry has no metadata or pagination and creation is permissionless, so listings can be spammed. All are fixed in V2 (spec C-07, C-16, C-19, C-20); none loses funds.

### KL-V1-09 [V1] Contracts unverified on the explorer {{remove when E7 verification is done}}
- At 2026-10-03 the V1 contracts were not verified on the Robinhood Chain explorer; source in this repository is the reference (`docs/handoffs/v1-sources.sha256`).

### KL-V1-10 [V1] Seed prices are not market prices
- The V1 feeds hold fixed seed values (TSLA 260, AMZN 183, NFLX 581, PLTR 26, AMD 138) while real quotes were TSLA 371 and PLTR 188 on 2026-10-03 (`docs/research/07-testnet-reality-check.md` section 2.3). Performance numbers in V1 are not market performance.

## B. V2 limitations (only if V2 ships)

### KL-V2-01 [V2] The price relayer is a trusted role
- **What happens**: prices come from Robinhood's Stock Token API (undocumented `tokenBid`/`tokenAsk`, no SLA) through a relayer holding `UPDATER_ROLE` on six `FengAggregator` contracts. There is no Chainlink feed for Robinhood Chain testnet.
- **Bounds**: each update must stay within {{maxDeviationBps: 1000 or 1500}} bps of the last answer; the role is revocable; there is no back-dating.
- **What is not bounded**: {{IF F-01 NOT adopted}} a stolen relayer key can chain updates in one block and reach any price; the per-update bound limits a bad API value, not a stolen key. {{IF F-01 adopted}} a stolen key can move a price by one bound per {{minimum interval}}; revoke within minutes. {{IF ENABLE_SHOCK=1}} the same key can display a plus or minus 30 percent shock.
- **Consequence on testnet**: a manipulated price lets an attacker drain the desk reserve (mock USDG); user shares are repriced consistently with the desk.
- **Mainnet path**: replace `FengAggregator` with Chainlink proxies through `ChainlinkPriceOracleV2`; not tested here.

### KL-V2-02 [V2] The venue is a mock market maker with a finite reserve
- **What happens**: in the Sandbox universe the `OracleDesk` mints and burns mock stock tokens against a mock USDG reserve at oracle price plus or minus 10 bps. It is liquidity by construction, not a market.
- **Consequences**: (a) USDG redemptions and rebalance sells revert if the reserve is empty or the desk owner pauses a token (`redeemInKind` is unaffected); (b) the owner can withdraw the reserve and change the spread at any time; (c) {{IF F-02 NOT adopted}} one transaction can trade the whole reserve at the current oracle price.
- **Informed trading**: a trader who sees the real price before the relayer pushes can deposit and redeem against the stale price; the desk takes the loss, not other holders. A moving price of more than about 20 bps within one tick is profitable. On a leaderboard this can distort rankings.

### KL-V2-03 [V2] Prices lag the market and freeze outside trading hours
- **What happens**: the relayer ticks every {{5 minutes}}, pushes on a 10 bps move or after 30 minutes. The API serves the Friday quote through the weekend (verified: byte-identical over 50 minutes on a Saturday), so the heartbeat republishes an old price with a fresh timestamp.
- **Consequences**: weekend and holiday prices are frozen; Monday gaps are priced at the first tick; a dead relayer leaves vaults tradable at the last price for up to {{12 h or 6 h}} (`maxPriceStaleness`), after which deposits, USDG redemptions and rebalances revert `StalePrice` while `redeemInKind` keeps working.
- **Not handled**: corporate actions (the relayer holds pushes while Robinhood marks a pending multiplier), trading halts beyond the API flag, a USDG depeg (USDG is assumed to equal 1 USD).

### KL-V2-04 [V2] Exits: what is guaranteed and what is not
- **Guaranteed by design**: `redeemInKind` and `redeemInKindExcluding` never read a feed and never call the desk; the guardian cannot pause any redeem function.
- **Not guaranteed**: USDG `redeem` needs fresh prices and desk liquidity; for a nested strategy the child must be able to unwind (`ChildRedeemFailed`). In-kind exit of a nested strategy returns child strategy tokens, which you then redeem.
- **Frozen assets**: if the issuer of a real token or of USDG pauses it or blocklists the vault, that slice cannot move; you can exit with every other asset and forfeit the frozen slice (`redeemInKindExcluding`). We do not recover frozen assets.

### KL-V2-05 [V2] Trusted keys and no timelock
- On testnet one deployer key is admin or owner of the mock USDG, mock stock tokens, aggregators, oracle, desk, registry and faucet, and is the default guardian ({{GUARDIAN_ADDRESS set or not}}). The guardian can pause deposits, in-kind deposits and rebalances (no expiry) but not exits, and cannot move funds. There is no timelock and no multisig. The contracts are immutable: a bug means redeploying.

### KL-V2-06 [V2] Live universe (real Stock Tokens and Paxos USDG) {{only if E4 ships}}
- Demo-scale only, seeded from faucet claims. The issuers' tokens are upgradeable proxies with pause and blocklist; we assert `uiMultiplier() == 1e18` and 6-decimal USDG at deploy but do not handle later multiplier changes. The desk runs in inventory mode with whatever tokens and USDG a human supplied; once it is empty, USDG redemptions revert and in-kind remains. Prices come from the same relayer as Sandbox.

### KL-V2-07 [V2] Costs and dilution inherent to the design
- Every rebalance trade pays the desk spread (up to about 20 bps of the notional shifted); short intervals (a 1-hour strategy) bleed holders by design; `depositInKind` is valued at the oracle with no spread, so a depositor can externalise up to about `2 * spread` of the deposited notional to existing holders (bounded by the weight cap); a donation of a constituent to a vault can force a rebalance whose spread holders pay (the donor loses the donation). Share price can dip by less than 1e-6 relative on a deposit at a price above 1 (virtual shares). Protection against first-depositor inflation attacks is verified for donations up to about 1e12 USDG-equivalent and by fuzzing; beyond that range it is untested.

### KL-V2-08 [V2] Nested strategies couple availability
- A depth-2 strategy cannot deposit or rebalance while a child is paused, stale or cannot trade (all-or-nothing), and `previewDeposit` for nested vaults is approximate (tolerance in spec C-36; use `minShares`). The depth cap is 2 and each strategy has at most 6 constituents.

### KL-V2-09 [V2] Marketplace and faucet are open
- Anyone can create strategies (about 0.00005 ETH each): expect spam, lookalike names and descriptions (the frontend escapes them and shows creator and vault address, but cannot stop impersonation). Anyone can deploy a vault through `VaultDeployerV2`; unregistered vaults cannot trade on the desk or be nested, and the frontend lists only registered strategies. The keeper filters or pages; it can be drained of gas by spam {{IF F-08 not adopted}}.
- The faucet gives 0.0002 ETH {{or the final amount}} and 10,000 mock USDG once per address, through a server wallet with per-IP limits; fresh addresses defeat "once per address", and the faucet holds {{funded ETH / ethPerClaim}} claims, after which it reports `FaucetEmpty`. Do not depend on it for a live demo without checking the balance.

### KL-V2-10 [V2] Scope and evidence
- Not implemented: management or performance fees, on-chain follow, upgradeability, a Uniswap v4 venue {{unless E4-T5 ships}}, Chainlink on testnet, Data Streams.
- Evidence: Foundry unit, fuzz and invariant suites (I1 to I11), a decimals matrix at 6 and 18, hostile-token mocks, coverage {{lines}} percent lines and {{branches}} percent branches on `contracts/v2`, and an independent review (`docs/security/review-v2.md`, {{open High/Critical: 0}}). Not done: a third-party audit, formal verification, Slither or Echidna runs {{unless run}}.

### KL-HIST-01 [V2] History note (optional)
- The first deployment (V1, archived) used a cash-pot redemption model and open mock price feeds; both were replaced in V2 (`docs/security/threat-model.md` section 6). V1 addresses remain on the explorer and must not be used.

## C. Limitations that hold in both outcomes

### KL-ALL-01 [BOTH] Testnet, mock money, no audit
- Robinhood Chain testnet only. USDG is mock (Sandbox) or faucet-limited Paxos testnet USDG (Live); no value at risk. No third-party audit has been done; the security work in `docs/security/` is an in-house independent review, not an audit.

### KL-ALL-02 [BOTH] Prices are references, not a live market
- Sandbox prices are quotes from Robinhood's Stock Token API republished by us (V2) or fixed seed values (V1); there is no Chainlink data feed for Robinhood Chain testnet. A mainnet deployment needs per-feed staleness limits (about four days for Stock Tokens given 24/5 trading, 26 hours for USDG), sequencer-uptime and `oraclePaused` checks, none of which exist here.

### KL-ALL-03 [BOTH] Always-on operations depend on a host
- The price relayer and the keeper run on a host chosen in E2 (R5). If the host or its funded wallets stop, prices go stale after the configured window and rebalances stop; the health endpoint shows it. Rebalancing is permissionless, so anyone can run the keeper.

### KL-ALL-04 [BOTH] USDG is assumed to be 1 USD
- Vaults never read a USDG price; a depeg of USDG is out of scope.

### KL-ALL-05 [BOTH] Network
- The public RPC is intermittently unreachable from some networks (TLS interception by some ISPs); that affects the demo, not the contracts.

### KL-ALL-06 [BOTH] Product limits
- Composition depth is capped at 2; share tokens are plain ERC-20; strategy history is event-sourced and starts at deployment.

## D. Facts to re-verify before pasting

1. Feed freshness and keeper liveness now (`/api/ops/health`, or `cast call <feed> 'latestRoundData()'`); replace the numbers in KL-V1-05.
2. Explorer verification status of the shipped contracts (KL-V1-09).
3. Decisions F-01 (relayer rate limit), F-02 (desk cap), F-03 (`ENABLE_SHOCK`), F-04 (faucet budget), F-05 (staleness window), F-08 and F-09 (keeper filter, guardian key) from `docs/security/threat-model.md` section 7; edit the `{{...}}` conditions in KL-V2-01 to KL-V2-09 accordingly.
4. The desk reserve and spread actually deployed (`reserveUsdg()`, `spreadBps()`), the faucet balance and claim count, and the guardian address.
5. Coverage and review results once `docs/security/review-v2.md` exists (KL-V2-10).
6. Whether the Live universe shipped (KL-V2-06).
7. That the V1 deployment is still the same source as `docs/handoffs/v1-sources.sha256` before quoting KL-V1-01 to KL-V1-03 as properties of the live contracts.
