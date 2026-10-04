"use client";

import { useSyncExternalStore, type ReactNode } from "react";
import { useAccount, useReadContracts } from "wagmi";
import { fengFaucetAbi } from "@/lib/abi/generated";
import { erc20Abi } from "@/lib/abi";
import { Button, ButtonLink } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Notice } from "@/components/ui/notice";
import { ProgressRing } from "@/components/ui/progress-ring";
import { useMarketplaceStrategies } from "@/lib/hooks/use-marketplace";
import { usePositions } from "@/lib/hooks/use-positions";
import { readCall, readValue } from "@/lib/hooks/use-v2-discovery-shared";
import { useContracts } from "@/lib/use-contracts";
import { readRebalanceSeen, subscribeRebalanceSeen } from "@/lib/watchlist";

type StepState = "done" | "current" | "todo";

interface Step {
  key: string;
  title: string;
  text: string;
  done: boolean;
  action?: ReactNode;
}

const noop = () => false;

export function StartGuide() {
  const { address } = useAccount();
  const { addresses, usdg } = useContracts();
  const { strategies, error: strategiesError, refetch: refetchStrategies } = useMarketplaceStrategies();
  const { positions, error: positionsError } = usePositions();
  const seenRebalance = useSyncExternalStore(subscribeRebalanceSeen, readRebalanceSeen, noop);
  const faucet = addresses.faucet;

  const fundsQuery = useReadContracts({
    contracts: address
      ? [
          readCall(usdg.address, erc20Abi, "balanceOf", [address]),
          ...(faucet ? [readCall(faucet, fengFaucetAbi, "hasClaimed", [address])] : []),
        ]
      : [],
    query: { enabled: Boolean(address), refetchInterval: 20_000 },
  });

  const loadFailed = Boolean(fundsQuery.error ?? strategiesError ?? positionsError);

  function retryReads() {
    void fundsQuery.refetch();
    refetchStrategies();
  }

  const usdgBalance = readValue<bigint>(fundsQuery.data?.[0]);
  const claimed = readValue<boolean>(fundsQuery.data?.[1]);
  const funded = (usdgBalance !== undefined && usdgBalance > 0n) || claimed === true;
  const deposited = positions.length > 0;
  const composed = address !== undefined && strategies.some((strategy) => strategy.creator.toLowerCase() === address.toLowerCase());
  const firstHeld = positions[0]?.vault;

  const steps: Step[] = [
    {
      key: "funds",
      title: "Get test funds",
      text: "Open the wallet menu in the top right and choose Get test funds. You receive a little gas and test USDG, once per wallet.",
      done: funded,
    },
    {
      key: "deposit",
      title: "Deposit into a strategy",
      text: "Pick a strategy on the marketplace and deposit USDG. You receive a Strategy Token that tracks its NAV.",
      done: deposited,
      action: (
        <ButtonLink href="/marketplace" size="sm" variant="secondary">
          Browse strategies
        </ButtonLink>
      ),
    },
    {
      key: "watch",
      title: "Watch a rebalance",
      text: "Open a strategy and watch its weights against target. When a rebalance lands, the bars move and a notice links to the transaction. Anyone can trigger one when it is due.",
      done: seenRebalance,
      action: (
        <ButtonLink href={firstHeld ? `/strategy/${firstHeld}` : "/marketplace"} size="sm" variant="secondary">
          {firstHeld ? "Open your strategy" : "Open the marketplace"}
        </ButtonLink>
      ),
    },
    {
      key: "compose",
      title: "Compose your own",
      text: "Combine stocks, or other strategies up to two levels deep, into a new Strategy Token that others can deposit into.",
      done: composed,
      action: (
        <ButtonLink href="/create" size="sm" variant="secondary">
          Create a strategy
        </ButtonLink>
      ),
    },
  ];

  const firstOpen = steps.findIndex((step) => !step.done);
  const doneCount = steps.filter((step) => step.done).length;
  const stateOf = (index: number): StepState => (steps[index].done ? "done" : index === firstOpen ? "current" : "todo");

  return (
    <Card variant="glass" className="start-card">
      <div className="start-card__top">
        <ProgressRing
          percent={(doneCount / steps.length) * 100}
          size={88}
          strokeWidth={10}
          complete={doneCount === steps.length}
          label={`${doneCount} of ${steps.length} steps done`}
        />
        <div>
          <p className="text-title text-ink">
            {doneCount} of {steps.length} done
          </p>
          <p className="text-caption text-ink-muted">
            {address ? "Read from your wallet on the active network." : "Connect a wallet to track your progress."}
          </p>
        </div>
      </div>
      {loadFailed ? (
        <Notice tone="error" role="alert">
          <span className="flex flex-wrap items-center gap-3">
            Could not read your progress from the network, so the steps below may be out of date.
            <Button size="sm" variant="secondary" onClick={retryReads}>
              Try again
            </Button>
          </span>
        </Notice>
      ) : null}
      {address ? null : <Notice tone="warn">Progress needs a connected wallet. You can still follow the steps.</Notice>}
      <ol className="start-steps">
        {steps.map((step, index) => {
          const state = stateOf(index);
          return (
            <li key={step.key} className="start-step" data-state={state} aria-current={state === "current" ? "step" : undefined}>
              <span className="start-step__mark" aria-hidden="true">
                {state === "done" ? "✓" : index + 1}
              </span>
              <div className="start-step__body">
                <h2 className="text-label text-ink">
                  {step.title}
                  {state === "done" ? <span className="sr-only"> (done)</span> : null}
                </h2>
                <p className="text-caption text-ink-muted">{step.text}</p>
                {step.action && state !== "done" ? <div className="start-step__action">{step.action}</div> : null}
              </div>
            </li>
          );
        })}
      </ol>
    </Card>
  );
}
