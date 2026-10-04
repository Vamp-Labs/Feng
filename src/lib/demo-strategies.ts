import { parseUnits } from "viem";
import { nestedHolding, stockHolding, type Holding } from "@/lib/holding-tones";
import type { StrategySummary } from "@/lib/hooks/use-marketplace";

const DEMO_USDG_DECIMALS = 6;

const usdg = (amount: string) => parseUnits(amount, DEMO_USDG_DECIMALS);

export const DEMO_STRATEGIES: readonly StrategySummary[] = [
  {
    vault: "0xd3a0000000000000000000000000000000000001",
    token: "0xd3a0000000000000000000000000000000000011",
    creator: "0x7a3f00000000000000000000000000000000c0de",
    depth: 2,
    createdAt: 0n,
    name: "Blue Chip Compounder",
    symbol: "BLUE",
    usdgDecimals: DEMO_USDG_DECIMALS,
    totalAssetsUSDG: usdg("248120.5"),
  },
  {
    vault: "0xd3a0000000000000000000000000000000000002",
    token: "0xd3a0000000000000000000000000000000000022",
    creator: "0x9be100000000000000000000000000000000f00d",
    depth: 1,
    createdAt: 0n,
    name: "Stable Yield Ladder",
    symbol: "LADR",
    usdgDecimals: DEMO_USDG_DECIMALS,
    totalAssetsUSDG: usdg("96340.25"),
  },
  {
    vault: "0xd3a0000000000000000000000000000000000003",
    token: "0xd3a0000000000000000000000000000000000033",
    creator: "0x41c800000000000000000000000000000000beef",
    depth: 2,
    createdAt: 0n,
    name: "Arbitrum Momentum Mix",
    symbol: "ARBX",
    usdgDecimals: DEMO_USDG_DECIMALS,
    totalAssetsUSDG: usdg("171890"),
  },
];

const DEMO_VAULTS = new Set<string>(DEMO_STRATEGIES.map((strategy) => strategy.vault));

export const isDemoStrategy = (strategy: Pick<StrategySummary, "vault">) => DEMO_VAULTS.has(strategy.vault);

export const DEMO_HOLDINGS: Readonly<Record<string, readonly Holding[]>> = {
  [DEMO_STRATEGIES[0].vault]: [stockHolding("AMZN", 4000), stockHolding("TSLA", 3000), nestedHolding("LADR", 3000)],
  [DEMO_STRATEGIES[1].vault]: [stockHolding("PLTR", 5000), stockHolding("NFLX", 5000)],
  [DEMO_STRATEGIES[2].vault]: [nestedHolding("BLUE", 4000), stockHolding("AMD", 3500), stockHolding("TSLA", 2500)],
};
