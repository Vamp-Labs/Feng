#!/usr/bin/env bash
set -euo pipefail

NETWORK="${1:-}"
STEP="${2:-all}"
MAX_ATTEMPTS="${DEPLOY_MAX_ATTEMPTS:-8}"

usage() {
  echo "Usage: scripts/deploy-v2.sh <robinhood-testnet|dry> [deploy|seed|all|live-deploy|live-seed|live]" >&2
  echo "  live-deploy: second OracleDesk (inventory mode) and second StrategyFactoryV2 on the real faucet stock tokens and Paxos USDG." >&2
  echo "  live-seed:   LIVE-AI, LIVE-5, LIVE-CORE sized from the deployer's actual real balances. live runs both." >&2
  echo "  dry spawns a throwaway local anvil, uses anvil's public default account and removes its outputs." >&2
}

if [[ -z "$NETWORK" ]]; then
  usage
  exit 1
fi

if [[ "$NETWORK" != "robinhood-testnet" && "$NETWORK" != "dry" ]]; then
  echo "Unknown network: $NETWORK" >&2
  usage
  exit 1
fi

if [[ "$STEP" != "deploy" && "$STEP" != "seed" && "$STEP" != "all" && "$STEP" != "live-deploy" && "$STEP" != "live-seed" && "$STEP" != "live" ]]; then
  echo "Unknown step: $STEP" >&2
  usage
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for tool in forge cast jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required but not installed." >&2
    exit 1
  fi
done

ANVIL_PID=""
cleanup() {
  if [[ -n "$ANVIL_PID" ]]; then
    kill "$ANVIL_PID" >/dev/null 2>&1 || true
  fi
  if [[ "$NETWORK" == "dry" && "${KEEP_DRY_OUTPUT:-0}" != "1" ]]; then
    rm -rf "deployments/$DEPLOY_NETWORK-v2" "$FOUNDRY_BROADCAST"
  fi
}

