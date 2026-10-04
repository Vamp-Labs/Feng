"use client";

import { useEffect, useRef } from "react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Notice } from "@/components/ui/notice";
import { useContracts } from "@/lib/use-contracts";
import { useTxFlow } from "@/lib/hooks/use-tx-flow";

export function RebalanceButton({
  vault,
  rebalanceNeeded,
  onRebalanced,
}: {
  vault: `0x${string}`;
  rebalanceNeeded?: { timeBased: boolean; thresholdBased: boolean };
  onRebalanced: () => void;
}) {
  const { rebalanceEngine } = useContracts();
  const { send, status, error } = useTxFlow();
  const notified = useRef(false);

  const needed = rebalanceNeeded?.timeBased || rebalanceNeeded?.thresholdBased;

  useEffect(() => {
    if (status === "success" && !notified.current) {
      notified.current = true;
      onRebalanced();
    }
    if (status !== "success") notified.current = false;
  }, [status, onRebalanced]);

  async function handleRebalance() {
    await send({ ...rebalanceEngine, functionName: "performRebalance", args: [vault] }).catch(() => {});
  }

  return (
    <div className="flex flex-col items-start gap-3">
      <div className="flex items-center gap-3">
        <span className="text-label text-ink">Rebalance</span>
        {rebalanceNeeded ? (
          <Badge tone={needed ? "amber" : "violet"}>
            {needed
              ? rebalanceNeeded.timeBased
                ? "Interval elapsed"
                : "Threshold breached"
              : "Up to date"}
          </Badge>
        ) : null}
      </div>
      <Button
        variant="secondary"
        onClick={handleRebalance}
        disabled={status === "signing" || status === "confirming"}
      >
        {status === "signing" || status === "confirming" ? "Rebalancing…" : "Rebalance now"}
      </Button>
      {status === "success" ? (
        <Notice tone="success" role="status">
          Rebalanced on-chain.
        </Notice>
      ) : null}
      {error ? (
        <Notice tone="error" role="alert">
          {error}
        </Notice>
      ) : null}
    </div>
  );
}
