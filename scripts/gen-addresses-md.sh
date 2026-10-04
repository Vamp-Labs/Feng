#!/usr/bin/env bash
set -euo pipefail

if locale -a 2>/dev/null | grep -qi '^c\.utf-\?8$'; then
  export LC_ALL=C.UTF-8
elif locale -a 2>/dev/null | grep -qi '^en_US\.utf-\?8$'; then
  export LC_ALL=en_US.UTF-8
fi

usage() {
  echo "Usage: scripts/gen-addresses-md.sh [network] [--inject FILE]" >&2
  echo "  network    folder under deployments/ (default: robinhood-testnet)" >&2
  echo "  --inject   replace the text between <!-- BEGIN:addresses --> and <!-- END:addresses --> in FILE" >&2
  echo "Env: GEN_ADDRESSES_ONCHAIN=0 skips every cast call; GEN_MAX_ATTEMPTS (default 8) sets the retry count." >&2
}

NETWORK=""
INJECT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --inject)
      INJECT="${2:-}"
      [[ -n "$INJECT" ]] || { usage; exit 1; }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$NETWORK" ]]; then
        NETWORK="$1"
        shift
      else
        usage
        exit 1
      fi
      ;;
  esac
done
NETWORK="${NETWORK:-robinhood-testnet}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDR_FILE="$ROOT_DIR/deployments/$NETWORK/addresses.json"
ONCHAIN="${GEN_ADDRESSES_ONCHAIN:-1}"
MAX_ATTEMPTS="${GEN_MAX_ATTEMPTS:-8}"
CAP=300
EM_DASH=$'—'
PAXOS_USDG_TESTNET="0x7e955252e15c84f5768b83c41a71f9eba181802f"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[[ -f "$ADDR_FILE" ]] || { echo "No addresses.json at $ADDR_FILE" >&2; exit 1; }

HAVE_CAST=0
if [[ "$ONCHAIN" == "1" ]] && command -v cast >/dev/null; then
  HAVE_CAST=1
fi

j() { jq -r "$1" "$ADDR_FILE"; }

CHAIN_ID="$(j '.chainId')"
RPC_URL="$(j '.rpcUrl // empty')"
EXPLORER="$(j '.explorerUrl // empty')"
EXPLORER="${EXPLORER%/}"
SCHEMA="$(j '.schemaVersion // 1')"

case "$CHAIN_ID" in
  46630|4663) NET_LABEL="Robinhood Chain" ;;
  421614) NET_LABEL="Arbitrum Sepolia" ;;
  42161) NET_LABEL="Arbitrum One" ;;
  42170) NET_LABEL="Arbitrum Nova" ;;
  *) NET_LABEL="Robinhood Chain" ;;
esac

retry() {
  local attempt=1 out
  while (( attempt <= MAX_ATTEMPTS )); do
    if out="$(timeout 20 "$@" 2>/dev/null)" && [[ -n "$out" ]]; then
      printf '%s\n' "$out"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
  return 1
}

first_token() { awk '{print $1}'; }

link() {
  local addr="$1"
  if [[ -n "$EXPLORER" ]]; then
    printf '[`%s`](%s/address/%s)' "$addr" "$EXPLORER" "$addr"
  else
    printf '`%s`' "$addr"
  fi
}

declare -a CORE_NAMES=() CORE_ADDRS=()
add_core() {
  local name="$1" addr="$2"
  [[ -n "$addr" && "$addr" != "null" ]] || return 0
  CORE_NAMES+=("$name")
  CORE_ADDRS+=("$addr")
}

REGISTRY="$(j '.marketplaceRegistry // empty')"
ENGINE="$(j '.rebalanceEngine // empty')"
FACTORY="$(j '.strategyFactory // empty')"
ORACLE="$(j '.oracle // empty')"
VENUE="$(j '.venue // empty')"
FAUCET="$(j '.faucet // empty')"
VAULT_DEPLOYER="$(j '.vaultDeployer // empty')"
USDG="$(j '.usdg // empty')"

