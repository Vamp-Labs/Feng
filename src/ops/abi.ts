import { fengAggregatorAbi } from "../lib/abi/generated/fengAggregator";
import { fengFaucetAbi } from "../lib/abi/generated/fengFaucet";
import { marketplaceRegistryV2Abi } from "../lib/abi/generated/marketplaceRegistryV2";
import { oracleDeskAbi } from "../lib/abi/generated/oracleDesk";
import { rebalanceEngineV2Abi } from "../lib/abi/generated/rebalanceEngineV2";
import { strategyVaultV2Abi } from "../lib/abi/generated/strategyVaultV2";

export { fengAggregatorAbi, fengFaucetAbi, marketplaceRegistryV2Abi, oracleDeskAbi, strategyVaultV2Abi };

export const aggregatorAbi = [
  {
    type: "function",
    name: "latestRoundData",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "roundId", type: "uint80" },
      { name: "answer", type: "int256" },
      { name: "startedAt", type: "uint256" },
      { name: "updatedAt", type: "uint256" },
      { name: "answeredInRound", type: "uint80" },
    ],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
] as const;

export const mockAggregatorWriteAbi = [
  {
    type: "function",
    name: "updateAnswer",
    stateMutability: "nonpayable",
    inputs: [{ name: "answer", type: "int256" }],
    outputs: [],
  },
] as const;

export const vaultErrorsAbi = [
  { type: "error", name: "StalePrice", inputs: [{ name: "token", type: "address" }, { name: "updatedAt", type: "uint256" }] },
  { type: "error", name: "SlippageExceeded", inputs: [{ name: "got", type: "uint256" }, { name: "min", type: "uint256" }] },
  { type: "error", name: "InsufficientLiquidity", inputs: [{ name: "token", type: "address" }] },
  { type: "error", name: "VenueSlippage", inputs: [{ name: "got", type: "uint256" }, { name: "min", type: "uint256" }] },
  { type: "error", name: "SwapTooLarge", inputs: [{ name: "usdgAmount", type: "uint256" }, { name: "maxSwapUsdg", type: "uint256" }] },
  { type: "error", name: "CheckpointTooSoon", inputs: [{ name: "nextAllowedAt", type: "uint256" }] },
  { type: "error", name: "ExceedsMaxWeight", inputs: [{ name: "token", type: "address" }] },
  { type: "error", name: "EnforcedPause", inputs: [] },
  { type: "error", name: "RebalanceNotNeeded", inputs: [] },
] as const;

export const engineV2Abi = [...rebalanceEngineV2Abi, ...vaultErrorsAbi] as const;

export const engineAbi = [
  {
    type: "function",
    name: "checkUpkeep",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "vaultsNeedingRebalance", type: "address[]" }],
  },
  {
    type: "function",
    name: "performRebalance",
    stateMutability: "nonpayable",
    inputs: [{ name: "vault", type: "address" }],
    outputs: [],
  },
  {
    type: "error",
    name: "StalePrice",
    inputs: [
      { name: "token", type: "address" },
      { name: "updatedAt", type: "uint256" },
    ],
  },
  {
    type: "error",
    name: "RebalanceNotNeeded",
    inputs: [{ name: "vault", type: "address" }],
  },
  {
    type: "error",
    name: "RebalanceNotNeeded",
    inputs: [],
  },
] as const;

export const registryAbi = [
  {
    type: "function",
    name: "getAllStrategies",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "vaults", type: "address[]" }],
  },
  {
    type: "function",
    name: "getStrategyInfo",
    stateMutability: "view",
    inputs: [{ name: "vault", type: "address" }],
    outputs: [
      { name: "token", type: "address" },
      { name: "creator", type: "address" },
      { name: "depth", type: "uint8" },
      { name: "createdAt", type: "uint256" },
    ],
  },
] as const;

export const vaultStateAbi = [
  {
    type: "function",
    name: "lastRebalanceTimestamp",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

export const tokenAbi = [
  {
    type: "function",
    name: "symbol",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "transfer",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "event",
    name: "Transfer",
    inputs: [
      { name: "from", type: "address", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "value", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
] as const;

export const multicallAbi = [
  {
    type: "function",
    name: "getCurrentBlockTimestamp",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "timestamp", type: "uint256" }],
  },
  {
    type: "function",
    name: "getEthBalance",
    stateMutability: "view",
    inputs: [{ name: "addr", type: "address" }],
    outputs: [{ name: "balance", type: "uint256" }],
  },
  {
    type: "function",
    name: "getBlockNumber",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "blockNumber", type: "uint256" }],
  },
] as const;
