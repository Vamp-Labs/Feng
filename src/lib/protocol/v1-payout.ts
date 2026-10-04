export function exactV1Payout(vaultUsdgBalance: bigint, shares: bigint, totalSupply: bigint): bigint {
  if (totalSupply === 0n) return 0n;
  return (vaultUsdgBalance * shares) / totalSupply;
}
