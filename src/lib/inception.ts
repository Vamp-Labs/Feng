import { formatUnits } from "viem";

export type ContractVersion = "v1" | "v2";

export const V1_INCEPTION_SHARE_PRICE_USDG = 0.001;

export function resolveContractVersion(): ContractVersion {
  return process.env.NEXT_PUBLIC_CONTRACT_VERSION === "v2" ? "v2" : "v1";
}

export interface ShareSupplySnapshot {
  navUsdg: bigint;
  totalSupply: bigint;
  usdgDecimals: number;
  shareDecimals: number;
}

export function sharePriceUsdg({ navUsdg, totalSupply, usdgDecimals, shareDecimals }: ShareSupplySnapshot): number | undefined {
  if (totalSupply === 0n) return undefined;
  const nav = Number(formatUnits(navUsdg, usdgDecimals));
  const supply = Number(formatUnits(totalSupply, shareDecimals));
  const price = nav / supply;
  return Number.isFinite(price) ? price : undefined;
}

export function sinceInceptionReturn(snapshot: ShareSupplySnapshot): number | undefined {
  const price = sharePriceUsdg(snapshot);
  if (price === undefined) return undefined;
  return price / V1_INCEPTION_SHARE_PRICE_USDG - 1;
}

export function sinceInceptionFromVault(sharePrice: bigint | undefined, inceptionSharePrice: bigint | undefined): number | undefined {
  if (sharePrice === undefined || inceptionSharePrice === undefined || inceptionSharePrice === 0n) return undefined;
  const ratio = Number(sharePrice) / Number(inceptionSharePrice);
  return Number.isFinite(ratio) ? ratio - 1 : undefined;
}

export function formatReturn(value: number | undefined): string {
  if (value === undefined) return "--";
  const percent = value * 100;
  const sign = percent > 0 ? "+" : "";
  return `${sign}${percent.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}%`;
}

export function returnSign(value: number | undefined): "up" | "down" | "flat" | "none" {
  if (value === undefined) return "none";
  const rounded = Math.round(value * 10_000);
  if (rounded > 0) return "up";
  if (rounded < 0) return "down";
  return "flat";
}
