export const rebalanceEngineAbi = [
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
] as const;
