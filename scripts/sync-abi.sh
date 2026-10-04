#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="${FOUNDRY_OUT:-out}"
TARGET_DIR="src/lib/abi/generated"
MODE="write"
DO_BUILD=0

for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --build) DO_BUILD=1 ;;
    *)
      echo "Usage: scripts/sync-abi.sh [--check] [--build]" >&2
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed." >&2
  exit 1
fi

if [[ "$DO_BUILD" == "1" ]]; then
  forge build >/dev/null
fi

CONTRACTS=(
  "StrategyVaultV2:strategyVaultV2Abi:strategyVaultV2"
  "StrategyFactoryV2:strategyFactoryV2Abi:strategyFactoryV2"
  "StrategyTokenV2:strategyTokenV2Abi:strategyTokenV2"
  "MarketplaceRegistryV2:marketplaceRegistryV2Abi:marketplaceRegistryV2"
  "SocialRegistry:socialRegistryAbi:socialRegistry"
  "RebalanceEngineV2:rebalanceEngineV2Abi:rebalanceEngineV2"
  "StrategyLens:strategyLensAbi:strategyLens"
  "OracleDesk:oracleDeskAbi:oracleDesk"
  "ChainlinkPriceOracleV2:chainlinkPriceOracleV2Abi:chainlinkPriceOracleV2"
  "FengAggregator:fengAggregatorAbi:fengAggregator"
  "FengFaucet:fengFaucetAbi:fengFaucet"
  "MockUSDGV2:mockUsdgV2Abi:mockUsdgV2"
  "MockStockToken:mockStockTokenAbi:mockStockToken"
  "StrategyVault:strategyVaultAbi:strategyVault"
  "StrategyFactory:strategyFactoryAbi:strategyFactory"
  "StrategyToken:strategyTokenAbi:strategyToken"
  "MarketplaceRegistry:marketplaceRegistryAbi:marketplaceRegistry"
  "RebalanceEngine:rebalanceEngineAbi:rebalanceEngine"
  "ChainlinkPriceOracle:chainlinkPriceOracleAbi:chainlinkPriceOracle"
  "MockUSDG:mockUsdgAbi:mockUsdg"
  "MockV3Aggregator:mockV3AggregatorAbi:mockV3Aggregator"
)

DEST="$(mktemp -d)"
trap 'rm -rf "$DEST"' EXIT

BARREL=""
for entry in "${CONTRACTS[@]}"; do
  IFS=":" read -r NAME EXPORT FILE <<<"$entry"
  ARTIFACT="$OUT_DIR/$NAME.sol/$NAME.json"
  if [[ ! -f "$ARTIFACT" ]]; then
    echo "Missing artifact for $NAME at $ARTIFACT. Run forge build first." >&2
    exit 1
  fi
  LENGTH="$(jq '.abi | length' "$ARTIFACT")"
  if [[ "$LENGTH" == "0" || "$LENGTH" == "null" ]]; then
    echo "Empty ABI for $NAME at $ARTIFACT." >&2
    exit 1
  fi
  printf 'export const %s = %s as const;\n' "$EXPORT" "$(jq --indent 2 '.abi' "$ARTIFACT")" >"$DEST/$FILE.ts"
  BARREL+="export { $EXPORT } from \"./$FILE\";"$'\n'
done
printf '%s' "$BARREL" >"$DEST/index.ts"

if [[ "$MODE" == "check" ]]; then
  if [[ ! -d "$TARGET_DIR" ]] || ! diff -r "$DEST" "$TARGET_DIR" >/dev/null; then
    echo "$TARGET_DIR is out of date. Run scripts/sync-abi.sh." >&2
    exit 1
  fi
  echo "$TARGET_DIR is up to date."
  exit 0
fi

mkdir -p "$TARGET_DIR"
find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.ts' -delete
cp "$DEST"/*.ts "$TARGET_DIR"/
echo "Wrote ${#CONTRACTS[@]} ABI modules to $TARGET_DIR"
