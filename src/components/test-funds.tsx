"use client";

import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/notice";
import { FAUCET_MESSAGES, type FaucetOutcome } from "@/lib/faucet";
import { formatEthBalance, formatTokenAmount } from "@/lib/format";
import { useTestFunds } from "@/lib/hooks/use-test-funds";
import { getActiveNetworkDefinition } from "@/lib/networks";
import styles from "./test-funds.module.css";

const USDG_FRACTION_DIGITS = 2;

function explorerTxUrl(txHash: string): string | undefined {
  const { explorerUrl } = getActiveNetworkDefinition();
  return explorerUrl ? `${explorerUrl}/tx/${txHash}` : undefined;
}

function FundsStatus({ outcome, pending }: { outcome?: FaucetOutcome; pending: boolean }) {
  if (pending) {
    return (
      <div className={styles.status} role="status">
        <Notice tone="success">Sending test funds. This can take up to 30 seconds.</Notice>
      </div>
    );
  }

  if (!outcome) return null;

  const message = outcome.status === "error" ? outcome.message : FAUCET_MESSAGES[outcome.status];
  const tone = outcome.status === "funded" || outcome.status === "already-claimed" ? "success" : outcome.status === "error" ? "error" : "warn";
  const link = outcome.status !== "error" && outcome.txHash ? explorerTxUrl(outcome.txHash) : undefined;

  return (
    <div className={styles.status} role={tone === "success" ? "status" : "alert"}>
      <Notice tone={tone}>
        {message}
        {link ? (
          <>
            {" "}
            <a className={styles.statusLink} href={link} target="_blank" rel="noreferrer">
              View transaction
            </a>
          </>
        ) : null}
      </Notice>
    </div>
  );
}

export function TestFundsPanel() {
  const funds = useTestFunds();
  const { label } = getActiveNetworkDefinition();

  return (
    <section className={styles.panel} aria-label="Test funds">
      <dl className={styles.balances}>
        <div className={styles.balance}>
          <dt className={styles.balanceLabel}>ETH</dt>
          <dd className={styles.balanceValue}>{funds.ethWei !== undefined ? formatEthBalance(funds.ethWei) : "—"}</dd>
        </div>
        <div className={styles.balance}>
          <dt className={styles.balanceLabel}>USDG</dt>
          <dd className={styles.balanceValue}>
            {funds.usdgRaw !== undefined && funds.usdgDecimals !== undefined
              ? formatTokenAmount(funds.usdgRaw, funds.usdgDecimals, USDG_FRACTION_DIGITS)
              : "—"}
          </dd>
        </div>
      </dl>
      <Button size="sm" onClick={funds.claim} disabled={funds.isPending || !funds.address}>
        {funds.isPending ? "Sending…" : "Get test funds"}
      </Button>
      <FundsStatus outcome={funds.outcome} pending={funds.isPending} />
      <p className="text-caption text-ink-muted">
        These are test funds on {label}. They have no real value.
      </p>
    </section>
  );
}

function missingSummary(needsEth: boolean, needsUsdg: boolean): string {
  if (needsEth && needsUsdg) return "This wallet has no test USDG and almost no ETH for gas.";
  if (needsUsdg) return "This wallet has no test USDG to deposit.";
  return "This wallet is almost out of ETH for gas.";
}

export function TestFundsPrompt() {
  const funds = useTestFunds();
  const { label } = getActiveNetworkDefinition();

  if (!funds.address || !funds.loaded) return null;
  const missing = funds.needsEth || funds.needsUsdg;
  if (!missing && !funds.outcome && !funds.isPending) return null;

  return (
    <div className={styles.promptStack}>
      {missing ? (
        <div className={styles.prompt}>
          <p className={styles.promptCopy}>
            {missingSummary(funds.needsEth, funds.needsUsdg)} Get free test funds on {label}.
          </p>
          <Button size="sm" onClick={funds.claim} disabled={funds.isPending}>
            {funds.isPending ? "Sending…" : "Get test funds"}
          </Button>
        </div>
      ) : null}
      <FundsStatus outcome={funds.outcome} pending={funds.isPending} />
    </div>
  );
}
