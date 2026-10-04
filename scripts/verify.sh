#!/usr/bin/env bash
set -uo pipefail

TARGET="${1:-}"
ATT="${VERIFY_MAX_ATTEMPTS:-8}"
ROOT_DIR="${VERIFY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

usage() {
  echo "Usage: scripts/verify.sh <deployment-dir-name | path/to/addresses.json>" >&2
  echo "  example: scripts/verify.sh robinhood-testnet" >&2
  echo "  env: VERIFY_DRY_RUN=1  VERIFY_ONLY=0xabc,0xdef  VERIFY_MAX_ATTEMPTS=8  VERIFY_LOG=path  VERIFY_ROOT=dir" >&2
  echo "       ROBINHOOD_TESTNET_RPC_URL (optional, read-only eth_call)  FOUNDRY_OUT / FOUNDRY_CACHE_PATH (separate build dirs)" >&2
  echo "  exit: 0 all verified, 1 a core contract is unverified, 3 only vaults/tokens/aux unverified, 4 registry listing failed, 2 usage" >&2
}

if [[ -z "$TARGET" ]]; then
  usage
  exit 2
fi

for tool in forge cast jq curl awk; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required but not installed." >&2
    exit 2
  fi
done

cd "$ROOT_DIR"

if [[ -f "$TARGET" ]]; then
  DEP="$TARGET"
  DNAME="$(basename "$(dirname "$TARGET")")"
elif [[ -f "deployments/$TARGET/addresses.json" ]]; then
  DEP="deployments/$TARGET/addresses.json"
  DNAME="$TARGET"
else
  echo "deployments/$TARGET/addresses.json not found." >&2
  usage
  exit 2
fi

RPC="${ROBINHOOD_TESTNET_RPC_URL:-$(jq -r '.rpcUrl // empty' "$DEP")}"
EXP="$(jq -r '.explorerUrl // empty' "$DEP")"
CHAIN="$(jq -r '.chainId // empty' "$DEP")"
EXP="${EXP%/}"
if [[ -z "$EXP" || -z "$CHAIN" ]]; then
  echo "$DEP has no explorerUrl or chainId; nothing to verify against." >&2
  exit 2
fi

DRY="${VERIFY_DRY_RUN:-0}"
ONLY="${VERIFY_ONLY:-}"
LOG="${VERIFY_LOG:-}"
WRITE_LOG=0
if [[ -n "$LOG" ]]; then
  WRITE_LOG=1
elif [[ "$DRY" != "1" && -z "$ONLY" ]]; then
  LOG="docs/handoffs/VERIFY-LOG.md"
  WRITE_LOG=1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

retry_out() {
  local i=1 out rc
  while :; do
    out="$("$@" 2>/dev/null)"
    rc=$?
    if (( rc == 0 )) && [[ -n "$out" ]]; then
      printf '%s' "$out"
      return 0
    fi
    if (( rc == 3 )); then
      return 3
    fi
    if (( i >= ATT )); then
      return 1
    fi
    i=$((i + 1))
    sleep $(( i < 6 ? i : 6 ))
  done
}

HTTP_CODE=""
HTTP_BODY=""
explorer_get() {
  local i=1 out code body
  while :; do
    if out="$(curl -sS -m 25 -w '\n%{http_code}' "$EXP/api/v2/$1" 2>/dev/null)"; then
      code="${out##*$'\n'}"
      body="${out%$'\n'*}"
      if [[ "$code" == "404" ]] || { [[ "$code" == "200" ]] && jq -e . >/dev/null 2>&1 <<<"$body"; }; then
        HTTP_CODE="$code"
        HTTP_BODY="$body"
        return 0
      fi
    fi
    if (( i >= ATT )); then
      return 1
    fi
    i=$((i + 1))
    sleep $(( i < 6 ? i : 6 ))
  done
}

rpc_raw() {
  local resp
  resp="$(curl -sS --fail -m 25 -X POST -H 'content-type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$1\",\"data\":\"$2\"},\"latest\"]}" "$RPC")" || return 1
  if jq -e '.error' >/dev/null 2>&1 <<<"$resp"; then
    return 3
  fi
  jq -er '.result' <<<"$resp" || return 1
}

view() {
  local to="$1" sig="$2" data raw
  data="$(cast calldata "${sig%%)(*})")" || return 1
  raw="$(retry_out rpc_raw "$to" "$data")" || return $?
  [[ "$raw" != "0x" ]] || return 3
  cast abi-decode "$sig" "$raw"
}

CFG="$(forge config --json 2>/dev/null)"
if [[ -z "$CFG" ]]; then
  echo "forge config failed." >&2
  exit 2
