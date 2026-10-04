#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
USDG_AMOUNT="${2:-10000}"
ETH_AMOUNT="${3:-0.0005}"
NETWORK="${FUND_NETWORK:-robinhood-testnet}"

if [[ -z "$TARGET" ]]; then
  echo "Usage: DEPLOYER_PRIVATE_KEY=0x... scripts/fund.sh <address> [usdg_amount=10000] [eth_amount=0.0005]" >&2
  exit 1
fi

if [[ -z "${DEPLOYER_PRIVATE_KEY:-}" ]]; then
  echo "DEPLOYER_PRIVATE_KEY is not set. It must be the MockUSDG owner (the deploy wallet)." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDR_FILE="$ROOT_DIR/deployments/$NETWORK/addresses.json"
if [[ ! -f "$ADDR_FILE" ]]; then
  echo "No deployment found at $ADDR_FILE" >&2
  exit 1
fi

RPC_URL="${FUND_RPC_URL:-$(jq -r '.rpcUrl' "$ADDR_FILE")}"
USDG="$(jq -r '.usdg' "$ADDR_FILE")"

DECIMALS="$(cast call "$USDG" "decimals()(uint8)" --rpc-url "$RPC_URL")"
USDG_UNITS="$(python3 -c "from decimal import Decimal; print(int(Decimal('$USDG_AMOUNT') * 10**$DECIMALS))")"

echo "Minting $USDG_AMOUNT USDG to $TARGET on $NETWORK"
cast send "$USDG" "mint(address,uint256)" "$TARGET" "$USDG_UNITS" \
  --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PRIVATE_KEY" >/dev/null

echo "Sending $ETH_AMOUNT ETH for gas to $TARGET"
cast send "$TARGET" --value "${ETH_AMOUNT}ether" \
  --rpc-url "$RPC_URL" --private-key "$DEPLOYER_PRIVATE_KEY" >/dev/null

echo "ETH:  $(cast balance "$TARGET" --rpc-url "$RPC_URL" --ether)"
echo "USDG: $(cast call "$USDG" "balanceOf(address)(uint256)" "$TARGET" --rpc-url "$RPC_URL")"
