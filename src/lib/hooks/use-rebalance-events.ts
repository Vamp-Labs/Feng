"use client";

import { useEffect, useRef } from "react";
import { usePublicClient } from "wagmi";
import type { Address, Hex } from "viem";
import { rebalancedEvent } from "@/lib/hooks/use-v2-discovery-logs";
import { IS_V2 } from "@/lib/protocol";

export interface RebalanceEvent {
  hash: Hex;
  blockNumber: bigint;
  timestamp: number;
  timeBased: boolean;
  thresholdBased: boolean;
  sharePrice: bigint;
}

const BASE_DELAY_MS = 12_000;
const MAX_DELAY_MS = 60_000;
const RESYNC_EVERY_POLLS = 20;

export function useRebalanceEvents(vault: Address | undefined, onEvent: (event: RebalanceEvent) => void) {
  const client = usePublicClient();
  const handler = useRef(onEvent);

  useEffect(() => {
    handler.current = onEvent;
  }, [onEvent]);

  useEffect(() => {
    if (!IS_V2 || !client || !vault) return;

    let cancelled = false;
    let timer: number | undefined;
    let failures = 0;
    let polls = 0;
    let cursor: bigint | undefined;

    const schedule = (delay: number) => {
      if (cancelled) return;
      timer = window.setTimeout(tick, delay);
    };

    async function tick() {
      if (cancelled || !client || !vault) return;
      if (document.hidden) {
        schedule(BASE_DELAY_MS);
        return;
      }
      try {
        if (cursor === undefined || polls >= RESYNC_EVERY_POLLS) {
          const head = await client.getBlockNumber();
          cursor = cursor === undefined ? head : head > cursor ? head : cursor;
          polls = 0;
        }
        const logs = await client.getLogs({
          address: vault,
          event: rebalancedEvent,
          strict: true,
          fromBlock: cursor + 1n,
          toBlock: "latest",
        });
        polls += 1;
        for (const log of logs) {
          if (cursor === undefined || log.blockNumber > cursor) cursor = log.blockNumber;
          handler.current({
            hash: log.transactionHash,
            blockNumber: log.blockNumber,
            timestamp: Number(log.args.timestamp),
            timeBased: log.args.timeBased,
            thresholdBased: log.args.thresholdBased,
            sharePrice: log.args.sharePrice,
          });
        }
        failures = 0;
        schedule(BASE_DELAY_MS);
      } catch {
        failures += 1;
        schedule(Math.min(BASE_DELAY_MS * 2 ** failures, MAX_DELAY_MS));
      }
    }

    const onVisible = () => {
      if (document.hidden || cancelled) return;
      window.clearTimeout(timer);
      schedule(0);
    };

    document.addEventListener("visibilitychange", onVisible);
    schedule(0);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [client, vault]);
}
