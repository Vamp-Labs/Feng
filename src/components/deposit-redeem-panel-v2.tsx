"use client";

import { useId, useMemo, useState } from "react";
import { LayoutGroup, m } from "framer-motion";
import { useQueryClient } from "@tanstack/react-query";
import { formatUnits, parseEventLogs, type Address, type TransactionReceipt } from "viem";
import { useAccount } from "wagmi";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Notice } from "@/components/ui/notice";
import { TestFundsPrompt } from "@/components/test-funds";
import { erc20Abi } from "@/lib/abi";
import { formatTokenAmount, safeParseAmount, truncateToFraction } from "@/lib/format";
import { PAXOS_FAUCET_URL, ROBINHOOD_FAUCET_URL } from "@/lib/faucet";
import { explainError, withUsdgDecimals, type DescribedError } from "@/lib/errors";
import { SEGMENT_SPRING } from "@/lib/motion";
import { v2Abis, ZERO_ADDRESS } from "@/lib/protocol";
import {
  DEFAULT_SLIPPAGE_BPS,
  SLIPPAGE_OPTIONS_BPS,
  formatSlippage,
  minAfterSlippage,
  nextSlippage,
} from "@/lib/protocol/slippage";
import { useRestoreFocus } from "@/lib/hooks/use-restore-focus";
import { useTxFlow } from "@/lib/hooks/use-tx-flow";
import { useV2Quote, type V2Mode, type V2Route } from "@/lib/hooks/use-v2-quotes";
import { useV2SwapLimit } from "@/lib/hooks/use-v2-swap-limit";
import { useV2Vault, type V2Constituent } from "@/lib/hooks/use-v2-vault";
import { largestLegPercent, sharesWorthUsdg, usdgValueOfShares } from "@/lib/protocol/swap-limit";
import { useContracts } from "@/lib/use-contracts";
import type { DepositRedeemPanelProps } from "@/components/deposit-redeem-panel-props";
import styles from "./deposit-redeem-panel.module.css";

const MODES: Array<{ mode: V2Mode; label: string }> = [
  { mode: "deposit", label: "Deposit" },
  { mode: "redeem", label: "Redeem" },
];

const ROUTES: Array<{ route: V2Route; label: string }> = [
  { route: "usdg", label: "USDG" },
  { route: "inKind", label: "In kind" },
];

type Action = "deposit" | "depositInKind" | "redeem" | "redeemInKind";

interface ReturnedToken {
  token: Address;
  symbol: string;
  amount: string;
  isShares: boolean;
}

interface ActionResult {
  action: Action;
  headline: string;
  returned: ReturnedToken[];
}

const RECOVERABLE_ON_REDEEM = new Set(["stale", "liquidity", "child", "feed", "limit"]);

function busyStatus(status: string): boolean {
  return status === "signing" || status === "confirming";
}

function summarizeReceipt(
  receipt: TransactionReceipt,
  action: Action,
  context: {
    vault: Address;
    account: Address;
    usdg?: Address;
    usdgDecimals?: number;
    usdgSymbol: string;
    shareSymbol: string;
    shareDecimals: number;
    constituents: V2Constituent[];
  },
): ActionResult {
  const vaultLogs = receipt.logs.filter((log) => log.address.toLowerCase() === context.vault.toLowerCase());
  const events = parseEventLogs({ abi: v2Abis.vault, logs: vaultLogs });

  if (action === "deposit") {
    const event = events.find((entry) => entry.eventName === "Deposit");
    const shares = event && event.eventName === "Deposit" ? event.args.shares : undefined;
    return {
      action,
      headline:
        shares !== undefined
          ? `Minted ${formatTokenAmount(shares, context.shareDecimals)} ${context.shareSymbol}.`
          : "Deposit confirmed on-chain.",
      returned: [],
    };
  }

  if (action === "depositInKind") {
    const event = events.find((entry) => entry.eventName === "DepositInKind");
    const shares = event && event.eventName === "DepositInKind" ? event.args.shares : undefined;
    return {
      action,
      headline:
        shares !== undefined
          ? `Minted ${formatTokenAmount(shares, context.shareDecimals)} ${context.shareSymbol}.`
          : "Deposit confirmed on-chain.",
      returned: [],
    };
  }

  if (action === "redeem") {
    const event = events.find((entry) => entry.eventName === "Redeem");
    const out = event && event.eventName === "Redeem" ? event.args.usdgAmount : undefined;
    return {
      action,
      headline:
        out !== undefined && context.usdgDecimals !== undefined
          ? `Received ${formatTokenAmount(out, context.usdgDecimals, 2)} ${context.usdgSymbol}.`
          : "Redeem confirmed on-chain.",
      returned: [],
    };
  }

  const transfers = parseEventLogs({ abi: erc20Abi, logs: receipt.logs, eventName: "Transfer" });
  const returned: ReturnedToken[] = [];
  for (const transfer of transfers) {
    if (transfer.args.to.toLowerCase() !== context.account.toLowerCase()) continue;
    if (transfer.args.from === ZERO_ADDRESS) continue;
    const token = transfer.address;
    const constituent = context.constituents.find((entry) => entry.token.toLowerCase() === token.toLowerCase());
    const isUsdg = context.usdg !== undefined && token.toLowerCase() === context.usdg.toLowerCase();
    const decimals = isUsdg ? (context.usdgDecimals ?? 18) : (constituent?.decimals ?? 18);
    returned.push({
      token,
      symbol: isUsdg ? context.usdgSymbol : (constituent?.symbol ?? "token"),
      amount: formatTokenAmount(transfer.args.value, decimals, 6),
      isShares: constituent?.isStrategyToken ?? false,
    });
  }
  return {
    action,
    headline: returned.length > 0 ? "Returned to your wallet:" : "Redeemed in kind.",
    returned,
  };
}

