"use client";

import { usePrivy } from "@privy-io/react-auth";
import { useAccount, useSwitchChain } from "wagmi";
import { WalletMenu } from "@/components/wallet-menu";
import styles from "./wallet-menu.module.css";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Magnetic } from "@/components/motion/magnetic";
import { buildConfiguredChains } from "@/lib/chains";

export function WalletConnect() {
  const { ready, authenticated, login, logout } = usePrivy();
  const { address, chain, chainId } = useAccount();
  const { switchChain } = useSwitchChain();

  if (!ready) {
    return <Skeleton className="wallet__skeleton" />;
  }

  if (!authenticated) {
    return (
      <Magnetic>
        <Button size="sm" variant="light" className="nav__cta" onClick={login}>
          Connect wallet
        </Button>
      </Magnetic>
    );
  }

  if (!address) {
    return (
      <Button size="sm" variant="secondary" className="nav__cta" disabled>
        Setting up wallet
      </Button>
    );
  }

  const primaryChainId = buildConfiguredChains()[0].id;
  const wrongNetwork = chainId !== primaryChainId;

  return (
    <div className="wallet">
      <button
        type="button"
        onClick={() => switchChain({ chainId: primaryChainId })}
        className={`badge-button ${styles.chainButton}`}
        aria-label={wrongNetwork ? "Switch network" : `Connected to ${chain?.name ?? "the network"}`}
        data-wrong={wrongNetwork ? "" : undefined}
        disabled={!wrongNetwork}
      >
        <Badge tone={wrongNetwork ? "amber" : "violet"}>
          {wrongNetwork ? "Wrong network" : chain?.name}
        </Badge>
      </button>
      <WalletMenu address={address} onLogout={logout} />
    </div>
  );
}
