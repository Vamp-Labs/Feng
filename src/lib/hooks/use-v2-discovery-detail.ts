"use client";

import { useMemo } from "react";
import { useReadContracts } from "wagmi";
import type { Address } from "viem";
import { erc20Abi } from "@/lib/abi";
import { strategyTokenV2Abi } from "@/lib/abi/generated";
import { usdgToNumber } from "@/lib/discovery-format";
import { sinceInceptionFromVault } from "@/lib/inception";
import { universeOfVault, v2Abis, ZERO_ADDRESS } from "@/lib/protocol";
import { useContracts } from "@/lib/use-contracts";
import type { ConstituentDetail, StrategyDetailData } from "@/lib/hooks/use-strategy-detail";
import { readCall, readError, readNumber, readValue } from "@/lib/hooks/use-v2-discovery-shared";

interface StrategyInfoV2 {
  vault: Address;
  token: Address;
  creator: Address;
  depth: number;
  createdAt: bigint;
  description: string;
  tags: readonly string[];
}

interface RawConstituent {
  token: Address;
  targetWeightBps: number;
  isStrategyToken: boolean;
}

const LIVE_POLL_MS = 20_000;
const BPS = 10_000;
const CHILD_READS = 4;
const CONSTITUENT_READS = 4;

export function useStrategyDetailV2(vault: Address | undefined): StrategyDetailData {
  const { addresses } = useContracts();
  const enabled = Boolean(vault);
  const registry = { address: addresses.marketplaceRegistry, abi: v2Abis.registry } as const;
  const liveFactory = addresses.live && addresses.live.strategyFactory !== ZERO_ADDRESS ? addresses.live.strategyFactory : undefined;

  const coreQuery = useReadContracts({
    contracts: vault
      ? [
          readCall(registry.address, registry.abi, "getStrategyInfoV2", [vault]),
          readCall(vault, v2Abis.vault, "totalAssetsUSDG"),
          readCall(vault, v2Abis.vault, "sharePrice"),
          readCall(vault, v2Abis.vault, "inceptionSharePrice"),
          readCall(vault, v2Abis.vault, "weights"),
          readCall(vault, v2Abis.vault, "getConstituents"),
          readCall(vault, v2Abis.vault, "rebalanceNeeded"),
          readCall(vault, v2Abis.vault, "priceStatus"),
          readCall(vault, v2Abis.vault, "maxWeightBps"),
          readCall(vault, v2Abis.vault, "rebalanceInterval"),
          readCall(vault, v2Abis.vault, "lastRebalanceTimestamp"),
          readCall(vault, v2Abis.vault, "usdgDecimals"),
          readCall(vault, v2Abis.vault, "maxPriceStaleness"),
          readCall(vault, v2Abis.vault, "paused"),
          readCall(vault, v2Abis.vault, "depth"),
        ]
      : [],
    query: { enabled, refetchInterval: LIVE_POLL_MS },
  });

  const info = readValue<StrategyInfoV2>(coreQuery.data?.[0]);
  const token = info?.token;

  const rawConstituents = useMemo<RawConstituent[]>(() => {
    const raw = readValue<readonly RawConstituent[]>(coreQuery.data?.[5]);
    return raw ? raw.map((c) => ({ token: c.token, targetWeightBps: Number(c.targetWeightBps), isStrategyToken: c.isStrategyToken })) : [];
  }, [coreQuery.data]);

  const metaQuery = useReadContracts({
    contracts:
      vault && token
        ? [
            readCall(token, erc20Abi, "name"),
            readCall(token, erc20Abi, "symbol"),
            readCall(token, erc20Abi, "decimals"),
            ...(liveFactory ? [readCall(liveFactory, v2Abis.factory, "vaultOf", [token])] : []),
            ...rawConstituents.flatMap((constituent, index) => [
              readCall(constituent.token, erc20Abi, "name"),
              readCall(constituent.token, erc20Abi, "symbol"),
              readCall(vault, v2Abis.vault, "effectiveMaxWeightBps", [BigInt(index)]),
              readCall(constituent.token, strategyTokenV2Abi, "vault"),
            ]),
          ]
        : [],
    query: { enabled: Boolean(vault && token && rawConstituents.length > 0), refetchInterval: LIVE_POLL_MS * 3 },
  });

  const metaBase = liveFactory ? 4 : 3;

  const nestedVaults = useMemo(
    () =>
      rawConstituents.map((constituent, index) =>
        constituent.isStrategyToken
          ? readValue<Address>(metaQuery.data?.[metaBase + index * CONSTITUENT_READS + 3])
          : undefined,
      ),
    [rawConstituents, metaQuery.data, metaBase],
  );

  const childList = useMemo(() => nestedVaults.filter((nested): nested is Address => nested !== undefined), [nestedVaults]);

  const childQuery = useReadContracts({
    contracts: childList.flatMap((child) => [
      readCall(child, v2Abis.vault, "totalAssetsUSDG"),
      readCall(child, v2Abis.vault, "sharePrice"),
      readCall(child, v2Abis.vault, "inceptionSharePrice"),
      readCall(child, v2Abis.vault, "usdgDecimals"),
    ]),
    query: { enabled: childList.length > 0, refetchInterval: LIVE_POLL_MS * 3 },
  });

  const totalAssetsUSDG = readValue<bigint>(coreQuery.data?.[1]);
  const sharePrice = readValue<bigint>(coreQuery.data?.[2]);
  const inceptionSharePrice = readValue<bigint>(coreQuery.data?.[3]);
  const weightsRaw = readValue<readonly number[]>(coreQuery.data?.[4]);
  const rebalanceFlags = readValue<readonly [boolean, boolean]>(coreQuery.data?.[6]);
  const priceStatusRaw = readValue<readonly [boolean, bigint]>(coreQuery.data?.[7]);
  const usdgDecimals = readNumber(coreQuery.data?.[11]);

  const weights = useMemo(() => weightsRaw?.map((value) => Number(value)), [weightsRaw]);

  const constituents = useMemo<ConstituentDetail[]>(() => {
    return rawConstituents.map((constituent, index) => {
      const base = metaBase + index * CONSTITUENT_READS;
      const meta = metaQuery.data;
      const nestedVault = nestedVaults[index];
      let childNavUsd: number | undefined;
      let childSharePrice: bigint | undefined;
      let childSinceInception: number | undefined;
      if (nestedVault) {
        const childBase = childList.indexOf(nestedVault) * CHILD_READS;
        const childData = childQuery.data;
        const childAssets = readValue<bigint>(childData?.[childBase]);
        const childDecimals = readNumber(childData?.[childBase + 3]);
        childSharePrice = readValue<bigint>(childData?.[childBase + 1]);
        childSinceInception = sinceInceptionFromVault(childSharePrice, readValue<bigint>(childData?.[childBase + 2]));
        childNavUsd =
          childAssets !== undefined && childDecimals !== undefined ? usdgToNumber(childAssets, childDecimals) : undefined;
      }
      const effectiveMax = readNumber(meta?.[base + 2]);
      return {
        ...constituent,
        name: readValue<string>(meta?.[base]),
        symbol: readValue<string>(meta?.[base + 1]),
        nestedVault,
        currentBps: weights?.[index],
        effectiveMaxBps: effectiveMax,
        childNavUsd,
        childSharePrice,
        childSinceInception,
      };
    });
  }, [rawConstituents, metaQuery.data, nestedVaults, childList, childQuery.data, weights, metaBase]);

  const idleBps = useMemo(() => {
    if (!weights || weights.length === 0) return undefined;
    return Math.max(0, BPS - weights.reduce((sum, value) => sum + value, 0));
  }, [weights]);

  const liveByVault = liveFactory ? readValue<Address>(metaQuery.data?.[3]) : undefined;
  const isLive =
    vault !== undefined &&
    ((liveByVault !== undefined && liveByVault.toLowerCase() === vault.toLowerCase()) || universeOfVault(addresses, vault) === "live");

  const registryError = readError(coreQuery.data?.[0]);

  return {
    token,
    creator: info?.creator,
    createdAt: info?.createdAt,
    depth: info ? Number(info.depth) : readNumber(coreQuery.data?.[14]),
    totalAssetsUSDG,
    sinceInception: sinceInceptionFromVault(sharePrice, inceptionSharePrice),
    constituents,
    rebalanceNeeded: rebalanceFlags ? { timeBased: rebalanceFlags[0], thresholdBased: rebalanceFlags[1] } : undefined,
    name: readValue<string>(metaQuery.data?.[0]),
    symbol: readValue<string>(metaQuery.data?.[1]),
    decimals: readNumber(metaQuery.data?.[2]),
    isLoading: coreQuery.isLoading,
    error: coreQuery.error ?? registryError,
    isRetrying: coreQuery.failureCount > 0,
    refetch: () => {
      coreQuery.refetch();
      metaQuery.refetch();
      childQuery.refetch();
    },
    v2: {
      description: info?.description,
      tags: info?.tags ?? [],
      universe: isLive ? "live" : "sandbox",
      usdgDecimals,
      navUsd: totalAssetsUSDG !== undefined && usdgDecimals !== undefined ? usdgToNumber(totalAssetsUSDG, usdgDecimals) : undefined,
      sharePrice,
      inceptionSharePrice,
      weights,
      idleBps,
      maxWeightBps: readNumber(coreQuery.data?.[8]),
      rebalanceInterval: readNumber(coreQuery.data?.[9]),
      lastRebalanceTimestamp: readNumber(coreQuery.data?.[10]),
      maxPriceStaleness: readNumber(coreQuery.data?.[12]),
      paused: readValue<boolean>(coreQuery.data?.[13]),
      priceFresh: priceStatusRaw ? priceStatusRaw[0] : undefined,
      oldestPriceUpdatedAt: priceStatusRaw ? Number(priceStatusRaw[1]) : undefined,
    },
  };
}
