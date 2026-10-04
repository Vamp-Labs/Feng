# Runbook: V2 deploy, verify, switch, Vercel production, rollback (E8-T4)

Scope: Robinhood Chain testnet (chain 46630) only. Source of truth for the contracts and the JSON schema is `docs/handoffs/04-contracts-v2.md` (sections 5.3 and 6). Verification background is `docs/research/11-blockscout-verification.md`. Nothing here is run automatically; the user runs the steps marked KEY.

## Conventions

- Run everything from the repo root. Quote the path: `cd "/home/cn/Projects/Competition/Web3/Arbitrum/Feng."` (the folder name ends with a dot).
- Keys only through exported shell variables. Never paste a key into a command line, a file or a chat. Never read or print any `.env*` file. Set a key without echo: `read -rs DEPLOYER_PRIVATE_KEY && export DEPLOYER_PRIVATE_KEY`.
- The network is flaky (DNS poisoning on `rpc.testnet.chain.robinhood.com` and the explorer about half the time). Every `cast`, `forge`, `curl` call is retried up to 8 times by the scripts; for the manual commands below use the helper once per shell:

```bash
retry() { local i; for i in 1 2 3 4 5 6 7 8; do "$@" && return 0; sleep 3; done; return 1; }
```

- Use separate Foundry build dirs when another process is building: `export FOUNDRY_OUT="$TMPDIR/out-d" FOUNDRY_CACHE_PATH="$TMPDIR/cache-d"`.
- Deploy and verify from the same commit. Any edit to `contracts/**` or `foundry.toml` between deploy and verify makes `scripts/verify.sh` report `NO_LOCAL_MATCH` for those addresses on purpose.
- Do not touch ports 3000 and 3001 while another dev server owns them.

## Environment names

