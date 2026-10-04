export const MAX_DEPTH = 2;
export const RAW_ASSET_DEPTH = 0;

export function computeResultingDepth(constituentDepths: number[]): number {
  const maxConstituentDepth = constituentDepths.length > 0 ? Math.max(...constituentDepths) : RAW_ASSET_DEPTH;
  return maxConstituentDepth + 1;
}

export interface ConstituentEligibility {
  eligible: boolean;
  reason?: string;
}

export function getConstituentEligibility(candidateDepth: number): ConstituentEligibility {
  const resultingDepth = candidateDepth + 1;
  if (resultingDepth > MAX_DEPTH) {
    return {
      eligible: false,
      reason: `Already at max composition depth (${MAX_DEPTH}) — nesting it would exceed the depth cap.`,
    };
  }
  return { eligible: true };
}

export function wouldExceedMaxDepth(constituentDepths: number[]): boolean {
  return computeResultingDepth(constituentDepths) > MAX_DEPTH;
}
