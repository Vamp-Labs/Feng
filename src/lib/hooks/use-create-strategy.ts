"use client";

import { useCallback, useMemo } from "react";
import { parseEventLogs } from "viem";
import { strategyFactoryAbi } from "@/lib/abi";
import { useTxFlow } from "@/lib/hooks/use-tx-flow";
import { IS_V2, universeAddresses, v2Abis, type Universe } from "@/lib/protocol";
import { useContracts } from "@/lib/use-contracts";

export interface CreateConstituent {
  token: `0x${string}`;
  targetWeightBps: number;
  isStrategyToken: boolean;
}

export interface CreateStrategyInput {
  name: string;
  symbol: string;
  constituents: CreateConstituent[];
  maxWeightBps: number;
  intervalSeconds: number;
  maxSlippageBps: number;
  description: string;
  tags: string[];
  universe: Universe;
}

export function useCreateStrategy() {
  const { addresses } = useContracts();
  const flow = useTxFlow();

  const create = useCallback(
    (input: CreateStrategyInput) => {
      if (!IS_V2) {
        return flow.send({
          address: addresses.strategyFactory,
          abi: strategyFactoryAbi,
          functionName: "createStrategy",
          args: [input.name, input.symbol, input.constituents, input.maxWeightBps, BigInt(input.intervalSeconds)],
        });
      }
      const scope = universeAddresses(addresses, input.universe);
      return flow.send({
        address: scope.strategyFactory,
        abi: v2Abis.factory,
        functionName: "createStrategy",
        args: [
          input.name,
          input.symbol,
          input.constituents,
          input.maxWeightBps,
          BigInt(input.intervalSeconds),
          input.maxSlippageBps,
          { description: input.description, tags: input.tags },
        ],
      });
    },
    [addresses, flow],
  );

  const vault = useMemo(() => {
    if (!flow.receipt) return undefined;
    const events = IS_V2
      ? parseEventLogs({ abi: v2Abis.factory, logs: flow.receipt.logs, eventName: "StrategyCreated" })
      : parseEventLogs({ abi: strategyFactoryAbi, logs: flow.receipt.logs, eventName: "StrategyCreated" });
    return events[0]?.args.vault;
  }, [flow.receipt]);

  return { create, status: flow.status, error: flow.error, failure: flow.failure, vault, reset: flow.reset };
}