| Name | Used by | Secret | Notes |
|---|---|---|---|
| `DEPLOYER_PRIVATE_KEY` | `scripts/deploy-v2.sh` | yes, KEY | testnet-only key, needs testnet ETH on 46630 |
| `DEPLOY_NETWORK` | DeployV2 / SeedV2 | no | the script sets it from its first argument (`robinhood-testnet`); output goes to `deployments/robinhood-testnet-v2/addresses.json` |
| `ROBINHOOD_TESTNET_RPC_URL` | deploy-v2.sh, verify.sh (read only) | no | default `https://rpc.testnet.chain.robinhood.com` |
| `GUARDIAN_ADDRESS` | DeployV2 | no | public address, default deployer |
| `RELAYER_ADDRESS` | DeployV2 | no | REQUIRED on `robinhood-testnet` (`deploy-v2.sh` and the script refuse to start without it, and refuse the deployer's own address). Public address that gets `UPDATER_ROLE` on the six feeds; must be the wallet behind `RELAYER_PRIVATE_KEY` on Vercel |
| `FAUCET_ADDRESS` | DeployV2 | no | REQUIRED on `robinhood-testnet` (not `FAUCET_DISPENSER_ADDRESS`; that old name is still read as a fallback but do not use it), must differ from the deployer. Public address behind `FAUCET_PRIVATE_KEY` on Vercel; gets `DISPENSER_ROLE` on `FengFaucet` |
| `ENABLE_SHOCK` | DeployV2 | no | `1` grants `SHOCK_ROLE` to the relayer and enables shock on the five stock feeds |
| `FAUCET_ETH_FUND_WEI` | DeployV2 | no | default `4000000000000000` (0.004 ETH): 40 claims (`FAUCET_DAILY_CAP`) at 0.0001 ETH each, so the funding pays exactly one full day |
| `WRITE_ADDRESSES` | DeployV2, SeedV2, DeployLive, SeedLive | no | the scripts write `deployments/*/addresses.json` only when this is `true`. `deploy-v2.sh` sets it for every broadcast; a manual `forge script` (simulation or broadcast) leaves the file untouched unless you export it yourself |
| `LIVE_HARDFORK` | deploy-v2.sh | no | default `osaka`; passed as `--hardfork` to the Live scripts only (see step 3a) |
| `DRY_RPC_URL` | deploy-v2.sh dry | no | optional local anvil, exactly `http://127.0.0.1:<port>` or `http://localhost:<port>`; anything else (including the `127.0.0.1:1@host` form) is rejected |
| `INIT_PRICE_TSLA`, `INIT_PRICE_AMZN`, `INIT_PRICE_NFLX`, `INIT_PRICE_PLTR`, `INIT_PRICE_AMD` | DeployV2 | no | optional, 8-decimal integers |
| `DEPLOY_MAX_ATTEMPTS`, `REDEPLOY`, `RESEED`, `FORGE_EXTRA_ARGS`, `KEEP_DRY_OUTPUT`, `LIVE_*` | deploy-v2.sh | no | confirm flags in the script before use |
| `VERIFY_DRY_RUN`, `VERIFY_ONLY`, `VERIFY_MAX_ATTEMPTS`, `VERIFY_LOG`, `VERIFY_ROOT` | verify.sh | no | no key needed, no transaction sent |
| `NEXT_PUBLIC_PRIVY_APP_ID`, `NEXT_PUBLIC_NETWORK`, `NEXT_PUBLIC_CHAIN_ID`, `NEXT_PUBLIC_RPC_URL`, `NEXT_PUBLIC_EXPLORER_URL` | Vercel build | no (Privy app id is public) | `NEXT_PUBLIC_NETWORK=robinhood-testnet`, `NEXT_PUBLIC_CHAIN_ID=46630` |
| `CRON_SECRET` | Vercel runtime, ops routes | yes | protects `/api/ops/tick`; the external clock sends it. Use at least 32 random characters |
| `RELAYER_PRIVATE_KEY`, `FAUCET_PRIVATE_KEY`, `KEEPER_PRIVATE_KEY` | Vercel runtime, `src/ops` | yes, KEY | server wallets, never the deployer key |
| `OPS_RELAYER_ADDRESS`, `OPS_FAUCET_ADDRESS`, `OPS_KEEPER_ADDRESS`, `OPS_FAUCET_DEPLOYMENT`, `OPS_RELAYER_MODE`, `OPS_RPC_URL` and the other `OPS_*` | Vercel runtime | no | full list and defaults: `docs/ops/RUNBOOK.md` section 3 and `src/ops/config.ts`. `OPS_RPC_URL*` may carry a provider key: it never reaches a response (health and tick show fixed phrases, details only in the server log) |
| `OPS_FAUCET_MODE` | Vercel runtime | no | unset is right: it resolves to `contract` when the V2 addresses file has a `faucet` address, otherwise `v1`. Set `v1` or `contract` only to override |
| `OPS_MAX_PRICE_AGE_SEC` | Vercel runtime | no | default 21600: no heartbeat `refresh()` once the last market-validated price push is older than this; the feed is reported `price stale` |

Which steps need the user's key: step 3 (deploy and seed) only for `DEPLOYER_PRIVATE_KEY`; step 8 (Vercel env) needs the relayer, faucet and keeper wallet keys the user already holds. Everything else needs no key.

## 0. Preconditions

```bash
cd "/home/cn/Projects/Competition/Web3/Arbitrum/Feng."
forge build && forge test
pnpm lint && pnpm exec tsc --noEmit
git status --short
sha256sum -c docs/handoffs/v1-sources.sha256 | grep -v ': OK$' || true
```

Expected: build and tests green (CI does the same), no output from the checksum filter (V1 sources unchanged, so V1 stays verifiable). Commit the contract sources first so deploy and verify share one commit. Record the commit: `git rev-parse HEAD`.

Record the current production deployment before changing anything (needed for rollback in step 10):

```bash
retry vercel list --environment production --status READY 2>&1 | head -8
```

Write down the newest READY production deployment URL as `PREV_PROD_URL`. Confirm the project is the existing one: `.vercel/project.json` must exist (never run `vercel link` to a new project and never create or delete a Vercel or Railway project for this).

## 1. Rehearse on a local anvil (no key, no network)

```bash
scripts/deploy-v2.sh dry all
```

Confirm flags in the script (`scripts/deploy-v2.sh` header: `<robinhood-testnet|dry> [deploy|seed|all|live-deploy|live-seed|live]`). Dry mode spawns a throwaway anvil with the public default account (or uses `DRY_RPC_URL`, a local anvil only) and removes its outputs unless `KEEP_DRY_OUTPUT=1`; it writes `deployments/dry-local-v2/addresses.json` like a real run, because the script sets `WRITE_ADDRESSES=true`. The script prints the RPC host, never the URL.

## 2. Check the deployer is funded (read only)

```bash
retry cast balance "$DEPLOYER_ADDRESS" --rpc-url https://rpc.testnet.chain.robinhood.com --ether
```

`DEPLOYER_ADDRESS` is the public address of the deployer. Budget: the faucet funding (`FAUCET_ETH_FUND_WEI`, 0.004 ETH default, 40 claims at 0.0001 ETH) plus gas for about 25 contract creations and ten strategy creations (spec 3.2, up to 6.5M gas each). If low, stop and ask the user to top up.

## 3. Deploy and seed V2 (KEY: `DEPLOYER_PRIVATE_KEY`)

```bash
read -rs DEPLOYER_PRIVATE_KEY && export DEPLOYER_PRIVATE_KEY
export RELAYER_ADDRESS=0x...  FAUCET_ADDRESS=0x...
export GUARDIAN_ADDRESS=0x...  ENABLE_SHOCK=1
scripts/deploy-v2.sh robinhood-testnet deploy
scripts/deploy-v2.sh robinhood-testnet seed
```

(or `scripts/deploy-v2.sh robinhood-testnet all`). Confirm flags in the script before running: the documented interface is `scripts/deploy-v2.sh <robinhood-testnet|dry> [deploy|seed|all]`, with retry on transient TLS errors and `--resume` after a partial broadcast. Rules:

- If a run fails midway, rerun the same command with the same arguments; the script resumes. Never start from scratch after a partial broadcast, and never set `REDEPLOY=1` or `RESEED=1` unless a second deployment is intended.
- The script refuses to deploy over a live `deployments/robinhood-testnet-v2/addresses.json` and refuses to seed twice. If the RPC cannot answer the code check (unreachable, intercepted), the script aborts before any broadcast ("state unknown"); rerun when the endpoint answers. It never falls through to a broadcast on an unknown state.
- `RELAYER_ADDRESS` and `FAUCET_ADDRESS` are mandatory for the `deploy` and `all` steps on `robinhood-testnet`; both must differ from the deployer.
- When done: `unset DEPLOYER_PRIVATE_KEY`.

### 3a. Live universe (optional, KEY: `DEPLOYER_PRIVATE_KEY`)

```bash
scripts/deploy-v2.sh robinhood-testnet live-deploy
scripts/deploy-v2.sh robinhood-testnet live-seed
```

(or `live`, both). Live deploys a second desk and factory on the real faucet tokens and the Paxos USDG and needs the sandbox set from step 3. The Live scripts must simulate the real tokens' bytecode, so `deploy-v2.sh` adds `--hardfork osaka` (override with `LIVE_HARDFORK`) for `DeployLive` and `SeedLive` only; a wrong value fails before any work. Sizing comes from the deployer's actual real balances (USDG from the Paxos faucet first); the Live desk swap cap is 25 USDG.

Result file (public addresses only): `deployments/robinhood-testnet-v2/addresses.json` (schema 5.3: `schemaVersion 2`, `oracle`, `venue`, `vaultDeployer`, `faucet`, `guardian`, `vaults[10]`, `live`).

## 4. Sanity-check the V2 file and chain state (read only)

```bash
V2=deployments/robinhood-testnet-v2/addresses.json
jq -e '.schemaVersion == 2 and .chainId == 46630 and (.vaults | length) == 10' "$V2"
RPC=https://rpc.testnet.chain.robinhood.com
REG="$(jq -r .marketplaceRegistry "$V2")"
retry cast call "$REG" "strategyCount()(uint256)" --rpc-url "$RPC"
retry cast call "$(jq -r .usdg "$V2")" "decimals()(uint8)" --rpc-url "$RPC"
```

Expected: `true`, `10`, `6`. If the vault count or any call differs, do not continue to the switch.

## 5. Verify V2 on Blockscout (no key)

```bash
VERIFY_DRY_RUN=1 scripts/verify.sh robinhood-testnet-v2
scripts/verify.sh robinhood-testnet-v2 > "${TMPDIR:-/tmp}/verify-v2.log" 2>&1 &
tail -f "${TMPDIR:-/tmp}/verify-v2.log"
```

- The dry run only classifies and must show no `NO_LOCAL_MATCH` for any non-`live.*` address. If it does, the checked-out sources differ from the deployed ones: check out the deploy commit and retry.
- A full run takes about 10 to 25 minutes (about 36 addresses plus ten vaults and ten tokens). It is idempotent: rerun it until it exits 0. Raise `VERIFY_MAX_ATTEMPTS=12` if lines show `ERR_EXPLORER` or `FAILED`.
- Exit codes: 0 all verified, 1 a core contract unverified, 3 only vaults, tokens or auxiliary contracts unverified, 4 the registry listing could not be read, 2 usage or build failure.
- It rewrites the `robinhood-testnet-v2` section of `docs/handoffs/VERIFY-LOG.md` (other deployments' sections are kept). Single address: `VERIFY_ONLY=0xabc... scripts/verify.sh robinhood-testnet-v2`.
- Gate "verified" claims (UI badge, submission text) on the explorer flag: `curl -s "https://explorer.testnet.chain.robinhood.com/api/v2/smart-contracts/<addr>" | jq .is_verified`.
- Manual escape hatch for one address: `forge verify-contract <addr> <path:Name> --show-standard-json-input > std.json`, then upload at the explorer's Verify contract page (Solidity, Standard JSON input).

## 6. Archive V1 and switch `deployments/robinhood-testnet` to V2

Do this only after steps 3 to 5 passed and the go/no-go (G1) decision is yes. This is a file change, not a transaction; commit it afterwards.

```bash
mkdir -p deployments/archive
cp -R deployments/robinhood-testnet deployments/archive/robinhood-testnet-v1
diff -r deployments/robinhood-testnet deployments/archive/robinhood-testnet-v1 && echo archive-identical
cp deployments/robinhood-testnet-v2/addresses.json deployments/robinhood-testnet/addresses.json
jq -e '.schemaVersion == 2 and .chainId == 46630' deployments/robinhood-testnet/addresses.json
```

Keep `deployments/robinhood-testnet-v2/` until the release is confirmed, then it can be removed (the two files are identical copies). The frontend (`src/lib/addresses.ts`) and ops (`DEPLOYMENT_REGISTRY` in `src/ops/config.ts`) read `deployments/robinhood-testnet/addresses.json`; the scripts that take a network name (`scripts/fund.sh`, `scripts/refresh-feeds.sh`, `scripts/keeper.sh`, `scripts/gen-addresses-md.sh`) read the same folder. The archived V1 file can still be passed to tools that take a path or a name, for example `scripts/verify.sh archive/robinhood-testnet-v1` (needs the V1 sources, see the sha256 check in step 0).

Regenerate derived artifacts and re-check:

```bash
scripts/sync-abi.sh
scripts/gen-addresses-md.sh robinhood-testnet
pnpm lint && pnpm exec tsc --noEmit
```

Confirm the ops lane has switched `DEPLOYMENT_REGISTRY` to the V2 feed kind before relying on the relayer; do not edit `src/ops` from this runbook.

## 7. Local production build (skip if a dev server or another build is running)

```bash
ss -ltn | grep -E ':300[01]'
NEXT_PUBLIC_PRIVY_APP_ID=<real public app id> NEXT_PUBLIC_NETWORK=robinhood-testnet \
  NEXT_PUBLIC_CHAIN_ID=46630 pnpm build
```

Do not build while another process holds `.next`. Skip this step if the check above shows listeners and rely on the Vercel build.

## 8. Vercel environment (existing project only; KEY for the server wallets)

```bash
retry vercel env ls production
```

This lists names only. Required names: the five `NEXT_PUBLIC_*` in the table, `CRON_SECRET`, `RELAYER_PRIVATE_KEY`, `FAUCET_PRIVATE_KEY`, `KEEPER_PRIVATE_KEY`, and the `OPS_*` names from `src/ops/config.ts`. Add or change one only when the V2 addresses require it (the contract addresses themselves ship inside the deployment through `deployments/robinhood-testnet/addresses.json`, so no address variable is needed):

```bash
printf '%s' "$RELAYER_PRIVATE_KEY" | vercel env add RELAYER_PRIVATE_KEY production
```

The value comes from the user's shell variable and is never printed. Update `OPS_RELAYER_ADDRESS`, `OPS_FAUCET_ADDRESS`, `OPS_FAUCET_DEPLOYMENT` the same way if the wallets or the faucet deployment changed. The wallet behind `RELAYER_PRIVATE_KEY` must equal `RELAYER_ADDRESS` from step 3 and the one behind `FAUCET_PRIVATE_KEY` must equal `FAUCET_ADDRESS`, otherwise the feeds and the faucet revert on missing roles. Environment changes apply only to new deployments.

## 9. Redeploy production on the existing Vercel project

```bash
test -f .vercel/project.json && echo linked
retry vercel deploy --prod
```

Do not pass `--yes` unless `.vercel/project.json` exists (an unlinked folder with `--yes` would create a new project). `.vercelignore` excludes `contracts`, `scripts`, `docs`, `lib`, `dev`, `out`, `cache` and `.env*`; `deployments/` is shipped on purpose, so make sure `deployments/robinhood-testnet/addresses.json` is the V2 file before deploying.

Smoke test (replace `$PROD_URL`):

```bash
retry curl -sS -o /dev/null -w '%{http_code}\n' "$PROD_URL/"
retry curl -sS -o /dev/null -w '%{http_code}\n' "$PROD_URL/api/ops/health"
```

Expected 200 for `/`. `/api/ops/health` is public (200 or 503 with fixed-phrase alarms, `faucet.mode` should read `contract`); `/api/ops/tick` needs `Authorization: Bearer <CRON_SECRET>` (401 without). Open the app, connect a wallet on Robinhood Chain testnet and confirm ten V2 vaults are listed and the explorer links of verified contracts open `#code`.

## 10. Rollback

Frontend only, instant, no chain action. V2 contracts stay on chain (they are additive and V1 is untouched), so rolling the site back is safe.

```bash
retry vercel rollback "$PREV_PROD_URL"
vercel rollback status
```

If `vercel rollback` refuses (plan limits), promote the old deployment instead: `retry vercel promote "$PREV_PROD_URL"`, then `vercel promote status`. The same operations exist in the Vercel dashboard (Deployments, the previous production deployment, Promote to Production).

Then restore the repo state so the next deploy does not reintroduce V2:

```bash
cp deployments/archive/robinhood-testnet-v1/addresses.json deployments/robinhood-testnet/addresses.json
jq -e '.chainId == 46630 and (.schemaVersion // 1) == 1' deployments/robinhood-testnet/addresses.json
```

Notes:

- A promoted old deployment keeps the environment and the bundled `deployments/` file it was built with, so it serves V1 even though the Vercel env now holds V2 values. Check `/api/ops/health` of the rolled-back deployment: relayer and keeper wallets may need their old `OPS_*` values if V1 ops must run again.
- The relayer and faucet roles on V2 contracts are independent of the site; nothing on chain needs undoing.
- Redeploy forward later with step 9 once the cause is fixed.

## Checklist

1. Step 0 green and commit recorded, previous production deployment recorded.
2. Step 1 dry deploy passes.
3. Step 3 (KEY) finished, JSON has 10 vaults.
4. Step 5 `scripts/verify.sh robinhood-testnet-v2` exits 0 and `VERIFY-LOG.md` shows `yes` for every row of the section.
5. Step 6 archive diff identical, V2 file in place.
6. Step 9 production smoke test passes.
7. Rollback command and `PREV_PROD_URL` are at hand.
