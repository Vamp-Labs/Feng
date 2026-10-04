#!/usr/bin/env bash
set -euo pipefail

NETWORK="${1:-}"

if [[ -z "$NETWORK" ]]; then
  echo "Usage: scripts/keeper.sh <network> [intervalSeconds] [maxIterations]" >&2
  echo "  network is a folder under deployments/, e.g. robinhood-testnet, arbitrum-sepolia, anvil" >&2
  exit 1
fi

INTERVAL_SECONDS="${2:-${KEEPER_INTERVAL_SECONDS:-30}}"
MAX_ITERATIONS="${3:-${KEEPER_MAX_ITERATIONS:-0}}"

if [[ -z "${KEEPER_PRIVATE_KEY:-}" ]]; then
  echo "KEEPER_PRIVATE_KEY is not set. Export a testnet-only key before running this script." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDR_FILE="$ROOT_DIR/deployments/$NETWORK/addresses.json"

if [[ ! -f "$ADDR_FILE" ]]; then
  echo "No addresses.json found at $ADDR_FILE" >&2
  exit 1
fi

RPC_URL="${KEEPER_RPC_URL:-$(jq -r '.rpcUrl' "$ADDR_FILE")}"
ENGINE="$(jq -r '.rebalanceEngine' "$ADDR_FILE")"

if [[ -z "$ENGINE" || "$ENGINE" == "null" ]]; then
  echo "No rebalanceEngine address in $ADDR_FILE" >&2
  exit 1
fi

echo "Keeper watching RebalanceEngine $ENGINE on $NETWORK ($RPC_URL), interval ${INTERVAL_SECONDS}s"

iteration=0
while true; do
  iteration=$((iteration + 1))
  VAULTS="$(cast call "$ENGINE" "checkUpkeep()(address[])" --rpc-url "$RPC_URL" 2>&1)" || {
    echo "[$iteration] checkUpkeep call failed: $VAULTS" >&2
    VAULTS="[]"
  }

  echo "[$iteration] checkUpkeep -> $VAULTS"

  if [[ "$VAULTS" != "[]" ]]; then
    VAULT_LIST="$(echo "$VAULTS" | tr -d '[]' | tr ',' '\n' | tr -d ' ')"
    while IFS= read -r VAULT; do
      [[ -z "$VAULT" ]] && continue
      echo "[$iteration] performRebalance($VAULT)"
      cast send "$ENGINE" "performRebalance(address)" "$VAULT" \
        --private-key "$KEEPER_PRIVATE_KEY" \
        --rpc-url "$RPC_URL" || echo "[$iteration] performRebalance failed for $VAULT" >&2
    done <<< "$VAULT_LIST"
  fi

  if (( MAX_ITERATIONS > 0 && iteration >= MAX_ITERATIONS )); then
    echo "Reached max iterations ($MAX_ITERATIONS), stopping."
    break
  fi

  sleep "$INTERVAL_SECONDS"
done