if [[ -z "$ORACLE" && "$HAVE_CAST" == "1" && -n "$FACTORY" && -n "$RPC_URL" ]]; then
  ORACLE="$(retry cast call "$FACTORY" "priceOracle()(address)" --rpc-url "$RPC_URL" | first_token || true)"
fi

add_core "Marketplace registry" "$REGISTRY"
add_core "Rebalance engine" "$ENGINE"
add_core "Price oracle" "$ORACLE"
add_core "Oracle desk" "$VENUE"
add_core "Faucet" "$FAUCET"
add_core "Strategy factory" "$FACTORY"
add_core "Vault deployer" "$VAULT_DEPLOYER"

declare -a TOK_NAMES=() TOK_ADDRS=()
LIVE_USDG="$(j '.live.usdg // empty')"
usdg_label() {
  local lower="${1,,}"
  if [[ "$lower" == "$PAXOS_USDG_TESTNET" ]]; then
    printf 'Paxos USDG'
  else
    printf 'Mock USDG'
  fi
}
if [[ -n "$LIVE_USDG" ]]; then
  TOK_NAMES+=("$(usdg_label "$LIVE_USDG")")
  TOK_ADDRS+=("$LIVE_USDG")
fi
if [[ -n "$USDG" ]]; then
  TOK_NAMES+=("$(usdg_label "$USDG")")
  TOK_ADDRS+=("$USDG")
fi
while IFS=$'\t' read -r sym addr; do
  [[ -n "$sym" ]] || continue
  TOK_NAMES+=("Mock $sym")
  TOK_ADDRS+=("$addr")
done < <(j '(.stockTokens // {}) | to_entries[] | [.key, .value] | @tsv')

declare -a FEED_NAMES=() FEED_ADDRS=()
while IFS=$'\t' read -r sym addr; do
  [[ -n "$sym" ]] || continue
  FEED_NAMES+=("$sym / USD feed")
  FEED_ADDRS+=("$addr")
done < <(j '(.priceOracles // {}) | to_entries[] | [.key, .value] | @tsv')

declare -a V_SYMS=() V_NAMES=() V_VAULTS=() V_TOKENS=() V_DEPTHS=() V_UNIVERSE=()
VAULT_SOURCE="none"
JSON_VAULTS="$(j '(.vaults // []) | length')"
if [[ "$JSON_VAULTS" -gt 0 ]]; then
  VAULT_SOURCE="addresses.json"
  while IFS=$'\t' read -r sym name vault token depth universe; do
    V_SYMS+=("$sym"); V_NAMES+=("$name"); V_VAULTS+=("$vault"); V_TOKENS+=("$token"); V_DEPTHS+=("$depth"); V_UNIVERSE+=("$universe")
  done < <(j '.vaults[] | [(.symbol // ""), (.name // ""), .vault, (.token // ""), ((.depth // "") | tostring), (.universe // "sandbox")] | @tsv')
elif [[ "$HAVE_CAST" == "1" && -n "$REGISTRY" && -n "$RPC_URL" ]]; then
  VAULT_SOURCE="read from the registry with cast"
  if vault_list="$(retry cast call "$REGISTRY" "getAllStrategies()(address[])" --rpc-url "$RPC_URL")"; then
    vault_list="${vault_list//[\[\],]/ }"
    for vault in $vault_list; do
      info="$(retry cast call "$REGISTRY" "getStrategyInfo(address)(address,address,uint8,uint256)" "$vault" --rpc-url "$RPC_URL" || true)"
      token="$(printf '%s\n' "$info" | sed -n '1p' | first_token)"
      depth="$(printf '%s\n' "$info" | sed -n '3p' | first_token)"
      sym=""
      name=""
      if [[ -n "$token" ]]; then
        sym="$(retry cast call "$token" "symbol()(string)" --rpc-url "$RPC_URL" | tr -d '"' || true)"
        name="$(retry cast call "$token" "name()(string)" --rpc-url "$RPC_URL" | tr -d '"' || true)"
      fi
      V_SYMS+=("$sym"); V_NAMES+=("$name"); V_VAULTS+=("$vault"); V_TOKENS+=("$token"); V_DEPTHS+=("$depth"); V_UNIVERSE+=("sandbox")
    done
    for i in "${!V_VAULTS[@]}"; do
      if [[ -n "${V_TOKENS[$i]}" && -z "${V_SYMS[$i]}" ]]; then
        V_SYMS[$i]="$(retry cast call "${V_TOKENS[$i]}" "symbol()(string)" --rpc-url "$RPC_URL" | tr -d '"' || true)"
      fi
      if [[ -n "${V_TOKENS[$i]}" && -z "${V_NAMES[$i]}" ]]; then
        V_NAMES[$i]="$(retry cast call "${V_TOKENS[$i]}" "name()(string)" --rpc-url "$RPC_URL" | tr -d '"' || true)"
      fi
    done
  else
    echo "warning: could not read getAllStrategies() from the registry; vault table omitted" >&2
    VAULT_SOURCE="unavailable"
  fi
