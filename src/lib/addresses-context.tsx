"use client";

import { createContext, useContext, type ReactNode } from "react";
import type { DeploymentAddresses } from "@/lib/addresses";
import type { NetworkKey } from "@/lib/networks";

interface ActiveNetworkContextValue {
  network: NetworkKey;
  addresses: DeploymentAddresses;
}

const ActiveNetworkContext = createContext<ActiveNetworkContextValue | null>(null);

export function ActiveNetworkProvider({
  network,
  addresses,
  children,
}: ActiveNetworkContextValue & { children: ReactNode }) {
  return (
    <ActiveNetworkContext.Provider value={{ network, addresses }}>
      {children}
    </ActiveNetworkContext.Provider>
  );
}

export function useActiveNetwork(): ActiveNetworkContextValue {
  const value = useContext(ActiveNetworkContext);
  if (!value) {
    throw new Error("useActiveNetwork must be used within an ActiveNetworkProvider");
  }
  return value;
}
