"use client";

import { useMemo } from "react";
import { useActiveNetwork } from "@/lib/addresses-context";
import { protocolContracts } from "@/lib/protocol";

export function useContracts() {
  const { addresses } = useActiveNetwork();
  return useMemo(() => protocolContracts(addresses), [addresses]);
}
