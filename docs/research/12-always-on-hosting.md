# 12. Always-on hosting for the Feng price relayer and keeper (research track R5)

- **Date**: 2026-10-03 (all "read" dates below are 2026-10-03) · **Track**: R5 of `docs/brainstorm/2026-10-03-feng-v2-plan.md` · **Feeds**: E2-T3, E2-T4, E2-T5, E2-T8, E10-T5, E7
- **Method**: Vercel, Railway, cron-job.org, UptimeRobot, Better Stack, GitHub, Cloudflare and Upstash primary pages; the Next.js 16.3.6 guides shipped in `node_modules/next/dist/docs/01-app/`; read-only Vercel CLI/API calls on the existing project; read-only Railway MCP calls; live `curl` probes of the Robinhood Chain RPC and of the live Vercel site. Nothing was created, deployed, linked, signed up for or deleted. No `.env*` file was read and no secret was printed.

## Summary

1. **The project is on Vercel Hobby** (`billing.plan = "hobby"`, status active; `vercel api /v2/teams/team_isUYixlBIdWzYSzt1P7ge9bg`). Vercel Cron on Hobby runs **once per day at most**, with the invocation landing anywhere inside the scheduled hour. A cron expression more frequent than daily **fails the deployment**. So Vercel Cron cannot be the keeper clock. It is at best a daily backstop.
2. **A Vercel route is a fine place to run the work**, because Hobby allows `maxDuration` up to 300 s (default 300 s with Fluid compute, which the project has on: `resourceConfig.fluid = true`, `functionDefaultTimeout = 300`). The binding limit is not Vercel but the pinger: cron-job.org waits only **30 s**. ~12 RPC calls take about 3 s end to end (measured), so a hard 22 s time budget fits with large margin.
3. **Best free pinger: cron-job.org.** Free, every 1 minute allowed, arbitrary custom headers (so `Authorization: Bearer ...` works), email notification on failure with "notify after N failures", 30 s timeout, no account cap stated. Sign-up uses an invisible reCAPTCHA and an email confirmation link. **UptimeRobot free cannot send custom headers** (5 min interval, header feature is paid), so use it only as an independent watchdog on the public health URL. Better Stack free (10 monitors, 3 min) is a second watchdog option.
4. **Railway is not needed.** The user's Railway account already exists (created 2026-09-30, one personal workspace, zero projects). Free/Trial plan limits (restart policy `Always` unavailable, 0.5 to 1 GB RAM, $1 per month credit after a one-time $5 trial, restricted outbound network on an unverified "Limited Trial") make it a poor fit for a day-one dependency. Estimated cost of a tiny always-on worker is about $1.4 per month, which already exceeds the Free plan credit.
5. **GitHub Actions `schedule`** has a documented 5 minute floor and documented delays at load; community reports show 5 to 20 minutes of lateness. Good as a redundant secondary caller, not as the primary clock for the 1 hour BLTZ rebalance. **Cloudflare Workers cron** is free (5 triggers, 10 ms CPU, minute granularity) and can only be a pinger on the free plan, not the worker itself.
6. **Recommended**: one tick route behind `Authorization: Bearer ${CRON_SECRET}`, called by cron-job.org every **5 minutes**; a public `/api/ops/health` watched by UptimeRobot (a different vendor) every 5 minutes; relayer heartbeat at 25 minutes (not 30) so feed age stays under the 35 minute acceptance line; keeper checked on every tick, which puts the BLTZ 1 hour time rebalance at most about 5 to 6 minutes late. Human time to set this up is about 30 to 35 minutes (section "Recommendations", runbook step list).

## Findings

### F1. Vercel plan tier and what it allows (question 1)

| Fact | Value | Source |
|---|---|---|
| Plan of team "Candra's projects" | `hobby`, status `active`, role OWNER | command: `vercel api /v2/teams/team_isUYixlBIdWzYSzt1P7ge9bg --raw` (billing.plan), 2026-10-03 |
| Project | `composable-strategy-marketplace`, id in `.vercel/project.json`, Node 24.x, framework nextjs | `vercel api /v9/projects/prj_S5dRGc6BccnT2mFGjUwgZ8bomWuX`, MCP `get_project` |
| Fluid compute | enabled (`resourceConfig.fluid: true`) | same call |
| Function region | `iad1` (`serverlessFunctionRegion`, `functionDefaultRegions: ["iad1"]`) | same call |
| Default function timeout | 300 s (`defaultResourceConfig.functionDefaultTimeout`) | same call |
| Crons currently defined | none (`crons.definitions: []`) | same call |
| Deployment protection | `ssoProtection.deploymentType = all_except_custom_domains` (Standard Protection). Observed: `https://composable-strategy-marketplace.vercel.app/` returns 200 publicly, while a deployment-hash URL (`...-msx2sfsu1-candras-projects.vercel.app`) returns 302 to login | `curl` probes 2026-10-03; protection scopes in https://vercel.com/docs/deployment-protection |
| Existing projects | 20 on the team (unchanged, not touched) | `vercel project ls` |

