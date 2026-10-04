# Feng demo script (3:00, timed)

Based on plan section 6.1 (`docs/brainstorm/2026-10-03-feng-v2-plan.md`) and the routes that exist in the app today: `/`, `/marketplace`, `/strategy/<vault>`, `/create`, `/positions`. UI labels below are the strings in `src/components/` on 2026-10-03; if the frontend lane renames one, trust the screen and fix this file.

**Skeleton pass.** Every V2-PENDING marker in this file marks something that depends on the V2 redeploy (Gate G1, 2026-10-04 10:21 SGT) or on features still being built by other lanes (test-funds button, performance view, slippage control, always-on ops). The script below works on the V1 deployment as it is on chain today; V2 only changes addresses and adds optional beats.

The recording is edited (waits for confirmations are cut) but nothing is faked: every transaction shown is real and its hash goes to the explorer tab. Record each beat as its own take so a flaky RPC costs one take, not the whole video.

## Cast of objects

| Object | V1 value (testnet, 2026-10-03) | Used in |
|---|---|---|
| App | https://composable-strategy-marketplace.vercel.app `[V2-PENDING: final URL, /marketplace must return 200]` | all beats |
| CORE (depth 2: AIGR 40, EQ5 40, TSLA 20) | `/strategy/0x2006Ef785A04b57c872E4C31Da3AcAd4550899dE` `[V2-PENDING: V2 vault address]` | beat 3, 4 |
| EVMO (TSLA 40, AMD 30, PLTR 30; max weight 40 percent) | `/strategy/0x9Ca97af52f2e1D03d86f48519CdD62dDA8a1E7cC` `[V2-PENDING: V2 vault address]` | beat 5 |
| AIGR (depth 1) and STRM (depth 1) | `/strategy/0x9f6123c775B62a88b7403ca8CaF41B0Ea6B2438B`, `/strategy/0x53e3d8394eaba13a4dd6DAB1fC88a305f7eC7EaC` `[V2-PENDING]` | beat 6 |
| Demo wallet | the Privy email wallet created at sign-in | beats 2 to 7 |
| Keeper wallet | separate address, never the demo wallet; its address is public on chain | beat 5 |
| Explorer | https://explorer.testnet.chain.robinhood.com | beats 4, 5 |

## Pre-flight checklist (T-60 minutes, then again T-10)

Run every item; do not record until all pass. Commands read only; keys come from your shell environment and are never typed on screen.