fi
SOLC="$(jq -r '.solc' <<<"$CFG")"
EVM="$(jq -r '.evm_version' <<<"$CFG")"
RUNS="$(jq -r '.optimizer_runs' <<<"$CFG")"
VIA_IR="$(jq -r '.via_ir' <<<"$CFG")"
OUTDIR="$(jq -r '.out' <<<"$CFG")"

echo "Deployment: $DNAME (chain $CHAIN) explorer $EXP"
echo "Building sources (solc $SOLC, evm $EVM, runs $RUNS, via_ir $VIA_IR)..."
if ! forge build >"$TMP/build.log" 2>&1; then
  tail -n 20 "$TMP/build.log" >&2
  echo "forge build failed; verification needs the same sources that were deployed." >&2
  exit 2
fi

find "$OUTDIR" -name '*.json' ! -name '*.dbg.json' -path '*.sol/*' -print0 \
  | xargs -0 jq -r '
      select((.bytecode.object // "") | length > 10)
      | ((.metadata.settings.compilationTarget // {}) | to_entries[0] | select(. != null) | "\(.key):\(.value)") as $id
      | select(($id | startswith("contracts/")) and (($id | test("/test/|/interfaces/")) | not))
      | "\(.bytecode.object | ascii_downcase) \($id)"' \
  | sort -u -k2 >"$TMP/map.txt"

CODES=()
IDS=()
while read -r code id; do
  [[ -n "$id" ]] || continue
  CODES+=("$code")
  IDS+=("$id")
done <"$TMP/map.txt"

if (( ${#IDS[@]} == 0 )); then
  echo "No deployable contracts found in $OUTDIR." >&2
  exit 2
fi
echo "Local creation bytecode for ${#IDS[@]} contracts."

LISTING_ERR=0

collect() {
  jq -r 'paths(type == "string") as $p
         | getpath($p) as $v
         | select($v | test("^0x[0-9a-fA-F]{40}$"))
         | "\($v)\t\($p | map(tostring) | join("."))"' "$DEP"

  local reg fac list v out i=0 rc
  reg="$(jq -r '.marketplaceRegistry // empty' "$DEP")"
  fac="$(jq -r '.strategyFactory // empty' "$DEP")"
  if [[ -n "$fac" ]]; then
    for fn in priceOracle venue; do
      out="$(view "$fac" "$fn()(address)")"
      rc=$?
      if (( rc == 0 )); then
        printf '%s\tfactory.%s\n' "$out" "$fn"
      elif (( rc != 3 )); then
        echo "WARN could not read factory $fn" >&2
        touch "$TMP/listing-err"
      fi
    done
  fi
  if [[ -n "$reg" ]]; then
    list="$(view "$reg" "getAllStrategies()(address[])")"
    rc=$?
    if (( rc != 0 )); then
      echo "WARN could not read registry vault list" >&2
      touch "$TMP/listing-err"
      return
    fi
    for v in $(tr -d '[] ' <<<"$list" | tr ',' ' '); do
      printf '%s\tregistry.vault.%s\n' "$v" "$i"
      out="$(view "$v" "token()(address)")"
      rc=$?
      if (( rc == 0 )); then
        printf '%s\tregistry.token.%s\n' "$out" "$i"
      else
        echo "WARN could not read token of vault $v" >&2
        touch "$TMP/listing-err"
      fi
      i=$((i + 1))
    done
  fi
}

collect | awk -F'\t' 'tolower($1) != "0x0000000000000000000000000000000000000000" && !seen[tolower($1)]++' >"$TMP/addrs.tsv"
[[ -f "$TMP/listing-err" ]] && LISTING_ERR=1
echo "Addresses to check: $(wc -l <"$TMP/addrs.tsv")"

is_core() {
  case "$1" in
    vaults.*|registry.vault.*|registry.token.*|live.vaults.*) return 1 ;;
    *) return 0 ;;
  esac
}

ok=0
skip=0
fail=0
dry=0
core_bad=0
other_bad=0
ROWS="$TMP/rows.md"
: >"$ROWS"

while IFS=$'\t' read -r a role; do
  [[ -n "$a" ]] || continue
  if [[ -n "$ONLY" && ",${ONLY,,}," != *",${a,,},"* ]]; then
    continue
  fi
  link="$EXP/address/$a#code"
  name="?"
  verified="no"
  state=""
  core=0
  is_core "$role" && core=1

  if ! explorer_get "smart-contracts/$a"; then
    state="ERR_EXPLORER"
  elif [[ "$HTTP_CODE" == "404" ]]; then
    state="NOT_A_CONTRACT"
  else
    sc="$HTTP_BODY"
    name="$(jq -r '.name // "?"' <<<"$sc")"
    if [[ "$(jq -r '.is_verified // false' <<<"$sc")" == "true" ]]; then
      state="ALREADY_VERIFIED"
      verified="yes"
    else
      creation="$(jq -r '.creation_bytecode // empty' <<<"$sc")"
      creation="${creation,,}"
      id=""
      args=""
      if [[ -n "$creation" ]]; then
        for k in "${!IDS[@]}"; do
          code="${CODES[$k]}"
          if [[ "$creation" == "$code"* ]]; then
            id="${IDS[$k]}"
            args="0x${creation:${#code}}"
            break
          fi
        done
      fi
      if [[ -z "$id" ]]; then
        state="NO_LOCAL_MATCH"
      else
        name="${id##*:}"
        [[ "$args" == "0x" ]] && args=""
        if [[ "$DRY" == "1" ]]; then
          state="DRY_RUN($id args=$(( ${#args} > 2 ? (${#args} - 2) / 2 : 0 ))B)"
        else
          cmd=(forge verify-contract "$a" "$id" --chain "$CHAIN" --verifier blockscout --verifier-url "$EXP/api/"
               --compiler-version "$SOLC" --evm-version "$EVM" --num-of-optimizations "$RUNS" --skip-is-verified-check --watch)
          [[ "$VIA_IR" == "true" ]] && cmd+=(--via-ir)
          [[ -n "$args" ]] && cmd+=(--constructor-args "$args")
          n=1
          state="FAILED"
          while (( n <= ATT )); do
            timeout 300 "${cmd[@]}" </dev/null >"$TMP/forge.out" 2>&1
            if explorer_get "smart-contracts/$a" && [[ "$HTTP_CODE" == "200" ]] \
               && [[ "$(jq -r '.is_verified // false' <<<"$HTTP_BODY")" == "true" ]]; then
              state="VERIFIED_NOW"
              verified="yes"
              break
            fi
            n=$((n + 1))
            sleep 3
          done
          if [[ "$state" == "FAILED" ]]; then
            tail -n 3 "$TMP/forge.out" | cut -c1-200 >&2
          fi
        fi
      fi
    fi
  fi

  case "$state" in
    ALREADY_VERIFIED) skip=$((skip + 1)) ;;
    VERIFIED_NOW) ok=$((ok + 1)) ;;
    DRY_RUN*) dry=$((dry + 1)) ;;
    NOT_A_CONTRACT) skip=$((skip + 1)) ;;
    NO_LOCAL_MATCH)
      if [[ "$role" == live.* ]]; then
        state="EXTERNAL"
        skip=$((skip + 1))
      else
        fail=$((fail + 1))
        (( core == 1 )) && core_bad=$((core_bad + 1)) || other_bad=$((other_bad + 1))
      fi
      ;;
    *)
      fail=$((fail + 1))
      (( core == 1 )) && core_bad=$((core_bad + 1)) || other_bad=$((other_bad + 1))
      ;;
  esac

  printf '%s\t%s\t%s\t%s\n' "$a" "$name" "$role" "$state"
  printf '| `%s` | %s | %s | [code](%s) | %s |\n' "$a" "$name" "$role" "$link" "$verified" >>"$ROWS"
