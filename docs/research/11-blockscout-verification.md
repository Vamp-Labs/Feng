# 11. Blockscout verification on Robinhood Chain testnet (R4)

Run on 2026-10-03 (about 14:20 to 14:45 UTC) from the user's machine, repo `/home/cn/Projects/Competition/Web3/Arbitrum/Feng.`. Tools: Foundry `forge 1.8.3 (cae51ad, 2026-09-15)`, explorer backend `v10.2.6` (`GET /api/v2/config/backend-version`). No private key was used, no transaction was sent, no `.env*` file was read. Per the coordinator's approval, exactly two contracts were verified on the real explorer: the V1 `MarketplaceRegistry` and one factory-made V1 `StrategyVault` (AIGR). Nothing else was submitted.

## Summary

- **Verification works and takes one command per contract.** `forge verify-contract <addr> <path:Name> --chain 46630 --verifier blockscout --verifier-url https://explorer.testnet.chain.robinhood.com/api/ --constructor-args <hex> --watch`. Both dry-run targets now show `is_verified: true`, `is_fully_verified: true` (full match, not partial) on Blockscout.
- **The compiler flags come from `foundry.toml` already** (`solc 0.8.24`, `evm_version paris`, `optimizer_runs 200`, `via_ir false`). Passing them explicitly is harmless and is what the script below does, but derived from `forge config --json`, never hard-coded.
- **Constructor arguments are the only per-contract input, and they can be read for free from the creation transaction**: Blockscout returns `creation_bytecode` (also for factory-made contracts created by an internal transaction); the arguments are the part after the locally compiled creation bytecode. For the AIGR vault (736 bytes of arguments) I confirmed this byte for byte against an independent `cast abi-encode` built from the vault's own getters. The same trick also classifies every address to its source file, so no hand-written address-to-contract table is needed.
- **Factory-made siblings are NOT auto-verified.** After verifying one vault, a second vault and a token of the same factory stayed `is_verified: false` after about six minutes and repeated REST reads, with no `verified_twin_address_hash`. The public Blockscout bytecode database (`eth-bytecode-db`) does know the `StrategyVault` source after our verification and returns a `FULL` match for the sibling vault's creation code, so the explorer UI may auto-verify siblings on a page view, but I could not prove that without verifying a third contract (not allowed). **Do not rely on it. Verify every vault explicitly.**
- **What scales to 20 vaults**: the per-contract loop in the script (estimated 10 to 30 s per contract including retries, so about 10 to 25 minutes for 20 vaults plus 20 tokens plus the core contracts; only the registry run, 9.4 s, was timed), because arguments are derived automatically and per contract. Standard-JSON input is a confirmed-reachable fallback (the API accepted the request shape; I only saw "Already verified" because I did not verify anything else). Flattening is a poor fallback here (multi-file OpenZeppelin imports).
- **The "TLS interception" is really DNS poisoning and it is heavy for Foundry, light for curl.** About half of the DNS answers for both hosts are the ISP address `36.86.63.185`, which serves a certificate for `internetsehatku.com` (or an expired one). `cast` and `forge` failed roughly 50 percent of attempts; `curl` failed once in roughly 80 explorer and RPC calls (it mostly picks the Cloudflare IPv6 address). Every forge call needs a retry loop (8 attempts was enough every time), and the success check should use `curl` against `/api/v2/smart-contracts/<addr>`, not forge's own status.
- **Idempotency is cheap**: skip when `is_verified` is true (the script does), and Blockscout and forge both answer "already verified" if you resubmit.

## Findings

### F1. Exact flags (question 1)

Working command (registry, run 2026-10-03; first attempt failed on DNS, second passed, see F5):

```bash
forge verify-contract 0x9A4A62b955e28C8Ed83585412c658161A746DACa \
  contracts/MarketplaceRegistry.sol:MarketplaceRegistry \
  --chain 46630 \
  --verifier blockscout \
  --verifier-url https://explorer.testnet.chain.robinhood.com/api/ \
  --compiler-version 0.8.24 --evm-version paris --num-of-optimizations 200 \
  --constructor-args 0x00000000000000000000000047575c31c8146022fab38dff5ce883b5e55f6785 \
  --watch
```

Output on the passing attempt (trimmed): `Submitted contract for verification: Response: OK, GUID: 9a4a62b9...1105f`, then `Contract verification status: Response: OK, Details: Pass - Verified`, `Contract successfully verified` (`scratchpad r4/verify-registry.log`).

Facts behind each flag:

