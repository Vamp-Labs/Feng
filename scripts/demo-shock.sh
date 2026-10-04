#!/usr/bin/env bash
set -euo pipefail

SYMBOL="TSLA"
PCT="18"
VAULT_SEL=""
WAIT_SEC="30"
DRY=0
RESTORE=1
ADDR_FILE="${DEMO_ADDRESSES:-}"
RPC_URL="${DEMO_RPC_URL:-}"
MAX_ATTEMPTS="${DEMO_MAX_ATTEMPTS:-6}"

usage() {
  cat >&2 <<'EOF'
Usage: scripts/demo-shock.sh [--dry] [--symbol TSLA] [--pct 18] [--vault EVMO|0x...] [--wait 30] [--no-restore]
                             [--addresses deployments/robinhood-testnet-v2/addresses.json] [--rpc <url>]

Pushes a bounded price shock through FengAggregator.shockAnswer, waits for the keeper to rebalance
(or calls RebalanceEngineV2.performRebalance itself when KEEPER_PRIVATE_KEY is set), then restores
the original price with updateAnswer.

Keys come from the environment only and are never printed:
  SHOCK_PRIVATE_KEY     account with SHOCK_ROLE (falls back to RELAYER_PRIVATE_KEY)
  RELAYER_PRIVATE_KEY   account with UPDATER_ROLE, used for the restore (falls back to SHOCK_PRIVATE_KEY)
  KEEPER_PRIVATE_KEY    optional, used when the keeper did not rebalance within --wait seconds

--dry only runs cast call: it reports the state and simulates the shock, the rebalance and the restore.
--wait 0 skips waiting for the keeper. --no-restore leaves the shocked price on chain.
The shock path only works when the deployment was made with ENABLE_SHOCK=1.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry) DRY=1; shift ;;
    --symbol) SYMBOL="${2:?--symbol needs a value}"; shift 2 ;;
    --pct) PCT="${2:?--pct needs a value}"; shift 2 ;;
    --vault) VAULT_SEL="${2:?--vault needs a value}"; shift 2 ;;
    --wait) WAIT_SEC="${2:?--wait needs a value}"; shift 2 ;;
    --no-restore) RESTORE=0; shift ;;
    --addresses) ADDR_FILE="${2:?--addresses needs a value}"; shift 2 ;;
    --rpc) RPC_URL="${2:?--rpc needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for tool in cast jq awk; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required but not installed." >&2; exit 1; }
done

if [[ -z "$ADDR_FILE" ]]; then
  ADDR_FILE="deployments/robinhood-testnet-v2/addresses.json"
fi
if [[ ! -f "$ADDR_FILE" ]]; then
  echo "No addresses file at $ADDR_FILE. The V2 deployment has not landed yet, or pass --addresses." >&2
  exit 1
fi
if [[ -z "$RPC_URL" ]]; then
  RPC_URL="$(jq -r '.rpcUrl' "$ADDR_FILE")"
fi

