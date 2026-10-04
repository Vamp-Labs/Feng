"use client";

import { useCallback, useEffect, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { useAccount, useBalance, useReadContracts } from "wagmi";
import { claimTestFunds, type FaucetOutcome } from "@/lib/faucet";
import { useUsdgDecimals } from "@/lib/hooks/use-usdg-decimals";
import { useContracts } from "@/lib/use-contracts";

const LOW_ETH_THRESHOLD_WEI = 100_000_000_000_000n;
const WATCH_WINDOW_MS = 45_000;
const WATCH_INTERVAL_MS = 3_000;

export function useTestFunds() {
  const { address } = useAccount();
  const { usdg } = useContracts();
  const [watchUntil, setWatchUntil] = useState(0);
  const [now, setNow] = useState(0);
  const watching = watchUntil > now;
  const refetchInterval = watching ? WATCH_INTERVAL_MS : false;

  const ethBalance = useBalance({
    address,
    query: { enabled: Boolean(address), refetchInterval },
  });

  const usdgDecimals = useUsdgDecimals();

  const usdgReads = useReadContracts({
    contracts: address ? [{ ...usdg, functionName: "balanceOf" as const, args: [address] as const }] : [],
    query: { enabled: Boolean(address), refetchInterval },
  });

  useEffect(() => {
    if (!watching) return;
    const timer = window.setInterval(() => setNow(Date.now()), WATCH_INTERVAL_MS);
    return () => window.clearInterval(timer);
  }, [watching]);

  const mutation = useMutation<FaucetOutcome, Error, `0x${string}`>({
    mutationFn: (target) => claimTestFunds(target),
    onSuccess: (outcome) => {
      if (outcome.status === "funded") {
        const current = Date.now();
        setNow(current);
        setWatchUntil(current + WATCH_WINDOW_MS);
      }
    },
  });

  const { mutate, reset, data: outcome, isPending } = mutation;

  const claim = useCallback(() => {
    if (address) mutate(address);
  }, [address, mutate]);

  const ethWei = ethBalance.data?.value;
  const usdgRaw = usdgReads.data?.[0]?.status === "success" ? (usdgReads.data[0].result as bigint) : undefined;
  const loaded = ethWei !== undefined && usdgRaw !== undefined && usdgDecimals !== undefined;

  return {
    address,
    ethWei,
    usdgRaw,
    usdgDecimals,
    needsEth: ethWei !== undefined && ethWei < LOW_ETH_THRESHOLD_WEI,
    needsUsdg: usdgRaw !== undefined && usdgRaw === 0n,
    loaded,
    outcome,
    isPending,
    claim,
    dismiss: reset,
  };
}