- **Verifier URL form**: `<explorer homepage URL>/api/` with the trailing `/api/`. Source: Blockscout docs, "Verifying against a specific instance": "Make sure to add /api/ to the end of the Blockscout homepage explorer URL". No API key needed for a per-instance URL ("any non-empty string works, or you can drop --etherscan-api-key entirely"). The docs' main example uses the paid PRO API `https://api.blockscout.com/v2/api?chain_id=<id>` with a key; **we do not need it**.
- **`--chain 46630` instead of `--rpc-url`**: the RPC is not needed for verification when the constructor arguments are given. Dropping `--rpc-url` removes the flakiest dependency. (`--guess-constructor-args` would need the RPC; not used.)
- **`--verifier blockscout`** is a documented value of `--verifier` in `forge verify-contract --help` (etherscan, sourcify, blockscout, oklink, custom).
- **Compiler settings**: `foundry.toml` has `solc_version = "0.8.24"`, `evm_version = "paris"`, `optimizer = true`, `optimizer_runs = 200`, `via_ir = false` (`foundry.toml:7-11`); `forge config --json` prints `{"solc":"0.8.24","evm_version":"paris","optimizer":true,"optimizer_runs":200,"via_ir":false,"bytecode_hash":"ipfs","cbor_metadata":true}`. The Foundry book states settings come from the usual config; I also ran the config-only form (no `--compiler-version`, `--evm-version`, `--num-of-optimizations`): forge started normally and reported the contract "already verified", so the flags are not mandatory, but explicit flags make the log self-documenting and fail loudly on drift.
- **Instance capability** (`GET /api/v2/smart-contracts/verification/config`): `solidity_compiler_versions` contains `v0.8.24+commit.e11b9ed9`; `solidity_evm_versions` contains `paris`; `verification_options` = `multi-part, vyper-multi-part, vyper-standard-input, flattened-code, standard-input, vyper-code` (no `sourcify` option on this instance); `is_rust_verifier_microservice_enabled: true`.
- **Explorer result** (`GET /api/v2/smart-contracts/0x9A4A...DACa`): `is_verified true, is_fully_verified true, is_partially_verified false, compiler_version v0.8.24+commit.e11b9ed9, evm_version paris, optimization_runs 200, language solidity, verified_at 2026-10-03T14:25:38Z`, 8 source files, `/api?module=contract&action=getsourcecode` returns the ABI and `ContractName`.
- **Minor**: `license_type` shows `none` even though the sources carry `SPDX-License-Identifier: MIT`. `forge verify-contract --license-type MIT` exists in the help ("Only used for Etherscan-style verifiers"); I did not test whether Blockscout honours it. Cosmetic.
- **Existing `scripts/deploy.sh:82-86`** calls `forge verify-contract "$ADDRESS" "contracts/$NAME.sol:$NAME" --rpc-url ... --verifier blockscout --verifier-url "$EXPLORER_API_URL" --watch` for factory, engine and registry **without constructor arguments, without retries and with a trailing `|| echo`**. It was never exercised against these three on this explorer. Blockscout's verifier documentation says it returns the on-chain constructor arguments itself, so omitting them may work, but I did not prove it (that would mean verifying a third and fourth contract). The script below always passes them.

### F2. Factory-made contracts, constructor arguments (question 2)

How the factory builds things:

- `StrategyFactory.createStrategy` does `new StrategyVault(name, symbol, usdg, address(priceOracle), constituentsMem, maxWeightBps, rebalanceInterval, depth_, maxPriceStaleness)` (`contracts/StrategyFactory.sol:76-88`); constructor signature `StrategyVault.sol:40-50`.
- The vault in turn does `token = new StrategyToken(name_, symbol_, address(this))` (`StrategyVault.sol:71`); signature `StrategyToken.sol:14`.
- Consequences: (a) each vault has different arguments (name, symbol, constituent array, maxWeightBps, interval, depth), (b) each token's arguments include its vault address, (c) the vault stores five values as `immutable` (`StrategyVault.sol:20-26`), which Solidity writes into the runtime bytecode, so sibling vaults do **not** have byte-identical runtime code, (d) the token is created by a nested `CREATE`, so there is no external transaction for it, only an internal one.

Real arguments, two independent ways (AIGR vault `0x9f6123c775B62a88b7403ca8CaF41B0Ea6B2438B`, token `0x795fdcf86910c263BD2aFFb96b12086995459E5C`, both created in tx `0x337a6bc2717605ce92e92dee2af8d4a3082f82331cb5334e2b185e3afd3e9d74` by factory `0xB0C8...1087`):

1. **From the explorer, no RPC**: `GET /api/v2/smart-contracts/<addr>` returns `creation_bytecode` (29,174 hex chars for the vault, 6,860 for the token, internal creation included). `forge inspect <Name> bytecode` gives the locally compiled creation bytecode. Result for the registry, factory, vault and token: the on-chain creation code starts with the local bytecode byte for byte, so **the current source equals what was deployed** (no source drift), and the remainder is exactly the ABI-encoded constructor arguments.
2. **From the chain with `cast abi-encode`** (the cross-check; the RPC getters are `name()`, `symbol()` on the token, `usdgToken()`, `priceOracle()`, `getConstituents()`, `maxWeightBps()`, `rebalanceInterval()`, `strategyDepth()`, `maxPriceStaleness()` on the vault):

