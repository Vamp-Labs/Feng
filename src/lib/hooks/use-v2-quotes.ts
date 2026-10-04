"use client";

import { useReadContract } from "wagmi";
import type { Address } from "viem";
import { v2Abis } from "@/lib/protocol";
import { useContracts } from "@/lib/use-contracts";

export type V2Mode = "deposit" | "redeem";
export type V2Route = "usdg" | "inKind";

export interface V2QuoteRequest {
  vault: Address;
  mode: V2Mode;
  route: V2Route;
  amount: bigint;
  inKindToken?: Address;
}

export interface InKindPreview {
  tokens: readonly Address[];
  amounts: readonly bigint[];
}

export interface V2Quote {
  shares?: bigint;
  navPayout?: bigint;
  venuePayout?: bigint;
  inKind?: InKindPreview;
  isFetching: boolean;
  error?: Error;
}

export function useV2Quote({ vault, mode, route, amount, inKindToken }: V2QuoteRequest): V2Quote {
  const { v2 } = useContracts();
  const lens = v2?.lens;
  const hasAmount = amount > 0n;

  const depositUsdg = useReadContract({
    address: vault,
    abi: v2Abis.vault,
    functionName: "previewDeposit",
    args: [amount],
    query: { enabled: mode === "deposit" && route === "usdg" && hasAmount },
  });

  const depositInKind = useReadContract({
    address: vault,
    abi: v2Abis.vault,
    functionName: "previewDepositInKind",
    args: inKindToken ? [inKindToken, amount] : undefined,
    query: { enabled: mode === "deposit" && route === "inKind" && hasAmount && Boolean(inKindToken) },
  });

  const navPayout = useReadContract({
    address: vault,
    abi: v2Abis.vault,
    functionName: "previewRedeem",
    args: [amount],
    query: { enabled: mode === "redeem" && route === "usdg" && hasAmount },
  });

  const venuePayout = useReadContract({
    address: lens,
    abi: v2Abis.lens,
    functionName: "quoteRedeem",
    args: [vault, amount],
    query: { enabled: mode === "redeem" && route === "usdg" && hasAmount && Boolean(lens) },
  });

  const inKind = useReadContract({
    address: lens,
    abi: v2Abis.lens,
    functionName: "previewRedeemInKind",
    args: [vault, amount],
    query: { enabled: mode === "redeem" && route === "inKind" && hasAmount && Boolean(lens) },
  });

  const active = mode === "deposit" ? (route === "usdg" ? depositUsdg : depositInKind) : route === "usdg" ? venuePayout : inKind;

  return {
    shares: mode === "deposit" ? (route === "usdg" ? depositUsdg.data : depositInKind.data) : undefined,
    navPayout: mode === "redeem" && route === "usdg" ? navPayout.data : undefined,
    venuePayout: mode === "redeem" && route === "usdg" ? venuePayout.data : undefined,
    inKind: mode === "redeem" && route === "inKind" && inKind.data ? { tokens: inKind.data[0], amounts: inKind.data[1] } : undefined,
    isFetching: active.isFetching,
    error: active.error ?? undefined,
  };
}
