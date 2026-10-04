"use client";

import { useId, useMemo, useState } from "react";
import { LayoutGroup, m } from "framer-motion";
import { useQueryClient } from "@tanstack/react-query";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/notice";
import { TestFundsPrompt } from "@/components/test-funds";
import { useContracts } from "@/lib/use-contracts";
import { useRestoreFocus } from "@/lib/hooks/use-restore-focus";
import { useTxFlow } from "@/lib/hooks/use-tx-flow";
import { useUsdgDecimals } from "@/lib/hooks/use-usdg-decimals";
import { formatTokenAmount, safeParseAmount } from "@/lib/format";
import { SEGMENT_SPRING } from "@/lib/motion";
import { strategyVaultAbi } from "@/lib/abi";
import { exactV1Payout } from "@/lib/protocol/v1-payout";
import type { DepositRedeemPanelProps } from "@/components/deposit-redeem-panel-props";
import styles from "./deposit-redeem-panel.module.css";

type Mode = "deposit" | "redeem";

const MODES: Array<{ mode: Mode; label: string }> = [
  { mode: "deposit", label: "Deposit" },
  { mode: "redeem", label: "Redeem" },
];

export function DepositRedeemPanelV1({ vault, token, tokenDecimals, tokenSymbol }: DepositRedeemPanelProps) {
  const { address, isConnected } = useAccount();
  const { usdg, erc20 } = useContracts();
  const queryClient = useQueryClient();
  const usdgDecimals = useUsdgDecimals();
  const [mode, setMode] = useState<Mode>("deposit");
  const groupId = useId();
  const [amount, setAmount] = useState("");

  const depositFlow = useTxFlow();
  const redeemFlow = useTxFlow();
  const approveFlow = useTxFlow();

  const usdgBalance = useReadContract({
    ...usdg,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });

  const usdgAllowance = useReadContract({
    ...usdg,
    functionName: "allowance",
    args: address ? [address, vault] : undefined,
    query: { enabled: Boolean(address) },
  });

  const strategyTokenBalance = useReadContract({
    ...erc20(token),
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });

  const parsedAmount = useMemo(() => {
    const decimals = mode === "deposit" ? usdgDecimals : tokenDecimals;
    return decimals === undefined ? 0n : safeParseAmount(amount, decimals);
  }, [amount, mode, usdgDecimals, tokenDecimals]);

  const previewDeposit = useReadContract({
    address: vault,
    abi: strategyVaultAbi,
    functionName: "previewDeposit",
    args: [parsedAmount],
    query: { enabled: mode === "deposit" && parsedAmount > 0n },
  });

  const payoutInputs = useReadContracts({
    contracts: [
      { ...usdg, functionName: "balanceOf" as const, args: [vault] as const },
      { ...erc20(token), functionName: "totalSupply" as const },
    ],
    query: { enabled: mode === "redeem" && parsedAmount > 0n },
  });

  const exactPayout = useMemo(() => {
    const cash = payoutInputs.data?.[0];
    const supply = payoutInputs.data?.[1];
    if (cash?.status !== "success" || supply?.status !== "success") return undefined;
    return exactV1Payout(cash.result as bigint, parsedAmount, supply.result as bigint);
  }, [payoutInputs.data, parsedAmount]);

  const needsApproval = mode === "deposit" && (usdgAllowance.data ?? 0n) < parsedAmount;

  function refreshReads() {
    void queryClient.invalidateQueries();
  }

  async function handleApprove() {
    await approveFlow.send({ ...usdg, functionName: "approve", args: [vault, parsedAmount] }).catch(() => {});
    refreshReads();
  }

  async function handleDeposit() {
    if (!address) return;
    await depositFlow
      .send({ address: vault, abi: strategyVaultAbi, functionName: "deposit", args: [parsedAmount, address] })
      .catch(() => {});
    refreshReads();
  }

  async function handleRedeem() {
    if (!address) return;
    await redeemFlow
      .send({ address: vault, abi: strategyVaultAbi, functionName: "redeem", args: [parsedAmount, address, address] })
      .catch(() => {});
    refreshReads();
  }

  const busy = [depositFlow, redeemFlow, approveFlow].some(
    (flow) => flow.status === "signing" || flow.status === "confirming",
  );

  const actionButton = useRestoreFocus(busy);

  const activeError = mode === "deposit" ? (depositFlow.error ?? approveFlow.error) : redeemFlow.error;
  const activeSuccess = mode === "deposit" ? depositFlow.status === "success" : redeemFlow.status === "success";
  const formatUsdgAmount = (value: bigint, fractionDigits = 2) =>
    usdgDecimals === undefined ? "—" : formatTokenAmount(value, usdgDecimals, fractionDigits);
  const waitingForDecimals = mode === "deposit" && usdgDecimals === undefined;

  return (
    <Card variant="glass" tone="violet" className={styles.panel}>
      <LayoutGroup id={groupId}>
        <div className="segmented">
          {MODES.map((option) => (
            <button
              key={option.mode}
              type="button"
              onClick={() => setMode(option.mode)}
              aria-pressed={mode === option.mode}
              className="segmented__option"
            >
              {mode === option.mode ? (
                <m.span layoutId="deposit-mode-pill" className="segmented__pill" transition={SEGMENT_SPRING} />
              ) : null}
              {option.label}
            </button>
          ))}
        </div>
      </LayoutGroup>

      {isConnected ? <TestFundsPrompt /> : null}

      <label className="field">
        <span className="field__label">{mode === "deposit" ? "USDG amount" : `${tokenSymbol} amount`}</span>
        <input
          value={amount}
          onChange={(event) => setAmount(event.target.value)}
          placeholder="0.0"
          inputMode="decimal"
          className="input"
          data-size="lg"
        />
        <span className="field__hint">
          Balance:{" "}
          {mode === "deposit"
            ? usdgBalance.data !== undefined && usdgDecimals !== undefined
              ? `${formatUsdgAmount(usdgBalance.data)} USDG`
              : "—"
            : strategyTokenBalance.data !== undefined
              ? `${formatTokenAmount(strategyTokenBalance.data, tokenDecimals)} ${tokenSymbol}`
              : "—"}
        </span>
      </label>

      <div className="receive">
        <span className="text-caption text-ink-secondary">
          {mode === "deposit" ? "You will receive" : "You will receive (exact payout)"}
        </span>
        <p className="text-stat text-ink">
          {mode === "deposit"
            ? previewDeposit.data !== undefined
              ? `${formatTokenAmount(previewDeposit.data, tokenDecimals)} ${tokenSymbol}`
              : "—"
            : exactPayout !== undefined
              ? `${formatUsdgAmount(exactPayout, 6)} USDG`
              : "—"}
        </p>
        {mode === "redeem" ? (
          <p className={styles.hint}>
            Payout is the vault&apos;s USDG balance times your shares divided by total supply. Child strategy tokens
            are sent to you as shares.
          </p>
        ) : null}
      </div>

      {activeError ? (
        <Notice tone="error" role="alert">
          {activeError}
        </Notice>
      ) : null}
      {activeSuccess ? (
        <Notice tone="success" role="status">
          Confirmed on-chain.
        </Notice>
      ) : null}

      {mode === "deposit" ? (
        needsApproval ? (
          <Button ref={actionButton} onClick={handleApprove} disabled={!isConnected || parsedAmount === 0n || busy || waitingForDecimals}>
            {approveFlow.status === "signing" || approveFlow.status === "confirming" ? "Approving…" : "Approve USDG"}
          </Button>
        ) : (
          <Button ref={actionButton} onClick={handleDeposit} disabled={!isConnected || parsedAmount === 0n || busy || waitingForDecimals}>
            {depositFlow.status === "signing" || depositFlow.status === "confirming" ? "Depositing…" : "Deposit"}
          </Button>
        )
      ) : (
        <Button ref={actionButton} onClick={handleRedeem} disabled={!isConnected || parsedAmount === 0n || busy}>
          {redeemFlow.status === "signing" || redeemFlow.status === "confirming" ? "Redeeming…" : "Redeem"}
        </Button>
      )}
      {!isConnected ? <span className="text-caption text-ink-muted">Connect a wallet first.</span> : null}
    </Card>
  );
}