fi

declare -a LIVE_NAMES=() LIVE_ADDRS=()
if [[ "$(j '(.live // null) != null')" == "true" ]]; then
  live_usdg="$(j '.live.usdg // empty')"
  [[ -n "$live_usdg" ]] && { LIVE_NAMES+=("$(usdg_label "$live_usdg")"); LIVE_ADDRS+=("$live_usdg"); }
  live_factory="$(j '.live.strategyFactory // empty')"
  [[ -n "$live_factory" ]] && { LIVE_NAMES+=("Live strategy factory"); LIVE_ADDRS+=("$live_factory"); }
  live_venue="$(j '.live.venue // empty')"
  [[ -n "$live_venue" ]] && { LIVE_NAMES+=("Live oracle desk"); LIVE_ADDRS+=("$live_venue"); }
  while IFS=$'\t' read -r sym addr; do
    [[ -n "$sym" ]] || continue
    LIVE_NAMES+=("Robinhood $sym stock token"); LIVE_ADDRS+=("$addr")
  done < <(j '(.live.stockTokens // {}) | to_entries[] | [.key, .value] | @tsv')
fi

block_line() { printf '%s: %s %s %s' "$NET_LABEL" "$1" "$EM_DASH" "$2"; }

BLOCK_FAIL=0
LINE_RE="^(Robinhood Chain|Arbitrum Sepolia|Arbitrum One|Arbitrum Nova): 0x[0-9a-fA-F]{40} ${EM_DASH} .+$"

