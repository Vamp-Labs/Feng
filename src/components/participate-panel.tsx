"use client";

import { useId, useMemo, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { formatUnits, type Address } from "viem";
import { useAccount } from "wagmi";
import { Badge } from "@/components/ui/badge";
import { Button, ButtonLink } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Notice } from "@/components/ui/notice";
import { TestFundsPrompt } from "@/components/test-funds";
import { erc20Abi } from "@/lib/abi";
import { formatTokenAmount, safeParseAmount } from "@/lib/format";
import { v2Abis } from "@/lib/protocol";
import { DEFAULT_SLIPPAGE_BPS, minAfterSlippage } from "@/lib/protocol/slippage";
import { useTxFlow } from "@/lib/hooks/use-tx-flow";
import { useV2Quote } from "@/lib/hooks/use-v2-quotes";
import { useV2Vault } from "@/lib/hooks/use-v2-vault";

function busyStatus(status: string): boolean {
  return status === "signing" || status === "confirming";
}

export function ParticipatePanel({
  vault,
  token,
  tokenDecimals,
  tokenSymbol,
  strategyName,
}: {
  vault: Address;
  token: Address;
  tokenDecimals: number;
  tokenSymbol: string;
  strategyName: string;
}) {
  const { address: account, isConnected } = useAccount();
  const info = useV2Vault(vault, token);
  const inputId = useId();
  const queryClient = useQueryClient();

  const [amount, setAmount] = useState("");
  const [confirmed, setConfirmed] = useState<{ amount: string; shares: string } | undefined>(undefined);

  const approveFlow = useTxFlow();
  const depositFlow = useTxFlow();

  const usdgSymbol = info.usdgSymbol ?? "USDG";
  const usdgDecimals = info.usdgDecimals;

  const parsedAmount = useMemo(
    () => (usdgDecimals === undefined ? 0n : safeParseAmount(amount, usdgDecimals)),
    [amount, usdgDecimals],
  );

  const quote = useV2Quote({ vault, mode: "deposit", route: "usdg", amount: parsedAmount });
  const minShares = quote.shares === undefined ? undefined : minAfterSlippage(quote.shares, DEFAULT_SLIPPAGE_BPS);

  const overBalance = parsedAmount > info.usdgBalance;
  const needsApproval = parsedAmount > 0n && info.usdgAllowance < parsedAmount;
  const busy = busyStatus(approveFlow.status) || busyStatus(depositFlow.status);
  const canSubmit =
    isConnected && parsedAmount > 0n && !overBalance && !info.paused && !busy && minShares !== undefined;

  function fillMax() {
    if (usdgDecimals === undefined) return;
    setAmount(formatUnits(info.usdgBalance, usdgDecimals));
  }

  async function handleApprove() {
    if (!info.usdg) return;
    try {
      await approveFlow.send({ address: info.usdg, abi: erc20Abi, functionName: "approve", args: [vault, parsedAmount] });
    } catch {
      return;
    } finally {
      void queryClient.invalidateQueries();
    }
  }

  async function handleParticipate() {
    if (!account || minShares === undefined) return;
    try {
      await depositFlow.send({
        address: vault,
        abi: v2Abis.vault,
        functionName: "deposit",
        args: [parsedAmount, account, minShares],
      });
      setConfirmed({
        amount: formatTokenAmount(parsedAmount, usdgDecimals ?? 18, 2),
        shares: quote.shares !== undefined ? formatTokenAmount(quote.shares, tokenDecimals) : "",
      });
      setAmount("");
    } catch {
      return;
    } finally {
      void queryClient.invalidateQueries();
    }
  }

  if (confirmed) {
    return (
      <Card variant="glass" tone="mint" className="participate-panel" id="participate">
        <Badge tone="mint">TESTNET</Badge>
        <p className="text-title text-ink">&#10003; Strategy participation confirmed</p>
        <dl className="participate-panel__summary">
          <div>
            <dt className="text-caption text-ink-muted">Strategy</dt>
            <dd className="text-label text-ink">{strategyName}</dd>
          </div>
          <div>
            <dt className="text-caption text-ink-muted">Amount</dt>
            <dd className="text-label text-ink">
              {confirmed.amount} {usdgSymbol}
            </dd>
          </div>
          {confirmed.shares ? (
            <div>
              <dt className="text-caption text-ink-muted">Received</dt>
              <dd className="text-label text-ink">
                {confirmed.shares} {tokenSymbol}
              </dd>
            </div>
          ) : null}
        </dl>
        <div className="flex flex-wrap gap-3">
          <ButtonLink href="/positions">View Portfolio</ButtonLink>
          <Button variant="secondary" onClick={() => setConfirmed(undefined)}>
            Participate again
          </Button>
        </div>
      </Card>
    );
  }

  return (
    <Card variant="glass" tone="mint" className="participate-panel" id="participate">
      <div className="participate-panel__head">
        <h2 className="text-title text-ink">Participate</h2>
        <Badge tone="mint">TESTNET</Badge>
      </div>
      <p className="text-caption text-ink-muted">
        This sends test {usdgSymbol} from your wallet into {strategyName}&apos;s vault and mints {tokenSymbol} strategy
        shares you can redeem any time. Everything runs on Robinhood Chain testnet — no real money moves.
      </p>

      {isConnected ? <TestFundsPrompt /> : null}

      <label className="field" htmlFor={inputId}>
        <span className="participate-panel__amount-row">
          <span className="field__label">{usdgSymbol} amount</span>
          <button type="button" className="participate-panel__max" onClick={fillMax} disabled={info.usdgBalance === 0n}>
            Max
          </button>
        </span>
        <input
          id={inputId}
          value={amount}
          onChange={(event) => setAmount(event.target.value)}
          placeholder="1,000"
          inputMode="decimal"
          className="input"
          data-size="lg"
          aria-invalid={overBalance}
        />
        <span className="field__hint">
          Balance: {isConnected && usdgDecimals !== undefined ? `${formatTokenAmount(info.usdgBalance, usdgDecimals, 2)} ${usdgSymbol}` : "—"}
          {overBalance ? " · amount is above your balance" : ""}
        </span>
      </label>

      <p className="participate-panel__receive text-caption text-ink-secondary">
        You will receive (estimate):{" "}
        <span className="text-label text-ink">
          {quote.shares !== undefined ? `${formatTokenAmount(quote.shares, tokenDecimals)} ${tokenSymbol}` : "—"}
        </span>
      </p>

      {info.paused ? <Notice tone="error">Participation is paused for this strategy. You can still redeem from the Advanced panel.</Notice> : null}
      {depositFlow.failure ? <Notice tone="error" role="alert">{depositFlow.failure.message}</Notice> : null}
      {approveFlow.failure ? <Notice tone="error" role="alert">{approveFlow.failure.message}</Notice> : null}

      {needsApproval ? (
        <Button onClick={handleApprove} disabled={!canSubmit}>
          {busyStatus(approveFlow.status) ? "Approving…" : `Approve ${usdgSymbol}`}
        </Button>
      ) : (
        <Button onClick={handleParticipate} disabled={!canSubmit}>
          {busyStatus(depositFlow.status) ? "Participating…" : "Participate"}
        </Button>
      )}
      {!isConnected ? <span className="text-caption text-ink-muted">Connect a wallet first.</span> : null}
    </Card>
  );
}
