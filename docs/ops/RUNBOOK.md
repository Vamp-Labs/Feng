# Feng ops runbook: price relayer, keeper, health, faucet

Scope: E2 (T1, T2, T3, T4 documentation, T8) and E10-T1 / E10-T5 documentation. Source of truth for the design: `docs/research/12-always-on-hosting.md` (host, pinger, time budget) and `docs/research/09-price-source-and-feed.md` (price source, cadence, bounds). No secret value appears in this file; only variable names.

## 1. What runs where

| Piece | What it is | Where |
|---|---|---|
| Tick | `GET` or `POST /api/ops/tick`. Runs the relayer, then the keeper, per deployment. Needs `Authorization: Bearer <CRON_SECRET>`. | Vercel route, `src/app/api/ops/tick/route.ts`, `maxDuration = 60` |
| Health | `GET /api/ops/health`. Public, read only, computed live from chain, `Cache-Control: no-store`, 200 or 503. | Vercel route, `src/app/api/ops/health/route.ts` |
| Faucet | `POST /api/faucet` with `{"address":"0x..."}`. | Vercel route, `src/app/api/faucet/route.ts` |
| Core | `src/ops/{config,rpc,redact,prices,relayer,keeper,scan,health,tick,faucet,auth,abi}.ts` and the self check `src/ops/check.ts`. No Next imports. `abi.ts` re-exports the generated V2 ABIs from `src/lib/abi/generated/**` (read only, written by `scripts/sync-abi.sh`). | shared by the routes and the worker |
| Worker | Loop shell over the same core for any machine with Node. | `scripts/ops-worker.ts` |
| Demo shock | Pushes a bounded price shock through `FengAggregator.shockAnswer`, rebalances, restores. | `scripts/demo-shock.sh` (section 13) |
| Clock | cron-job.org calls the tick every 5 minutes. | external, free |
| Watchdog | UptimeRobot watches `/api/ops/health` every 5 minutes. A different vendor from the clock. | external, free |
| Laptop fallback | `scripts/keeper.sh` and `scripts/refresh-feeds.sh` (bash and cast). | the user's machine |

Rules the core enforces (all knobs are env vars, section 3):

