import type { Address } from "viem";
import { engineV2Abi, marketplaceRegistryV2Abi } from "./abi";
import type { Deployment } from "./config";
import { BudgetExceededError, shortError, type Budget, type OpsClients } from "./rpc";

export type ScanResult = {
  count: number;
  needing: Address[] | null;
  errors: string[];
};

async function scanPage(
  clients: OpsClients,
  budget: Budget,
  engine: Address,
  offset: number,
  limit: number,
  errors: string[],
): Promise<Address[] | null> {
  try {
    const page = await clients.call(budget, `checkUpkeepRange ${offset}+${limit}`, () =>
      clients.client.readContract({
        address: engine,
        abi: engineV2Abi,
        functionName: "checkUpkeepRange",
        args: [BigInt(offset), BigInt(limit)],
      }),
    );
    return [...page];
  } catch (error) {
    if (limit <= 1 || error instanceof BudgetExceededError) {
      errors.push(`checkUpkeepRange ${offset}+${limit} failed: ${shortError(error)}`);
      return null;
    }
    const half = Math.ceil(limit / 2);
    const first = await scanPage(clients, budget, engine, offset, half, errors);
    const second = await scanPage(clients, budget, engine, offset + half, limit - half, errors);
    if (first === null && second === null) return null;
    return [...(first ?? []), ...(second ?? [])];
  }
}

export async function strategyCount(clients: OpsClients, budget: Budget, deployment: Deployment): Promise<number> {
  const total = await clients.call(budget, "strategyCount", () =>
    clients.client.readContract({
      address: deployment.addresses.marketplaceRegistry,
      abi: marketplaceRegistryV2Abi,
      functionName: "strategyCount",
    }),
  );
  return Number(total);
}

export async function scanUpkeepV2(
  clients: OpsClients,
  budget: Budget,
  deployment: Deployment,
  pageSize: number,
  count: number,
): Promise<ScanResult> {
  const errors: string[] = [];
  const found: Address[] = [];
  let pages = 0;
  let unreadable = 0;
  for (let offset = 0; offset < count; offset += pageSize) {
    pages += 1;
    const page = await scanPage(clients, budget, deployment.addresses.rebalanceEngine, offset, pageSize, errors);
    if (page === null) unreadable += 1;
    else found.push(...page);
  }
  const needing = pages > 0 && unreadable === pages ? null : [...new Set(found)];
  return { count, needing, errors };
}

export async function listVaultsV2(
  clients: OpsClients,
  budget: Budget,
  deployment: Deployment,
  pageSize: number,
  count: number,
): Promise<Address[]> {
  const vaults: Address[] = [];
  for (let offset = 0; offset < count; offset += pageSize) {
    const page = await clients.call(budget, `getStrategies ${offset}`, () =>
      clients.client.readContract({
        address: deployment.addresses.marketplaceRegistry,
        abi: marketplaceRegistryV2Abi,
        functionName: "getStrategies",
        args: [BigInt(offset), BigInt(pageSize)],
      }),
    );
    vaults.push(...page);
  }
  return vaults;
}
