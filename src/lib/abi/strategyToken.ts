import { erc20Abi } from "@/lib/abi/erc20";

export const strategyTokenAbi = [
  ...erc20Abi,
  {
    type: "function",
    name: "vault",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
] as const;
