"use client";

import { useCallback, useState } from "react";
import { useWalletClient } from "wagmi";
import { buildConfiguredChains } from "@/lib/chains";

export type AddNetworkState = "idle" | "pending" | "added" | "error";

export function useAddNetwork() {
  const { data: walletClient } = useWalletClient();
  const [state, setState] = useState<AddNetworkState>("idle");
  const chain = buildConfiguredChains()[0];

  const add = useCallback(async () => {
    if (!walletClient) {
      setState("error");
      return;
    }
    setState("pending");
    try {
      await walletClient.addChain({ chain });
      setState("added");
    } catch {
      setState("error");
    }
  }, [walletClient, chain]);

  return { add, state, chainLabel: chain.name };
}