if ! [[ "$PCT" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
  echo "--pct must be a number such as 18 or -12.5" >&2
  exit 1
fi
BPS="$(awk -v p="$PCT" 'BEGIN { printf "%d", (p * 100) + (p < 0 ? -0.5 : 0.5) }')"
if [[ "$BPS" == "0" ]]; then
  echo "--pct rounds to zero basis points, nothing to do." >&2
  exit 1
fi

retry() {
  local attempt=1
  local out
  while true; do
    if out="$("$@" 2>&1)"; then
      printf '%s\n' "$out"
      return 0
    fi
    if (( attempt >= MAX_ATTEMPTS )); then
      printf '%s\n' "$out" >&2
      return 1
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
}

first_field() { awk 'NR==1 { print $1 }'; }

call() {
  local to="$1"; shift
  retry cast call "$to" "$@" --rpc-url "$RPC_URL"
}

FEED="$(jq -r --arg s "$SYMBOL" '.priceOracles[$s] // empty' "$ADDR_FILE")"
ENGINE="$(jq -r '.rebalanceEngine // empty' "$ADDR_FILE")"
REGISTRY="$(jq -r '.marketplaceRegistry // empty' "$ADDR_FILE")"
if [[ -z "$FEED" || -z "$ENGINE" || -z "$REGISTRY" ]]; then
  echo "$ADDR_FILE has no feed for $SYMBOL, or no rebalanceEngine or marketplaceRegistry." >&2
  exit 1
fi

SHOCK_KEY="${SHOCK_PRIVATE_KEY:-${RELAYER_PRIVATE_KEY:-}}"
RESTORE_KEY="${RELAYER_PRIVATE_KEY:-${SHOCK_PRIVATE_KEY:-}}"
KEEPER_KEY="${KEEPER_PRIVATE_KEY:-}"
if [[ -z "$SHOCK_KEY" ]]; then
  echo "Set SHOCK_PRIVATE_KEY (or RELAYER_PRIVATE_KEY) in the environment. The key is never printed." >&2
  exit 1
fi
SHOCK_ADDR="$(cast wallet address --private-key "$SHOCK_KEY")"
RESTORE_ADDR="$(cast wallet address --private-key "$RESTORE_KEY")"

SHOCK_ENABLED="$(call "$FEED" "shockEnabled()(bool)" | first_field)"
if [[ "$SHOCK_ENABLED" != "true" ]]; then
  echo "Shock is disabled on this deployment: $SYMBOL feed $FEED reports shockEnabled() = false." >&2
  echo "The deployment must be made with ENABLE_SHOCK=1, or the admin must call setShockEnabled(true) on the five stock feeds and grant SHOCK_ROLE to the shock wallet. Nothing was sent." >&2
  exit 3
fi
SHOCK_ROLE="$(call "$FEED" "SHOCK_ROLE()(bytes32)" | first_field)"
UPDATER_ROLE="$(call "$FEED" "UPDATER_ROLE()(bytes32)" | first_field)"
HAS_SHOCK="$(call "$FEED" "hasRole(bytes32,address)(bool)" "$SHOCK_ROLE" "$SHOCK_ADDR" | first_field)"
if [[ "$HAS_SHOCK" != "true" ]]; then
  echo "Wallet $SHOCK_ADDR does not hold SHOCK_ROLE on the $SYMBOL feed. Use the wallet that was given SHOCK_ROLE at deploy time (the relayer when ENABLE_SHOCK=1). Nothing was sent." >&2
  exit 3
fi
HAS_UPDATER="$(call "$FEED" "hasRole(bytes32,address)(bool)" "$UPDATER_ROLE" "$RESTORE_ADDR" | first_field)"
if [[ "$RESTORE" == "1" && "$HAS_UPDATER" != "true" ]]; then
  echo "Wallet $RESTORE_ADDR does not hold UPDATER_ROLE on the $SYMBOL feed, so the restore would fail. Set RELAYER_PRIVATE_KEY to the relayer wallet, or pass --no-restore." >&2
  exit 3
fi

DECIMALS="$(call "$FEED" "decimals()(uint8)" | first_field)"
ORIGINAL="$(call "$FEED" "latestAnswer()(int256)" | first_field)"
ANCHOR="$(call "$FEED" "anchorAnswer()(int256)" | first_field)"
MAX_SHOCK="$(call "$FEED" "maxShockBps()(uint16)" | first_field)"
TARGET=$(( ORIGINAL * (10000 + BPS) / 10000 ))
DIST=$(( TARGET > ANCHOR ? TARGET - ANCHOR : ANCHOR - TARGET ))
LIMIT=$(( ANCHOR * MAX_SHOCK / 10000 ))

fmt() { awk -v v="$1" -v d="$DECIMALS" 'BEGIN { printf "%.4f", v / (10 ^ d) }'; }

echo "Deployment file : $ADDR_FILE"
echo "RPC             : $RPC_URL"
echo "Feed            : $SYMBOL $FEED"
echo "Price now       : $(fmt "$ORIGINAL")  (anchor $(fmt "$ANCHOR"), shock bound ${MAX_SHOCK} bps)"
echo "Shock target    : $(fmt "$TARGET")  (${PCT}% from the current price)"
if [[ "$ORIGINAL" != "$ANCHOR" ]]; then
  echo "Note            : the current price differs from the anchor, a shock or an unsettled move may already be displayed."
fi
if (( DIST > LIMIT )); then
  echo "The target is $(( DIST * 10000 / ANCHOR )) bps from the anchor, above the shock bound of ${MAX_SHOCK} bps. Choose a smaller --pct. Nothing was sent." >&2
  exit 3
fi

if [[ -n "$VAULT_SEL" ]]; then
  if [[ "$VAULT_SEL" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    VAULT="$VAULT_SEL"
  else
    VAULT="$(jq -r --arg s "$VAULT_SEL" '[.vaults[]? | select(.symbol == $s)][0].vault // empty' "$ADDR_FILE")"
  fi
else
  VAULT="$(jq -r '[.vaults[]? | select(.symbol == "EVMO")][0].vault // empty' "$ADDR_FILE")"
fi
if [[ -z "$VAULT" ]]; then
  echo "No vault resolved. Pass --vault <symbol|address>." >&2
  exit 1
fi
echo "Watching vault  : $VAULT"

vault_needed() {
  local out
  out="$(call "$VAULT" "rebalanceNeeded()(bool,bool)")"
  if grep -q true <<<"$out"; then echo true; else echo false; fi
}

last_rebalance() { call "$VAULT" "lastRebalanceTimestamp()(uint256)" | first_field; }

BEFORE_NEEDED="$(vault_needed)"
echo "Vault rebalanceNeeded before: $BEFORE_NEEDED"

if [[ "$DRY" == "1" ]]; then
  echo "--- dry run: cast call only, nothing is sent"
  if retry cast call "$FEED" "shockAnswer(int256)" "$TARGET" --from "$SHOCK_ADDR" --rpc-url "$RPC_URL" >/dev/null; then
    echo "shockAnswer($TARGET) from $SHOCK_ADDR: simulation ok"
  else
    echo "shockAnswer($TARGET) from $SHOCK_ADDR: simulation reverted" >&2
    exit 4
  fi
  if retry cast call "$FEED" "updateAnswer(int256)" "$ORIGINAL" --from "$RESTORE_ADDR" --rpc-url "$RPC_URL" >/dev/null; then
    echo "updateAnswer($ORIGINAL) from $RESTORE_ADDR (restore): simulation ok"
  else
    echo "updateAnswer($ORIGINAL) from $RESTORE_ADDR (restore): simulation reverted" >&2
    exit 4
  fi
  SIM_FROM="$SHOCK_ADDR"
  if [[ -n "$KEEPER_KEY" ]]; then
    SIM_FROM="$(cast wallet address --private-key "$KEEPER_KEY")"
  fi
  if [[ "$BEFORE_NEEDED" == "true" ]]; then
    if retry cast call "$ENGINE" "performRebalance(address)" "$VAULT" --from "$SIM_FROM" --rpc-url "$RPC_URL" >/dev/null 2>&1; then
      echo "performRebalance($VAULT): simulation ok at the current price"
    else
      echo "performRebalance($VAULT): simulation reverted at the current price"
    fi
  else
    echo "performRebalance: not simulated, the vault does not need a rebalance at the current price (it will after the shock)."
  fi
  echo "dry run complete"
  exit 0
fi

SHOCKED=0
restore() {
  local code=$?
  trap - EXIT INT TERM
  if [[ "$SHOCKED" == "1" && "$RESTORE" == "1" ]]; then
    echo "--- restoring $SYMBOL to $(fmt "$ORIGINAL")"
    if retry cast send "$FEED" "updateAnswer(int256)" "$ORIGINAL" --private-key "$RESTORE_KEY" --rpc-url "$RPC_URL" --json | jq -r '"restore tx " + .transactionHash + " status " + .status'; then
      local now
      now="$(call "$FEED" "latestAnswer()(int256)" | first_field)"
      echo "Price after restore: $(fmt "$now")"
    else
      echo "RESTORE FAILED. Run: cast send $FEED \"updateAnswer(int256)\" $ORIGINAL with the relayer wallet, or let the relayer restore the market price." >&2
      code=5
    fi
  elif [[ "$SHOCKED" == "1" ]]; then
    echo "--no-restore: the shocked price stays on chain. The relayer restores the market price after OPS_SHOCK_HOLD_SEC (default 600 s) when it runs in market mode."
  fi
  exit "$code"
}
trap restore EXIT INT TERM

echo "--- sending shockAnswer($TARGET)"
SHOCK_OUT="$(retry cast send "$FEED" "shockAnswer(int256)" "$TARGET" --private-key "$SHOCK_KEY" --rpc-url "$RPC_URL" --json)"
SHOCKED=1
echo "$SHOCK_OUT" | jq -r '"shock tx " + .transactionHash + " status " + .status'
NOW="$(call "$FEED" "latestAnswer()(int256)" | first_field)"
echo "Price after shock: $(fmt "$NOW")"

AFTER_NEEDED="$(vault_needed)"
echo "Vault rebalanceNeeded after the shock: $AFTER_NEEDED"
if [[ "$AFTER_NEEDED" != "true" ]]; then
  echo "The vault does not need a rebalance at this shock size; the keeper has nothing to do for it. Try a larger --pct or another --vault."
fi

START_REBALANCE="$(last_rebalance)"
if [[ "$AFTER_NEEDED" == "true" && "$WAIT_SEC" -gt 0 ]]; then
  echo "--- waiting up to ${WAIT_SEC}s for the keeper"
  waited=0
  while (( waited < WAIT_SEC )); do
    sleep 3
    waited=$(( waited + 3 ))
    if [[ "$(last_rebalance)" != "$START_REBALANCE" ]]; then
      echo "The keeper rebalanced the vault after ${waited}s."
      break
    fi
  done
fi

if [[ "$AFTER_NEEDED" == "true" && "$(last_rebalance)" == "$START_REBALANCE" ]]; then
  if [[ -n "$KEEPER_KEY" ]]; then
    echo "--- calling performRebalance from the keeper wallet"
    retry cast send "$ENGINE" "performRebalance(address)" "$VAULT" --private-key "$KEEPER_KEY" --rpc-url "$RPC_URL" --json | jq -r '"rebalance tx " + .transactionHash + " status " + .status'
  else
    echo "The keeper has not rebalanced yet and KEEPER_PRIVATE_KEY is not set. The next tick will do it."
  fi
fi

if [[ "$AFTER_NEEDED" == "true" ]]; then
  LAST="$(last_rebalance)"
  if [[ "$LAST" != "$START_REBALANCE" ]]; then
    echo "Vault rebalanced at timestamp $LAST; needed now: $(vault_needed)"
  fi
fi
