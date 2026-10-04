export const BPS_DENOMINATOR = 10_000n;

export const SLIPPAGE_OPTIONS_BPS = [50, 100, 200] as const;

export type SlippageBps = (typeof SLIPPAGE_OPTIONS_BPS)[number];

export const DEFAULT_SLIPPAGE_BPS: SlippageBps = 100;

export function minAfterSlippage(amount: bigint, slippageBps: number): bigint {
  const kept = BPS_DENOMINATOR - BigInt(slippageBps);
  return (amount * kept) / BPS_DENOMINATOR;
}

export function nextSlippage(current: number): SlippageBps | undefined {
  return SLIPPAGE_OPTIONS_BPS.find((option) => option > current);
}

export function formatSlippage(bps: number): string {
  return `${(bps / 100).toLocaleString("en-US", { maximumFractionDigits: 2 })}%`;
}
