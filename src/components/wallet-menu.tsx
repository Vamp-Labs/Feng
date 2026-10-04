"use client";

import { useEffect, useId, useRef, useState, type FocusEvent } from "react";
import { Button } from "@/components/ui/button";
import { TestFundsPanel } from "@/components/test-funds";
import { useAddNetwork } from "@/lib/hooks/use-add-network";
import { shortenAddress } from "@/lib/format";
import styles from "./wallet-menu.module.css";

const COPIED_RESET_MS = 1_600;

function ChevronDown({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="m6 9 6 6 6-6" />
    </svg>
  );
}

export function WalletMenu({ address, onLogout }: { address: `0x${string}`; onLogout: () => void }) {
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const panelId = useId();
  const addNetwork = useAddNetwork();

  useEffect(() => {
    if (!open) return;
    const closeOnOutsidePress = (event: PointerEvent) => {
      if (event.target instanceof Node && !rootRef.current?.contains(event.target)) setOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      setOpen(false);
      rootRef.current?.querySelector<HTMLButtonElement>("button[aria-controls]")?.focus();
    };
    document.addEventListener("pointerdown", closeOnOutsidePress);
    document.addEventListener("keydown", closeOnEscape);
    return () => {
      document.removeEventListener("pointerdown", closeOnOutsidePress);
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, [open]);

  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), COPIED_RESET_MS);
    return () => window.clearTimeout(timer);
  }, [copied]);

  function closeOnFocusLeave(event: FocusEvent<HTMLDivElement>) {
    if (event.relatedTarget instanceof Node && !event.currentTarget.contains(event.relatedTarget)) setOpen(false);
  }

  async function copyAddress() {
    try {
      await navigator.clipboard.writeText(address);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  }

  const addLabel =
    addNetwork.state === "pending"
      ? "Waiting for wallet…"
      : addNetwork.state === "added"
        ? "Network added"
        : `Add ${addNetwork.chainLabel} to wallet`;

  return (
    <div className={styles.root} ref={rootRef} onBlur={closeOnFocusLeave}>
      <Button
        size="sm"
        variant="secondary"
        className={`nav__cta ${styles.trigger}`}
        aria-expanded={open}
        aria-controls={panelId}
        aria-haspopup="dialog"
        onClick={() => setOpen((value) => !value)}
      >
        {shortenAddress(address)}
        <ChevronDown className={styles.chevron} />
      </Button>
      {open ? (
        <div id={panelId} role="dialog" aria-label="Wallet" className={styles.panel} data-lenis-prevent="">
          <div className={styles.identity}>
            <div className={styles.identityText}>
              <span className="text-overline text-ink-muted">Connected wallet</span>
              <span className={styles.address}>{shortenAddress(address, 6)}</span>
            </div>
            <Button size="sm" variant="ghost" onClick={copyAddress} aria-live="polite">
              {copied ? "Copied" : "Copy"}
            </Button>
          </div>
          <hr className={styles.divider} />
          <TestFundsPanel />
          <hr className={styles.divider} />
          <div className={styles.networkRow}>
            <button
              type="button"
              className="text-button"
              data-underline=""
              onClick={addNetwork.add}
              disabled={addNetwork.state === "pending"}
            >
              {addLabel}
            </button>
            {addNetwork.state === "error" ? (
              <p className="text-caption text-ink-muted" role="alert">
                Your wallet could not add the network. Add it manually from the wallet settings.
              </p>
            ) : null}
          </div>
          <Button variant="secondary" size="sm" onClick={onLogout}>
            Log out
          </Button>
        </div>
      ) : null}
    </div>
  );
}
