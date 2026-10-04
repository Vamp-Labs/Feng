"use client";

import { useEffect, useId, useRef, useState } from "react";

export function RealVsSimulated() {
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const root = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const onPointer = (event: PointerEvent) => {
      if (root.current && event.target instanceof Node && !root.current.contains(event.target)) setOpen(false);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false);
        trigger.current?.focus();
      }
    };
    document.addEventListener("pointerdown", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return (
    <div className="real-note" ref={root}>
      <button
        ref={trigger}
        type="button"
        className="real-note__trigger"
        aria-expanded={open}
        aria-controls={panelId}
        onClick={() => setOpen((value) => !value)}
      >
        <span aria-hidden="true" className="real-note__mark">
          ?
        </span>
        What is real, what is simulated
      </button>
      {open ? (
        <div className="real-note__panel" id={panelId} role="region" aria-label="What is real and what is simulated">
          <dl>
            <div>
              <dt>Real</dt>
              <dd>
                The contracts. The vault, share token, registry and rebalance engine run on Robinhood Chain testnet, and every
                number here is read from them.
              </dd>
            </div>
            <div>
              <dt>Simulated</dt>
              <dd>
                The market. Prices come from relayer-fed feeds, not an exchange. Trades fill against a mock desk with a fixed
                spread, and the sandbox stock tokens and USDG are test tokens with no value.
              </dd>
            </div>
            <div>
              <dt>Live universe</dt>
              <dd>
                Strategies marked Live assets hold the real Robinhood faucet stock tokens and Paxos USDG. Prices and fills are
                still the relayer feeds and a small funded desk, so trade size is capped.
              </dd>
            </div>
          </dl>
        </div>
      ) : null}
    </div>
  );
}