1. **Network is not filtered.** Five consecutive reads must succeed (the ISP TLS interception is intermittent): `for i in 1 2 3 4 5; do cast chain-id --rpc-url https://rpc.testnet.chain.robinhood.com || echo FAIL; done` should print `46630` five times. Any FAIL: switch to a phone hotspot or VPN outside the filter and repeat.
2. **Site is the current build.** `curl -sS -o /dev/null -w '%{http_code}\n' https://composable-strategy-marketplace.vercel.app/marketplace` prints `200`, and the tab title says Feng. `[V2-PENDING: replace the URL if a new alias is used]`
3. **Feeds are fresh.** `[V2-PENDING: /api/ops/health route deployed]` Run `curl -s https://composable-strategy-marketplace.vercel.app/api/ops/health | jq '{ok, alarms, feeds: [.feeds[] | {symbol, ageSec}]}'`; expect `ok: true`, `alarms: []` and every `ageSec` under 2100 (35 minutes). Fallback that works on V1 today: for each feed in `deployments/robinhood-testnet/addresses.json` (`priceOracles`) run `cast call <feed> "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url https://rpc.testnet.chain.robinhood.com`; the fourth value is `updatedAt`; `date +%s` minus it must be under 3600 (V1 reverts every deposit, redeem and rebalance with `StalePrice` after 86,400 seconds, so refresh with `scripts/refresh-feeds.sh robinhood-testnet` and a funded key in your environment if needed).
4. **Funds.** Demo wallet: at least 0.0005 ETH and at least 2,000 USDG (`cast balance <demo>`; `cast call <usdg> "balanceOf(address)(uint256)" <demo>`; V1 mock USDG has 18 decimals, so 2,000 USDG is `2000000000000000000000`). `[V2-PENDING: with the faucet, show the "Get test funds" button instead of funding by script, and USDG has 6 decimals]` Keeper wallet: at least 0.0005 ETH. If a new wallet needs funds: `scripts/fund.sh <address> 10000 0.0005` with `DEPLOYER_PRIVATE_KEY` in the environment.
5. **Wallet network.** After sign-in the nav badge reads the testnet name (not the amber "Wrong network"). If amber, click the badge to switch.
6. **Demo state for beat 5.** Pick the shock method and confirm the vault reports a needed rebalance before recording: `cast call <EVMO vault> "rebalanceNeeded()(bool,bool)" --rpc-url https://rpc.testnet.chain.robinhood.com` shows `true` in either position. V1 shock (the mock feed's `updateAnswer` is open): push TSLA from 260 to 307 USD, an 18 percent move that takes TSLA in EVMO from 40 to about 44 percent: `cast send <TSLA feed 0x07E30B29789019D681346326d62e2Abdea88B4c0> "updateAnswer(int256)" 30700000000 --rpc-url https://rpc.testnet.chain.robinhood.com --private-key "$SHOCK_KEY"`. `[V2-PENDING: use the V2 demo-shock script and its relayer-signed two-step push; the V1 open updateAnswer disappears in V2]`
7. **Keeper is quiet until needed.** Stop the loop keeper (`scripts/keeper.sh`) and pause the pinger job `[V2-PENDING: cron-job.org tick job]` so the vault is still flagged when the take starts. Have one command ready: `KEEPER_PRIVATE_KEY` in the environment, then `scripts/keeper.sh robinhood-testnet 30 1` (one iteration).
8. **Browser.** One window, 1920 by 1080, 100 percent zoom, dark theme, bookmarks and extensions hidden, notifications off, Privy session already created (sign-in is recorded as a separate take). Tabs ready in order: app home, explorer on the EVMO vault address (`/address/<vault>?tab=logs`), terminal with the one-iteration keeper command.
9. **Rehearse twice with a stopwatch.** Each beat must land inside its window below. Cut anything that does not.

## Timed script

| Time | Beat | Screen | Narration (about 140 words per minute) |
|---|---|---|---|
| 0:00 to 0:20 | 1. Problem and one-liner | `/` hero | "Tokenized stocks are easy to hold and hard to manage. Feng turns an investment strategy into a token: the weights, the rules and the rebalancing live on chain. And because a strategy is a token, it can sit inside another strategy. This is Feng, on Robinhood Chain testnet." |
| 0:20 to 0:50 | 2. Sign in and marketplace | nav, Privy, `/marketplace` | "I sign in with an email. Privy creates a wallet, no extension needed. `[V2-PENDING: One click gets test ETH and test USDG.]` The marketplace reads every strategy straight from an on-chain registry: ten strategies, their NAV, and what each one holds. Two of them are nested." |
| 0:50 to 1:25 | 3. Composability | `/strategy/<CORE>` | "Core Satellite holds two other strategies and one stock. Depth two. AI Growth and Big Five Equal are Strategy Tokens, not stocks, and the NAV I see here is read from their vaults live. The factory caps nesting at two levels and rejects cycles, so the recursion is bounded." |
| 1:25 to 2:00 | 4. Deposit | deposit panel, explorer | "I deposit a thousand USDG. Approve, then deposit, and the vault mints strategy shares. The preview tells me what I receive before I sign. `[V2-PENDING: and a minimum-shares limit protects me from slippage.]` On this testnet the stock tokens and the USDG are mocks, and the README lists exactly what is mocked." |
| 2:00 to 2:30 | 5. Keeper rebalance | `/strategy/<EVMO>`, terminal, explorer | "Now the rules. A price shock pushed Tesla above this strategy's maximum weight, so the vault says Threshold breached. Rebalancing is permissionless: this keeper is a plain address with no special role. It calls the engine, and here is the event on the explorer. Weights are back to target." |
| 2:30 to 2:50 | 6. Compose a new strategy | `/create` | "Composing takes a minute. I tap AI Growth and Streaming Giants, split evenly, name it, and create. One transaction, and a new depth-two strategy is in the marketplace." |
| 2:50 to 3:00 | 7. Redeem and close | strategy page, end card | "Redeem any time. Feng: investment strategies as composable onchain primitives. Real chain, real contracts, real keeper. Mock assets, stated plainly. `[V2-PENDING: replace the last sentence if the Live universe with real Paxos USDG shipped and was shown.]`" |

Spoken word counts (without the V2 sentences): beat 1 is 48 words, beat 2 is 37, beat 3 is 49, beat 4 is 43, beat 5 is 49, beat 6 is 28, beat 7 is 20; 274 words in total, about 2:00 of speech at 140 words per minute, which leaves about a minute for on-screen actions and the pauses while transactions confirm. If a take runs long, remove sentences; do not speed up.

## Click-by-click

### Beat 1 (0:00 to 0:20): `/`

1. Navigate to `/`. Wait for the hero headline "Turn strategies into composable tokens" and the lede to finish animating.
2. Hold on the hero for the first two sentences, then move the pointer toward the "Create a strategy" button without clicking it.
3. Cut at 0:20.

### Beat 2 (0:20 to 0:50): sign in, marketplace

1. Click "Connect wallet" in the nav. In the Privy modal enter the demo email, then the one-time code. (Record this as its own take; if the code email is slow, shorten it in the edit.)
2. Confirm the nav now shows the network badge (testnet name) and the shortened address.
3. `[V2-PENDING: click "Get test funds", wait for the funded notice, show the ETH and USDG balances.]`
4. Click "Marketplace" in the nav. Wait until the stats row shows Strategies, TVL and Nested and the cards show NAV values (not dashes).
5. Point at the "Nested" stat and at the CORE and CONV cards. Cut.

### Beat 3 (0:50 to 1:25): CORE

1. Click the CORE card ("Core Satellite", NAV shown). The URL becomes `/strategy/<vault>`.
2. Point at the "Depth 2" badge, then the NAV chip.
3. Scroll to "Constituents & weights". Point at the rows: the two "Nested Strategy" badges (AI Growth 40 percent, Big Five Equal 40 percent) and TSLA 20 percent.
4. Click a "Nested Strategy" badge: it opens that child's page. Show its NAV for two seconds, then go back. (This proves the parent value is read from the child.)

### Beat 4 (1:25 to 2:00): deposit

1. On CORE's page, in the right panel keep the "Deposit" segment selected.
2. Type `1000` in the "USDG amount" field. Wait for "You will receive" to show a share amount.
3. Click "Approve USDG"; confirm in the Privy wallet prompt; wait for the button to change to "Deposit".
4. Click "Deposit"; confirm; wait for the notice "Confirmed on-chain." Cut the waiting.
5. Open the transaction on the explorer for two seconds (hash from the wallet prompt or the activity list). `[V2-PENDING: show the minimum-shares setting before confirming.]`
6. Optional if time remains: click "Positions" and show "Positions held 1 / 10".

### Beat 5 (2:00 to 2:30): keeper rebalance

1. Open `/strategy/<EVMO vault>`. The "Rebalance" card shows the amber badge "Threshold breached" (or "Interval elapsed" for a time trigger).
2. Show the terminal and run `scripts/keeper.sh robinhood-testnet 30 1`; the output lists the flagged vault and a `performRebalance` line with status 1.
3. Return to the page; the badge flips to "Up to date" (reload if it does not refresh; the page refetches after a rebalance it initiated).
4. Switch to the explorer tab on the vault's logs, refresh, and point at the new `Rebalanced` event and the sender (the keeper address, not the deployer).
5. Variant if the keeper tick fails: click "Rebalance now" on the page with the demo wallet; it sends the same permissionless call; narrate "anyone can press this".

### Beat 6 (2:30 to 2:50): create

1. Click "Create" in the nav (`/create`).
2. In "Tokens", tap the AIGR and STRM chips (the ones with the layers icon). They appear under "Weights". CORE and CONV show "Locked" because a depth-2 strategy cannot be nested again; do not tap them.
3. Click "Even split" (50 and 50).
4. In the form: Name `Demo Mix`, Ticker `DEMO-MIX`, Max weight `60`, Rebalance "Every 7 days".
5. Click "Create strategy", confirm in the wallet, wait for "Strategy created", then click "View strategy". Point at "Depth 2".

### Beat 7 (2:50 to 3:00): redeem and close

1. On any strategy you hold (CORE), click the "Redeem" segment, type a share amount, wait for "You will receive", click "Redeem", confirm. A cut to the notice "Confirmed on-chain." is enough.
2. End card (added in the edit): "Feng. Investment strategies as composable onchain primitives." plus the live URL and the repository URL `[V2-PENDING: repo URL]`.

## Fallback path if the RPC flakes

The testnet RPC and explorer fail intermittently from filtered networks (see `docs/handoffs/DEMO-NOTES.md` section 1).

1. **Prevent**: record from a phone hotspot or a VPN outside the filter; run pre-flight item 1 right before every take.
2. **Per-take recovery**: if a transaction or a read fails mid-take, stop, retry the same beat; each beat is an independent take. Never fake a success or splice a result from a different action.
3. **Stale feeds**: a `StalePrice` revert on deposit or rebalance means the feeds aged out. Refresh them (`scripts/refresh-feeds.sh robinhood-testnet` on V1, the relayer tick on V2 `[V2-PENDING]`) and retake.
4. **Slow wallet confirmation**: cut the wait in the edit; keep the transaction hash on screen once.
5. **Provider endpoint**: if the public RPC is unusable all day, point the app at a provider endpoint through `NEXT_PUBLIC_RPC_URL` (providers are listed in `https://docs.robinhood.com/chain/connecting/`); the key stays in the Vercel environment, never in the repo. This needs a redeploy.
6. **Last resort, clearly labelled**: record the beats against the local anvil path in `docs/handoffs/DEMO-NOTES.md` section 0 and caption every screen "local anvil, not the testnet". Use this only as a supplement; the submission must still show the testnet addresses.
7. **If a judge runs it live and it breaks**: show the pre-recorded video and the explorer links in `README.md`, and say which dependency failed.

## After recording

See `docs/submission/video-shotlist.md` for the edit plan, and `docs/submission/CHECKLIST.md` for the upload and the "plays while logged out" check.