export function DepositRedeemPanelV2({ vault, token, tokenDecimals, tokenSymbol }: DepositRedeemPanelProps) {
  const { address, isConnected } = useAccount();
  const { addresses } = useContracts();
  const queryClient = useQueryClient();
  const info = useV2Vault(vault, token);
  const groupId = useId();

  const [mode, setMode] = useState<V2Mode>("deposit");
  const [route, setRoute] = useState<V2Route>("usdg");
  const [amount, setAmount] = useState("");
  const [slippageBps, setSlippageBps] = useState<number>(DEFAULT_SLIPPAGE_BPS);
  const [pickedToken, setPickedToken] = useState<Address | undefined>(undefined);
  const [lastAction, setLastAction] = useState<Action | undefined>(undefined);
  const [result, setResult] = useState<ActionResult | undefined>(undefined);
  const [failure, setFailure] = useState<DescribedError | undefined>(undefined);

  const approveFlow = useTxFlow();
  const actionFlow = useTxFlow();

  const usdgSymbol = info.usdgSymbol ?? "USDG";
  const heldConstituents = useMemo(
    () => info.constituents.filter((constituent) => constituent.balance > 0n),
    [info.constituents],
  );
  const activeToken =
    mode === "deposit" && route === "inKind"
      ? (heldConstituents.find((constituent) => constituent.token === pickedToken) ?? heldConstituents[0])
      : undefined;

  const inputDecimals =
    mode === "redeem" ? tokenDecimals : route === "usdg" ? info.usdgDecimals : activeToken?.decimals;
  const inputSymbol = mode === "redeem" ? tokenSymbol : route === "usdg" ? usdgSymbol : (activeToken?.symbol ?? "token");
  const inputBalance =
    mode === "redeem" ? info.shareBalance : route === "usdg" ? info.usdgBalance : (activeToken?.balance ?? 0n);
  const inputAllowance = route === "usdg" ? info.usdgAllowance : (activeToken?.allowance ?? 0n);
  const spendToken: Address | undefined = route === "usdg" ? info.usdg : activeToken?.token;

  const parsedAmount = useMemo(
    () => (inputDecimals === undefined ? 0n : safeParseAmount(amount, inputDecimals)),
    [amount, inputDecimals],
  );

  const swapLimit = useV2SwapLimit(vault, info.constituents);

  const quote = useV2Quote({
    vault,
    mode,
    route,
    amount: parsedAmount,
    inKindToken: activeToken?.token,
  });

  const minShares = quote.shares === undefined ? undefined : minAfterSlippage(quote.shares, slippageBps);
  const minUsdgOut = quote.venuePayout === undefined ? undefined : minAfterSlippage(quote.venuePayout, slippageBps);

  const overBalance = parsedAmount > inputBalance;

  const limitedValueUsdg =
    route !== "usdg" || parsedAmount === 0n
      ? undefined
      : mode === "deposit"
        ? parsedAmount
        : info.sharePrice === undefined
          ? undefined
          : usdgValueOfShares(parsedAmount, info.sharePrice);
  const maxInputForLimit =
    swapLimit.maxTotalUsdg === undefined
      ? undefined
      : mode === "deposit"
        ? swapLimit.maxTotalUsdg
        : info.sharePrice === undefined
          ? undefined
          : sharesWorthUsdg(swapLimit.maxTotalUsdg, info.sharePrice);
  const limitFractionDigits = mode === "deposit" ? 2 : 4;
  const limitMaxInput =
    maxInputForLimit === undefined || inputDecimals === undefined
      ? undefined
      : truncateToFraction(maxInputForLimit, inputDecimals, limitFractionDigits);
  const overLimit =
    limitedValueUsdg !== undefined &&
    swapLimit.maxTotalUsdg !== undefined &&
    maxInputForLimit !== undefined &&
    limitedValueUsdg > swapLimit.maxTotalUsdg;
  const needsApproval = mode === "deposit" && parsedAmount > 0n && inputAllowance < parsedAmount;
  const busy = busyStatus(approveFlow.status) || busyStatus(actionFlow.status);
  const depositBlocked = mode === "deposit" && info.paused;
  const isStale = info.priceFresh === false;
  const noInKindTokens = mode === "deposit" && route === "inKind" && heldConstituents.length === 0;
  const quoteMissing =
    mode === "deposit"
      ? minShares === undefined
      : route === "usdg"
        ? minUsdgOut === undefined
        : quote.inKind === undefined;

  const canSubmit =
    isConnected &&
    parsedAmount > 0n &&
    !overBalance &&
    !overLimit &&
    !busy &&
    !depositBlocked &&
    !noInKindTokens &&
    (mode === "redeem" && route === "inKind" ? true : !quoteMissing);

  const actionButton = useRestoreFocus(busy);

  function refresh() {
    void queryClient.invalidateQueries();
  }

  function changeMode(next: V2Mode) {
    setMode(next);
    setFailure(undefined);
    setResult(undefined);
    approveFlow.reset();
    actionFlow.reset();
  }

  function changeRoute(next: V2Route) {
    setRoute(next);
    setFailure(undefined);
    setResult(undefined);
    approveFlow.reset();
    actionFlow.reset();
  }

  function fillMax() {
    if (inputDecimals === undefined) return;
    setAmount(formatUnits(inputBalance, inputDecimals));
  }

  function fillLimit() {
    if (inputDecimals === undefined || limitMaxInput === undefined) return;
    const capped = limitMaxInput < inputBalance ? limitMaxInput : inputBalance;
    setAmount(formatUnits(capped, inputDecimals));
  }

  async function handleApprove() {
    if (!spendToken) return;
    setFailure(undefined);
    try {
      await approveFlow.send({ address: spendToken, abi: erc20Abi, functionName: "approve", args: [vault, parsedAmount] });
    } catch (error) {
      setFailure(explainError(error));
    }
    refresh();
  }

  async function handleAct() {
    if (!address) return;
    setFailure(undefined);
    setResult(undefined);
    approveFlow.reset();
    const action: Action =
      mode === "deposit" ? (route === "usdg" ? "deposit" : "depositInKind") : route === "usdg" ? "redeem" : "redeemInKind";
    setLastAction(action);
    try {
      const receipt =
        action === "deposit"
          ? await actionFlow.send({
              address: vault,
              abi: v2Abis.vault,
              functionName: "deposit",
              args: [parsedAmount, address, minShares ?? 0n],
            })
          : action === "depositInKind" && activeToken
            ? await actionFlow.send({
                address: vault,
                abi: v2Abis.vault,
                functionName: "depositInKind",
                args: [activeToken.token, parsedAmount, address, minShares ?? 0n],
              })
            : action === "redeem"
              ? await actionFlow.send({
                  address: vault,
                  abi: v2Abis.vault,
                  functionName: "redeem",
                  args: [parsedAmount, address, address, minUsdgOut ?? 0n],
                })
              : await actionFlow.send({
                  address: vault,
                  abi: v2Abis.vault,
                  functionName: "redeemInKind",
                  args: [parsedAmount, address, address],
                });
      setResult(
        summarizeReceipt(receipt, action, {
          vault,
          account: address,
          usdg: info.usdg,
          usdgDecimals: info.usdgDecimals,
          usdgSymbol,
          shareSymbol: tokenSymbol,
          shareDecimals: tokenDecimals,
          constituents: info.constituents,
        }),
      );
      setAmount("");
    } catch (error) {
      setFailure(explainError(error));
    }
    refresh();
  }

  function redeemInKindInstead() {
    setMode("redeem");
    setRoute("inKind");
    setFailure(undefined);
    approveFlow.reset();
    actionFlow.reset();
  }

  function raiseTolerance() {
    const next = nextSlippage(slippageBps);
    if (next !== undefined) setSlippageBps(next);
    setFailure(undefined);
    actionFlow.reset();
  }

  const failedOnRedeemUsdg = lastAction === "redeem";
  const offerInKind =
    failure !== undefined && failedOnRedeemUsdg && (RECOVERABLE_ON_REDEEM.has(failure.category) || quote.error !== undefined);
  const offerRaise = failure?.category === "slippage" && nextSlippage(slippageBps) !== undefined;
  const flowFailure = withUsdgDecimals(failure ?? approveFlow.failure ?? actionFlow.failure, info.usdgDecimals);

  const actionLabel =
    mode === "deposit"
      ? busyStatus(actionFlow.status)
        ? "Depositing…"
        : "Deposit"
      : busyStatus(actionFlow.status)
        ? "Redeeming…"
        : route === "inKind"
          ? "Redeem in kind"
          : "Redeem";

  const approveLabel = busyStatus(approveFlow.status) ? "Approving…" : `Approve ${inputSymbol}`;

  const showMin = mode === "deposit" ? minShares !== undefined : mode === "redeem" && route === "usdg" && minUsdgOut !== undefined;

  return (
    <Card variant="glass" tone="violet" className={styles.panel}>
      <div className={styles.badges}>
        {info.universe === "live" ? <Badge tone="amber">Live assets</Badge> : <Badge tone="neutral">Sandbox</Badge>}
        {isStale ? <Badge tone="danger">Prices stale</Badge> : null}
        {info.paused ? <Badge tone="danger">Deposits paused</Badge> : null}
        {info.universe === "live" ? (
          <>
            <a className={styles.badgeLink} href={PAXOS_FAUCET_URL} target="_blank" rel="noreferrer">
              Paxos faucet
            </a>
            <a className={styles.badgeLink} href={ROBINHOOD_FAUCET_URL} target="_blank" rel="noreferrer">
              Robinhood faucet
            </a>
          </>
        ) : null}
      </div>

      <LayoutGroup id={groupId}>
        <div className="segmented">
          {MODES.map((option) => (
            <button
              key={option.mode}
              type="button"
              onClick={() => changeMode(option.mode)}
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

      <div className={styles.route} role="group" aria-label={mode === "deposit" ? "Pay with" : "Receive as"}>
        {ROUTES.map((option) => (
          <button
            key={option.route}
            type="button"
            className={styles.routeOption}
            aria-pressed={route === option.route}
            onClick={() => changeRoute(option.route)}
          >
            {option.label}
          </button>
        ))}
      </div>

      {isConnected && info.universe === "sandbox" ? <TestFundsPrompt /> : null}

      {mode === "deposit" && route === "inKind" ? (
        <label className="field">
          <span className="field__label">Token to deposit</span>
          <div className="select">
            <select
              value={activeToken?.token ?? ""}
              onChange={(event) => setPickedToken(event.target.value as Address)}
              disabled={heldConstituents.length === 0}
            >
              {heldConstituents.length === 0 ? <option value="">No constituent tokens in this wallet</option> : null}
              {heldConstituents.map((constituent) => (
                <option key={constituent.token} value={constituent.token}>
                  {constituent.symbol ?? constituent.token} ·{" "}
                  {formatTokenAmount(constituent.balance, constituent.decimals)}
                </option>
              ))}
            </select>
          </div>
        </label>
      ) : null}

      <label className="field">
        <span className={styles.amountRow}>
          <span className="field__label">{`${inputSymbol} amount`}</span>
          <button type="button" className={styles.maxButton} onClick={fillMax} disabled={inputBalance === 0n}>
            Max
          </button>
        </span>
        <input
          value={amount}
          onChange={(event) => setAmount(event.target.value)}
          placeholder="0.0"
          inputMode="decimal"
          className="input"
          data-size="lg"
          aria-invalid={overBalance}
        />
        <span className="field__hint">
          Balance:{" "}
          {isConnected && inputDecimals !== undefined
            ? `${formatTokenAmount(inputBalance, inputDecimals, mode === "redeem" ? 4 : 2)} ${inputSymbol}`
            : "—"}
          {overBalance ? " · amount is above your balance" : ""}
        </span>
      </label>

      <div className={styles.slippage} role="group" aria-label="Slippage tolerance">
        <span className={styles.slippageLabel}>Slippage</span>
        {SLIPPAGE_OPTIONS_BPS.map((option) => (
          <button
            key={option}
            type="button"
            className={styles.slippageOption}
            aria-pressed={slippageBps === option}
            onClick={() => setSlippageBps(option)}
          >
            {formatSlippage(option)}
          </button>
        ))}
      </div>

      <div className="receive">
        <span className="text-caption text-ink-secondary">
          {mode === "redeem" && route === "inKind" ? "You will receive" : "You will receive (estimate)"}
        </span>
        {mode === "redeem" && route === "inKind" ? (
          quote.inKind ? (
            <ul className={styles.tokenList}>
              {quote.inKind.tokens.map((returnedToken, index) => {
                if ((quote.inKind?.amounts[index] ?? 0n) === 0n) return null;
                const constituent = info.constituents.find(
                  (entry) => entry.token.toLowerCase() === returnedToken.toLowerCase(),
                );
                const isUsdg = info.usdg !== undefined && returnedToken.toLowerCase() === info.usdg.toLowerCase();
                const decimals = isUsdg ? (info.usdgDecimals ?? 18) : (constituent?.decimals ?? 18);
                const symbol = isUsdg ? usdgSymbol : (constituent?.symbol ?? "token");
                return (
                  <li key={returnedToken} className={styles.tokenRow}>
                    <span>
                      {symbol}
                      {constituent?.isStrategyToken ? <span className={styles.tokenKind}> · strategy shares</span> : null}
                    </span>
                    <span>{formatTokenAmount(quote.inKind?.amounts[index] ?? 0n, decimals, 6)}</span>
                  </li>
                );
              })}
            </ul>
          ) : (
            <p className="text-stat text-ink">—</p>
          )
        ) : (
          <p className="text-stat text-ink">
            {mode === "deposit"
              ? quote.shares !== undefined
                ? `${formatTokenAmount(quote.shares, tokenDecimals)} ${tokenSymbol}`
                : "—"
              : quote.venuePayout !== undefined && info.usdgDecimals !== undefined
                ? `${formatTokenAmount(quote.venuePayout, info.usdgDecimals, 2)} ${usdgSymbol}`
                : "—"}
          </p>
        )}
        <dl className={styles.details}>
          {showMin ? (
            <div className={styles.detailRow}>
              <dt className={styles.detailLabel}>Minimum after {formatSlippage(slippageBps)} slippage</dt>
              <dd className={styles.detailValue}>
                {mode === "deposit" && minShares !== undefined
                  ? `${formatTokenAmount(minShares, tokenDecimals)} ${tokenSymbol}`
                  : minUsdgOut !== undefined && info.usdgDecimals !== undefined
                    ? `${formatTokenAmount(minUsdgOut, info.usdgDecimals, 2)} ${usdgSymbol}`
                    : "—"}
              </dd>
            </div>
          ) : null}
          {mode === "redeem" && route === "usdg" && quote.navPayout !== undefined && info.usdgDecimals !== undefined ? (
            <div className={styles.detailRow}>
              <dt className={styles.detailLabel}>At net asset value</dt>
              <dd className={styles.detailValue}>
                {formatTokenAmount(quote.navPayout, info.usdgDecimals, 2)} {usdgSymbol}
              </dd>
            </div>
          ) : null}
          {info.sharePrice !== undefined && info.usdgDecimals !== undefined ? (
            <div className={styles.detailRow}>
              <dt className={styles.detailLabel}>Share price</dt>
              <dd className={styles.detailValue}>
                {formatTokenAmount(info.sharePrice, info.usdgDecimals, 4)} {usdgSymbol}
              </dd>
            </div>
          ) : null}
        </dl>
        {mode === "redeem" && route === "inKind" ? (
          <p className={styles.hint}>
            Redeeming in kind sends your share of every holding straight to your wallet. It does not use price feeds
            or the desk, so it works even when prices are stale.
          </p>
        ) : null}
      </div>

      {isStale && !(mode === "redeem" && route === "inKind") && flowFailure?.category !== "stale" ? (
        <Notice tone="warn" role="status">
          <span className={styles.notice}>
            Price feeds for this strategy are stale. {mode === "deposit" ? "Deposits" : `Redeeming to ${usdgSymbol}`}{" "}
            will revert until prices refresh.
            {mode === "redeem" ? (
              <Button size="sm" variant="secondary" onClick={redeemInKindInstead}>
                Redeem in kind
              </Button>
            ) : null}
          </span>
        </Notice>
      ) : null}

      {info.universe === "live" ? (
        <p className={styles.hint}>
          Live assets are real testnet tokens controlled by their issuers. They can be paused, frozen or upgraded by the
          issuer, which can block deposits and redeems.
        </p>
      ) : null}

      {overLimit &&
      swapLimit.capUsdg !== undefined &&
      swapLimit.legScale !== undefined &&
      limitMaxInput !== undefined &&
      inputDecimals !== undefined &&
      info.usdgDecimals !== undefined ? (
        <Notice tone="warn" role="status">
          <span className={styles.notice}>
            This amount is above the per-trade limit. The desk fills at most{" "}
            {formatTokenAmount(swapLimit.capUsdg, info.usdgDecimals, 2)} {usdgSymbol} per trade and this strategy sends up
            to {largestLegPercent(swapLimit.legScale)}% of {mode === "deposit" ? "a deposit" : "a redemption"} to one
            holding, so the most you can {mode === "deposit" ? "deposit" : "redeem"} is{" "}
            {formatTokenAmount(limitMaxInput, inputDecimals, limitFractionDigits)} {inputSymbol}.
            <span className={styles.noticeActions}>
              <Button size="sm" onClick={fillLimit}>
                Use max
              </Button>
              {mode === "redeem" ? (
                <Button size="sm" variant="secondary" onClick={redeemInKindInstead}>
                  Redeem in kind
                </Button>
              ) : null}
            </span>
          </span>
        </Notice>
      ) : null}

      {quote.error && parsedAmount > 0n && !isStale && !overLimit && !(mode === "redeem" && route === "inKind") ? (
        <Notice tone="warn" role="status">
          <span className={styles.notice}>
            {explainError(quote.error).message}
            {mode === "redeem" ? (
              <Button size="sm" variant="secondary" onClick={redeemInKindInstead}>
                Redeem in kind
              </Button>
            ) : null}
          </span>
        </Notice>
      ) : null}

      {flowFailure ? (
        <Notice tone="error" role="alert">
          <span className={styles.notice}>
            {flowFailure.message}
            {offerInKind || offerRaise || (failure?.category === "paused" && mode === "deposit") ? (
              <span className={styles.noticeActions}>
                {offerInKind ? <Button size="sm" onClick={redeemInKindInstead}>Redeem in kind</Button> : null}
                {offerRaise ? (
                  <Button size="sm" variant="secondary" onClick={raiseTolerance}>
                    Raise tolerance to {formatSlippage(nextSlippage(slippageBps) ?? slippageBps)}
                  </Button>
                ) : null}
                {failure?.category === "paused" && mode === "deposit" ? (
                  <Button size="sm" variant="secondary" onClick={() => changeMode("redeem")}>
                    Go to redeem
                  </Button>
                ) : null}
              </span>
            ) : null}
          </span>
        </Notice>
      ) : null}

      {result ? (
        <Notice tone="success" role="status">
          <span className={styles.notice}>
            {result.headline}
            {result.returned.length > 0 ? (
              <ul className={styles.tokenList}>
                {result.returned.map((entry) => (
                  <li key={entry.token} className={styles.tokenRow}>
                    <span>
                      {entry.symbol}
                      {entry.isShares ? <span className={styles.tokenKind}> · strategy shares</span> : null}
                    </span>
                    <span>{entry.amount}</span>
                  </li>
                ))}
              </ul>
            ) : null}
          </span>
        </Notice>
      ) : null}

      {mode === "deposit" && needsApproval ? (
        <Button ref={actionButton} data-action="approve" onClick={handleApprove} disabled={!canSubmit}>
          {approveLabel}
        </Button>
      ) : (
        <Button ref={actionButton} data-action="submit" onClick={handleAct} disabled={!canSubmit}>
          {actionLabel}
        </Button>
      )}
      {!isConnected ? <span className="text-caption text-ink-muted">Connect a wallet first.</span> : null}
      {addresses.explorerUrl && actionFlow.hash ? (
        <a className={styles.resultLink} href={`${addresses.explorerUrl}/tx/${actionFlow.hash}`} target="_blank" rel="noreferrer">
          View transaction
        </a>
      ) : null}
    </Card>
  );
}
