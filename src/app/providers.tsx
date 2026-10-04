"use client";

import { useState, type ReactNode } from "react";
import { PrivyProvider, type PrivyClientConfig } from "@privy-io/react-auth";
import { WagmiProvider } from "@privy-io/wagmi";
import { QueryClientProvider } from "@tanstack/react-query";
import { createWagmiConfig } from "@/lib/wagmi-config";
import { createQueryClient } from "@/lib/query-client";
import { buildConfiguredChains } from "@/lib/chains";
import { ActiveNetworkProvider } from "@/lib/addresses-context";
import type { DeploymentAddresses } from "@/lib/addresses";
import type { NetworkKey } from "@/lib/networks";
import { MotionProvider } from "@/components/motion-provider";
import { SmoothScroll } from "@/components/smooth-scroll";

const PRIVY_APP_ID = process.env.NEXT_PUBLIC_PRIVY_APP_ID;
const PRIVY_ACCENT_COLOR = "#35f9a5";

function buildPrivyConfig(): PrivyClientConfig {
  const chains = buildConfiguredChains();
  return {
    loginMethods: ["email", "google", "wallet"],
    embeddedWallets: { ethereum: { createOnLogin: "users-without-wallets" } },
    defaultChain: chains[0],
    supportedChains: chains,
    appearance: {
      theme: "dark",
      accentColor: PRIVY_ACCENT_COLOR,
      walletChainType: "ethereum-only",
    },
  };
}

export function Providers({
  network,
  addresses,
  children,
}: {
  network: NetworkKey;
  addresses: DeploymentAddresses;
  children: ReactNode;
}) {
  const [wagmiConfig] = useState(() => createWagmiConfig());
  const [privyConfig] = useState(() => buildPrivyConfig());
  const [queryClient] = useState(() => createQueryClient());

  if (!PRIVY_APP_ID) {
    throw new Error(
      "NEXT_PUBLIC_PRIVY_APP_ID is not set. Add it to .env.local (see .env.example) and restart the dev server.",
    );
  }

  return (
    <PrivyProvider appId={PRIVY_APP_ID} config={privyConfig}>
      <QueryClientProvider client={queryClient}>
        <WagmiProvider config={wagmiConfig}>
          <ActiveNetworkProvider network={network} addresses={addresses}>
            <MotionProvider>
              <SmoothScroll>{children}</SmoothScroll>
            </MotionProvider>
          </ActiveNetworkProvider>
        </WagmiProvider>
      </QueryClientProvider>
    </PrivyProvider>
  );
}
