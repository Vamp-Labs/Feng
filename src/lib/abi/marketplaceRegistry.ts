export const marketplaceRegistryAbi = [
  {
    type: "function",
    name: "registerStrategy",
    stateMutability: "nonpayable",
    inputs: [
      { name: "vault", type: "address" },
      { name: "token", type: "address" },
      { name: "creator", type: "address" },
    ],
    outputs: [],
  },
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
  {
    type: "event",
    name: "StrategyRegistered",
    inputs: [
      { name: "vault", type: "address", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "creator", type: "address", indexed: true },
    ],
    anonymous: false,
  },
] as const;
