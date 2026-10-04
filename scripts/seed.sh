#!/usr/bin/env bash
set -euo pipefail

NETWORK="${1:-robinhood-testnet}"
MAX_ATTEMPTS="${SEED_MAX_ATTEMPTS:-8}"
DRY_RUN="${SEED_DRY_RUN:-0}"

if [[ -z "${DEPLOYER_PRIVATE_KEY:-}" ]]; then
  echo "DEPLOYER_PRIVATE_KEY is not set. It must be the MockUSDG owner (the deploy wallet)." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ADDR_FILE="deployments/$NETWORK/addresses.json"
if [[ ! -f "$ADDR_FILE" ]]; then
  echo "No deployment found at $ADDR_FILE" >&2
  exit 1
fi

RPC_URL="${SEED_RPC_URL:-$(jq -r '.rpcUrl' "$ADDR_FILE")}"
CHAIN_ID="$(jq -r '.chainId' "$ADDR_FILE")"
RUN_FILE="broadcast/SeedStrategies.s.sol/$CHAIN_ID/run-latest.json"

export DEPLOY_NETWORK="$NETWORK"

if [[ "$DRY_RUN" == "1" ]]; then
  forge script script/SeedStrategies.s.sol --rpc-url "$RPC_URL"
  exit 0
fi

MARKER="$(mktemp)"
trap 'rm -f "$MARKER"' EXIT

attempt=1
mode="fresh"
while true; do
  if [[ "$mode" == "fresh" ]]; then
    cmd=(forge script script/SeedStrategies.s.sol --rpc-url "$RPC_URL" --broadcast --slow)
  else
    cmd=(forge script script/SeedStrategies.s.sol --rpc-url "$RPC_URL" --broadcast --slow --resume)
  fi

  if "${cmd[@]}"; then
    echo "Seed complete on $NETWORK."
    exit 0
  fi

  if (( attempt >= MAX_ATTEMPTS )); then
    echo "Seed failed after $MAX_ATTEMPTS attempts. Do NOT rerun from scratch if $RUN_FILE exists; use --resume." >&2
    exit 1
  fi

  if [[ -f "$RUN_FILE" && "$RUN_FILE" -nt "$MARKER" ]]; then
    mode="resume"
  fi
  echo "Attempt $attempt failed, retrying in $mode mode ($((attempt + 1))/$MAX_ATTEMPTS)..." >&2
  attempt=$((attempt + 1))
  sleep 3
done