done <"$TMP/addrs.tsv"

echo "verified_now=$ok already_or_skipped=$skip dry_run=$dry failed=$fail core_unverified=$core_bad other_unverified=$other_bad"

if (( WRITE_LOG == 1 )); then
  mkdir -p "$(dirname "$LOG")"
  {
    printf '## %s (chain %s, %s)\n\n' "$DNAME" "$CHAIN" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Explorer %s. verified_now=%s already_or_skipped=%s failed=%s core_unverified=%s other_unverified=%s.\n\n' \
      "$EXP" "$ok" "$skip" "$fail" "$core_bad" "$other_bad"
    printf '| Address | Name | Role | Explorer | Verified |\n|---|---|---|---|---|\n'
    cat "$ROWS"
    printf '\n'
  } >"$TMP/section.md"
  {
    printf '# Verification log\n\nWritten by scripts/verify.sh. One section per deployment, latest run only. Verified is the explorer is_verified flag read at the end of the run.\n\n'
    if [[ -f "$LOG" ]]; then
      awk -v skip="## $DNAME " 'BEGIN { keep = 0 } /^## / { keep = (index($0, skip) != 1) } keep { print }' "$LOG"
    fi
    cat "$TMP/section.md"
  } >"$TMP/log.md"
  mv "$TMP/log.md" "$LOG"
  echo "Wrote $LOG"
fi

if (( core_bad > 0 )); then
  exit 1
fi
if (( LISTING_ERR == 1 )); then
  exit 4
fi
if (( other_bad > 0 )); then
  exit 3
fi
exit 0
