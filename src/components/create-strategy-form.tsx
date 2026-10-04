"use client";

import { useMemo, useState, type CSSProperties } from "react";
import { useRouter } from "next/navigation";
import { usePrivy } from "@privy-io/react-auth";
import { useAccount } from "wagmi";
import { AnimatePresence, m } from "framer-motion";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Notice } from "@/components/ui/notice";
import { StateCard } from "@/components/ui/state-card";
import { ProgressRing } from "@/components/ui/progress-ring";
import { LayersIcon } from "@/components/ui/icons";
import { StrategyHoldings } from "@/components/strategy-holdings";
import { useConstituentOptions, type ConstituentOption } from "@/lib/hooks/use-constituent-options";
import { useV2ConstituentOptions } from "@/lib/hooks/use-v2-constituent-options";
import { useCreateStrategy } from "@/lib/hooks/use-create-strategy";
import { useContracts } from "@/lib/use-contracts";
import { percentToBps, sumBps, utf8Bytes } from "@/lib/format";
import { PAXOS_FAUCET_URL, ROBINHOOD_FAUCET_URL } from "@/lib/faucet";
import { IS_V2, hasLiveUniverse, type Universe } from "@/lib/protocol";
import { SLIPPAGE_OPTIONS_BPS, formatSlippage } from "@/lib/protocol/slippage";
import { nestedHolding, stockHolding, type Holding } from "@/lib/holding-tones";
import { EASE_OUT } from "@/lib/motion";
import styles from "./create-strategy-form.module.css";

interface Row {
  id: string;
  address: `0x${string}`;
  weightPercent: number;
}

const REBALANCE_INTERVALS = [
  { label: "Every 24 hours", seconds: 86_400 },
  { label: "Every 7 days", seconds: 604_800 },
  { label: "Every 30 days", seconds: 2_592_000 },
] as const;

const MAX_CONSTITUENTS = 6;
const MIN_CONSTITUENTS = 2;

const MAX_DESCRIPTION_BYTES = 160;
const MAX_TAGS = 3;
const MAX_EXTRA_TAGS = MAX_TAGS - 1;
const MAX_TAG_BYTES = 16;
const MAX_NAME_BYTES = 48;
const MAX_SYMBOL_BYTES = 10;
const MAX_SLIPPAGE_BPS = 500;
const MIN_WEIGHT_PERCENT = 1;
const DEFAULT_MAX_WEIGHT_PERCENT = 100;
const TAG_PATTERN = /^[a-z0-9-]+$/;
const DEFAULT_CREATE_SLIPPAGE_BPS = 100;
const CREATE_SLIPPAGE_OPTIONS_BPS = [...SLIPPAGE_OPTIONS_BPS, MAX_SLIPPAGE_BPS] as const;

const CATEGORY_OPTIONS = [
  { slug: "ai", label: "AI" },
  { slug: "robotics", label: "Robotics" },
  { slug: "space", label: "Space" },
  { slug: "energy", label: "Energy" },
  { slug: "semiconductors", label: "Semiconductors" },
  { slug: "technology", label: "Technology" },
] as const;

const STEP_LABELS = ["Name & ticker", "Thesis", "Stocks & allocation", "Preview", "Publish"] as const;
type Step = 1 | 2 | 3 | 4;
const LAST_STEP: Step = 4;

const STEP_TRANSITION = { duration: 0.22, ease: EASE_OUT };

function normalizeTag(raw: string): string {
  return raw.trim().toLowerCase().replace(/\s+/g, "-");
}

function evenPercents(count: number): number[] {
  if (count <= 0) return [];
  const baseBps = Math.floor(10_000 / count);
  const remainder = 10_000 - baseBps * count;
  return Array.from({ length: count }, (_, index) => (baseBps + (index < remainder ? 1 : 0)) / 100);
}

function withEvenWeights(rows: Row[]): Row[] {
  const weights = evenPercents(rows.length);
  return rows.map((row, index) => ({
    ...row,
    weightPercent: weights[index] ?? 0,
  }));
}

function optionTone(option: ConstituentOption): Holding["tone"] {
  if (option.isStrategyToken) return "layered";
  return stockHolding(option.symbol, 0).tone;
}

function toHolding(option: ConstituentOption, weightPercent: number): Holding {
  const weightBps = percentToBps(weightPercent);
  return option.isStrategyToken
    ? nestedHolding(option.symbol, weightBps)
    : stockHolding(option.symbol, weightBps);
}