build_block() {
  local -n names=$1
  local -n addrs=$2
  local block="" line candidate i
  DROPPED=()
  for i in "${!names[@]}"; do
    line="$(block_line "${addrs[$i]}" "${names[$i]}")"
    if [[ -z "$block" ]]; then
      candidate="$line"
    else
      candidate="$block"$'\n'"$line"
    fi
    if (( ${#candidate} <= CAP )); then
      block="$candidate"
    else
      DROPPED+=("${names[$i]}")
    fi
  done
  BLOCK="$block"
}

emit_block() {
  local title="$1" len status line
  shift
  local -n bnames=$1
  local -n baddrs=$2
  build_block bnames baddrs
  len=${#BLOCK}
  status="PASS"
  if [[ -z "$BLOCK" ]] || (( len > CAP )); then
    status="FAIL"
    BLOCK_FAIL=1
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! [[ "$line" =~ $LINE_RE ]]; then
      status="FAIL"
      BLOCK_FAIL=1
    fi
  done <<<"$BLOCK"
  printf '**%s**: %d of %d characters, %s\n\n' "$title" "$len" "$CAP" "$status"
  printf '```text\n%s\n```\n\n' "${BLOCK:-N/A}"
  if (( ${#DROPPED[@]} > 0 )); then
    printf 'Not included (character cap): %s. They are listed in the tables above.\n\n' "$(IFS=,; echo "${DROPPED[*]}" | sed 's/,/, /g')"
  fi
}

emit_table() {
  local title="$1"
  shift
  local -n tnames=$1
  local -n taddrs=$2
  (( ${#tnames[@]} > 0 )) || return 0
  printf '#### %s\n\n| Contract | Address |\n|---|---|\n' "$title"
  local i
  for i in "${!tnames[@]}"; do
    printf '| %s | %s |\n' "${tnames[$i]}" "$(link "${taddrs[$i]}")"
  done
  printf '\n'
}

generate() {
  printf 'Network: %s, chain id %s. Source: `deployments/%s/addresses.json` (schema %s)' "$NET_LABEL" "$CHAIN_ID" "$NETWORK" "$SCHEMA"
  printf '. Generated by `scripts/gen-addresses-md.sh`.\n\n'

  emit_table "Core contracts" CORE_NAMES CORE_ADDRS
  emit_table "Tokens" TOK_NAMES TOK_ADDRS
  emit_table "Price feeds" FEED_NAMES FEED_ADDRS
  emit_table "Live universe (real Paxos USDG and Robinhood faucet stock tokens)" LIVE_NAMES LIVE_ADDRS

  if (( ${#V_VAULTS[@]} > 0 )); then
    printf '#### Strategies\n\nSource: %s.\n\n| Symbol | Name | Depth | Vault | Strategy token |\n|---|---|---|---|---|\n' "$VAULT_SOURCE"
    local i
    for i in "${!V_VAULTS[@]}"; do
      printf '| %s | %s | %s | %s | %s |\n' "${V_SYMS[$i]:-}" "${V_NAMES[$i]:-}" "${V_DEPTHS[$i]:-}" "$(link "${V_VAULTS[$i]}")" "$( [[ -n "${V_TOKENS[$i]}" ]] && link "${V_TOKENS[$i]}" || true )"
    done
    printf '\n'
  fi

  printf '#### HackQuest address blocks\n\n'
  printf 'Format: `network: address %s label`, one per line, em dash U+2014, at most %d characters per field.\n\n' "$EM_DASH" "$CAP"

  declare -a CB_N=() CB_A=() FB_N=() FB_A=()
  local i
  for i in "${!CORE_NAMES[@]}"; do
    case "${CORE_NAMES[$i]}" in
      "Strategy factory"|"Vault deployer") ;;
      *) CB_N+=("${CORE_NAMES[$i]}"); CB_A+=("${CORE_ADDRS[$i]}") ;;
    esac
  done
  if [[ -n "$FACTORY" ]]; then
    FB_N+=("Strategy factory"); FB_A+=("$FACTORY")
  fi
  if [[ "$(j '(.live.strategyFactory // "") != ""')" == "true" ]]; then
    FB_N+=("Live strategy factory"); FB_A+=("$(j '.live.strategyFactory')")
  fi

  emit_block "List your Core Protocol / Smart Contract Addresses" CB_N CB_A
  emit_block "List your Factory/Pool Contracts" FB_N FB_A
  emit_block "List your Token Contract Address" TOK_NAMES TOK_ADDRS

  if [[ -n "$FACTORY" ]]; then
    printf '**Contract Address (single input)**: `%s` (strategy factory)\n\n' "$FACTORY"
  fi
}

OUTPUT="$(generate)"

if [[ -n "$INJECT" ]]; then
  [[ -f "$INJECT" ]] || { echo "No such file: $INJECT" >&2; exit 1; }
  grep -q '<!-- BEGIN:addresses -->' "$INJECT" && grep -q '<!-- END:addresses -->' "$INJECT" \
    || { echo "Markers <!-- BEGIN:addresses --> and <!-- END:addresses --> not found in $INJECT" >&2; exit 1; }
  TMP="$(mktemp)"
  GEN_BODY="$OUTPUT" awk '
    /<!-- BEGIN:addresses -->/ { print; print ENVIRON["GEN_BODY"]; skipping = 1; next }
    /<!-- END:addresses -->/ { skipping = 0 }
    !skipping { print }
  ' "$INJECT" >"$TMP"
  cat "$TMP" >"$INJECT"
  rm -f "$TMP"
  echo "Injected addresses into $INJECT" >&2
else
  printf '%s\n' "$OUTPUT"
fi

if (( BLOCK_FAIL )); then
  echo "FAIL: at least one HackQuest block is empty, longer than $CAP characters or not in the 'network: address ${EM_DASH} label' format" >&2
  exit 2
fi
