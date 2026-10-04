export const strategyFactoryAbi = [
  {
    type: "function",
    name: "createStrategy",
    stateMutability: "nonpayable",
    inputs: [
      { name: "name", type: "string" },
      { name: "symbol", type: "string" },
      {
        name: "constituents",
        type: "tuple[]",
        components: [
          { name: "token", type: "address" },
          { name: "targetWeightBps", type: "uint16" },
          { name: "isStrategyToken", type: "bool" },
        ],
      },
      { name: "maxWeightBps", type: "uint16" },
      { name: "rebalanceInterval", type: "uint256" },
    ],
    outputs: [
      { name: "vault", type: "address" },
      { name: "token", type: "address" },
    ],
  },
  {
    type: "event",
    name: "StrategyCreated",
    inputs: [
      { name: "vault", type: "address", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "creator", type: "address", indexed: true },
      { name: "depth", type: "uint8", indexed: false },
    ],
    anonymous: false,
  },
] as const;
