"use client";

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { useAccount, usePublicClient } from "wagmi";
import type { Position } from "@/lib/hooks/use-positions";
import { IS_V2 } from "@/lib/protocol";
import {
  averageCostBasis,
  fetchPositionEvents,
  findFirstBlockAtOrAfter,
  positionPnl,
  type PositionPnl,
} from "@/lib/protocol/history";
import { useContracts } from "@/lib/use-contracts";

export function useV2PositionPnl(positions: readonly Position[]) {
  const { address } = useAccount();
  const client = usePublicClient();
  const { addresses } = useContracts();
  const deployedAt = addresses.deployedAt;
  const vaultKey = positions.map((position) => position.vault).join(",");
  const enabled = IS_V2 && Boolean(address) && Boolean(client) && positions.length > 0;

  const fromBlock = useQuery({
    queryKey: ["v2-history-from-block", client?.chain?.id, deployedAt],
    queryFn: async () => (client && deployedAt ? findFirstBlockAtOrAfter(client, deployedAt) : 0n),
    enabled,
    staleTime: Infinity,
    gcTime: Infinity,
  });

  const events = useQuery({
    queryKey: ["v2-history-events", client?.chain?.id, address, vaultKey, fromBlock.data?.toString()],
    queryFn: async () => {
      if (!client || !address) return [];
      return fetchPositionEvents(client, positions.map((position) => position.vault), address, fromBlock.data ?? 0n);
    },
    enabled: enabled && fromBlock.data !== undefined,
    staleTime: 15_000,
  });

  const byVault = useMemo(() => {
    const result: Partial<Record<string, PositionPnl>> = {};
    if (!events.data) return result;
    for (const position of positions) {
      if (position.valueUsdg === undefined) continue;
      const own = events.data.filter((event) => event.vault.toLowerCase() === position.vault.toLowerCase());
      const pnl = positionPnl(averageCostBasis(own), position.balance, position.valueUsdg);
      if (pnl) result[position.vault] = pnl;
    }
    return result;
  }, [events.data, positions]);

  return {
    byVault,
    isLoading: enabled && (fromBlock.isLoading || events.isLoading),
    error: fromBlock.error ?? events.error ?? undefined,
  };
}