```bash
cast abi-encode "constructor(string,string,address,address,(address,uint16,bool)[],uint16,uint256,uint8,uint256)" \
  "AI Growth" AIGR 0x6F0aa2cc939604b7e62935365521EA72C1908B70 0xD86Ef6e14701e28BBBDd4641306b001ECC857b3B \
  "[(0x3B05F23D529B0FbF5cb80397537B91e321Bcd764,3500,false),(0x52218d3562ffD89a9a863805D83D42f4d3c02FFa,3500,false),(0x7e80cb6344dF7A371fC6AC104d3fc922a4e4c4F1,3000,false)]" \
  4000 604800 1 86400
# token
cast abi-encode "constructor(string,string,address)" "AI Growth" AIGR 0x9f6123c775B62a88b7403ca8CaF41B0Ea6B2438B
```

Both outputs equal the suffix of the explorer's creation code exactly (vault: 736 bytes of arguments, token: 224 bytes). Same check for registry (`constructor(address)` with the deployer as admin, 32 bytes, confirmed with `hasRole(0x00, deployer) = true`) and factory (`constructor(address,address,address,uint256)` = registry, oracle `0xD86E...857b3B`, USDG mock, `86400`; suffix equal).

Gotchas found while doing this:

- `cast call` prints numbers with annotations in text mode (`86400 [8.64e4]`); strip them, or use `--json`.
- With `--json`, **a failed attempt prints a JSON error object to stdout**, so a naive `$(cast call ... --json)` inside a retry loop can capture an error blob. Capture only the output of a successful (exit code 0) attempt.
- `cast call --json` for a `uint256` returned the value as a string (`["604800"]`) and for `uint16` as a number (`[4000]`); `jq -r '.[0]'` handles both.

**Similar match (auto-verifying siblings)**:

