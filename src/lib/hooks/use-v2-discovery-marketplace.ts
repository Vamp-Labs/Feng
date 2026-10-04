"use client";

import { useMemo } from "react";
import { useReadContracts } from "wagmi";
import type { Address } from "viem";
import { erc20Abi } from "@/lib/abi";
import { sinceInceptionFromVault } from "@/lib/inception";
import { usdgToNumber } from "@/lib/discovery-format";
import { universeOfVault, v2Abis, ZERO_ADDRESS } from "@/lib/protocol";
import { useContracts } from "@/lib/use-contracts";
import type { MarketplaceData, StrategySummary } from "@/lib/hooks/use-marketplace";
import { MAX_STRATEGIES, PAGE_SIZE, POLL_MS, readCall, readNumber, readValue } from "@/lib/hooks/use-v2-discovery-shared";

interface StrategyInfoV2 {
  vault: Address;
  token: Address;
  creator: Address;
  depth: number;
  createdAt: bigint;
  description: string;
  tags: readonly string[];
}

const VAULT_READS = 5;

export function useMarketplaceStrategiesV2(): MarketplaceData {
  const { addresses } = useContracts();
  const registry = { address: addresses.marketplaceRegistry, abi: v2Abis.registry } as const;
  const liveFactory = addresses.live && addresses.live.strategyFactory !== ZERO_ADDRESS ? addresses.live.strategyFactory : undefined;

  const firstPage = useReadContracts({
    contracts: [
      readCall(registry.address, registry.abi, "strategyCount"),
      readCall(registry.address, registry.abi, "getStrategies", [0n, BigInt(PAGE_SIZE)]),
    ],
  });

  const count = readValue<bigint>(firstPage.data?.[0]);
  const firstVaults = readValue<readonly Address[]>(firstPage.data?.[1]);

  const extraOffsets = useMemo(() => {
    if (count === undefined) return [];
    const total = Math.min(Number(count), MAX_STRATEGIES);
    const offsets: number[] = [];
    for (let offset = PAGE_SIZE; offset < total; offset += PAGE_SIZE) offsets.push(offset);
    return offsets;
  }, [count]);

  const extraPages = useReadContracts({
    contracts: extraOffsets.map((offset) =>
      readCall(registry.address, registry.abi, "getStrategies", [BigInt(offset), BigInt(PAGE_SIZE)]),
    ),
    query: { enabled: extraOffsets.length > 0 },
  });

  const vaults = useMemo<Address[]>(() => {
    const rest = extraPages.data?.flatMap((entry) => readValue<readonly Address[]>(entry) ?? []) ?? [];
    return [...(firstVaults ?? []), ...rest];
  }, [firstVaults, extraPages.data]);

  const stateQuery = useReadContracts({
    contracts: vaults.flatMap((vault) => [
      readCall(registry.address, registry.abi, "getStrategyInfoV2", [vault]),
      readCall(vault, v2Abis.vault, "totalAssetsUSDG"),
      readCall(vault, v2Abis.vault, "sharePrice"),
      readCall(vault, v2Abis.vault, "inceptionSharePrice"),
      readCall(vault, v2Abis.vault, "usdgDecimals"),
    ]),
    query: { enabled: vaults.length > 0, refetchInterval: POLL_MS },
  });

  const infos = useMemo(
    () => vaults.map((_, index) => readValue<StrategyInfoV2>(stateQuery.data?.[index * VAULT_READS])),
    [vaults, stateQuery.data],
  );

  const tokensKnown = vaults.length > 0 && stateQuery.data !== undefined;
  const perVaultMeta = liveFactory ? 3 : 2;

  const metaQuery = useReadContracts({
    contracts: infos.flatMap((info) => {
      if (!info) return [];
      return [
        readCall(info.token, erc20Abi, "name"),
        readCall(info.token, erc20Abi, "symbol"),
        ...(liveFactory ? [readCall(liveFactory, v2Abis.factory, "vaultOf", [info.token])] : []),
      ];
    }),
    query: { enabled: tokensKnown && infos.some((info) => info !== undefined), staleTime: 60_000 },
  });

  const strategies = useMemo<StrategySummary[]>(() => {
    const items: StrategySummary[] = [];
    let metaIndex = 0;
    vaults.forEach((vault, index) => {
      const info = infos[index];
      if (!info) return;
      const base = index * VAULT_READS;
      const data = stateQuery.data;
      const totalAssetsUSDG = readValue<bigint>(data?.[base + 1]);
      const sharePrice = readValue<bigint>(data?.[base + 2]);
      const inceptionSharePrice = readValue<bigint>(data?.[base + 3]);
      const usdgDecimals = readNumber(data?.[base + 4]);
      const meta = metaQuery.data;
      const name = readValue<string>(meta?.[metaIndex]);
      const symbol = readValue<string>(meta?.[metaIndex + 1]);
      const liveVault = liveFactory ? readValue<Address>(meta?.[metaIndex + 2]) : undefined;
      metaIndex += perVaultMeta;
      const isLive =
        (liveVault !== undefined && liveVault.toLowerCase() === vault.toLowerCase()) ||
        universeOfVault(addresses, vault) === "live";

      items.push({
        vault,
        token: info.token,
        creator: info.creator,
        depth: Number(info.depth),
        createdAt: BigInt(info.createdAt),
        description: info.description,
        tags: info.tags,
        universe: isLive ? "live" : "sandbox",
        totalAssetsUSDG,
        usdgDecimals,
        navUsd: totalAssetsUSDG !== undefined && usdgDecimals !== undefined ? usdgToNumber(totalAssetsUSDG, usdgDecimals) : undefined,
        sharePrice,
        inceptionSharePrice,
        sinceInception: sinceInceptionFromVault(sharePrice, inceptionSharePrice),
        name,
        symbol,
      });
    });
    return items;
  }, [vaults, infos, stateQuery.data, metaQuery.data, perVaultMeta, liveFactory, addresses]);

  const error = firstPage.error ?? extraPages.error ?? stateQuery.error;
  const firstFailed = firstPage.isSuccess && firstVaults === undefined;

  return {
    strategies,
    isLoading: firstPage.isLoading || (vaults.length > 0 && stateQuery.isLoading),
    isEmpty: firstPage.isSuccess && !firstFailed && vaults.length === 0,
    error: error ?? (firstFailed ? new Error("The registry did not return its strategy list.") : null),
    isRetrying: firstPage.failureCount > 0 || stateQuery.failureCount > 0,
    refetch: () => {
      firstPage.refetch();
      extraPages.refetch();
      stateQuery.refetch();
      metaQuery.refetch();
    },
  };
}