if [[ "$NETWORK" == "dry" ]]; then
  DEPLOY_NETWORK="dry-local"
  FOUNDRY_BROADCAST="${DRY_BROADCAST_DIR:-$(mktemp -d)}"
  export FOUNDRY_BROADCAST
  trap cleanup EXIT
  if [[ -n "${DRY_RPC_URL:-}" ]]; then
    if [[ ! "$DRY_RPC_URL" =~ ^http://(127\.0\.0\.1|localhost):([0-9]{1,5})/?$ ]] || (( 10#${BASH_REMATCH[2]} < 1 || 10#${BASH_REMATCH[2]} > 65535 )); then
      echo "DRY_RPC_URL must be exactly http://127.0.0.1:<port> or http://localhost:<port> (a local anvil)." >&2
      exit 1
    fi
    RPC_URL="${DRY_RPC_URL%/}"
  else
    command -v anvil >/dev/null 2>&1 || { echo "anvil is required for dry mode." >&2; exit 1; }
    ANVIL_PORT="${ANVIL_PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')}"
    RPC_URL="http://127.0.0.1:$ANVIL_PORT"
    read -r -a anvil_extra <<<"${ANVIL_EXTRA_ARGS:-}"
    anvil --port "$ANVIL_PORT" --silent "${anvil_extra[@]}" >/dev/null 2>&1 &
    ANVIL_PID=$!
  fi
  DEPLOYER_PRIVATE_KEY="$(cast wallet private-key --mnemonic 'test test test test test test test test test test test junk')"
  export DEPLOYER_PRIVATE_KEY
  for _ in $(seq 1 50); do
    if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done
else
  DEPLOY_NETWORK="$NETWORK"
  RPC_URL="${ROBINHOOD_TESTNET_RPC_URL:-https://rpc.testnet.chain.robinhood.com}"
  if [[ -z "${DEPLOYER_PRIVATE_KEY:-}" ]]; then
    echo "DEPLOYER_PRIVATE_KEY is not set. Export a testnet-only key before running this script." >&2
    exit 1
  fi
  if [[ "$STEP" == "deploy" || "$STEP" == "all" ]]; then
    if [[ -z "${RELAYER_ADDRESS:-}" ]]; then
      echo "RELAYER_ADDRESS is not set. Export the public address of the relayer wallet (it must differ from the deployer)." >&2
      exit 1
    fi
    if [[ -z "${FAUCET_ADDRESS:-${FAUCET_DISPENSER_ADDRESS:-}}" ]]; then
      echo "FAUCET_ADDRESS is not set. Export the public address of the faucet dispenser wallet (it must differ from the deployer)." >&2
      exit 1
    fi
  fi
fi

export DEPLOY_NETWORK
export LIVE_USDG="${LIVE_USDG:-0x7E955252E15c84f5768B83c41a71F9eba181802F}"
export LIVE_TOKEN_AMZN="${LIVE_TOKEN_AMZN:-0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02}"
export LIVE_TOKEN_TSLA="${LIVE_TOKEN_TSLA:-0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E}"
export LIVE_TOKEN_AMD="${LIVE_TOKEN_AMD:-0x71178BAc73cBeb415514eB542a8995b82669778d}"
export LIVE_TOKEN_PLTR="${LIVE_TOKEN_PLTR:-0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0}"
export LIVE_TOKEN_NFLX="${LIVE_TOKEN_NFLX:-0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93}"

ADDR_FILE="deployments/$DEPLOY_NETWORK-v2/addresses.json"

retry() {
  local attempt=1
  until "$@"; do
    if (( attempt >= MAX_ATTEMPTS )); then
      return 1
    fi
    echo "Command failed, retrying ($((attempt + 1))/$MAX_ATTEMPTS)..." >&2
    attempt=$((attempt + 1))
    sleep 3
  done
}

RPC_HOST="${RPC_URL#*://}"
RPC_HOST="${RPC_HOST%%[/?#]*}"
RPC_HOST="${RPC_HOST##*@}"

CHAIN_ID=""
if ! CHAIN_ID="$(retry cast chain-id --rpc-url "$RPC_URL" 2>/dev/null)"; then
  echo "Cannot reach the RPC at $RPC_HOST after $MAX_ATTEMPTS attempts." >&2
  exit 1
fi

echo "Network: $DEPLOY_NETWORK (chain $CHAIN_ID) via $RPC_HOST"
echo "Retry budget: $MAX_ATTEMPTS attempts (rpc.testnet.chain.robinhood.com has shown intermittent"
echo "TLS interception from some network paths, see docs/handoffs/DEMO-NOTES.md)"

run_script() {
  local script_file="$1"
  local script_name
  script_name="$(basename "$script_file")"
  export WRITE_ADDRESSES=true
  local run_file="${FOUNDRY_BROADCAST:-broadcast}/$script_name/$CHAIN_ID/run-latest.json"
  local before="none"
  if [[ -f "$run_file" ]]; then
    before="$(sha256sum "$run_file" | cut -d' ' -f1)"
  fi

  local attempt=1
  local resume=0
  while true; do
    local args=(script "$script_file" --rpc-url "$RPC_URL" --broadcast --slow -vv)
    if [[ "$script_name" == *Live.s.sol ]]; then
      args+=(--hardfork "${LIVE_HARDFORK:-osaka}")
    fi
    if [[ -n "${FORGE_EXTRA_ARGS:-}" ]]; then
      read -r -a extra <<<"$FORGE_EXTRA_ARGS"
      args+=("${extra[@]}")
    fi
    if (( resume == 1 )); then
      args+=(--resume)
    fi
    local out_file
    out_file="$(mktemp)"
    if forge "${args[@]}" 2>&1 | tee "$out_file"; then
      rm -f "$out_file"
      return 0
    fi
    if grep -Eq 'script failed: ((Seed|Deploy)Live: |(RelayerAddressRequired|RelayerAddressIsDeployer|FaucetAddressRequired|FaucetAddressIsDeployer)\()' "$out_file"; then
      rm -f "$out_file"
      echo "$script_name stopped on a precondition (message above). No transaction was sent. Fix it and rerun." >&2
      return 1
    fi
    rm -f "$out_file"
    local after="none"
    if [[ -f "$run_file" ]]; then
      after="$(sha256sum "$run_file" | cut -d' ' -f1)"
    fi
    if (( attempt >= MAX_ATTEMPTS )); then
      echo "$script_name failed after $attempt attempts against $DEPLOY_NETWORK." >&2
      if [[ "$after" != "$before" ]]; then
        echo "A partial broadcast exists at $run_file. Do not rerun from scratch; rerun with the same arguments to resume." >&2
      else
        echo "No transaction was sent." >&2
      fi
      return 1
    fi
    if [[ "$after" != "$before" ]]; then
      resume=1
      echo "Attempt $attempt failed after a partial broadcast, resuming ($((attempt + 1))/$MAX_ATTEMPTS)..." >&2
    else
      echo "Attempt $attempt failed before any transaction was sent, retrying ($((attempt + 1))/$MAX_ATTEMPTS)..." >&2
    fi
    attempt=$((attempt + 1))
    sleep 3
  done
}

has_code() {
  local code
  if ! code="$(retry cast code "$1" --rpc-url "$RPC_URL" 2>/dev/null)" || [[ ! "$code" =~ ^0x[0-9a-fA-F]*$ ]]; then
    echo "Cannot read contract code from the RPC at $RPC_HOST (state unknown). Aborting before any broadcast. Rerun when the endpoint is reachable." >&2
    exit 1
  fi
  [[ "$code" != "0x" ]]
}

if [[ "$STEP" == "deploy" || "$STEP" == "all" ]]; then
  if [[ -f "$ADDR_FILE" && "${REDEPLOY:-0}" != "1" ]]; then
    if has_code "$(jq -r '.usdg' "$ADDR_FILE")"; then
      echo "$ADDR_FILE points at a live deployment. Refusing to broadcast a second one. Set REDEPLOY=1 to deploy a fresh set." >&2
      exit 1
    fi
  fi
  run_script script/DeployV2.s.sol
  echo "Wrote $ADDR_FILE"
fi

if [[ "$STEP" == "seed" || "$STEP" == "all" ]]; then
  if [[ ! -f "$ADDR_FILE" ]]; then
    echo "$ADDR_FILE not found. Run the deploy step first." >&2
    exit 1
  fi
  SEEDED="$(jq -r '.vaults | length' "$ADDR_FILE")"
  if [[ "$SEEDED" != "0" && "${RESEED:-0}" != "1" ]]; then
    if has_code "$(jq -r '.vaults[0].vault' "$ADDR_FILE")"; then
      echo "$ADDR_FILE already lists $SEEDED live vaults. Refusing to seed twice. Set RESEED=1 to create another set." >&2
      exit 1
    fi
  fi
  run_script script/SeedV2.s.sol
  echo "Updated $ADDR_FILE with the seeded vaults"
fi

if [[ "$STEP" == "live-deploy" || "$STEP" == "live" ]]; then
  if [[ ! -f "$ADDR_FILE" ]]; then
    echo "$ADDR_FILE not found. Run the sandbox deploy step first (Live shares its oracle, registry and vault deployer)." >&2
    exit 1
  fi
  if ! has_code "$(jq -r '.oracle' "$ADDR_FILE")"; then
    echo "The sandbox oracle in $ADDR_FILE has no code on this chain. Deploy the sandbox set first." >&2
    exit 1
  fi
  LIVE_FACTORY="$(jq -r '.live.strategyFactory // "0x0000000000000000000000000000000000000000"' "$ADDR_FILE")"
  if [[ "$LIVE_FACTORY" != "0x0000000000000000000000000000000000000000" ]] && has_code "$LIVE_FACTORY"; then
    echo "$ADDR_FILE already lists a live StrategyFactoryV2 on this chain. Refusing to deploy a second Live set." >&2
    exit 1
  fi
  run_script script/DeployLive.s.sol
  echo "Updated $ADDR_FILE with the live desk and factory"
fi

if [[ "$STEP" == "live-seed" || "$STEP" == "live" ]]; then
  if [[ ! -f "$ADDR_FILE" ]]; then
    echo "$ADDR_FILE not found. Run live-deploy first." >&2
    exit 1
  fi
  LIVE_SEEDED="$(jq -r '.live.vaults | length' "$ADDR_FILE")"
  if [[ "$LIVE_SEEDED" != "0" && "${RESEED:-0}" != "1" ]]; then
    if has_code "$(jq -r '.live.vaults[0].vault' "$ADDR_FILE")"; then
      echo "$ADDR_FILE already lists $LIVE_SEEDED live vaults. Refusing to seed twice." >&2
      exit 1
    fi
  fi
  run_script script/SeedLive.s.sol
  echo "Updated $ADDR_FILE with the seeded live vaults"
fi

echo "Done. Public addresses:"
jq -r '
  "usdg                \(.usdg)",
  "oracle              \(.oracle)",
  "venue               \(.venue)",
  "faucet              \(.faucet)",
  "lens                \(.lens)",
  "strategyFactory     \(.strategyFactory)",
  "rebalanceEngine     \(.rebalanceEngine)",
  "marketplaceRegistry \(.marketplaceRegistry)",
  (.vaults[] | "vault \(.symbol) \(.vault)"),
  "live venue          \(.live.venue)",
  "live factory        \(.live.strategyFactory)",
  (.live.vaults[] | "live vault \(.symbol) \(.vault)")
' "$ADDR_FILE"