**Vercel Cron by plan** (https://vercel.com/docs/cron-jobs/usage-and-pricing, last_updated 2026-07-15):

| Plan | Cron jobs per project | Minimum interval | Precision |
|---|---|---|---|
| Hobby | 100 | **once per day** | per hour (up to +59 min) |
| Pro | 100 | once per minute | per minute |
| Enterprise | 100 | once per minute | per minute |

Verbatim: "Cron expressions that would run more frequently will fail during deployment" with the error "Hobby accounts are limited to daily cron jobs. This cron expression would run more than once per day." A `0 1 * * *` job "will trigger anywhere between 1:00 am and 1:59 am". The belief in the plan ("Hobby is daily only") is **confirmed**.

**Other Vercel Cron behaviours** (https://vercel.com/docs/cron-jobs, 2026-09-16; https://vercel.com/docs/cron-jobs/manage-cron-jobs, 2026-08-11):
- Vercel sends an HTTP **GET** to the project's **production** deployment URL. User agent is `vercel-cron/1.0`; header `x-vercel-cron-schedule` carries the cron expression.
- **Authorization header**: if the project has an env var `CRON_SECRET`, Vercel automatically sends `Authorization: Bearer <value of CRON_SECRET>`. Vercel recommends at least 16 random characters. The documented check is `authHeader !== \`Bearer ${cronSecret}\`` and also `!cronSecret` (fail closed when unset).
- No retry on failure. Delivery is best effort and can also be duplicated, so handlers must be idempotent and reconciliation based.
- Redirects are not followed (a 3xx is final). Timezone is always UTC. Cron invocations that return a redirect or cached response do not appear in logs.
- Cron duration limits equal Vercel Function limits.

**Function duration** (https://vercel.com/docs/functions/limitations, https://vercel.com/docs/fluid-compute, https://vercel.com/docs/functions/configuring-functions/duration):

| Runtime | Plan | Default | Maximum |
|---|---|---|---|
| Node.js, Bun, Python with Fluid | Hobby | 300 s | **300 s** |
| same | Pro / Enterprise | 300 s | 800 s (1800 s extended, beta) |

Exceeding it returns 504 `FUNCTION_INVOCATION_TIMEOUT`. In App Router the config is `export const maxDuration = <seconds>` in the route file; the local Next 16.3.6 guide `03-api-reference/03-file-conventions/02-route-segment-config/maxDuration.md` confirms this and says the value is passed to the platform. Edge runtime is **deprecated** in this Next version (`runtime.md`); use the default `nodejs`.

**Region pinning in Next 16.3.6**: `preferredRegion` is **deprecated** (`preferredRegion.md`: "Remove the `preferredRegion` export from your route files"). On Vercel set the region with `vercel.json` `"regions": ["iad1"]` or the dashboard (Settings, Functions). Hobby is limited to a **single region** (https://vercel.com/docs/functions/configuring-functions/region, "Limits" table). All 19 Vercel compute regions are outside Indonesia (list at https://vercel.com/docs/regions: iad1, cle1, sfo1, pdx1, yul1, gru1, dub1, lhr1, cdg1, fra1, arn1, bom1, sin1, hkg1, hnd1, kix1, icn1, syd1, cpt1; there is no Jakarta region).

**Region nearest to the RPC.** `rpc.testnet.chain.robinhood.com` is a CNAME to `customer-origin.offchainlabs.com` with Cloudflare anycast addresses (172.66.147.70, 104.20.46.209; DoH `1.1.1.1/dns-query`, 2026-10-03). Responses carry `server: cloudflare`, `x-envoy-upstream-service-time: 1`. From this machine the edge colo is Singapore (`cf-ray ...-SIN`). Measured on a reused connection: about 0.22 to 0.24 s per JSON-RPC call, of which client to edge is about 0.04 s, so the edge to origin leg is about 0.18 s. That rules out an origin in Asia but does not pin the origin to a Vercel region. Because every Vercel region reaches a nearby Cloudflare POP, the region matters little; keep the existing **`iad1`** (project default, also Vercel's default and failover root) unless a measured test says otherwise. The origin location is **not discoverable** from outside; see Still unknown.

**Hobby limits that matter for ticks** (https://vercel.com/docs/plans/hobby, https://vercel.com/docs/logs/runtime, https://vercel.com/docs/vercel-firewall/vercel-waf/rate-limiting):
- Included: 1,000,000 function invocations, 4 CPU-hours Active CPU, 360 GB-hours memory. Exceeding means waiting 30 days to use the feature again ("Hobby billing cycle").
- Runtime logs retention on Hobby: **1 hour**. So Vercel logs cannot be the monitoring record; the pinger history and on-chain state must be.
- Hobby use is restricted to non-commercial personal use (fair use guidelines); acceptable for a testnet hackathon project.
- WAF rate limiting: 1 rule per project on Hobby, 3 custom firewall rules in total (relevant to E10-T5, not to the tick).
- Env vars: 64 KB total per deployment; **Sensitive** variables (unreadable after creation) can only be created in Production and Preview, not Development (https://vercel.com/docs/environment-variables/sensitive-environment-variables, 2026-08-28).

**Active CPU budget (estimate, assumption A3).** At roughly 0.3 s of Active CPU per tick (Active CPU pauses while the function waits on I/O per https://vercel.com/docs/functions/configuring-functions/duration): every 5 min = 8,640 ticks per month = about 0.7 CPU-hours; every 2 min = about 1.8 h; every 1 min = about 3.6 h of the 4 h cap. A 1 minute cadence leaves almost no headroom; 5 minutes is comfortable.

### F2. How the route must protect itself

From the Vercel cron docs plus the local Next guide `01-getting-started/15-route-handlers.md` ("Route Handlers are not cached by default"; reading `request.headers` keeps it dynamic):
1. Read `request.headers.get('authorization')`; compare to `Bearer ${process.env.CRON_SECRET}`; if `CRON_SECRET` is unset or empty, **reject** (fail closed, never allow).
2. Compare with `crypto.timingSafeEqual` on equal-length buffers (hash both sides with SHA-256 first so lengths always match). Do not trust the `vercel-cron/1.0` user agent or `x-vercel-cron-schedule`; both are spoofable.
3. Return a bare 401 with no detail. Never log the header, the secret, or any private key; never accept the secret in the query string.
4. Implement both `GET` and `POST` (cron-job.org can do either; Vercel Cron sends GET).
5. Be idempotent: the work is reconciled from chain state each tick (read `updatedAt`, `checkUpkeep`, simulate before sending). Two overlapping ticks then cost a failed simulation or a nonce error, not a double effect. Vercel itself documents duplicates and concurrency (cron manage page, "Cron job delivery and idempotency").
6. Respond with a small JSON summary and a status code the pinger understands (200 ok, 503 degraded), because cron-job.org judges only the HTTP status and stores the first part of the response body for 2 days.
7. The pinger must call the **production alias** (`composable-strategy-marketplace.vercel.app`). Deployment-hash URLs are behind SSO and return a 302, which cron-job.org counts as failure by default ("Treat redirects as success" is off), which is a useful tripwire if protection scope ever changes.

### F3. Free external pingers (question 2)

| | cron-job.org | UptimeRobot Free | Better Stack Free | Cloudflare Workers cron (free) | Upstash QStash (free) |
|---|---|---|---|---|---|
| Minimum interval | **1 min** ("up to 60 times an hour") | 5 min | 3 min checks | 1 min (cron expression), UTC | schedules, 10 active; 1,000 messages per day |
| Custom header (`Authorization: Bearer`) | **Yes**, arbitrary except `User-Agent`, `Connection` | **No** (custom headers and statuses are marked unavailable on Free; API monitoring "with authentication and custom headers" is "no" on Free) | API has `request_headers`; plan gating **not stated** on the pages read | Yes, in Worker code (`fetch` with headers) | not verified |
| Failure notification | Email, plus Slack, Discord, Telegram, webhook, ntfy etc. channels; "Notify after N subsequent failures"; notify on recovery; notify on auto-disable | Email (all plans), SMS and voice credits paid | Slack and email on Free | none built in (Worker logs only) | retries billed as extra messages |
| Request timeout | 30 s (FAQ), field "Timeout" in job advanced settings | not stated on pages read | not stated | cron CPU 10 ms (wall time not CPU) | 15 min HTTP response on Free |
| Job limit | none stated, "fair usage" | 50 monitors | 10 monitors, 10 heartbeats | 5 cron triggers per account | 10 active schedules |
| Auto-disable | after more than 25 consecutive failures (email on request) | n/a | n/a | n/a | n/a |
| Sign-up friction | email, password, **invisible reCAPTCHA**, email confirmation link | **Cloudflare Turnstile** in the sign-up bundle, email confirmation | **reCAPTCHA** on the sign-up page | Cloudflare account + `wrangler login` browser OAuth | account |
| Reliability statement | "cannot give a promise or a guarantee on punctuality"; "slight delays during peak hours"; console history shows scheduled vs executed time and a "Jitter" column | monitoring product, 5 min | monitoring product | "run on underutilized machines" (no timing guarantee) | n/a |
| Stores history | last 50 executions, headers and bodies for 2 days | uptime log | incidents | no | 3 days logs |

Sources: https://cron-job.org/en/faq/ and https://cron-job.org/en/ (read 2026-10-03); the cron-job.org console web app bundle `https://console.cron-job.org/static/js/main.394da973.js` (UI strings for Custom headers, Timeout, "Treat redirects ... as success", "Notify after ... subsequent failures", notification channel types, `size:"invisible"` reCAPTCHA on sign-up, Turnstile on test runs, plan table rows "Max job timeout" and "Max failures before disabling a job" for Default vs Sustaining membership); https://uptimerobot.com/pricing/ (free: "5 min. monitoring interval", "API monitoring: no", comparison row "Custom headers & statuses": cross on Free, ticks on Solo and above; parsed from the page's embedded plan JSON and table); https://dashboard.uptimerobot.com/sign-up (JS chunks contain Cloudflare Turnstile); https://betterstack.com/pricing and https://betterstack.com/uptime ("10 monitors, 10 heartbeats and a status page with 3-minute checks totally free"); https://betterstack.com/docs/uptime/api/create-a-new-monitor/ (`request_headers`, `check_frequency`); https://betterstack.com/users/sign-up (reCAPTCHA markers); https://developers.cloudflare.com/workers/platform/limits/ (5 cron triggers on Free, CPU per cron trigger 10 ms on Free, 50 subrequests per invocation on Free, cron wall time 15 min); https://developers.cloudflare.com/workers/configuration/cron-triggers/ (Sep 4, 2026 update); https://upstash.com/docs/qstash/overall/pricing.

cron-job.org's free tier is therefore the only option that checks all four boxes (interval at or under 5 min, custom Authorization header, failure email, no card). Whether the sign-up invisible reCAPTCHA shows a visible puzzle cannot be known without trying; plan for one possible click-through.

Probing a state-changing route from a multi-location monitor (UptimeRobot location checks, Better Stack multi-location) would fire it from several places per interval; that is another reason the watchdogs only poll the read-only health route.

### F4. Railway (question 3)

- User's Railway state (read-only MCP): `whoami` returns user `candra0x6`, registrationStatus REGISTERED, account created 2026-09-30; `list-workspaces` returns one personal workspace "C4N's Projects" with `projectCount: 0`; `list-projects` returns `[]`. The workspace plan and trial type are **not exposed** by the MCP tools available read-only (`railway-agent` requires a project id, so it was not called).
- Documented plan model (https://docs.railway.com/pricing/plans, https://docs.railway.com/pricing/free-trial, read via MCP `fetch-docs`): a Trial gives a one-time $5 grant valid 30 days, then the account reverts to the **Free plan with $1 of credit per month, no rollover**. Free plan service limits: 1 replica, **0.5 GB RAM**, 1 vCPU. Trial: 1 GB RAM, shared vCPU, 5 services per project. Hobby is $5 per month and includes $5 of usage. Pro $20.
- **Restart policy** (https://docs.railway.com/deployments/restart-policy): on Free and Trial, `Always` is **not available**, and `On Failure` is limited to 10 restarts. A looping worker that ever exits is therefore restarted at most 10 times, then stays down.
- **Limited vs Full Trial**: unverified accounts (no linked GitHub passing Railway's automated check) get "restricted outbound network access and only a limited set of ports". The docs do not say whether HTTPS 443 to the RPC is allowed. This may be exactly the free-plan block hit by the previous attempt, but the earlier error text is not available to this track (Still unknown).
- **Railway cron** (docs guides `cron-workers-queues`, `cut-idle-costs-serverless`, via `search-docs`): minimum interval **5 minutes**, UTC, a still-running previous run causes the next to be skipped. A cron service that runs `tick` and exits is billed only for its run seconds, so it is the cheap Railway shape; an always-on `while(true)` worker is the expensive one.
- **Cost estimate** (arithmetic from the price table: RAM $10 per GB-month, CPU $20 per vCPU-month, egress $0.05 per GB): a Node loop at about 0.1 GB RAM and about 0.02 vCPU average is about $1.00 + $0.40 = **about $1.4 per month**, above the Free $1 credit, so Hobby ($5, includes $5 usage) would be needed after the $5 trial. As a 5 minute cron that runs about 10 s each, 8,640 runs × 10 s ≈ 24 h of 0.1 GB, well under $0.10 per month. These are estimates (assumption A5).
- Verdict: a new (or the existing) account could host it **if** it reaches Full Trial; it adds a fourth moving part, cannot be proven from here, and the plan's own rule says not to touch the user's Railway. Use as an optional second shell only after the Vercel path is live.

### F5. GitHub Actions `schedule` and Cloudflare Workers cron (question 4)

GitHub documented behaviour (https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows, read 2026-10-03):
- "The shortest interval you can run scheduled workflows is once every 5 minutes."
- "The schedule event can be delayed during periods of high loads of GitHub Actions workflow runs. High load times include the start of every hour. If the load is sufficiently high enough, some queued jobs may be dropped. To decrease the chance of delay, schedule your workflow to run at a different time of the hour."
- Only runs from the default branch; in a **public** repository scheduled workflows are **automatically disabled after 60 days without repository activity**.

Observed jitter:
- https://github.com/orgs/community/discussions/122271 (May 2024): one user reports delays of "5, 13, 22 minutes" on `33 11 * * *`; another "delays between 5 to 20 minutes". No GitHub staff reply.
- https://runhooks.app/blog/github-actions-scheduled-workflows-unreliable/ : "sometimes by 5 to 20 minutes", with an example run sequence 09:00, 09:11, nothing at 09:15, 09:22. No stated methodology.
- https://dev.to/krissv/monitoring-github-actions-scheduled-workflows-a-practical-guide-31h7 : "delays of 30 to 60 minutes aren't unusual" during busy periods (anecdote, no data).
Conclusion: expect 5 to 20 minutes late, occasionally skipped, with worst behaviour around the top of the hour. That is acceptable for a 30 minute price heartbeat, **not** for hitting an exact 1 hour BLTZ window, and the repository does not exist yet (`docs/brainstorm/...` section 0: "the repo is not a git repository"). Needs the GitHub repo and an Actions secret holding `CRON_SECRET` (Actions secrets are write-only after saving).

Cloudflare Workers cron (limits page read 2026-10-03): Free plan allows **5 cron triggers per account**, **10 ms CPU per cron trigger invocation** (waiting on `fetch` does not count as CPU), 50 subrequests per invocation. Cron wall time up to 15 minutes. Cron Triggers "run on underutilized machines" so timing is not guaranteed. A Worker `scheduled()` that `fetch`es the Vercel tick URL with an `Authorization` header is a legitimate free pinger, but needs a Cloudflare account, `wrangler login`, a `wrangler deploy`, and `wrangler secret put`. Running viem signing inside the free Worker is not advisable (10 ms CPU). It is a third platform for little gain over cron-job.org.

### F6. Can ~12 RPC calls over an intermittently broken TLS path finish, and how (extra question)

Measured on 2026-10-03 from this machine (the user's network, ISP interception present), all against `https://rpc.testnet.chain.robinhood.com`:
- 40 sequential `eth_blockNumber` calls: **36 ok, 4 failed** (10 percent), every failure was `curl: (60) SSL: no alternative certificate subject name matches target hostname`, i.e. the interception handing back a wrong certificate, and each failed **instantly** (0.000 s), not by hanging.
- Successful call timing: first call on a new connection 0.30 to 0.37 s (TCP 0.04 s, TLS 0.08 to 0.15 s); later calls on the same connection 0.21 to 0.24 s. Block production: 1,000 blocks in 153 s (about 0.15 s per block), so a transaction can be included in about 1 s.
- Therefore 12 sequential calls take about 12 × 0.23 + 0.4 = **about 3.2 s**. Even a 5 minute cadence with 6 feed pushes plus 3 rebalances (each send plus receipt wait) fits in roughly 5 to 12 s.
- Retry math using the observed 10 percent per-attempt failure as a pessimistic bound: with 3 attempts per call a call fails with probability 0.1^3 = 0.1 percent and a 12-call tick fails with about 1.2 percent; with 4 attempts 0.01 percent per call and about 0.12 percent per tick. Failures cost about 0 s plus backoff. viem 2.56.9 (installed) defaults: `retryCount = 3`, `retryDelay = 150`, exponential delay `(1 << count) * retryDelay` (150, 300, 600 ms, 1.05 s total), and generic network errors with no HTTP status are retried (`node_modules/viem/_cjs/utils/buildRequest.js`, `createTransport.js`; HTTP transport default timeout 10 s). `waitForTransactionReceipt` polls at `clamp(blockTime/2, 500, 4000)` ms, default 2 s for a chain without `blockTime`, so set `pollingInterval: 500`.
- **Important**: the ISP interception sits between the user's laptop and the internet. A Vercel function in `iad1` leaves through AWS, so the failure rate there should be near zero. That is assumption A1, to be confirmed in the first soak by counting retries in the tick summary. The design below keeps the 10 percent figure as a worst case.
- **Verdict: yes.** Against Hobby `maxDuration` 300 s the margin is about 90 times. The binding limit is cron-job.org's **30 s** request timeout.

## Recommendations

### R-1. Architecture (decision)

Primary clock: **cron-job.org every 5 minutes, GET `https://composable-strategy-marketplace.vercel.app/api/ops/tick` with header `Authorization: Bearer <CRON_SECRET>`**.
Independent watchdog: **UptimeRobot Free HTTP monitor, every 5 minutes, on `/api/ops/health`** (public, read-only, no header needed).
Optional backstop with no extra account: a daily Vercel Cron in `vercel.json` (`{"path": "/api/ops/tick", "schedule": "17 3 * * *"}`), which Vercel authenticates with the same `CRON_SECRET` automatically. Never put a more frequent expression in `vercel.json` on Hobby, the deployment will fail.
Optional second caller once the GitHub repo exists: a GitHub Actions workflow on an off-peak minute (for example `*/10` offset to `3-59/10`), same Bearer header from an Actions secret. Skip Railway and Cloudflare unless a pinger outage actually occurs.

### R-2. Tick route: time budget and retry design

Entry `src/app/api/ops/tick/route.ts`, Node runtime, `export const maxDuration = 60` (Hobby maximum is 300; 60 is only a safety net), `GET` and `POST`. No `preferredRegion` (deprecated); region comes from `vercel.json` or the project setting (currently `iad1`).

```ts
export const maxDuration = 60

const BUDGET_MS = 22_000
const MIN_TO_SEND_MS = 6_000
const READ_TIMEOUT_MS = 3_000

export async function GET(request: Request) {
  if (!authorized(request)) return new Response('Unauthorized', { status: 401 })
  const deadline = Date.now() + BUDGET_MS
  const left = () => deadline - Date.now()
  const summary = newSummary()
  const state = await readAll(left)           // one Multicall3 aggregate3: feeds, checkUpkeep, balances
  await relay(state, left, summary)           // only feeds due: age >= 25 min or move >= 10 bps
  await keep(state, left, summary)            // checkUpkeep again after prices, simulate then send
  summary.elapsedMs = BUDGET_MS - left()
  return Response.json(summary, { status: summary.critical ? 503 : 200 })
}
```

Rules:
1. **Budget 22 s total**, strictly below cron-job.org's 30 s timeout. Check `left()` before every step. **Never start a send with less than 6 s left** (a send needs a receipt wait); push the work to the next tick instead and report `skipped: "budget"`.
2. **Reads batched**: use Multicall3 (`0xcA11bde05977b3631167028862bE2a173976CA11`, present per `docs/research/07-testnet-reality-check.md`) so the six feed reads, `checkUpkeep` and balances are one RPC round trip, not 12 to 20.
3. **Per-call policy**: viem HTTP transport with `timeout: 3000`, `retryCount: 3`, `retryDelay: 200` (delays 200, 400, 800 ms), built per tick. Retry any error without an HTTP status (TLS, reset, DNS) and 408, 429, 5xx; do not retry reverts. If a tick-wide abort is wanted, race each step against the deadline and abort in-flight fetches at the deadline (viem option behaviour for a shared `AbortSignal` must be verified during the build; the race on `left()` is the guaranteed part).
4. **Writes**: fetch the pending nonce once, send the due `updateAnswer` transactions with consecutive nonces, then await all receipts in parallel with `pollingInterval: 500` and a timeout of `min(left() - 2000, 8000)`. Always `simulateContract` before `performRebalance`; a failed simulation (already rebalanced by a duplicate tick) is a skip, not an error.
5. **Never leave an orphan**: return every sent transaction hash in the response; if a receipt timed out, the next tick reconciles from the pending nonce and chain state. `StalePrice` on a keeper simulation triggers one relayer pass then one retry within the same budget.
6. **Status mapping for the pinger** (cron-job.org judges status only): 200 when everything due was handled or skipped for budget; **503** when critical (relayer or keeper wallet below the ETH floor, any feed older than 6 h, all RPC attempts failed, `CRON_SECRET` unset on the server). A 503 triggers the cron-job.org failure email and a clear body line for the 2 day response history (this is E2-T8).
7. **Concurrency**: no lock is required for correctness (idempotent from chain state, section F2). If a lock is later wanted, Vercel documents Redis locks, but that adds a service; not recommended for a testnet demo.
8. Log only counters and addresses, never headers or keys.

### R-3. Health endpoint (detecting a dead host)

`/api/ops/health`: public, read-only, `Cache-Control: no-store` on errors and `public, s-maxage=20` on 200 (bounds RPC load from the footer badge and the watchdog). Computed only from chain: per-feed age (`updatedAt`), keeper and relayer ETH balances, time of the last `Rebalanced` event by the keeper address, plus RPC latency and the retry count of the last read. Return **503** when any feed age is over 35 minutes (hold mode) or a balance is under its floor, **200** otherwise. No storage service is needed, which also covers the fact that Hobby runtime logs are retained for only 1 hour.

Detection chain (two independent vendors, so one outage cannot silence both):
1. cron-job.org: failure email when the tick returns non-2xx twice in a row ("Notify after 2 subsequent failures"), on recovery, and on auto-disable.
2. UptimeRobot: failure email when health is 503 or unreachable (covers: cron-job.org dead, job disabled, Vercel down, key out of gas). Worst-case detection of a silent dead pinger is about 35 min (feed age threshold) plus one 5 minute check, so under 45 minutes.

### R-4. Cadence (satisfies the 1 hour BLTZ strategy and the 30 min price push)

- BLTZ is seeded with `rebalanceInterval = 1 hours` and a 50 percent max weight (`script/SeedStrategies.s.sol:86`: `_create(6, "High Beta Blitz", "BLTZ", PLTR 5000 / TSLA 5000, 5000, 1 hours)`), so it becomes eligible every 60 minutes and any pinger cadence adds lag, never earlier action.
- **Tick every 5 minutes** (cron-job.org free allows 1 minute, UptimeRobot 5, Better Stack 3, GitHub 5). Keeper evaluated every tick, so a time-based rebalance fires within one tick of becoming due: lag at most about 5 minutes plus pinger jitter (cron-job.org makes no punctuality promise), so under about 6 minutes in the normal case.
- **Price push**: relayer pushes when move is at least 10 bps **or** feed age is at least **25 minutes** (instead of 30). With a 5 minute tick the worst feed age is then about 30 minutes, which keeps the E2 acceptance line "feeds under 35 min" with a 5 minute cushion for one missed tick. A 30 minute threshold would put the worst case at 35 minutes, exactly on the boundary.
- Why not 1 minute: it multiplies invocations by 5 and Active CPU to about 3.6 of the 4 free CPU-hours (estimate A3), for no benefit to a 1 hour or 30 minute requirement.
- Tick idempotency also makes a faster burst safe during the demo (run `scripts/demo-shock.sh`, then trigger a manual tick with curl and the secret held in the user's shell, never in a file).

### R-5. Where each secret lives, rotation, detection

| Secret | Lives in | Notes |
|---|---|---|
| `CRON_SECRET` | Vercel env (Production, **Sensitive**) and the cron-job.org job's custom header (and the GitHub Actions secret if used) | Generate locally and copy to the clipboard without printing, for example `openssl rand -hex 32 \| wl-copy`. Because Sensitive values cannot be read back from Vercel, the user must keep the source value long enough to paste it into cron-job.org. |
| `KEEPER_PRIVATE_KEY`, `RELAYER_PRIVATE_KEY`, `FAUCET_PRIVATE_KEY` | Vercel env (Production, Sensitive) only | Testnet, low-balance keys; separate wallets so a leak of one cannot drain another. Never in the repo, the pinger or logs. |
| `DEPLOYER_PRIVATE_KEY` | Only in the user's local shell for deploy and funding | Not set on Vercel. |

Vercel states env values are encrypted at rest; Sensitive additionally makes them unreadable after creation and redacts them in build logs (https://vercel.com/docs/environment-variables, https://vercel.com/docs/environment-variables/sensitive-environment-variables). A change applies only to new deployments, so a redeploy is part of every rotation (https://vercel.com/docs/environment-variables/rotating-secrets, last_updated 2026-07-15).

**Rotate `CRON_SECRET`**: (1) generate a new value; (2) edit the Vercel var (Production) and **Redeploy**; (3) immediately edit the cron-job.org header to `Bearer <new>`; (4) run "Test run" in cron-job.org and expect 200; (5) update the GitHub secret if present. Expect one or two failed pings in the gap; "notify after 2 failures" absorbs that. Zero-gap alternative (optional, needs an extra env name beyond the standing list, so coordinate): accept `CRON_SECRET_PREVIOUS` for one rotation window.

**Rotate a wallet key**: create a new wallet, fund it with a small amount of ETH, set the new env value, redeploy, confirm the new address appears in the health JSON, then sweep the old wallet and retire it. If the key had an on-chain role (faucet, keeper allowlist in V2), revoke it with the deployer.

**Dead host detection**: R-3.

### R-6. Human steps, in order, with estimated minutes

Assumes the tick and health routes are built and deployed to the existing Vercel project by the E2 and E7 agents (not part of this research). Agent-only steps are marked (agent).

| # | Who | Step | Min |
|---|---|---|---|
| 1 | User | In a local terminal run `openssl rand -hex 32 \| wl-copy` (the value is copied, not displayed). Keep it on the clipboard until step 3. | 1 |
| 2 | User | Generate keeper and relayer wallets locally (for example `cast wallet new`), note only the **public addresses** to give the agent for funding, keep the private keys for step 3, then clear the terminal. | 3 |
| 3 | User | Vercel dashboard, project `composable-strategy-marketplace`, Settings, Environment Variables: add `CRON_SECRET`, `KEEPER_PRIVATE_KEY`, `RELAYER_PRIVATE_KEY` (and `FAUCET_PRIVATE_KEY` for E10), environment **Production**, toggle **Sensitive** on, Save. | 5 |
| 4 | Agent | Fund keeper, relayer and faucet addresses from the deployer (gas is about 0.01 gwei; a few thousandths of an ETH each is enough). Deploy to production (E7). Verify: `curl` with no header returns 401, with the header returns 200 (the agent must read the secret from the user's shell or ask the user to run this one command). | 5 |
| 5 | User | Open https://console.cron-job.org, **Sign up** (email, password, pass the bot check; if a challenge appears solve it), open the confirmation email and click the link. The ISP may break TLS to some hosts; if a page fails, reload. | 5 |
| 6 | User | In cron-job.org create a cronjob. Title `feng-tick`. URL `https://composable-strategy-marketplace.vercel.app/api/ops/tick`. Schedule: every **5 minutes**. Open **Advanced**: Request method **GET**; Custom headers, add header `Authorization` with value `Bearer ` followed by the pasted secret; **Timeout** 30; leave "Treat redirects with HTTP 3xx status code as success" **off**. Notifications ("Notify me when..."): enable "execution of the cronjob fails" with "Notify after 2 subsequent failures", "succeeds after it failed before", and "will be disabled because of too many failures"; "Notify via" the account email. Save, ensure the job is **enabled**, press **Test run** and expect HTTP 200. | 8 |
| 7 | User | Open https://dashboard.uptimerobot.com/sign-up (Turnstile bot check, email confirm). Create monitor: type **HTTP(s)**, URL `https://composable-strategy-marketplace.vercel.app/api/ops/health`, interval **5 minutes** (the Free minimum), alert contact: your email, enable alerts on down and on up. | 7 |
| 8 | User | (Optional, 2 min) Confirm in the cron-job.org job history that two consecutive executions show 200 and a small JSON body, and in UptimeRobot that the monitor is Up. | 2 |
| 9 | Agent | E2-T5 soak: at least 4 hours with a real keeper-address `Rebalanced` event, feed ages under 35 minutes, a kill test (disable the job for 40 minutes, expect the UptimeRobot email), one injected TLS failure. | 0 user |

Human total **about 30 to 36 minutes**. Minimum viable subset if time is critical (steps 1, 3, 5, 6): about 19 minutes, giving a working clock and failure email but no independent watchdog.

## Implications per role

- **GP/ops (E2-T1 to T5, T8)**: ship `/api/ops/tick` and `/api/ops/health` exactly as in R-2 and R-3; `maxDuration = 60`, no `preferredRegion`, Node runtime, Multicall3 reads, `pollingInterval: 500`, heartbeat threshold 25 minutes, 22 s budget, 503 on critical. Put the runbook (R-5, R-6) in `docs/ops/RUNBOOK.md`. Do not add a `crons` entry more frequent than daily to `vercel.json`. Keep `scripts/keeper.sh` as the laptop fallback.
- **work:frontend (E2-T7, E10-T2)**: the footer badge reads `/api/ops/health`; it is cached 20 s at the CDN, so show "as of" rather than a live second counter. Faucet UI states come from the faucet route, not from health.
- **E7 deploy**: deploy to the production alias `composable-strategy-marketplace.vercel.app` (public). Hash URLs are SSO protected and unusable for the pinger. Env changes need a redeploy. Verify `curl` 401 versus 200 after deploy.
- **E10-T5 (faucet)**: Hobby gets one WAF rate-limit rule per project (counting key IP) and three custom rules in total, so spend the one rate-limit rule on `/api/faucet`; the tick is protected by the secret, not by a rule.
- **E3 (V2)**: the hourly `checkpoint` call rides on the same 5 minute tick (do it when the last checkpoint is at least 60 minutes old, from chain state), no separate schedule.
- **R2 owner (price source)**: the relayer must reach `api.robinhood.com` **from Vercel datacenter IPs**, which was not tested here; confirm on first deploy and keep the `hold` fallback.
- **E8 tests**: add tests for the auth guard (unset secret rejects, wrong length, timing-safe path), the time budget (steps skipped when `left()` is small) and the retry classifier (TLS error retried, revert not retried).
- **E11 / README**: describe the architecture honestly (external pinger plus Vercel route, testnet, Hobby plan) and link the live health endpoint as the liveness proof.
- **User**: about 30 to 36 minutes of clicking and pasting (R-6); two email confirmations; keep the `CRON_SECRET` source value until it is pasted into cron-job.org.

## Assumptions and open questions

- **A1.** Vercel `iad1` reaches `rpc.testnet.chain.robinhood.com` without the ISP interception seen from Indonesia. Likely, since the interception is local to the user's ISP, but not proven. Check: first soak, count retries and errors in the tick summary.
- **A2.** The project's production alias stays public. Observed today as 200; if protection scope is changed to "All Deployments", cron-job.org will get 401/302 and fail (which the failure email will surface).
- **A3.** About 0.3 s Active CPU per tick (estimate, not measured). Check in the Vercel usage page after the soak; Hobby cap is 4 CPU-hours per 30 days.
- **A4.** cron-job.org behaves as its FAQ says (1 minute minimum, 30 s timeout, custom headers). Verified by reading the FAQ and the live console bundle, not by running a job.
- **A5.** Railway cost figures are arithmetic from the published unit prices with assumed resource use (0.1 GB, 0.02 vCPU), not a measurement.
- **A6.** Whether Vercel keeps executing the function after the pinger disconnects at 30 s is not documented in the pages read. The 22 s budget makes this moot.
- **A7.** The RPC enforces no rate limit that a tick every 5 minutes (about 20 calls) could hit; the same applies to the health route cached for 20 s. No limit is documented on the pages read.
- **Open question for the coordinator**: allow an extra env name `CRON_SECRET_PREVIOUS` for zero-downtime rotation? Default: no, accept a short gap.
- **Open question**: use the daily Vercel Cron backstop at all? It adds nearly nothing (once a day, up to 59 min late) and a typo in `vercel.json` breaks the deploy. Default: include it only if the E2 agent validates the expression locally; skippable.

## Sources

All read 2026-10-03.

Vercel
- https://vercel.com/docs/cron-jobs (last_updated 2026-09-16)
- https://vercel.com/docs/cron-jobs/usage-and-pricing (2026-07-15)
- https://vercel.com/docs/cron-jobs/manage-cron-jobs (2026-08-11)
- https://vercel.com/docs/functions/limitations ; https://vercel.com/docs/fluid-compute ; https://vercel.com/docs/functions/configuring-functions/duration (2026-08-24)
- https://vercel.com/docs/functions/configuring-functions/region ; https://vercel.com/docs/regions
- https://vercel.com/docs/plans/hobby ; https://vercel.com/docs/logs/runtime ; https://vercel.com/docs/deployment-protection ; https://vercel.com/docs/vercel-firewall/vercel-waf/rate-limiting
- https://vercel.com/docs/environment-variables ; https://vercel.com/docs/environment-variables/sensitive-environment-variables (2026-08-28) ; https://vercel.com/docs/environment-variables/rotating-secrets (2026-07-15)
- Commands: `vercel whoami` (candra0x6), `vercel teams ls` (one team, candras-projects), `vercel project ls`, `vercel api /v2/teams/team_isUYixlBIdWzYSzt1P7ge9bg --raw` (plan hobby), `vercel api /v9/projects/prj_S5dRGc6BccnT2mFGjUwgZ8bomWuX --raw` (fluid true, region iad1, crons empty, ssoProtection all_except_custom_domains); Vercel MCP `get_team`, `get_project`.
- `curl` of `https://composable-strategy-marketplace.vercel.app/` (200) and of a deployment-hash URL (302); `/api/ops/health` currently 404 (not built yet).

Next.js 16.3.6 local guides (`node_modules/next/dist/docs/01-app/`)
- `03-api-reference/03-file-conventions/route.md`; `.../02-route-segment-config/maxDuration.md`; `.../preferredRegion.md` (deprecated); `.../runtime.md` (edge deprecated); `01-getting-started/15-route-handlers.md` (not cached by default); `03-api-reference/04-functions/after.md` (`after` runs within the route's max duration).

Pingers and schedulers
- https://cron-job.org/en/ ; https://cron-job.org/en/faq/ ; https://cron-job.org/en/privacy/ ; `https://console.cron-job.org/static/js/main.394da973.js` (console UI strings, plan table rows)
- https://uptimerobot.com/pricing/ ; https://dashboard.uptimerobot.com/sign-up (JS chunks reference Turnstile)
- https://betterstack.com/pricing ; https://betterstack.com/uptime ; https://betterstack.com/docs/uptime/api/create-a-new-monitor/ ; https://betterstack.com/users/sign-up
- https://upstash.com/docs/qstash/overall/pricing
- https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
- https://github.com/orgs/community/discussions/122271 ; https://runhooks.app/blog/github-actions-scheduled-workflows-unreliable/ ; https://dev.to/krissv/monitoring-github-actions-scheduled-workflows-a-practical-guide-31h7
- https://developers.cloudflare.com/workers/configuration/cron-triggers/ ; https://developers.cloudflare.com/workers/platform/limits/

Railway (via MCP `fetch-docs` and `search-docs`)
- https://docs.railway.com/pricing/plans ; https://docs.railway.com/pricing/free-trial ; https://docs.railway.com/pricing/faqs ; https://docs.railway.com/deployments/restart-policy ; guides `cron-workers-queues`, `cut-idle-costs-serverless`
- MCP `whoami`, `list-workspaces`, `list-projects` (read-only account state)

Chain probes and local files
- DoH `https://1.1.1.1/dns-query?name=rpc.testnet.chain.robinhood.com&type=A` ; `curl` timing and 40-call burst against the RPC ; `eth_getBlockByNumber` block time sample
- `docs/brainstorm/2026-10-03-feng-v2-plan.md` sections 0, 5.2, E2, E10, 7 R5 ; `docs/research/07-testnet-reality-check.md` ; `script/SeedStrategies.s.sol:86` ; `scripts/keeper.sh`, `scripts/refresh-feeds.sh` ; `node_modules/viem/_cjs/utils/buildRequest.js`, `.../clients/transports/createTransport.js` (viem 2.56.9)

**Recommendation**
1. Run the work as a Vercel route (`/api/ops/tick`, Bearer `CRON_SECRET`, `maxDuration = 60`, 22 s internal budget, Multicall3 reads, retries 3 with 200 ms exponential backoff, 503 on critical) on the existing project in `iad1`.
2. Call it every 5 minutes from **cron-job.org** (free, custom header, failure email, notify after 2 failures).
3. Watch `/api/ops/health` (503 when any feed is over 35 minutes old or a wallet is under its floor) with **UptimeRobot Free** every 5 minutes, a different vendor from the clock.
4. Relayer heartbeat at 25 minutes or 10 bps; keeper on every tick; BLTZ time rebalance lag under about 6 minutes.
5. Secrets only as Vercel Sensitive Production env vars; `CRON_SECRET` also pasted once into the cron-job.org header; rotation is edit, redeploy, update header, test.
6. Do not use Vercel Cron for anything more than an optional daily backstop; do not use Railway, GitHub Actions or Cloudflare unless the primary path fails.

**Still unknown**
1. Where the Robinhood RPC origin physically sits (Cloudflare hides it), so which Vercel region is truly nearest. Measure after deploy by comparing RPC latency in the tick summary; iad1 is the default pick.
2. Whether the Vercel function path to the RPC is free of the TLS interception (A1) and whether `api.robinhood.com` accepts Vercel datacenter IPs.
3. Whether cron-job.org's sign-up will show a visible CAPTCHA challenge, and its real punctuality (no guarantee published; the console history "Jitter" column will show it after the first hour).
4. Whether request headers are available on the Better Stack Free plan (the pages read do not say), and whether UptimeRobot's Turnstile on sign-up is interactive.
5. The exact error that blocked the previous Railway attempt, the user's Railway plan and trial type (Full or Limited), and whether outbound 443 is allowed there.
6. Measured Active CPU per tick against the 4 CPU-hour Hobby cap.
7. Whether Vercel keeps running a function after the pinger closes the connection at 30 s.
