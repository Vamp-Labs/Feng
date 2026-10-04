#!/usr/bin/env bash
set -euo pipefail

NETWORK="${1:-}"
MAX_ATTEMPTS="${DEPLOY_MAX_ATTEMPTS:-8}"

if [[ -z "$NETWORK" ]]; then
  echo "Usage: scripts/deploy.sh <robinhood-testnet|arbitrum-sepolia>" >&2
  exit 1
fi

if [[ "$NETWORK" != "robinhood-testnet" && "$NETWORK" != "arbitrum-sepolia" ]]; then
  echo "Unknown network: $NETWORK (expected robinhood-testnet or arbitrum-sepolia)" >&2
  exit 1
fi

if [[ -z "${DEPLOYER_PRIVATE_KEY:-}" ]]; then
  echo "DEPLOYER_PRIVATE_KEY is not set. Export a testnet-only key before running this script." >&2
  exit 1
fi

if [[ "$NETWORK" == "robinhood-testnet" ]]; then
  RPC_URL="${ROBINHOOD_TESTNET_RPC_URL:-https://rpc.testnet.chain.robinhood.com}"
  EXPLORER_API_URL="${ROBINHOOD_TESTNET_EXPLORER_API_URL:-https://explorer.testnet.chain.robinhood.com/api}"
  VERIFIER="blockscout"
else
  RPC_URL="${ARBITRUM_SEPOLIA_RPC_URL:-https://sepolia-rollup.arbitrum.io/rpc}"
  EXPLORER_API_URL="${ARBITRUM_SEPOLIA_EXPLORER_API_URL:-https://api-sepolia.arbiscan.io/api}"
  VERIFIER="etherscan"
fi

echo "Deploying to $NETWORK via $RPC_URL"
echo "Retry budget: $MAX_ATTEMPTS attempts (rpc.testnet.chain.robinhood.com has shown intermittent"
echo "TLS interception from some network paths — see docs/handoffs/DEMO-NOTES.md)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

attempt=1
until DEPLOY_NETWORK="$NETWORK" forge script script/Deploy.s.sol \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --slow \
  -vvv; do
  if (( attempt >= MAX_ATTEMPTS )); then
    echo "Deploy failed after $MAX_ATTEMPTS attempts against $NETWORK." >&2
    exit 1
  fi
  echo "Attempt $attempt failed, retrying ($((attempt + 1))/$MAX_ATTEMPTS)..." >&2
  attempt=$((attempt + 1))
  sleep 3
done

echo "Broadcast complete. Wrote deployments/$NETWORK/addresses.json"

if [[ "${SKIP_VERIFY:-0}" == "1" ]]; then
  echo "SKIP_VERIFY=1, skipping Blockscout/Arbiscan verification."
  exit 0
fi

ADDR_FILE="deployments/$NETWORK/addresses.json"
CONTRACTS=(strategyFactory rebalanceEngine marketplaceRegistry)
SOURCE_NAMES=(StrategyFactory RebalanceEngine MarketplaceRegistry)

for i in "${!CONTRACTS[@]}"; do
  KEY="${CONTRACTS[$i]}"
  NAME="${SOURCE_NAMES[$i]}"
  ADDRESS="$(jq -r ".$KEY" "$ADDR_FILE")"
  if [[ -z "$ADDRESS" || "$ADDRESS" == "null" ]]; then
    echo "No address recorded for $KEY, skipping verification." >&2
    continue
  fi
  echo "Verifying $NAME at $ADDRESS on $NETWORK via $VERIFIER"
  if [[ "$VERIFIER" == "etherscan" ]]; then
    forge verify-contract "$ADDRESS" "contracts/$NAME.sol:$NAME" \
      --rpc-url "$RPC_URL" \
      --verifier etherscan \
      --verifier-url "$EXPLORER_API_URL" \
      --etherscan-api-key "${ARBISCAN_API_KEY:-}" \
      --watch || echo "Verification for $NAME did not complete automatically; verify manually on the explorer." >&2
  else
    forge verify-contract "$ADDRESS" "contracts/$NAME.sol:$NAME" \
      --rpc-url "$RPC_URL" \
      --verifier blockscout \
      --verifier-url "$EXPLORER_API_URL" \
      --watch || echo "Verification for $NAME did not complete automatically; verify manually on the explorer." >&2
  fi
done