- Blockscout docs (Smart contract verification microservice, "Verification Algorithm"): the verifier "Extracts all metadata hash fields from creationTxInput" and "Compares non-metadata sections of the onchain bytecode with the results of local compilation", so a same-source contract with a different metadata hash is accepted. Constructor arguments are returned by the verifier as "constructor arguments used during on chain creation".
- Explorer source, `v10.2.6`, `apps/explorer/lib/explorer/chain/fetcher/look_up_smart_contract_sources_on_demand.ex`: an on-demand fetcher asks Ethereum Bytecode DB for sources of an **unverified** contract and, on a `FULL` match (or `PARTIAL` if the contract is already partially verified), publishes the sources. It is triggered from `Address.update_address_result` (`apps/explorer/lib/explorer/chain/address.ex:1064`), i.e. when a single address is loaded (UI page view, websocket `eth_bytecode_db_lookup_started` events documented at https://docs.blockscout.com/devs/verification/websocket-notifications).
- Measured: the public `https://eth-bytecode-db.services.blockscout.com/api/v2/bytecodes/sources:search` (POST `{"bytecode": <creation_bytecode>, "bytecodeType": "CREATION_INPUT"}`) returns `MarketplaceRegistry FULL` for the registry, `StrategyVault FULL` for **both** the verified AIGR vault and the unverified second vault `0x53e3d8394eaba13a4dd6DAB1fC88a305f7eC7EaC` (different constructor arguments and a different creation length: 28,982 versus 29,174 chars), and `[]` (no match) for the unverified `StrategyToken`, `ChainlinkPriceOracle` and `StrategyFactory`. So the bytecode database ignores constructor arguments and immutables, and it holds exactly what we verified, nothing more.
- Measured on the explorer instance: the second vault `0x53e3...7EaC`, the seventh vault `0x8438...2A1A` and the AIGR token stayed `is_verified: false` (both `/api/v2/smart-contracts/<a>` and `/api/v2/addresses/<a>`, `verified_twin_address_hash: null`, and the Etherscan-style `getabi` returned "Contract source code not verified") at 14:39, 14:40, 14:41 and 14:44 UTC, after I loaded the REST address endpoints and the HTML page. The REST calls do not necessarily run the same path as a browser session, and I did not drive a browser (that could verify a sibling, outside the approval).
- Verdict: similar match is a **possible bonus, not a plan**. It also never applies to tokens whose source was not yet verified once. Always verify each address.

Fallbacks:

- **Standard-JSON input**: `forge verify-contract <addr> <path:Name> --show-standard-json-input > std.json` prints the exact compiler input (8 source files for the registry, 18,468 bytes, optimizer 200, `evmVersion paris`, `viaIR false`, remappings). Blockscout UI: Other, Verify contract, "Solidity (Standard JSON input)". API: `POST /api/v2/smart-contracts/<addr>/verification/via/standard-input` with multipart fields `compiler_version=v0.8.24+commit.e11b9ed9`, `contract_name`, `autodetect_constructor_args=true` or `constructor_args=<hex>`, `license_type`, and `files[0]=@std.json`. Tested on the already verified registry: HTTP answer `{"message":"Already verified"}`, which proves the endpoint is reachable and the request is accepted; a successful new verification through it was **not** exercised.
- **Flattened**: Blockscout's own docs say the flattened method "is recommended only for a single-file smart contract without any imports". Our contracts import OpenZeppelin v5 across several files and repeat `SPDX` lines when flattened; avoid.
- **Sourcify**: this instance does not list a `sourcify` verification option (F1), so Foundry's `--verifier sourcify` is not an alternative.

Which scales to 20 vaults: the per-address loop (script below). Cost estimate from this run: the registry took 9.4 s wall including one failed attempt (`time` output); I did not time the vault run separately. Each submission uploads about 8 to 18 KB of source and Blockscout recompiles remotely. 20 vaults plus 20 tokens plus about 15 core and mock contracts at roughly 10 to 30 s is about 10 to 25 minutes sequentially. Parallelism is not needed and would only add DNS failures.

A design option for V2 (contracts lane): if vaults were EIP-1167 clones of one implementation, one verification would cover all vaults and the argument problem disappears. That is a design decision outside R4; V1 and the current V2 sketch use `new StrategyVault(...)` with immutables.

### F3. Does it work through the interception, what wrapper is needed (question 3)

Measurements (2026-10-03, 14:2x to 14:4x UTC):

| Probe | Result |
|---|---|
| `getent ahosts rpc.testnet.chain.robinhood.com` x6 | 3 answers were `36.86.63.185` only (ISP), 3 were Cloudflare (104.26.4.165, 104.26.5.165, 172.67.71.221, plus IPv6) |
| `getent ahosts explorer.testnet.chain.robinhood.com` x6 | same split, 3 of 6 poisoned |
| `cast chain-id --rpc-url <rpc>` | 15/30 passed, then 10/20 passed |
| `cast call ... --rpc-url <explorer>/api/eth-rpc` | 6/20 passed (the explorer host is poisoned too) |
| `curl` POST `eth_chainId` to the RPC host | 20/20 passed |
| `curl` GET `/api/v2/stats` on the explorer | 30/30 passed; 12/12 connected to IPv6 `2606:4700:3030::ac43:be3c`, `ssl_verify_result 0` |
| `forge verify-contract` (registry) | attempt 1 failed (before submitting), attempt 2 passed with one `Warning: Failed to request verification status ... waiting 5 seconds before trying again (4 tries remaining)` inside the run |

Error texts seen: `invalid peer certificate: certificate not valid for name "...com"; certificate is only valid for DnsName("internetsehatku.com") or DnsName("www.internetsehatku.com")`, and `certificate expired: ... not valid after 1780567529` (the ISP block page). `curl` reported `SSL: no alternative certificate subject name matches target hostname` on the rare failure.

Interpretation (not proven at packet level): consistent with DNS poisoning that redirects `A` lookups to the ISP block host; clients that prefer the AAAA record (curl here) mostly escape it, `hyper/reqwest` inside forge and cast do not. Each new attempt re-resolves, so a plain retry works.

Where forge fails: forge's pre-check `getabi` request (hard error, aborts the run, observed), the submission POST, and the status polling (forge retries this one itself: `--retries 5 --delay 5` defaults). A transient failure after the POST can leave the contract verified while forge returned an error; the script therefore re-checks the explorer after every attempt and only counts success if `is_verified` is true.

Required wrapper (implemented in the script): retry the whole `forge verify-contract` up to 8 times (the repo's standing budget; 8 was enough every time here), sleep 3 s between, add `--skip-is-verified-check` (removes the flaky `getabi` pre-check, our own REST check replaces it), and judge success only by `curl .../api/v2/smart-contracts/<addr>` returning `is_verified: true`. Keep RPC use out of the verification path: the arguments come from the explorer, and the few remaining chain reads (vault list) use `curl` JSON-RPC, which was 20/20.

A possible environment-level fix (not done, needs root, out of scope): pin both hostnames to the Cloudflare address in `/etc/hosts` or use a DoH-capable resolver. For `curl` the documented `--resolve` form with the DoH-resolved IP also works.

### F4. Dry-run record (question 4)

State before: all 36 addresses of the V1 deployment unverified (registry `is_verified false`, `creation_status success`, backend `v10.2.6`).

Contracts handled (every address derived in V1 by the script: 12 mocks incl. USDG, 5 stock mocks and 6 feeds; factory; engine; registry; `ChainlinkPriceOracle` `0xD86E...857b3B` which is **not in `addresses.json`** and was found through `StrategyFactory.priceOracle()`; 10 vaults; 10 tokens):

1. **MarketplaceRegistry `0x9A4A62b955e28C8Ed83585412c658161A746DACa`**: command in F1. Verified 14:25:38Z. Explorer: `is_verified true`, `is_fully_verified true`, `name MarketplaceRegistry`, `optimization_runs 200`, `evm_version paris`, `constructor_args 0x0000...7575c31c...6785`, ABI 20 entries, 8 source files. URL `https://explorer.testnet.chain.robinhood.com/address/0x9A4A62b955e28C8Ed83585412c658161A746DACa#code`.
2. **StrategyVault AIGR `0x9f6123c775B62a88b7403ca8CaF41B0Ea6B2438B`** (factory-made), run through `verify.sh` with `VERIFY_ONLY=<addr>`; the script derived the arguments from the creation code and submitted (equivalent single command):

```bash
forge verify-contract 0x9f6123c775B62a88b7403ca8CaF41B0Ea6B2438B contracts/StrategyVault.sol:StrategyVault \
  --chain 46630 --verifier blockscout --verifier-url https://explorer.testnet.chain.robinhood.com/api/ \
  --compiler-version 0.8.24 --evm-version paris --num-of-optimizations 200 --skip-is-verified-check \
  --constructor-args <736-byte hex, see F2> --watch
```

   Script line printed: `0x9f61...B243B  contracts/StrategyVault.sol:StrategyVault  OK  https://explorer.testnet.chain.robinhood.com/address/0x9f61...B243B#code`, `verified=1 skipped=0 failed=0`. Verified 14:38:36Z. Explorer: `is_verified true`, `is_fully_verified true`, `name StrategyVault`, `compiler_version v0.8.24+commit.e11b9ed9`, `evm_version paris`, `optimization_runs 200`, ABI 30 entries. Cross-check via `cast abi-encode` equal (F2).
3. **Resubmissions** (idempotency proof): forge without `--skip-is-verified-check` prints `... is already verified. Skipping verification.`; with the flag Blockscout answers `Contract source code already verified`; the standard-input API answers `{"message":"Already verified"}`; a second run of `verify.sh` on the vault prints `ALREADY_VERIFIED(StrategyVault)`.

State after (check done at 14:41 to 14:44 UTC): registry and AIGR vault verified (full match); the other 34 V1 addresses (including nine sibling vaults and ten tokens) `is_verified false`; global counters `/api/v2/smart-contracts/counters` unaffected. `VERIFY_DRY_RUN=1 bash verify.sh` classified all 34 remaining addresses to a source file with correct argument sizes (MockUSDG 32 B, MockStockToken 256 B, MockV3Aggregator 64 B, factory 128 B, engine 32 B, oracle 32 B, vaults 640 to 928 B depending on constituent count and name length, tokens 224 B), and none reported source drift.

### F5. Things that did not work or are untested

- Test of the final script's **live submit path after the last edits** was not possible (the only two allowed contracts were already verified). The live path ran with a slightly earlier revision (hard-coded `0.8.24/paris/200` flags, forge output to a fixed temp file). The final revision differs only in deriving the flags from `forge config --json`, redirecting stdin from `/dev/null` and using `mktemp`; it passed `bash -n`, a full dry run and the idempotent skip. The deploy lane must run it for real on V1 first (as E7-T2 already says).
- `--license-type`, constructor-less verification, and a successful standard-JSON verification were not tested (would need verifying more contracts).
- Similar-match through a browser page view was not tested (F2).

## Recommendations

1. **Use the script below as `scripts/verify.sh`** (the deploy lane writes the file; per the plan `scripts/verify.sh` is in lane A, E7-T2). It verifies everything in `addresses.json` plus the factory oracle plus all registry vaults and tokens, is idempotent, retries, and never needs a private key or the RPC through forge.
2. **Always pass `--constructor-args`, derived from the explorer's creation code**, not typed by hand. Keep `cast abi-encode` as an independent audit when a log line looks odd.
3. **Never judge success from forge's exit code or output.** Judge by `GET /api/v2/smart-contracts/<addr>` `is_verified`.
4. **Do not rely on similar match**; treat any auto-verified sibling as a bonus. Log it (`is_verified_via_eth_bytecode_db` field) if it ever happens.
5. **Run it now on V1** for the remaining 34 addresses (about 10 to 25 minutes), after the user or the deploy lane confirms; then V2 is a rerun with another JSON path. Update `scripts/deploy.sh:73-88` to call the same script (it currently omits arguments and retries).
6. **Keep the standard-JSON file as the manual escape hatch**: `forge verify-contract ... --show-standard-json-input`, upload at the explorer's "Verify contract" page.
7. **Do not change compiler settings between deploy and verify.** Any edit to a `contracts/**` file or to `foundry.toml` after a deploy makes the local creation code differ, and the script will report `EXTERNAL_OR_SOURCE_DRIFT` for those addresses (deliberately) instead of submitting a doomed request. For V2 verify from the same commit that deployed.
8. **Libraries and via_ir**: the script handles `via_ir` from config; contracts that link libraries are not handled (V1 has none). Tell the contracts lane to avoid external libraries or extend the script with `--libraries`.
9. **Log**: the script appends to `docs/handoffs/VERIFY-LOG.tsv` (address, contract, result, explorer link). The plan names `VERIFY-LOG.md`; either generate a Markdown table from the TSV or change the variable `VERIFY_LOG`.

### Ready-to-use script (tested as noted in F5)

```bash
#!/usr/bin/env bash
# scripts/verify.sh [deployments/<name>/addresses.json]
# env: VERIFY_DRY_RUN=1  VERIFY_ONLY=0xabc,0xdef  VERIFY_MAX_ATTEMPTS=8  VERIFY_LOG=path  ROBINHOOD_TESTNET_RPC_URL=...
# needs: forge, cast, jq, curl. No private key. Idempotent: verified addresses are skipped.
set -uo pipefail
ROOT="${VERIFY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; cd "$ROOT"
DEP="${1:-deployments/robinhood-testnet/addresses.json}"
ATT="${VERIFY_MAX_ATTEMPTS:-8}"
RPC="${ROBINHOOD_TESTNET_RPC_URL:-$(jq -r .rpcUrl "$DEP")}"
EXP="$(jq -r .explorerUrl "$DEP")"; CHAIN="$(jq -r .chainId "$DEP")"
LOG="${VERIFY_LOG:-docs/handoffs/VERIFY-LOG.tsv}"; mkdir -p "$(dirname "$LOG")"

retry_out() {                       # prints stdout of the first successful attempt only
  local i=1 out
  while :; do
    if out="$("$@" 2>/dev/null)" && [[ -n "$out" ]]; then printf '%s' "$out"; return 0; fi
    (( i >= ATT )) && return 1
    i=$((i+1)); sleep $(( i < 6 ? i : 6 ))
  done
}
explorer() { retry_out curl -sS --fail -m 25 "$EXP/api/v2/$1"; }
rpc_raw() { curl -sS --fail -m 25 -X POST -H 'content-type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$1\",\"data\":\"$2\"},\"latest\"]}" "$RPC" | jq -er .result; }
view() {                            # view <to> "<fn>(<args>)(<ret>)" -> decoded values; curl, not cast, talks to the chain
  local to="$1" sig="$2" data raw; data="$(cast calldata "${sig%%)(*})")" || return 1
  raw="$(retry_out rpc_raw "$to" "$data")" || return 1
  cast abi-decode "$sig" "$raw"
}

CFG="$(forge config --json 2>/dev/null)"
SOLC="$(jq -r .solc <<<"$CFG")"; EVM="$(jq -r .evm_version <<<"$CFG")"
RUNS="$(jq -r .optimizer_runs <<<"$CFG")"; VIA_IR="$(jq -r .via_ir <<<"$CFG")"

build_map() {                       # "<creation bytecode hex> <path:Name>" per deployable contract in contracts/
  forge build >/dev/null 2>&1 || { echo "forge build failed" >&2; exit 1; }
  for f in out/*/*.json; do
    local code id
    code="$(jq -r '.bytecode.object // empty' "$f")"; [[ ${#code} -gt 10 ]] || continue
    id="$(jq -r '.metadata.settings.compilationTarget // {} | to_entries[0] | "\(.key):\(.value)"' "$f")"
    [[ "$id" == contracts/* && "$id" != contracts/test/* && "$id" != contracts/interfaces/* ]] || continue
    printf '%s %s\n' "$code" "$id"
  done
}
MAP="$(build_map)"

addrs() {                           # every address in the JSON, the factory oracle, every registry vault and its token
  jq -r '.. | strings | select(test("^0x[0-9a-fA-F]{40}$"))' "$DEP"
  local reg fac v; reg="$(jq -r '.marketplaceRegistry' "$DEP")"; fac="$(jq -r '.strategyFactory' "$DEP")"
  view "$fac" "priceOracle()(address)"
  for v in $(view "$reg" "getAllStrategies()(address[])" | tr -d '[] ' | tr ',' ' '); do
    echo "$v"; view "$v" "token()(address)"
  done
}
ALL="$(addrs | awk '!s[tolower($0)]++')"

OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT
ok=0; skip=0; fail=0
while read -r a; do
  [[ -n "$a" ]] || continue
  [[ -n "${VERIFY_ONLY:-}" && ",${VERIFY_ONLY,,}," != *",${a,,},"* ]] && continue
  sc="$(explorer "smart-contracts/$a")" || { echo -e "$a\t?\tERR_EXPLORER" | tee -a "$LOG"; fail=$((fail+1)); continue; }
  if [[ "$(jq -r '.is_verified // false' <<<"$sc")" == "true" ]]; then
    echo -e "$a\t-\tALREADY_VERIFIED($(jq -r '.name' <<<"$sc"))" | tee -a "$LOG"; skip=$((skip+1)); continue
  fi
  creation="$(jq -r '.creation_bytecode // empty' <<<"$sc")"
  if [[ -z "$creation" ]]; then echo -e "$a\t?\tNO_CREATION_CODE" | tee -a "$LOG"; skip=$((skip+1)); continue; fi
  id=""; args=""
  while read -r code name; do
    if [[ "$creation" == "$code"* ]]; then id="$name"; args="0x${creation:${#code}}"; break; fi
  done <<<"$MAP"
  if [[ -z "$id" ]]; then echo -e "$a\t?\tEXTERNAL_OR_SOURCE_DRIFT" | tee -a "$LOG"; skip=$((skip+1)); continue; fi
  [[ "$args" == "0x" ]] && args=""
  cmd=(forge verify-contract "$a" "$id" --chain "$CHAIN" --verifier blockscout --verifier-url "$EXP/api/"
       --compiler-version "$SOLC" --evm-version "$EVM" --num-of-optimizations "$RUNS" --skip-is-verified-check --watch)
  [[ "$VIA_IR" == "true" ]] && cmd+=(--via-ir)
  [[ -n "$args" ]] && cmd+=(--constructor-args "$args")
  if [[ "${VERIFY_DRY_RUN:-0}" == "1" ]]; then echo -e "$a\t$id\tDRY_RUN args=$(( ${#args} > 2 ? (${#args}-2)/2 : 0 ))B"; continue; fi
  n=1; res=FAIL
  while (( n <= ATT )); do
    "${cmd[@]}" </dev/null >"$OUT" 2>&1
    sc="$(explorer "smart-contracts/$a")" && [[ "$(jq -r '.is_verified // false' <<<"$sc")" == "true" ]] && { res=OK; break; }
    n=$((n+1)); sleep 3
  done
  echo -e "$a\t$id\t$res\t$EXP/address/$a#code" | tee -a "$LOG"
  [[ "$res" == OK ]] && ok=$((ok+1)) || fail=$((fail+1))
done <<<"$ALL"
echo "verified=$ok skipped=$skip failed=$fail"
(( fail == 0 ))
```

Design notes: the address-to-contract mapping is by creation-code prefix, so externals (the `live` real USDG and stock tokens, which are proxies we did not deploy) fall into `EXTERNAL_OR_SOURCE_DRIFT` and are skipped without a request; V2 `schemaVersion 2` files work unchanged because the JSON is scanned recursively (`oracle`, `venue`, `faucet`, `guardian` and the `vaults[]` array are picked up, and registry vaults are read from chain as well). It does not need the vault list in JSON; the registry is the source of truth. The exit code is non-zero when anything failed, so CI can gate on it.

## Implications per role

- **GP/deploy (E7-T2, T4)**: write `scripts/verify.sh` from the script above; run `VERIFY_DRY_RUN=1` first, then for real on V1 (34 addresses left), then on V2 and Live. Expect 10 to 25 minutes per full run on this network, and expect the `forge` log lines `certificate not valid for name` (benign, retried). Commit `docs/handoffs/VERIFY-LOG.md` generated from the TSV. Replace the unretried verify block in `scripts/deploy.sh:73-88` by a call to this script.
- **GP/contracts (E3, E4)**: keep deploy and verify on the same commit; do not leave `contracts/**` edits between deploy and verify; avoid external libraries; if V2 adds a vault template, clones (EIP-1167) would make verification of N vaults one step, but the current `new StrategyVault(...)` with immutables is fine. Keep the oracle address in `addresses.json` (V1 omitted it; the V2 schema has `oracle`).
- **Ops (E2)**: nothing depends on verification. The keeper, relayer and faucet scripts hit the same poisoned hosts from this laptop, so apply the same rule there: retry the whole call and judge by the result (cast fails about half of attempts here). A hosted worker will not see this.
- **Frontend (E6, E9)**: explorer deep links to `#code` are valid for contracts that report `is_verified: true`; for others the link shows only bytecode. Gate any "Verified" badge on `GET <explorer>/api/v2/smart-contracts/<addr>` `is_verified`, not on an assumption. The registry and AIGR vault links work now: `https://explorer.testnet.chain.robinhood.com/address/<addr>#code`.
- **Submission (E11)**: the contract-address block can legitimately say "verified on Blockscout" only for addresses that returned `is_verified: true` at submission time; today that is two of 36 V1 addresses. Re-run the script right before the form is filled.
- **Tests/CI (E8)**: a cheap CI check is the dry-run mode (`VERIFY_DRY_RUN=1`): it fails on source drift without sending anything. It needs only the RPC and explorer reads.
- **User**: nothing needed for verification (no key, no CAPTCHA). Optionally pin the two hostnames in `/etc/hosts` to the Cloudflare address to halve all Foundry failures; this needs root and was not done.

## Assumptions and open questions

Assumptions:

- The tool version (`forge 1.8.3`) and explorer (`v10.2.6`) stay the same until the next deploy; the Blockscout flag set above is the one verified against them.
- The ISP behaviour (about half of DNS answers poisoned) is time-varying; the retry count of 8 is enough at 50 percent per attempt (0.4 percent chance of eight consecutive failures per call) but the script makes many calls, so for a long run raise `VERIFY_MAX_ATTEMPTS` to 12 if lines show `ERR_EXPLORER` or a `FAIL`.
- The V2 contracts are compiled with the same `foundry.toml` settings; if `via_ir` or the runs change, the script follows the config.
- The explorer API is public and unauthenticated for this use; Blockscout rate limits for the instance's `/api/` verification endpoints are not documented to us and were not hit.

Open questions:

1. Does the explorer UI auto-verify sibling vaults and tokens on a page view via the Ethereum Bytecode DB? Code says it can for `FULL` matches; observation through REST says not within six minutes. (Test: open a sibling vault's page in a browser and wait; if it flips to verified, record it in the log; this publishes that sibling's source, so only with the user's go-ahead.)
2. Does Blockscout verification succeed when `--constructor-args` is omitted (the existing `deploy.sh` form)? The verifier is documented to return the on-chain arguments, but it is untested here.
3. Does `--license-type MIT` change the `license_type: none` shown on the explorer?
4. Is a successful standard-JSON verification through the REST endpoint (`/verification/via/standard-input`) working end to end? Only the "already verified" answer was observed.
5. Is the TLS problem DNS-only? A `--resolve` run of `forge` is impossible (no flag); a hosts-file pin would settle it.

## Sources

Primary sources fetched 2026-10-03 unless noted.

- Blockscout docs, "Verify smart contracts with Foundry Forge": https://docs.blockscout.com/devs/verification/foundry-verification (per-instance form `--verifier-url <explorer>/api/`, `--verifier blockscout`, API key not needed).
- Blockscout docs, "Smart contract verification microservice" (verification algorithm, constructor arguments): https://docs.blockscout.com/setup/microservices/smart-contract-verification
- Blockscout docs, "Verify contracts using the Blockscout UI" (flattened recommended for single file only, standard JSON): https://docs.blockscout.com/devs/verification/blockscout-ui
- Blockscout docs, websocket events incl. `eth_bytecode_db_lookup_started`, `smart_contract_was_verified`: https://docs.blockscout.com/devs/verification/websocket-notifications
- Blockscout docs, Smart Contract Verification API (constructor argument fields): https://docs.blockscout.com/devs/verification/blockscout-smart-contract-verification-api
- Blockscout source `v10.2.6`: https://raw.githubusercontent.com/blockscout/blockscout/v10.2.6/apps/explorer/lib/explorer/chain/fetcher/look_up_smart_contract_sources_on_demand.ex and `.../apps/explorer/lib/explorer/chain/address.ex` (line 1064 `LookUpSmartContractSourcesOnDemand.trigger_fetch`).
- Foundry reference, `forge verify-contract`: https://www.getfoundry.sh/reference/forge/verify-contract (flags `--chain`, `--constructor-args`, `--guess-constructor-args`, `--skip-is-verified-check`, `--show-standard-json-input`, `--retries`, `--delay`, `--license-type`, `--verifier`).
- Explorer REST (instance): `GET https://explorer.testnet.chain.robinhood.com/api/v2/smart-contracts/<addr>`, `/api/v2/addresses/<addr>`, `/api/v2/smart-contracts/verification/config`, `/api/v2/config/backend-version` (`v10.2.6`), `/api/v2/smart-contracts/counters`, `POST /api/v2/smart-contracts/<addr>/verification/via/standard-input`.
- Public bytecode database: `POST https://eth-bytecode-db.services.blockscout.com/api/v2/bytecodes/sources:search`.
- Repo evidence: `foundry.toml:7-11`, `contracts/StrategyFactory.sol:32,76-89`, `contracts/StrategyVault.sol:20-26,40-50,71`, `contracts/StrategyToken.sol:14`, `contracts/MarketplaceRegistry.sol:25`, `scripts/deploy.sh:73-88`, `deployments/robinhood-testnet/addresses.json`, `docs/brainstorm/2026-10-03-feng-v2-plan.md` sections 0, E1, E7-T2, 7 R4.
- Commands whose output is cited: `forge verify-contract` (registry, vault), `forge config --json`, `forge inspect <Name> bytecode`, `forge verify-contract --show-standard-json-input`, `cast abi-encode`, `cast call`, `getent ahosts`, `curl` probes listed in F3. Working files: `/tmp/claude-1000/-home-cn-Projects-Competition-Web3-Arbitrum-Feng-/5c2bd609-53ec-44f7-8841-4c8e359dad8c/scratchpad/r4/` (`verify.sh`, `verify-registry.log`, `run_vault.log`, `dry2.log`, `std.json`).

### Recommendation

1. Verify every address explicitly with the script above (`forge verify-contract --verifier blockscout --verifier-url <explorer>/api/ --chain 46630`, constructor arguments taken from the explorer's `creation_bytecode` minus the local `forge inspect` bytecode, retry 8 times, success judged by `is_verified` on the REST API).
2. Do V1 now (34 addresses left) as the rehearsal, V2 and Live later with the same script and the same commit that deployed.
3. Treat similar match as a bonus only; keep standard-JSON as the manual fallback; avoid flattened.
4. Replace the unretried, argument-less verify block in `scripts/deploy.sh` with a call to the script.
5. Gate every "Verified" claim in the UI and the submission on the REST `is_verified` flag.

### Still unknown

1. Whether a browser page view makes the explorer auto-verify sibling vaults and tokens from the bytecode database (the database already holds `StrategyVault` and returns `FULL` for siblings; the explorer had not applied it after about six minutes of REST reads).
2. Whether verification works with no `--constructor-args` (the form in `scripts/deploy.sh`).
3. Whether a standard-JSON verification through `/api/v2/smart-contracts/<addr>/verification/via/standard-input` succeeds end to end (only the "Already verified" reply was seen).
4. Whether `--license-type` is honoured by Blockscout (explorer shows `license_type: none`).
5. Whether the poisoning is DNS-only (hosts-file pin untested) and whether it will be as frequent on the demo machine or from the judges' networks (judges are expected to be unaffected).
6. The live-submit path of the final script revision (only dry run and idempotent skip were run after the last edit; the previous revision submitted the vault successfully).
