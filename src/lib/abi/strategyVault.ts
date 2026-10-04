const constituentTuple = {
  type: "tuple[]",
  name: "",
  components: [
    { name: "token", type: "address" },
    { name: "targetWeightBps", type: "uint16" },
    { name: "isStrategyToken", type: "bool" },
  ],
} as const;

export const strategyVaultAbi = [
  {
    type: "function",
    name: "deposit",
    stateMutability: "nonpayable",
    inputs: [
      { name: "usdgAmount", type: "uint256" },
      { name: "receiver", type: "address" },
    ],
    outputs: [{ name: "shares", type: "uint256" }],
  },
  {
    type: "function",
    name: "redeem",
    stateMutability: "nonpayable",
    inputs: [
      { name: "shares", type: "uint256" },
      { name: "receiver", type: "address" },
      { name: "owner", type: "address" },
    ],
    outputs: [{ name: "usdgAmount", type: "uint256" }],
  },
  {
    type: "function",
    name: "previewDeposit",
    stateMutability: "view",
    inputs: [{ name: "usdgAmount", type: "uint256" }],
    outputs: [{ name: "shares", type: "uint256" }],
  },
  {
    type: "function",
    name: "previewRedeem",
    stateMutability: "view",
    inputs: [{ name: "shares", type: "uint256" }],
    outputs: [{ name: "usdgAmount", type: "uint256" }],
  },
  {
    type: "function",
    name: "totalAssetsUSDG",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "getConstituents",
    stateMutability: "view",
    inputs: [],
    outputs: [constituentTuple],
  },
  {
    type: "function",
    name: "depth",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "rebalanceNeeded",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "timeBased", type: "bool" },
      { name: "thresholdBased", type: "bool" },
    ],
  },
  {
    type: "function",
    name: "executeRebalance",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
  {
    type: "event",
    name: "Deposit",
    inputs: [
      { name: "sender", type: "address", indexed: true },
      { name: "receiver", type: "address", indexed: true },
      { name: "usdgAmount", type: "uint256", indexed: false },
      { name: "shares", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Redeem",
    inputs: [
      { name: "sender", type: "address", indexed: true },
      { name: "receiver", type: "address", indexed: true },
      { name: "owner", type: "address", indexed: true },
      { name: "shares", type: "uint256", indexed: false },
      { name: "usdgAmount", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Rebalanced",
    inputs: [
      { name: "timestamp", type: "uint256", indexed: true },
      { name: "timeBased", type: "bool", indexed: false },
      { name: "thresholdBased", type: "bool", indexed: false },
    ],
    anonymous: false,
  },
] as const;

export type Constituent = {
  token: `0x${string}`;
  targetWeightBps: number;
  isStrategyToken: boolean;
};
