"use client";

import { usePrivy } from "@privy-io/react-auth";
import { useAccount, useSwitchChain } from "wagmi";
import { Button } from "@/components/ui/button";
import { buildConfiguredChains } from "@/lib/chains";
import { useAddNetwork, type AddNetworkState } from "@/lib/hooks/use-add-network";
import styles from "./network-banner.module.css";

export function NetworkBannerView({
  networkName,
  switchFailed,
  switching,
  addState,
  onSwitch,
  onAdd,
}: {
  networkName: string;
  switchFailed: boolean;
  switching: boolean;
  addState: AddNetworkState;
  onSwitch: () => void;
  onAdd: () => void;
}) {
  return (
    <div className={styles.banner} role="alert">
      <p className={styles.copy}>
        {switchFailed
          ? `Your wallet did not switch networks. Add ${networkName} to the wallet, then try again.`
          : `Your wallet is on a different network. Switch to ${networkName} to continue.`}
      </p>
      <div className={styles.actions}>
        <Button size="sm" onClick={onSwitch} disabled={switching}>
          {switching ? "Switching…" : "Switch network"}
        </Button>
        <Button size="sm" variant="secondary" onClick={onAdd} disabled={addState === "pending"}>
          {addState === "added" ? "Network added" : "Add network"}
        </Button>
      </div>
    </div>
  );
}

export function NetworkBanner() {
  const { ready, authenticated } = usePrivy();
  const { address, chainId } = useAccount();
  const { switchChain, isPending, error } = useSwitchChain();
  const addNetwork = useAddNetwork();
  const primary = buildConfiguredChains()[0];

  if (!ready || !authenticated || !address || chainId === primary.id) return null;

  return (
    <NetworkBannerView
      networkName={primary.name}
      switchFailed={Boolean(error)}
      switching={isPending}
      addState={addNetwork.state}
      onSwitch={() => switchChain({ chainId: primary.id })}
      onAdd={addNetwork.add}
    />
  );
}