- Global time budget 22 s per tick, strictly below cron-job.org's 30 s timeout. No transaction is sent with less than 6 s left; that work moves to the next tick and is reported under `skipped`.
- Reads are batched with Multicall3 (`0xcA11bde05977b3631167028862bE2a173976CA11`). RPC calls retry on certificate, ECONNRESET, timeout and rate-limit errors with exponential backoff (3 attempts at the transport, and the call layer repeats the whole call once more). Reverts are never retried.
- Relayer pushes a feed when it is older than 25 minutes, or (market mode) when the live mid moved 10 bps or more. A feed never ages past 12 hours. One symbol failing never aborts the tick.
- One tick serves every deployment present on disk, newest first (V2, then V1), sequentially so the relayer nonce is never raced. V1 runs in hold mode with `MockV3Aggregator.updateAnswer`; V2 runs in market mode with `FengAggregator.updateAnswer` and `refresh`.
- V2 feeds (`feedKind: "feng"`): no move means `refresh()` (fresh `updatedAt`, same answer, anchor untouched); a move means `updateAnswer(answer)`. The aggregator bounds every `updateAnswer` against its anchor (`maxDeviationBps`, 1000) and, with the anchor window patch (R-V2-01), moves the anchor at most once per `ANCHOR_WINDOW` (1 hour). The relayer reads `anchorAnswer`, `maxDeviationBps` and `ANCHOR_WINDOW` per feed, clamps each push to `min(OPS_MAX_STEP_BPS, maxDeviationBps)` of the anchor, and after each confirmed step re-reads the anchor and continues (up to `OPS_MAX_STEPS_PER_TICK`). When no further progress is possible it stops and reports `held at the deviation bound` under `skipped`; it never sends a push that would revert. A stuck feed pushes `updateAnswer(current)` at the next heartbeat, which rolls the anchor once the window has expired, and the following tick continues. A `forceAnswer` re-anchor and the first seeding are admin only and never the relayer's job.
- Heartbeat freshness guard (R-V2-29): `refresh()` only re-stamps `updatedAt`, so it must not keep a price that nobody validated looking fresh. In V2 market mode the relayer reads `anchorSetAt` per feed and treats `now - anchorSetAt` (chain time) as the age of the last market-validated push. When a feed needs a heartbeat and this tick has no valid quote for it (fetch failed, halt, spread too wide, `generatedAt` missing or off, sanity hold) and the last validated push is older than `OPS_MAX_PRICE_AGE_SEC` (default 21600, 6 hours) or unknown, the relayer sends nothing for that feed, reports `price stale` under `skipped`, adds a critical (`<SYMBOL> price stale, no market-validated price for N h, heartbeat refresh stopped`) and health shows `<id> <SYMBOL> price stale`. The feed then ages and the vault paths revert with `StalePrice` instead of trading on an unvalidated price. The keeper's forced refresh obeys the same rule. A quiet but validated market is not stale: when the quote is valid, the move is below `OPS_PUSH_BPS` and the anchor window has expired, the heartbeat is an `updateAnswer` of the validated mid (inside the band) instead of a bare `refresh`, which renews `anchorSetAt`. Hold mode and a displayed shock keep their plain `refresh`. V1 mock feeds have no `anchorSetAt` and stay in hold mode. Weekends: while the API quote stays valid nothing is stale; if the quote turns invalid for longer than 6 hours the alarm is the intended behaviour (raise `OPS_MAX_PRICE_AGE_SEC` to accept a longer gap).
- Price API trust: a quote is used only when `tokenSymbol` matches, `isTradingHalt` is a boolean, bid and ask are plain decimals with `0 < bid <= ask`, the spread is within `OPS_SPREAD_MAX_BPS` and `generatedAt` is present, parseable and within `OPS_CLOCK_SKEW_SEC` (120) of the host clock. A missing or unreadable `generatedAt` (fail closed since R-V2-29) skips that symbol with `price clock` under `skipped` and the reason `generatedAt missing or unreadable` in `deployments[].relayer.feeds[].quote.reason`.
- Error text policy (R-V2-27): no provider error text, RPC URL, hostname or env value appears in any response. `shortError` returns one phrase from a fixed set (`rpc unreachable`, `rpc timeout`, `rpc rate limited`, `rpc error`, `call reverted`, `time budget exhausted`, `price api error`, `internal error`) and writes the detail to the server log only (`console.error`, `ops error [<label>] <phrase>: <detail>`), with URLs, hosts, IPs, 64 hex characters and any token of 20 or more `[A-Za-z0-9_-]` replaced by `<redacted>`; the same line is logged once per minute. Every health alarm also passes through the redaction, an addresses file that cannot be loaded is reported as `<id> addresses could not be loaded`, and the health route answers `{"ok":false,"alarms":["health unavailable"]}` with 503 if it throws. `node src/ops/check.ts` (Node 24 or newer, no install) proves it with a fake provider that answers 401 with the request URL and a key-like string; the same file checks the `generatedAt` rule, the stale heartbeat guard and the faucet mode default (8 tests).
- Shock hold: in V2 market mode a feed whose latest answer came from `shockAnswer` (found through `AnswerShocked` logs of the last `OPS_SHOCK_HOLD_SEC`, default 600 s) is only refreshed, never repriced, so a demo shock stays on screen. After the hold the next tick restores the market price with `updateAnswer`.
- Keeper V1 reads `RebalanceEngine.checkUpkeep()`. Keeper V2 never calls `checkUpkeep()` or `getAllStrategies()` (R-V2-15: they can exceed an RPC gas cap): it reads `strategyCount()` and pages `RebalanceEngineV2.checkUpkeepRange(offset, 25)` (`OPS_KEEPER_PAGE_SIZE`, 5 to 50), halving a page that fails. Then, per vault, `simulateContract` and only then `performRebalance` (sent with a 30 percent gas buffer). If the simulation reverts with `StalePrice`, it runs a forced relayer pass once per tick and retries that vault once. A revert from another cause is recorded for that vault only.
- Keeper V2 checkpoints: vaults whose `lastCheckpointTimestamp` is older than `OPS_CHECKPOINT_SEC` (3600, never below the deployment's `checkpointMinInterval`, 1800) are sent to `RebalanceEngineV2.checkpoint(address[])` in batches of `OPS_CHECKPOINT_BATCH` (10). The batch is simulated first; if the engine would record 0 (too early or prices stale) nothing is sent. `checkpointed` in the tick JSON is the number of vaults recorded.
- A wallet below `OPS_SEND_MIN_ETH` is never used to send. Below its alarm floor the tick returns 503.
- Every write path has a dry run: `OPS_DRY_RUN=1` (or the worker flag `--dry-run`) simulates only and reports `wouldPush` and `wouldRebalance`. In a dry run a stale vault is re-simulated with the six feeds overridden to "just pushed" state, so the report shows what would rebalance once feeds are fresh.

## 2. Status codes and the JSON

Tick (`GET|POST /api/ops/tick`):

- 401 plain text `Unauthorized` when `CRON_SECRET` is unset on the server or the bearer does not match (constant-time compare, fails closed).
- 200 when nothing critical happened (per-vault errors are listed in `errors` but do not fail the tick).
- 503 with `ok:false` and a `critical` list when: a keeper or relayer key is missing, the keeper or relayer balance is below its alarm floor or send floor, any feed is older than 6 hours after the tick, `checkUpkeep` or the feed state cannot be read at all. cron-job.org judges only the status code, so a 503 triggers its failure email.
- Body: `{ ok, dryRun, generatedAt, elapsedMs, pushed: [symbols], rebalanced: [vaults], checkpointed: <vaults recorded>, wouldCheckpoint: [vaults], errors: [], wouldPush, wouldRebalance, skipped, critical, absent: [deployment ids without an addresses file], deployments: [{ id, mode, relayer, keeper }] }`. A missing optional deployment (V2 before it lands) is listed under `absent` and is not an error. A present but malformed addresses file is an error and a `critical`. `deployments[].keeper.notes` holds a per-vault trace such as `simulate: StalePrice | relayer: forced refresh run | retry simulate: ok | sent 0x...`.

Health (`GET /api/ops/health`): 200 when `ok` is true, 503 otherwise. Fields: `ok`, `generatedAt` (unix s), `alarms` (strings), `feeds[]` (`deployment`, `symbol`, `price`, `updatedAt`, `ageSec`), `keeper {address, balanceEth}`, `relayer {address, balanceEth, mode, modes}` (`mode` is the newest maintained deployment, `modes` maps every deployment id), `vaults[]` (`deployment`, `symbol`, `vault`, `lastRebalance`, `lastCheckpoint`, `navUsdg`, `needed`; the last two are V2 only), `desk` (V2: `address`, `reserveUsdg`, `fundedUsdg`, `withdrawnUsdg`, `spreadBps`, `vaultNavUsdg`, `coverage`, or `null`), `faucet {address, balanceEth, balanceUsdg, claimsToday, mode, contract}` (`address` is the dispenser wallet; `contract` is the `FengFaucet` view: `address`, `balanceEth`, `claimsToday`, `dailyCap`, `ethPerClaim`, `usdgPerClaim`, `claimsAvailable`, `claimsLeftToday`, `dispenserAuthorized`), `absent`, `deployments[]`. Every alarm is a fixed phrase (see "Error text policy" in section 1); the price stale alarm is `<id> <SYMBOL> price stale`. Everything is read directly from the contracts, no `StrategyLens`. `ok` is false when any maintained feed is older than 35 minutes, when a keeper, relayer or faucet balance is below its floor, when an address is not configured, when a chain read fails, when the relayer wallet lacks `UPDATER_ROLE` on a V2 feed, when the desk reserve covers less than `OPS_DESK_MIN_COVERAGE` (1.0) times the vault NAV, or (faucet in contract mode) when the faucet contract can pay fewer than `OPS_FAUCET_MIN_CLAIMS` (3) more claims or the dispenser wallet lacks `DISPENSER_ROLE`. `desk.coverage` is `reserveUsdg / vaultNavUsdg`, where the NAV is the sum of `totalAssetsUSDG()` over every registered vault (nested vaults are counted twice on purpose, so the figure is conservative); it is `null` when any NAV read fails. Ages are measured against the chain's own block timestamp (Multicall3 `getCurrentBlockTimestamp`), not the host clock. `claimsToday` counts USDG transfers out of the faucet wallet over about 24 hours (best effort, `null` when the log query fails). Nothing is stored; the response is rebuilt from chain reads, with a 15 s in-process memo to bound RPC load.

Faucet (`POST /api/faucet`): body `{status, txHash?}` with `status` one of `funded` (200), `already-claimed` (200), `faucet-empty` (503), `invalid-address` (400), `rate-limited` (429). In contract mode the contract errors map as `AlreadyClaimed` to `already-claimed`, `FaucetEmpty`, `DailyCapReached` and `TransferFailed` to `faucet-empty`, `RecipientIsContract` and `ZeroAddress` to `invalid-address`; any other revert (for example a dispenser without `DISPENSER_ROLE`) logs the error name on the server and returns `faucet-empty`. `faucet-empty` is also returned when the faucet key is not configured or a chain call fails after validation (the cause goes to the server log, never to the response). The faucet wallet balance is never in the response.

## 3. Environment variables

Secrets (Vercel, Production, Sensitive on; never in the repo, never in a pinger except `CRON_SECRET` in the cron-job.org header):

| Name | Used by | Notes |
|---|---|---|
| `CRON_SECRET` | tick route | At least 16 random characters. Unset means every tick call gets 401. |
| `KEEPER_PRIVATE_KEY` | keeper | Dedicated testnet wallet. The existing keeper wallet (the `from` of the 16 historical `Rebalanced` transactions) works if its key is already in hand. |
| `RELAYER_PRIVATE_KEY` | relayer | Dedicated testnet wallet. In V1 hold mode `updateAnswer` is open to anyone, so any funded key works; in V2 this address must be the `RELAYER_ADDRESS` given to `DeployV2` (it holds `UPDATER_ROLE`, and `SHOCK_ROLE` when the deploy used `ENABLE_SHOCK=1`). |
| `FAUCET_PRIVATE_KEY` | faucet | Dedicated testnet wallet. V1 mode: pre-funded with ETH and test USDG (section 5). Contract mode: must be the `FAUCET_ADDRESS` given to `DeployV2` (holds `DISPENSER_ROLE`), and needs only gas ETH. |
| `SHOCK_PRIVATE_KEY` | `scripts/demo-shock.sh` only | Never set on Vercel. The wallet with `SHOCK_ROLE`; the script falls back to `RELAYER_PRIVATE_KEY`. |
| `DEPLOYER_PRIVATE_KEY` | not set on Vercel | Only in the user's local shell, for funding and deploys. |

Public or optional knobs (all have defaults; set only to change behaviour):

| Name | Default | Meaning |
|---|---|---|
| `OPS_DRY_RUN` | off | `1` simulates only: no key is needed, nothing is sent. |
| `OPS_RELAYER_MODE` | `hold` | `hold` or `market` for every deployment. |
| `OPS_MODE_<ID>` | unset | Per deployment override, for example `OPS_MODE_V1=hold`, `OPS_MODE_V2=market`. Wins over `OPS_RELAYER_MODE`. |
| `RELAYER_PAUSED` | off | `1` makes the relayer skip every push (used while a demo price shock is on screen). |
| `OPS_RPC_URL` | the `rpcUrl` of each addresses.json | Override the RPC endpoint. |
| `OPS_BUDGET_MS`, `OPS_MIN_SEND_MS` | 22000, 6000 | Tick budget and the minimum time left to start a send. |
| `OPS_HEARTBEAT_SEC` | 1500 | Re-publish a feed this old (25 minutes). |
| `OPS_PUSH_BPS` | 10 | Market mode move that triggers a push. |
| `OPS_HARD_MAX_AGE_SEC` | 43200 | A feed is always pushed at this age (12 hours). |
| `OPS_HEALTH_MAX_AGE_SEC` | 2100 | Health alarm age (35 minutes). |
| `OPS_CRITICAL_FEED_AGE_SEC` | 21600 | Tick returns 503 when a feed is still older than this (6 hours). |
| `OPS_SPREAD_MAX_BPS` | 500 | Quotes with a wider bid/ask spread are skipped. |
| `OPS_CLOCK_SKEW_SEC` | 120 | Largest accepted difference between the quote's `generatedAt` and the host clock. A missing `generatedAt` is rejected too. |
| `OPS_MAX_PRICE_AGE_SEC` | 21600 | V2 market mode: heartbeat `refresh()` is not used when the last market-validated push (`now - anchorSetAt`) is older than this; the feed is reported `price stale` instead (6 hours). |
| `OPS_SANITY_MOVE_BPS` | 5000 | Market mode ignores a single move larger than this (wrong decimals, API glitch). |
| `OPS_MAX_STEP_BPS`, `OPS_MAX_STEPS_PER_TICK` | 900, 3 | V2 aggregator pushes are clamped to `min(this, on-chain maxDeviationBps)` of the anchor and chased for up to this many confirmed steps per tick. |
| `OPS_SHOCK_HOLD_SEC` | 600 | V2 market mode only refreshes a feed whose latest answer is a `shockAnswer` newer than this. `0` disables the hold. |
| `OPS_SEND_MIN_ETH` | 0.00002 | Below this a wallet never sends. |
| `OPS_KEEPER_MIN_ETH`, `OPS_RELAYER_MIN_ETH`, `OPS_FAUCET_MIN_ETH` | 0.0003, 0.001, 0.0005 | Alarm floors. |
| `OPS_KEEPER_ADDRESS`, `OPS_RELAYER_ADDRESS`, `OPS_FAUCET_ADDRESS` | unset | Public address to report when the matching private key is not in the environment (read only checks and dry runs). |
| `OPS_FAUCET_OPTIONAL` | off | `1` stops an unconfigured faucet from turning health red. |
| `OPS_FAUCET_MODE` | auto | Unset or any value other than `v1` or `contract`: `contract` when a loaded deployment (the one named by `OPS_FAUCET_DEPLOYMENT` if set) has a `faucet` address in its addresses file, otherwise `v1` (R-V2-28). `contract` uses `FengFaucet.claimFor(address)` sent by the dispenser wallet (`FAUCET_PRIVATE_KEY`); `v1` is the legacy wallet-funded path (direct USDG and ETH transfers, no on-chain cap). An explicit `v1` or `contract` always wins. `faucet.mode` in health shows the effective value. |
| `OPS_FAUCET_DEPLOYMENT` | auto | Deployment id the faucet uses. Auto is the first deployment in V1 mode and the newest deployment that has a `faucet` address in contract mode. |
| `OPS_FAUCET_MIN_CLAIMS` | 3 | Contract mode health alarm when the faucet contract balance pays fewer claims than this. |
| `OPS_DESK_MIN_COVERAGE` | 1 | Health alarm when `desk.coverage` falls below this multiple of vault NAV. |
| `OPS_KEEPER_PAGE_SIZE` | 25 | V2 `checkUpkeepRange` and `getStrategies` page size, clamped to 5 to 50 (R-V2-15). |
| `OPS_CHECKPOINT_SEC`, `OPS_CHECKPOINT_MIN_SEC`, `OPS_CHECKPOINT_BATCH` | 3600, 1800, 10 | V2 checkpoint cadence per vault, the rate limit used when `addresses.json` has no `checkpointMinInterval`, and the batch size per transaction. |
| `OPS_DEPLOYMENTS` | all | Comma separated deployment ids to serve, for example `v2`. |
| `OPS_ADDRESSES_<ID>` | registry path | Path under `deployments/` of that deployment's addresses file (relative, no `..`), for example `OPS_ADDRESSES_V2=dry-local-v2/addresses.json`. |
| `OPS_RELAYER_<ID>`, `OPS_KEEPER_<ID>` | `1` | `0` stops the relayer or the keeper for that deployment (archive a deployment without a code change). |
| `OPS_RPC_URL_<ID>` | `OPS_RPC_URL` or the file | RPC endpoint for one deployment. |
| `OPS_PRICE_API_BASE` | `https://api.robinhood.com/rhj/prices` | Price API base URL (a local stub in rehearsals). |
| `OPS_WORKER_INTERVAL_SEC` | 300 | Worker loop period. |

## 4. First-time setup, in order

Estimated human time 30 to 35 minutes (research doc 12, R-6). Steps marked (agent) are done by the coordinator or an agent.

1. In a local terminal generate the clock secret without displaying it: `openssl rand -hex 32 | wl-copy`. Keep it on the clipboard until step 5.
2. Create the wallets locally, for example `cast wallet new` three times (keeper, relayer, faucet). Note only the public addresses for funding; keep each private key for step 3. Clear the terminal afterwards.
3. Vercel dashboard, the Feng project, Settings, Environment Variables. Add `CRON_SECRET`, `KEEPER_PRIVATE_KEY`, `RELAYER_PRIVATE_KEY`, `FAUCET_PRIVATE_KEY`, environment Production, Sensitive on. Add any `OPS_*` knob you want to change from section 3 (none are required). Redeploy: a change applies only to new deployments.
4. (agent) Fund the wallets from the deployer, section 5. Deploy to production. Verify section 6.
5. Open https://console.cron-job.org, sign up (email, password, bot check, confirmation email). Create a cronjob:
   - Title `feng-tick`.
   - URL `https://<production alias>/api/ops/tick` (research doc 12 used `https://composable-strategy-marketplace.vercel.app/api/ops/tick`; use whatever the production alias is after the rebrand).
   - Schedule: every 5 minutes.
   - Advanced: request method GET, custom header `Authorization` with value `Bearer ` followed by the pasted secret, timeout 30, leave "Treat redirects with HTTP 3xx status code as success" off.
   - Notifications: on failure with "Notify after 2 subsequent failures", on recovery, and on auto-disable, to your email.
   - Save, make sure it is enabled, press Test run and expect HTTP 200 (or 503 with a JSON `critical` list, which means the pipe works and a wallet or feed needs attention).
6. Open https://dashboard.uptimerobot.com, sign up, create an HTTP(s) monitor on `https://<production alias>/api/ops/health`, interval 5 minutes (the free minimum), alerts on down and up to your email. UptimeRobot free cannot send custom headers, which is why it watches the public health URL and not the tick. The health route returns 503 when any feed is over 35 minutes old or a balance is under its floor, so a dead clock is detected within about 45 minutes.
7. Confirm in the cron-job.org history that two consecutive runs show 200 and a small JSON body, and in UptimeRobot that the monitor is Up.
8. (agent) Soak at least 4 hours: feed ages under 35 minutes throughout, one rebalance sent by the keeper address, a kill and restart test (disable the cron-job.org job for 40 minutes and expect the UptimeRobot email), one injected TLS failure. Record it in `docs/ops/SOAK-LOG.md`.

Vercel Cron on the Hobby plan is daily at best, so it cannot be the clock. Do not add a more frequent `crons` entry to `vercel.json`: Hobby fails the deployment. A daily backstop entry is optional and adds little.

## 5. Funding (gas is about 0.01 gwei)

| Wallet | ETH | Other | Why |
|---|---|---|---|
| Relayer | 0.005 | none | About 0.0038 ETH per 30 days of 30 minute heartbeats on six feeds, measured at 44,249 gas per push. Alarm at 0.001. |
| Keeper | 0.003 | none | A transaction costs roughly 0.00001 to 0.00005 ETH (plan estimate); the existing keeper holds about 0.00097 ETH, so top up before the soak. Alarm at 0.0003. |
| Faucet | 0.004 | 200,000 test USDG | 0.004 ETH covers 20 fills at 0.0002 ETH each; 200,000 USDG covers 20 fills of 10,000. Alarm at 0.0005 ETH. |

V2 contract mode does not use this wallet for funds: the `FengFaucet` contract holds the ETH (fund it through `FAUCET_ETH_FUND_WEI` at deploy, or a plain value transfer later; claim 21 of the default 0.004 ETH reverts `FaucetEmpty`, so use at least 0.008 ETH for the daily cap of 40) and mints the USDG itself (it holds `MINTER_ROLE`). The dispenser wallet needs only gas, about 0.001 ETH.

The faucet wallet needs test USDG before the V1 faucet can work. `MockUSDG` is owner-mint and the deployer is the owner, so from the deployer's shell (the key comes from the environment, never typed into a file; retry on a TLS error):

```
cast send 0x6F0aa2cc939604b7e62935365521EA72C1908B70 "mint(address,uint256)" <FAUCET_ADDRESS> 200000000000000000000000 --rpc-url https://rpc.testnet.chain.robinhood.com --private-key "$DEPLOYER_PRIVATE_KEY"
```

The amount is 200,000 with 18 decimals (the V1 mock). The faucet reads the token's `decimals()` at run time and never assumes 18, so the same wallet works with a 6 decimal USDG once V2 lands. Send ETH with `cast send <ADDRESS> --value 0.004ether ...`.

## 6. Verify after every deploy

```
curl -i https://<alias>/api/ops/tick
curl -s -H "Authorization: Bearer $CRON_SECRET" https://<alias>/api/ops/tick
curl -s https://<alias>/api/ops/health
```

Expect 401 with no header, a JSON summary with the header (put the secret in your shell variable from the clipboard, not in a file), and a health JSON whose `keeper.address`, `relayer.address` and `faucet.address` match the wallets you created. Before the keys exist the health JSON lists `relayer address is not configured` and 503, which is correct.

Dry run without keys, from the repo root (no transaction can be sent):

```
OPS_DRY_RUN=1 OPS_KEEPER_ADDRESS=<keeper address> node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON scripts/ops-worker.ts --once
```

## 7. How to read health

- `ok:true`: every maintained feed is under 35 minutes old, every wallet is above its floor, and (V2) the relayer holds its role, the desk covers the vault NAV and the faucet contract can pay claims. The pinger sees 200.
- A feed alarm (`v1 TSLA feed is 41 min old`): the clock missed ticks or the relayer wallet is dry. Check the cron-job.org history (jitter column, last statuses), then the relayer balance. The relayer can push at most 6 feeds per tick, so one healthy tick fixes a transient miss.
- `v2 relayer lacks UPDATER_ROLE on ...`: the `RELAYER_PRIVATE_KEY` address is not the `RELAYER_ADDRESS` of the V2 deploy. Grant the role with the deployer key, or change the key. The tick reports `relayer address does not hold UPDATER_ROLE` as critical until fixed.
- A balance alarm: top up the named wallet. The tick keeps working above `OPS_SEND_MIN_ETH`, but it returns 503 so the failure email arrives before the wallet is dry.
- `vaults[].needed:true` for longer than one tick: the keeper cannot rebalance it. Run the dry run (section 6) and read `deployments[].keeper.notes`. `vaults[].lastCheckpoint` older than about 1 hour for a vault nobody touches means the keeper checkpoint is failing: read `deployments[].keeper.checkpointNotes`.
- `desk.reserveUsdg` and `desk.coverage` (reserve divided by total vault NAV): a coverage under 1 means the desk could not buy back every vault's holdings; top up with `OracleDesk.fundReserve`. `desk.spreadBps` is the desk's own sell spread (10 by default); `fundedUsdg` less `withdrawnUsdg` is the owner funding.
- `faucet.contract`: `claimsAvailable` is how many claims the contract's ETH still pays, `claimsLeftToday` is `dailyCap - claimsToday` (resets at 00:00 UTC, an exhausted day is not an alarm). `dispenserAuthorized:false` means `FAUCET_PRIVATE_KEY` is not the dispenser; every claim then returns `faucet-empty`.
- `skipped` entries such as `held at the deviation bound, target is 2500 bps from the anchor, anchor window open` in the tick JSON are not failures: the market moved further than `FengAggregator` allows inside its anchor window, the relayer follows as far as the contract permits and continues on later ticks. A frozen target that persists for hours points at a stale quote or an admin `forceAnswer` that is needed.
- Weekend or market closed: the price API returns the last Friday quote, so market mode pushes nothing but the heartbeat (`refresh()` in V2); `ageSec` stays under 25 minutes and the price is frozen. That is expected. Do not treat a frozen price as an outage.
- Sandbox prices in V1 hold mode are the seed constants (TSLA 260, AMZN 183, NFLX 581, PLTR 26, AMD 138), not market prices. The site must say so until V2 runs in market mode.

## 8. Rotation

Rotate `CRON_SECRET`: generate a new value, edit the Vercel variable (Production) and redeploy, immediately edit the cron-job.org header to the new bearer, press Test run and expect 200. Expect one or two failed pings in the gap; "notify after 2 failures" absorbs that.

Rotate a wallet key: create a new wallet, fund it, set the new env value, redeploy, confirm the new address in the health JSON, sweep the old wallet, retire it. If the key held an on-chain role (V2 `UPDATER_ROLE`), revoke it with the admin key and grant it to the new address.

If a key may have leaked, treat it as spent: rotate it first, then investigate. These are testnet keys with small balances, but a leaked relayer key can set sandbox prices.

## 9. Laptop fallback (when the Vercel path is down)

- Keeper: `KEEPER_PRIVATE_KEY=<from shell> scripts/keeper.sh robinhood-testnet 30` (bash and cast loop, 30 s).
- Feed refresh: `scripts/refresh-feeds.sh robinhood-testnet` pushes the constant V1 seed prices once. Run it at least every 6 hours, or the vaults revert `StalePrice` after 24 hours. It overwrites the current answers with the seed constants, so after a market mode switch use the worker below instead.
- Worker, same core as the route: `node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON scripts/ops-worker.ts` (Node 22.18 or newer; the repo has no `tsx`, Node's built-in type stripping runs the TypeScript and the script registers a resolver hook for the extensionless imports). Flags: `--once`, `--dry-run`, `--interval=300`. It reads the same env vars as section 3 from the process environment (export them in the shell, or pass your own untracked file with `node --env-file=<file>`). It prints one JSON line per tick and exits non-zero in `--once` mode when the tick is not ok. Run it from a host outside the user's ISP when possible: the ISP intercepts TLS to the RPC intermittently, and the core retries but cannot cure a long outage.
- The local resolver returns a wrong host for `api.robinhood.com`. Market mode from the laptop therefore needs a working resolver for that name; hold mode does not call the price API at all.

## 10. Switch hold to market, and the V2 deployment

Hold mode (V1 default) re-publishes the last on-chain answer so `updatedAt` stays fresh and never changes the price. Market mode fetches `https://api.robinhood.com/rhj/prices/{SYMBOL}`, takes `tokenBid` and `tokenAsk`, uses the mid scaled to the feed's decimals (8), skips on `isTradingHalt`, a spread over 500 bps, a `generatedAt` that is missing or more than 120 s from the host clock, or a failed fetch (the feed then holds its last answer and the tick reports the reason), and pushes at a move of 10 bps or more. Prices are never read in hold mode.

Do not switch V1 to market mode: the seed prices are far from the real ones, so the sanity guard (`OPS_SANITY_MOVE_BPS`, default 50%) would hold NFLX, PLTR and AMD and a lowered guard would reprice the live vaults at once. Market mode is for V2, whose feeds start from real quotes.

The single entry for the V2 deployment is the `v2` item of `DEPLOYMENT_REGISTRY` in `src/ops/config.ts`: id `v2`, file `deployments/robinhood-testnet-v2/addresses.json` (schema v2), `feedKind: "feng"`, engine `v2`, default mode `market`, `optional: true`. The loader reads the file at run time (the build traces `deployments/**/*.json`). When the file is absent the tick and health simply serve V1 and list `v2` under `absent`; nothing crashes and nothing alarms. When it appears, the next deploy of the app serves both deployments in one tick with no further code change: V1 stays in hold mode, V2 in market mode.

Switch procedure at gate G1 (the V2 file lands):

1. Confirm the V2 deployment was made with `RELAYER_ADDRESS` equal to the address of `RELAYER_PRIVATE_KEY`, `FAUCET_ADDRESS` equal to the address of `FAUCET_PRIVATE_KEY`, and `ENABLE_SHOCK=1` if the shock demo is wanted (`scripts/deploy-v2.sh robinhood-testnet all`).
2. Commit the V2 addresses file with the app, redeploy. No env change is needed: `OPS_MODE_V2` defaults to market through the registry, `OPS_MODE_V1` to hold.
3. Run section 6 against the new deployment. `GET /api/ops/health` must list both deployments under `deployments[]`, 12 feed ages (6 per deployment) under 35 minutes, `relayer.modes` `{"v1":"hold","v2":"market"}`, `desk.coverage` well above 1 and `faucet.contract.dispenserAuthorized: true`.
4. Faucet: no variable is needed, the mode is `contract` as soon as the V2 file has a `faucet` address (`faucet.mode` in health shows it); `OPS_FAUCET_MODE=contract` or `v1` overrides. Claim once from a fresh address (`funded`), again (`already-claimed`), confirm `faucet.contract.claimsToday` moved. Set `OPS_FAUCET_MODE=v1` to fall back to V1 transfers (no on-chain cap, use deliberately).
5. After V1 is archived (E7-T3 copies the V2 file over `deployments/robinhood-testnet/addresses.json`): the V1 entry would then read a V2 file. Keep V1 fresh by moving the old V1 file to `deployments/robinhood-testnet-v1/addresses.json` and setting `OPS_ADDRESSES_V1=robinhood-testnet-v1/addresses.json` (V1 stays live and fresh, hold mode); to stop maintaining it set `OPS_RELAYER_V1=0` and `OPS_KEEPER_V1=0` (it then drops out of the health alarms but still appears under `deployments`). If the V2 file is copied over the V1 path and V1 is dropped, set `OPS_DEPLOYMENTS=v2` and `OPS_ADDRESSES_V2=robinhood-testnet/addresses.json`.
6. Check the first hour: every V2 feed `ageSec` under 35 minutes, one `checkpointed` count in the tick JSON, and the keeper `scanned` equals the registry's `strategyCount`.

Local rehearsal against a throwaway anvil (no key other than anvil's public ones): start `anvil --port 8590`, copy the Multicall3 code to `0xcA11bde05977b3631167028862bE2a173976CA11` with `anvil_setCode` (plain anvil does not have it), then `DRY_RPC_URL=http://127.0.0.1:8590 KEEP_DRY_OUTPUT=1 ENABLE_SHOCK=1 RELAYER_ADDRESS=<anvil 0> FAUCET_ADDRESS=<anvil 2> scripts/deploy-v2.sh dry all`. `deploy-v2.sh` sets `WRITE_ADDRESSES=true` for the forge scripts (they only write `deployments/*/addresses.json` when it is set, so a manual `forge script` simulation, or a manual broadcast without it, never overwrites a deployment file); `DRY_RPC_URL` must be exactly `http://127.0.0.1:<port>` or `http://localhost:<port>`; `has_code` aborts before any broadcast when the RPC cannot answer, and the script prints the RPC host only. Run the worker with `OPS_DEPLOYMENTS=v2 OPS_ADDRESSES_V2=dry-local-v2/addresses.json OPS_RPC_URL=http://127.0.0.1:8590` (the faucet mode resolves to `contract` by itself) and the three `*_PRIVATE_KEY` variables set to anvil accounts 0, 1 and 2, and `OPS_PRICE_API_BASE` pointing at a local stub that serves the price API shape. `evm_increaseTime` plus `evm_mine` moves chain time for the heartbeat, checkpoint and stale price paths.

## 11. Faucet notes (E10-T1, E10-T5)

- V1 fallback mode: the faucet wallet sends 10,000 USDG (read decimals from the token) when the target holds less than 5,000, and 0.0002 ETH when the target holds less than 0.0001. Repeated calls therefore cannot drain it: a funded address returns `already-claimed`.
- Contract mode (the default whenever the V2 addresses file has a `faucet` address, or `OPS_FAUCET_MODE=contract`; V2): the dispenser wallet (`FAUCET_PRIVATE_KEY`) calls `FengFaucet.claimFor(address)`. The call is simulated first and the contract revert name is mapped to the response status (section 2), so a repeat claim costs no gas. The contract mints the USDG, pays the ETH, enforces one claim per address and the daily cap. The send uses a 30 percent gas buffer and waits for the receipt; a receipt that reverts after a passing simulation (a race) is mapped through `hasClaimed`. The dispenser balance is checked against `OPS_SEND_MIN_ETH` before sending.
- Validation: addresses are checksum-agnostic, the zero address and any address with contract code are rejected (`invalid-address`).
- Limiter: in-memory and best effort, per server instance (6 requests per IP per 10 minutes, 1 per address per minute, one claim in flight per address, sends serialized per instance). It resets on every cold start and is not shared across instances. The real limiter is a Vercel Firewall rate-limit rule on `/api/faucet` counting by IP (E10-T5, the one rate-limit rule the Hobby plan allows).
- The faucet wallet's balances are published only through the health JSON.
- Real limit in contract mode: one claim per address and `dailyCap` (40) per UTC day, so at most 40 x 0.0001 ETH = 0.004 ETH leaves the contract per day, and the dispenser pays gas only for claims that simulate successfully. A sybil with 40 fresh addresses can use up the day (availability loss, not a larger loss). Set `OPS_FAUCET_MODE=v1` only deliberately: that path has no on-chain cap.

## 12. Known gaps

- The send paths (relayer, keeper, faucet) were exercised on a local anvil with anvil's public keys, not on the live chain; the live chain was only read and simulated. Run section 4 step 8 on the real deployment.
- The V2 paths were exercised against the V2 contracts on a local anvil (`scripts/deploy-v2.sh dry all`), including the anchor window patch (R-V2-01). Gas on the real chain carries an L1 component of about 10 percent; the 30 percent buffer covers it.
- `FengAggregator` bounds the size of an update, not the rate (R-V2-01 F-01, accepted). The ops relayer pushes at most `OPS_MAX_STEPS_PER_TICK` times per feed per tick and never more than a 9 percent step, but a stolen `UPDATER_ROLE` key is not limited by that. The runbook mitigation is `revokeRole` plus the `AnswerUpdated` frequency alert, and keeping the relayer key off shared machines.
- The Live universe shares the sandbox price feeds (R-V2-03): a relayer outage or a market closed heartbeat gap also stops Live deposits with `StalePrice`.
- The price band check against `dailyLow` and `dailyHigh` and the corporate-action pause check from research doc 09 (R-A.4) are not implemented: they need the `/rhj/assets` and `/rhj/corporate-actions` endpoints. The five tickers currently have multiplier 1.0 and no pending action.
- A move larger than the sanity limit is held instead of confirmed by a second fetch 16 s later (R-A.6), to stay inside the 22 s budget.
- The shock hold finds a displayed shock through `getLogs` over about `OPS_SHOCK_HOLD_SEC * 10 + 1000` blocks. If the RPC rejects the query the hold is skipped (the relayer would then restore the market price at its next push), and no alarm is raised.
- Vercel runtime logs on Hobby are kept for 1 hour; the pinger history and the chain are the record.

## 13. Demo shock (`scripts/demo-shock.sh`)

Pushes a bounded price shock through `FengAggregator.shockAnswer`, lets the keeper rebalance, then restores the original price. It works only when the deployment was made with `ENABLE_SHOCK=1` (the five stock feeds report `shockEnabled() = true` and the relayer wallet holds `SHOCK_ROLE`); otherwise it prints `Shock is disabled on this deployment ...` and exits 3 without sending anything.

```
SHOCK_PRIVATE_KEY=... RELAYER_PRIVATE_KEY=... KEEPER_PRIVATE_KEY=... scripts/demo-shock.sh --dry
SHOCK_PRIVATE_KEY=... RELAYER_PRIVATE_KEY=... KEEPER_PRIVATE_KEY=... scripts/demo-shock.sh [--symbol TSLA] [--pct 18] [--vault EVMO] [--wait 30] [--no-restore]
```

- Keys come from the shell environment only and are never printed (export them from a local untracked source; do not paste them into a command history you keep). `SHOCK_PRIVATE_KEY` falls back to `RELAYER_PRIVATE_KEY` and the reverse. `KEEPER_PRIVATE_KEY` is optional.
- `--dry` uses `cast call` only: it prints the feed state, simulates `shockAnswer(target)` from the shock wallet and the restore `updateAnswer(original)` from the relayer wallet, and reports whether the watched vault needs a rebalance.
- Defaults: TSLA +18 percent, vault `EVMO` (40 percent TSLA, so +18 percent lifts it to about 44 percent and crosses its threshold). The shock must stay within `maxShockBps` (3000) of the feed's anchor; the script refuses a larger one before sending.
- Sequence: send the shock, check `rebalanceNeeded()` on the vault, wait up to `--wait` seconds (default 30, `0` skips) for the keeper to change `lastRebalanceTimestamp`; if it did not, call `RebalanceEngineV2.performRebalance(vault)` from `KEEPER_PRIVATE_KEY` (without the key it says the next tick will do it); finally push the original price back with `updateAnswer`, from an `EXIT` trap so the restore also runs after an error. After the restore the vault is off target in the other direction, which the next tick or keeper pass rebalances; that second leg is a good demo beat.
- The relayer does not undo a shock for `OPS_SHOCK_HOLD_SEC` (600 s default): it only refreshes the feed. Keep the demo shorter than that, or raise the variable, or set `RELAYER_PAUSED=1`. `--no-restore` leaves the shock on chain; the relayer then restores the market price after the hold.
- Pick the restore wallet carefully: `updateAnswer` needs `UPDATER_ROLE`, and the original price must be within `maxDeviationBps` of the anchor, which is true unless an earlier shock is still displayed. The `--dry` run checks both.
- The script reads `deployments/robinhood-testnet-v2/addresses.json` and its `rpcUrl`; `--addresses <file>` and `--rpc <url>` (or `DEMO_ADDRESSES`, `DEMO_RPC_URL`) point it at a local rehearsal. Reads are retried on TLS interception (`DEMO_MAX_ATTEMPTS`, default 6).