function StepIndicator({ activeIndex }: { activeIndex: number }) {
  return (
    <ol className={styles.stepper} aria-label="Create strategy progress">
      {STEP_LABELS.map((label, index) => {
        const position = index + 1;
        const state = position < activeIndex ? "done" : position === activeIndex ? "active" : "upcoming";
        return (
          <li key={label} className={styles.stepItem} data-state={state}>
            <span className={styles.stepDot} aria-hidden="true">
              {state === "done" ? "✓" : position}
            </span>
            <span className={styles.stepLabel}>{label}</span>
          </li>
        );
      })}
    </ol>
  );
}

export function CreateStrategyForm() {
  const { isConnected } = useAccount();
  const { login } = usePrivy();
  const { addresses } = useContracts();
  const { create, status, error, vault: createdVault, reset } = useCreateStrategy();
  const router = useRouter();
  const [universe, setUniverse] = useState<Universe>("sandbox");
  const legacyOptions = useConstituentOptions();
  const universeOptions = useV2ConstituentOptions(universe);
  const { options, isLoading: optionsLoading } = IS_V2 ? universeOptions : legacyOptions;
  const optionsError = IS_V2 ? universeOptions.error : null;
  const liveAvailable = hasLiveUniverse(addresses);

  const [step, setStep] = useState<Step>(1);
  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [rows, setRows] = useState<Row[]>([]);
  const [maxWeightPercent, setMaxWeightPercent] = useState(DEFAULT_MAX_WEIGHT_PERCENT);
  const [intervalSeconds, setIntervalSeconds] = useState<number>(REBALANCE_INTERVALS[1].seconds);
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState("");
  const [extraTags, setExtraTags] = useState<string[]>([]);
  const [tagDraft, setTagDraft] = useState("");
  const [maxSlippageBps, setMaxSlippageBps] = useState<number>(
    CREATE_SLIPPAGE_OPTIONS_BPS.find((option) => option === addresses.defaultMaxSlippageBps) ?? DEFAULT_CREATE_SLIPPAGE_BPS,
  );

  const tags = useMemo(() => [category, ...extraTags].filter((tag): tag is string => tag.length > 0), [category, extraTags]);

  const optionByAddress = useMemo(() => {
    const map = new Map<string, ConstituentOption>();
    for (const option of options) map.set(option.address, option);
    return map;
  }, [options]);

  const selectedRows = rows;
  const totalPercent = selectedRows.reduce((total, row) => total + row.weightPercent, 0);
  const totalBps = sumBps(selectedRows.map((row) => percentToBps(row.weightPercent)));
  const selectedAddresses = new Set(selectedRows.map((row) => row.address));
  const overWeightRows = selectedRows.filter((row) => row.weightPercent > maxWeightPercent);
  const isComplete = totalBps === 10_000;

  const stockOptions = options.filter((option) => !option.isStrategyToken);
  const strategyOptions = options.filter((option) => option.isStrategyToken);

  const holdings = useMemo(
    () =>
      selectedRows.flatMap((row) => {
        const option = optionByAddress.get(row.address);
        return option ? [toHolding(option, row.weightPercent)] : [];
      }),
    [selectedRows, optionByAddress],
  );

  const intervalLabel =
    REBALANCE_INTERVALS.find((interval) => interval.seconds === intervalSeconds)?.label ?? "Custom";

  const step1Errors = useMemo(() => {
    const list: string[] = [];
    if (!name.trim()) list.push("Give the strategy a name.");
    if (!symbol.trim()) list.push("Give the strategy a ticker symbol.");
    if (IS_V2) {
      if (utf8Bytes(name.trim()) > MAX_NAME_BYTES) list.push(`The name can be at most ${MAX_NAME_BYTES} bytes.`);
      const symbolBytes = utf8Bytes(symbol.trim());
      if (symbol.trim() && (symbolBytes < 2 || symbolBytes > MAX_SYMBOL_BYTES)) {
        list.push(`The ticker must be 2 to ${MAX_SYMBOL_BYTES} bytes.`);
      }
    }
    return list;
  }, [name, symbol]);

  const step2Errors = useMemo(() => {
    const list: string[] = [];
    if (!description.trim()) list.push("Describe the thesis in a sentence.");
    if (utf8Bytes(description) > MAX_DESCRIPTION_BYTES) list.push(`The thesis can be at most ${MAX_DESCRIPTION_BYTES} bytes.`);
    if (!category) list.push("Pick a category.");
    return list;
  }, [description, category]);

  const step3Errors = useMemo(() => {
    const list: string[] = [];
    if (selectedRows.length < MIN_CONSTITUENTS) list.push(`Pick at least ${MIN_CONSTITUENTS} constituents.`);
    if (IS_V2 && selectedRows.some((row) => row.weightPercent < MIN_WEIGHT_PERCENT)) {
      list.push(`Each weight must be at least ${MIN_WEIGHT_PERCENT}%.`);
    }
    if (totalBps !== 10_000) {
      list.push(`Weights must sum to exactly 100% (currently ${totalPercent.toFixed(2)}%).`);
    }
    if (overWeightRows.length > 0) {
      list.push(
        `${overWeightRows.length} constituent(s) exceed the ${maxWeightPercent}% max-weight constraint.`,
      );
    }
    return list;
  }, [selectedRows, totalBps, totalPercent, overWeightRows.length, maxWeightPercent]);

  const errors = useMemo(
    () => [...step1Errors, ...step2Errors, ...step3Errors],
    [step1Errors, step2Errors, step3Errors],
  );

  const stepErrors: Record<Step, string[]> = { 1: step1Errors, 2: step2Errors, 3: step3Errors, 4: [] };

  const canSubmit = errors.length === 0 && status !== "signing" && status !== "confirming";

  function changeUniverse(next: Universe) {
    if (next === universe) return;
    setUniverse(next);
    setRows([]);
  }

  function addTag() {
    const next = normalizeTag(tagDraft);
    if (!next || extraTags.length >= MAX_EXTRA_TAGS || extraTags.includes(next) || next === category) return;
    if (!TAG_PATTERN.test(next) || utf8Bytes(next) > MAX_TAG_BYTES) return;
    setExtraTags((prev) => [...prev, next]);
    setTagDraft("");
  }

  function removeTag(tag: string) {
    setExtraTags((prev) => prev.filter((entry) => entry !== tag));
  }

  const draftTag = normalizeTag(tagDraft);
  const draftInvalid = draftTag.length > 0 && (!TAG_PATTERN.test(draftTag) || utf8Bytes(draftTag) > MAX_TAG_BYTES);

  function toggleOption(option: ConstituentOption) {
    if (!option.eligible) return;

    setRows((prev) => {
      const exists = prev.some((row) => row.address === option.address);
      if (exists) {
        return withEvenWeights(prev.filter((row) => row.address !== option.address));
      }
      if (prev.length >= MAX_CONSTITUENTS) return prev;
      return withEvenWeights([
        ...prev,
        { id: crypto.randomUUID(), address: option.address, weightPercent: 0 },
      ]);
    });
  }

  function updateWeight(id: string, weightPercent: number) {
    const next = Number.isFinite(weightPercent) ? Math.max(0, Math.min(100, weightPercent)) : 0;
    setRows((prev) => prev.map((row) => (row.id === id ? { ...row, weightPercent: next } : row)));
  }

  function removeRow(id: string) {
    setRows((prev) => withEvenWeights(prev.filter((row) => row.id !== id)));
  }

  function splitEven() {
    setRows((prev) => withEvenWeights(prev));
  }

  function goNext() {
    if (step === LAST_STEP) return;
    if (stepErrors[step].length > 0) return;
    setStep((current) => (current === LAST_STEP ? current : ((current + 1) as Step)));
  }

  function goBack() {
    setStep((current) => (current === 1 ? current : ((current - 1) as Step)));
  }

  async function handleSubmit() {
    if (!isConnected) {
      login();
      return;
    }
    if (!canSubmit) return;
    const constituents = selectedRows.map((row) => {
      const option = optionByAddress.get(row.address);
      return {
        token: row.address,
        targetWeightBps: percentToBps(row.weightPercent),
        isStrategyToken: option?.isStrategyToken ?? false,
      };
    });

    await create({
      name: name.trim(),
      symbol: symbol.trim().toUpperCase(),
      constituents,
      maxWeightBps: percentToBps(maxWeightPercent),
      intervalSeconds,
      maxSlippageBps,
      description: description.trim(),
      tags,
      universe,
    }).catch(() => {});
  }

  if (status === "success") {
    const vault = createdVault;
    return (
      <StateCard
        art="done"
        role="status"
        title="Strategy published"
        actions={
          <>
            {vault ? <Button onClick={() => router.push(`/strategy/${vault}`)}>View strategy</Button> : null}
            <Button variant="secondary" onClick={() => router.push("/")}>
              Back to Explore
            </Button>
          </>
        }
      >
        <p>
          {name} (${symbol.toUpperCase()}) is live. It now appears in Explore, you&apos;re the creator others will see on
          it, and anyone can follow it.
        </p>
      </StateCard>
    );
  }

  const createLabel = !isConnected
    ? "Connect wallet"
    : status === "signing"
      ? "Confirm in wallet…"
      : status === "confirming"
        ? "Publishing…"
        : "Publish strategy";
  const submitDisabled = isConnected && !canSubmit;
  const activeStepIndex = status === "signing" || status === "confirming" ? 5 : step;
  const continueDisabled = stepErrors[step].length > 0;

  function renderChip(option: ConstituentOption) {
    const selected = selectedAddresses.has(option.address);
    const atCapacity = !selected && selectedRows.length >= MAX_CONSTITUENTS;
    const disabled = !option.eligible || atCapacity;

    return (
      <button
        key={option.address}
        type="button"
        className={styles.chip}
        data-tone={optionTone(option)}
        aria-pressed={selected}
        disabled={disabled}
        title={
          !option.eligible
            ? option.reason
            : atCapacity
              ? `Maximum ${MAX_CONSTITUENTS} constituents`
              : selected
                ? `Remove ${option.symbol}`
                : `Add ${option.symbol}`
        }
        onClick={() => toggleOption(option)}
      >
        <span className={styles.chipTone} aria-hidden="true" />
        {option.isStrategyToken ? <LayersIcon className={styles.chipLayers} /> : null}
        {option.symbol}
        {!option.eligible ? <span className={styles.chipMeta}>Locked</span> : null}
      </button>
    );
  }

  const allChips = [...stockOptions, ...strategyOptions];
  const categoryLabel = CATEGORY_OPTIONS.find((option) => option.slug === category)?.label;

  function renderStep1() {
    return (
      <section className={styles.section} aria-labelledby="create-identity">
        <div className={styles.sectionHead}>
          <h2 id="create-identity" className={styles.sectionTitle}>
            Name &amp; ticker
          </h2>
        </div>
        <p className={styles.sectionHint}>What should people call this strategy, and its ticker on Explore.</p>
        <div className={styles.fields}>
          <label className="field">
            <span className="field__label">Name</span>
            <input
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="AI Will Win"
              className="input"
              autoFocus
            />
          </label>
          <label className="field">
            <span className="field__label">Ticker</span>
            <input
              value={symbol}
              onChange={(event) => setSymbol(event.target.value)}
              placeholder="AIWIN"
              maxLength={IS_V2 ? MAX_SYMBOL_BYTES : 11}
              className="input"
            />
          </label>
        </div>
      </section>
    );
  }

  function renderStep2() {
    return (
      <section className={styles.section} aria-labelledby="create-thesis">
        <div className={styles.sectionHead}>
          <h2 id="create-thesis" className={styles.sectionTitle}>
            Thesis
          </h2>
        </div>
        <p className={styles.sectionHint}>What do you believe, in one sentence? This is what people read first.</p>
        <label className="field">
          <span className="field__label">Thesis</span>
          <textarea
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            placeholder="AI infrastructure will define the next decade."
            rows={3}
            className={`input ${styles.textarea}`}
            aria-invalid={utf8Bytes(description) > MAX_DESCRIPTION_BYTES}
          />
          <span className={styles.counter} data-over={utf8Bytes(description) > MAX_DESCRIPTION_BYTES ? "" : undefined}>
            {utf8Bytes(description)}/{MAX_DESCRIPTION_BYTES} bytes
          </span>
        </label>

        <div className="flex flex-col gap-2">
          <h3 className={styles.sectionTitle}>Category</h3>
          <div className={styles.chipGrid} role="radiogroup" aria-label="Category">
            {CATEGORY_OPTIONS.map((option) => (
              <button
                key={option.slug}
                type="button"
                role="radio"
                aria-checked={category === option.slug}
                className={styles.chip}
                data-selected={category === option.slug ? "" : undefined}
                onClick={() => setCategory(option.slug)}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>

        <div className="field">
          <label className="field__label" htmlFor="create-tag-input">
            Additional tags (optional)
          </label>
          <div className={styles.tagEntry}>
            <input
              id="create-tag-input"
              value={tagDraft}
              onChange={(event) => setTagDraft(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter" || event.key === ",") {
                  event.preventDefault();
                  addTag();
                }
              }}
              placeholder="growth"
              className="input"
              disabled={extraTags.length >= MAX_EXTRA_TAGS}
              aria-invalid={draftInvalid}
            />
            <Button
              size="sm"
              variant="secondary"
              onClick={addTag}
              disabled={!draftTag || draftInvalid || extraTags.length >= MAX_EXTRA_TAGS || extraTags.includes(draftTag)}
            >
              Add
            </Button>
          </div>
          <span className={styles.counter} data-over={draftInvalid ? "" : undefined}>
            {draftTag ? `${utf8Bytes(draftTag)}/${MAX_TAG_BYTES} bytes · ` : ""}
            {extraTags.length}/{MAX_EXTRA_TAGS} extra tags · lowercase letters, digits and dashes
          </span>
          {extraTags.length > 0 ? (
            <ul className={styles.tagList}>
              {extraTags.map((tag) => (
                <li key={tag}>
                  <button type="button" className={styles.tag} onClick={() => removeTag(tag)} aria-label={`Remove tag ${tag}`}>
                    {tag}
                    <span aria-hidden="true"> ×</span>
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      </section>
    );
  }

  function renderStep3() {
    return (
      <>
        {IS_V2 && liveAvailable ? (
          <section className={styles.section} aria-labelledby="create-universe">
            <div className={styles.sectionHead}>
              <h2 id="create-universe" className={styles.sectionTitle}>
                Universe
              </h2>
              {universe === "live" ? <Badge tone="amber">Live assets</Badge> : null}
            </div>
            <div className={styles.universeSwitch} role="group" aria-label="Universe">
              {(["sandbox", "live"] as const).map((option) => (
                <button
                  key={option}
                  type="button"
                  className={styles.universeOption}
                  aria-pressed={universe === option}
                  onClick={() => changeUniverse(option)}
                >
                  {option === "sandbox" ? "Sandbox" : "Live"}
                </button>
              ))}
            </div>
            {universe === "live" ? (
              <p className={styles.universeNote}>
                Live strategies hold real testnet stock tokens and Paxos USDG, which their issuers control. Get test
                funds from the{" "}
                <a href={PAXOS_FAUCET_URL} target="_blank" rel="noreferrer">
                  Paxos faucet
                </a>{" "}
                and the{" "}
                <a href={ROBINHOOD_FAUCET_URL} target="_blank" rel="noreferrer">
                  Robinhood faucet
                </a>
                .
              </p>
            ) : (
              <p className={styles.universeNote}>Sandbox strategies hold mock tokens priced by the Feng oracle.</p>
            )}
          </section>
        ) : null}

        <section className={styles.section} aria-labelledby="create-tokens">
          <div className={styles.sectionHead}>
            <h2 id="create-tokens" className={styles.sectionTitle}>
              Select stocks
            </h2>
            <p className={styles.sectionHint}>
              {selectedRows.length}/{MAX_CONSTITUENTS} in basket
            </p>
          </div>
          <div className={styles.chipGrid}>
            {optionsLoading && allChips.length === 0
              ? Array.from({ length: 8 }, (_, index) => (
                  <div key={index} className={styles.skeletonChip} aria-hidden="true" />
                ))
              : allChips.map(renderChip)}
          </div>
          {optionsError ? (
            <Notice tone="error" role="alert">
              Could not check which tokens the desk supports. Locked tokens unlock once the connection is back. Reload the
              page to try again.
            </Notice>
          ) : null}
        </section>

        <section className={styles.section} aria-labelledby="create-basket">
          <div className={styles.sectionHead}>
            <h2 id="create-basket" className={styles.sectionTitle}>
              Set allocation to 100%
            </h2>
            {selectedRows.length > 0 ? (
              <button type="button" className="text-button" onClick={splitEven}>
                Even split
              </button>
            ) : null}
          </div>

          {selectedRows.length === 0 ? (
            <p className={styles.empty}>Tap stocks above to build the basket.</p>
          ) : (
            <div className={styles.basketList}>
              {selectedRows.map((row) => {
                const option = optionByAddress.get(row.address);
                const ticker = option?.symbol ?? "—";
                return (
                  <div key={row.id} className={styles.basketRow}>
                    <span className={styles.basketIdentity}>
                      <span
                        className={styles.chipTone}
                        data-tone={option ? optionTone(option) : "slate"}
                        aria-hidden="true"
                      />
                      {option?.isStrategyToken ? <LayersIcon className={styles.chipLayers} /> : null}
                      {ticker}
                    </span>
                    <input
                      type="range"
                      className={styles.slider}
                      style={{ "--fill": `${row.weightPercent}%` } as CSSProperties}
                      min={0}
                      max={100}
                      step={0.5}
                      value={row.weightPercent}
                      aria-label={`Weight for ${ticker}`}
                      onChange={(event) => updateWeight(row.id, Number(event.target.value))}
                    />
                    <input
                      type="number"
                      min={0}
                      max={100}
                      step={0.5}
                      value={row.weightPercent}
                      aria-label={`Weight percent for ${ticker}`}
                      className={`input num ${styles.weightInput}`}
                      data-size="sm"
                      data-align="end"
                      onChange={(event) => updateWeight(row.id, Number(event.target.value))}
                    />
                    <span className={styles.percentMark}>%</span>
                    <button
                      type="button"
                      className={styles.remove}
                      aria-label={`Remove ${ticker}`}
                      onClick={() => removeRow(row.id)}
                    >
                      Remove
                    </button>
                  </div>
                );
              })}
            </div>
          )}
          <p className={styles.depthNote}>Depth max 2 · nested Strategy Tokens are cycle-checked.</p>
        </section>

        <details className={styles.advanced}>
          <summary className="text-button">Advanced settings</summary>
          <div className={styles.metaFields}>
            <div className={styles.fields}>
              <label className="field">
                <span className="field__label">Max weight per asset</span>
                <input
                  type="number"
                  min={1}
                  max={100}
                  value={maxWeightPercent}
                  onChange={(event) => setMaxWeightPercent(Number(event.target.value))}
                  className="input num"
                />
              </label>
              <label className="field">
                <span className="field__label">Rebalance</span>
                <div className="select">
                  <select value={intervalSeconds} onChange={(event) => setIntervalSeconds(Number(event.target.value))}>
                    {REBALANCE_INTERVALS.map((interval) => (
                      <option key={interval.seconds} value={interval.seconds}>
                        {interval.label}
                      </option>
                    ))}
                  </select>
                </div>
              </label>
            </div>
            {IS_V2 ? (
              <label className="field">
                <span className="field__label">Max slippage per trade</span>
                <div className="select">
                  <select value={maxSlippageBps} onChange={(event) => setMaxSlippageBps(Number(event.target.value))}>
                    {CREATE_SLIPPAGE_OPTIONS_BPS.map((option) => (
                      <option key={option} value={option}>
                        {formatSlippage(option)}
                        {option === MAX_SLIPPAGE_BPS ? " (cap)" : ""}
                      </option>
                    ))}
                  </select>
                </div>
              </label>
            ) : null}
          </div>
        </details>
      </>
    );
  }

  function renderStep4() {
    return (
      <section className={styles.section} aria-labelledby="create-review">
        <div className={styles.sectionHead}>
          <h2 id="create-review" className={styles.sectionTitle}>
            Preview
          </h2>
        </div>
        <div className={styles.reviewRow}>
          <span className={styles.reviewLabel}>Strategy</span>
          <span>
            {name.trim() || "Untitled"} · <strong>${symbol.trim().toUpperCase() || "TICKER"}</strong>
          </span>
        </div>
        <div className={styles.reviewRow}>
          <span className={styles.reviewLabel}>Thesis</span>
          <span>{description.trim()}</span>
        </div>
        <div className={styles.reviewRow}>
          <span className={styles.reviewLabel}>Category</span>
          <span className="flex flex-wrap gap-2">
            {categoryLabel ? <Badge tone="violet">{categoryLabel}</Badge> : null}
            {extraTags.map((tag) => (
              <Badge key={tag} tone="neutral">
                #{tag}
              </Badge>
            ))}
          </span>
        </div>
        <div className={styles.reviewRow}>
          <span className={styles.reviewLabel}>Allocation</span>
          <div className="min-w-[14rem] flex-1">
            <StrategyHoldings holdings={holdings.length > 0 ? holdings : undefined} size="stage" />
          </div>
        </div>
        <p className="text-caption text-ink-muted">
          Max weight {maxWeightPercent}% · {intervalLabel.toLowerCase()} · slippage {formatSlippage(maxSlippageBps)}
          {IS_V2 && universe === "live" ? " · live assets" : ""}
        </p>

        {errors.length > 0 || (status === "error" && error) ? (
          <div className={styles.notices}>
            {errors.length > 0 ? (
              <Notice tone="warn">
                <ul>
                  {errors.map((message) => (
                    <li key={message}>{message}</li>
                  ))}
                </ul>
              </Notice>
            ) : null}
            {status === "error" && error ? (
              <Notice tone="error" role="alert">
                {error}{" "}
                <button type="button" onClick={reset} className="text-button" data-underline="">
                  Reset
                </button>
              </Notice>
            ) : null}
          </div>
        ) : null}

        <Button onClick={handleSubmit} disabled={submitDisabled}>
          {createLabel}
        </Button>
        {!isConnected ? <p className={styles.previewHint}>Connect a wallet to publish this strategy.</p> : null}
      </section>
    );
  }

  return (
    <div className={styles.composer}>
      <Card variant="glass" className={styles.main}>
        <StepIndicator activeIndex={activeStepIndex} />
        <AnimatePresence mode="wait" initial={false}>
          <m.div
            key={step}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={STEP_TRANSITION}
            className={styles.stepPanel}
          >
            {step === 1 ? renderStep1() : step === 2 ? renderStep2() : step === 3 ? renderStep3() : renderStep4()}
          </m.div>
        </AnimatePresence>

        {step !== LAST_STEP ? (
          <div className={styles.stepFooter}>
            <Button variant="secondary" onClick={goBack} disabled={step === 1}>
              Back
            </Button>
            <Button onClick={goNext} disabled={continueDisabled}>
              Continue
            </Button>
          </div>
        ) : (
          <div className={styles.stepFooter}>
            <Button variant="secondary" onClick={goBack}>
              Back
            </Button>
          </div>
        )}
      </Card>

      <Card variant="glass" tone="mint" className={styles.preview}>
        <div className={styles.previewIdentity}>
          <p className={styles.previewName}>{name.trim() || "Untitled strategy"}</p>
          <p className={styles.previewTicker}>{symbol.trim() ? symbol.trim().toUpperCase() : "TICKER"}</p>
        </div>

        <div className={styles.previewRing} aria-live="polite">
          <ProgressRing percent={totalPercent} complete={isComplete} label="allocated" />
          <p className={styles.previewCaption}>
            Weights must sum to exactly 100% before you can publish.
          </p>
        </div>

        <div className={styles.previewHoldings}>
          <StrategyHoldings holdings={holdings.length > 0 ? holdings : undefined} size="tile" />
        </div>

        <div className={styles.previewMeta}>
          {categoryLabel ? <Badge tone="violet">{categoryLabel}</Badge> : null}
          <Badge tone="mint">{intervalLabel}</Badge>
          <Badge tone="neutral">{selectedRows.length} assets</Badge>
          {IS_V2 && universe === "live" ? <Badge tone="amber">Live assets</Badge> : null}
        </div>

        <div className={styles.previewActions}>
          {step === LAST_STEP ? (
            <Button onClick={handleSubmit} disabled={submitDisabled}>
              {createLabel}
            </Button>
          ) : (
            <Button onClick={goNext} disabled={continueDisabled}>
              Continue
            </Button>
          )}
          {!isConnected ? <p className={styles.previewHint}>Connect a wallet to publish this strategy.</p> : null}
        </div>
      </Card>

      <div className={styles.mobileBar}>
        <div className={styles.mobileAlloc}>
          <span className={styles.mobileAllocValue} data-complete={isComplete ? "" : undefined}>
            {Math.round(totalPercent)}%
          </span>
          <span className={styles.mobileAllocLabel}>Allocated</span>
        </div>
        {step === LAST_STEP ? (
          <Button onClick={handleSubmit} disabled={submitDisabled} size="sm">
            {createLabel}
          </Button>
        ) : (
          <Button onClick={goNext} disabled={continueDisabled} size="sm">
            Continue
          </Button>
        )}
      </div>
    </div>
  );
}
