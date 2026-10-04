"use client";

import { useMemo } from "react";
import { useAccount, useReadContracts } from "wagmi";
import type { Address } from "viem";
import { erc20Abi } from "@/lib/abi";
import { universeOfVault, v2Abis, type Universe } from "@/lib/protocol";
import { useContracts } from "@/lib/use-contracts";

export interface V2Constituent {
  token: Address;
  targetWeightBps: number;
  isStrategyToken: boolean;
  symbol?: string;
  decimals: number;
  balance: bigint;
  allowance: bigint;
}

export interface V2VaultInfo {
  usdg?: Address;
  usdgDecimals?: number;
  usdgSymbol?: string;
  usdgBalance: bigint;
  usdgAllowance: bigint;
  maxSlippageBps?: number;
  paused: boolean;
  priceFresh?: boolean;
  oldestUpdatedAt?: bigint;
  sharePrice?: bigint;
  inceptionSharePrice?: bigint;
  navUsdg?: bigint;
  constituents: V2Constituent[];
  universe: Universe;
  shareBalance: bigint;
  isLoading: boolean;
  error?: Error;
}

const DEFAULT_TOKEN_DECIMALS = 18;

export function useV2Vault(vault: Address, shareToken: Address): V2VaultInfo {
  const { address: account } = useAccount();
  const { addresses } = useContracts();

  const core = useReadContracts({
    contracts: [
      { address: vault, abi: v2Abis.vault, functionName: "usdgToken" },
      { address: vault, abi: v2Abis.vault, functionName: "usdgDecimals" },
      { address: vault, abi: v2Abis.vault, functionName: "maxSlippageBps" },
      { address: vault, abi: v2Abis.vault, functionName: "paused" },
      { address: vault, abi: v2Abis.vault, functionName: "priceStatus" },
      { address: vault, abi: v2Abis.vault, functionName: "getConstituents" },
      { address: vault, abi: v2Abis.vault, functionName: "sharePrice" },
      { address: vault, abi: v2Abis.vault, functionName: "inceptionSharePrice" },
      { address: vault, abi: v2Abis.vault, functionName: "totalAssetsUSDG" },
    ],
  });

  const usdg = core.data?.[0]?.status === "success" ? core.data[0].result : undefined;
  const constituentList = useMemo(
    () => (core.data?.[5]?.status === "success" ? core.data[5].result : []),
    [core.data],
  );

  const holder = account ?? vault;
  const holderReads = core.data
    ? [
        ...(usdg
          ? [
              { address: usdg, abi: erc20Abi, functionName: "symbol" as const },
              { address: usdg, abi: erc20Abi, functionName: "balanceOf" as const, args: [holder] as const },
              { address: usdg, abi: erc20Abi, functionName: "allowance" as const, args: [holder, vault] as const },
            ]
          : []),
        { address: shareToken, abi: erc20Abi, functionName: "balanceOf" as const, args: [holder] as const },
        ...constituentList.flatMap((constituent) => [
          { address: constituent.token, abi: erc20Abi, functionName: "symbol" as const },
          { address: constituent.token, abi: erc20Abi, functionName: "decimals" as const },
          { address: constituent.token, abi: erc20Abi, functionName: "balanceOf" as const, args: [holder] as const },
          { address: constituent.token, abi: erc20Abi, functionName: "allowance" as const, args: [holder, vault] as const },
        ]),
      ]
    : [];

  const holders = useReadContracts({ contracts: holderReads, query: { enabled: Boolean(core.data) } });

  return useMemo<V2VaultInfo>(() => {
    const coreData = core.data;
    const read = <T,>(index: number): T | undefined => {
      const entry = coreData?.[index];
      return entry?.status === "success" ? (entry.result as T) : undefined;
    };
    const holderData = holders.data;
    const holderOffset = usdg ? 3 : 0;
    const holderValue = <T,>(index: number): T | undefined => {
      const entry = holderData?.[index];
      return entry?.status === "success" ? (entry.result as T) : undefined;
    };
    const priceStatus = read<readonly [boolean, bigint]>(4);
    const constituents: V2Constituent[] = constituentList.map((constituent, index) => {
      const base = holderOffset + 1 + index * 4;
      return {
        token: constituent.token,
        targetWeightBps: constituent.targetWeightBps,
        isStrategyToken: constituent.isStrategyToken,
        symbol: holderValue<string>(base),
        decimals: Number(holderValue<number>(base + 1) ?? DEFAULT_TOKEN_DECIMALS),
        balance: account ? (holderValue<bigint>(base + 2) ?? 0n) : 0n,
        allowance: account ? (holderValue<bigint>(base + 3) ?? 0n) : 0n,
      };
    });
    return {
      usdg,
      usdgDecimals: read<number>(1) === undefined ? undefined : Number(read<number>(1)),
      usdgSymbol: usdg ? holderValue<string>(0) : undefined,
      usdgBalance: account && usdg ? (holderValue<bigint>(1) ?? 0n) : 0n,
      usdgAllowance: account && usdg ? (holderValue<bigint>(2) ?? 0n) : 0n,
      maxSlippageBps: read<number>(2),
      paused: read<boolean>(3) ?? false,
      priceFresh: priceStatus?.[0],
      oldestUpdatedAt: priceStatus?.[1],
      sharePrice: read<bigint>(6),
      inceptionSharePrice: read<bigint>(7),
      navUsdg: read<bigint>(8),
      constituents,
      universe: universeOfVault(addresses, vault),
      shareBalance: account ? (holderValue<bigint>(holderOffset) ?? 0n) : 0n,
      isLoading: core.isLoading || (Boolean(core.data) && holders.isLoading),
      error: core.error ?? holders.error ?? undefined,
    };
  }, [core.data, core.isLoading, core.error, holders.data, holders.isLoading, holders.error, constituentList, usdg, account, addresses, vault]);
}
