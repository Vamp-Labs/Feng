#!/usr/bin/env bash
set -euo pipefail

NETWORK="${1:-robinhood-testnet}"
MAX_ATTEMPTS="${REFRESH_MAX_ATTEMPTS:-6}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDR_FILE="$ROOT_DIR/deployments/$NETWORK/addresses.json"
if [[ ! -f "$ADDR_FILE" ]]; then
  echo "No deployment found at $ADDR_FILE" >&2
  exit 1
fi

KEY="${REFRESH_PRIVATE_KEY:-${KEEPER_PRIVATE_KEY:-${DEPLOYER_PRIVATE_KEY:-}}}"
if [[ -z "$KEY" ]]; then
  echo "Set REFRESH_PRIVATE_KEY, KEEPER_PRIVATE_KEY or DEPLOYER_PRIVATE_KEY (any funded testnet key; updateAnswer is open)." >&2
  exit 1
fi

RPC_URL="${REFRESH_RPC_URL:-$(jq -r '.rpcUrl' "$ADDR_FILE")}"

declare -A PRICES=(
  [USDG]=100000000
  [TSLA]=26000000000
  [AMZN]=18300000000
  [NFLX]=58100000000
  [PLTR]=2600000000
  [AMD]=13800000000
  [NVDA]=18650000000
  [TSMC]=22600000000
  [MSFT]=51400000000
  [GOOGL]=19800000000
  [RKLB]=2900000000
  [ISRG]=59800000000
  [XOM]=11300000000
  [ENPH]=4950000000
)

for ticker in "${!PRICES[@]}"; do
  feed="$(jq -r ".priceOracles.$ticker" "$ADDR_FILE")"
  for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    if cast send "$feed" "updateAnswer(int256)" "${PRICES[$ticker]}" \
      --rpc-url "$RPC_URL" --private-key "$KEY" >/dev/null 2>&1; then
      echo "refreshed $ticker"
      break
    fi
    if (( attempt == MAX_ATTEMPTS )); then
      echo "failed to refresh $ticker after $MAX_ATTEMPTS attempts" >&2
      exit 1
    fi
    sleep 3
  done
done
