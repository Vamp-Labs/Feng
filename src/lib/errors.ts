import {
  BaseError,
  ContractFunctionRevertedError,
  HttpRequestError,
  RawContractError,
  TimeoutError,
  UserRejectedRequestError,
  decodeErrorResult,
  formatUnits,
  type Abi,
  type Hex,
} from "viem";
import {
  chainlinkPriceOracleV2Abi,
  fengFaucetAbi,
  marketplaceRegistryV2Abi,
  oracleDeskAbi,
  rebalanceEngineV2Abi,
  strategyFactoryAbi,
  strategyFactoryV2Abi,
  strategyTokenV2Abi,
  strategyVaultAbi,
  strategyVaultV2Abi,
} from "@/lib/abi/generated";
import { socialRegistrySketchAbi } from "@/lib/abi/social-registry-sketch";

const MAX_MESSAGE_LENGTH = 180;

export const NETWORK_UNREACHABLE_MESSAGE =
  "Could not reach the Robinhood Chain testnet RPC. Check your connection and try again.";

export type ErrorCategory =
  | "stale"
  | "liquidity"
  | "slippage"
  | "paused"
  | "child"
  | "weight"
  | "limit"
  | "amount"
  | "balance"
  | "allowance"
  | "feed"
  | "input"
  | "network"
  | "rejected"
  | "other";

export interface DescribedError {
  message: string;
  category: ErrorCategory;
  name?: string;
  limitUsdg?: bigint;
}

interface RevertCopy {
  message: string;
  category: ErrorCategory;
}

const REVERT_COPY: Record<string, RevertCopy> = {
  StalePrice: {
    message: "A price feed for this strategy is stale, so trading through the desk is paused until prices refresh.",
    category: "stale",
  },
  SlippageExceeded: {
    message: "The price moved more than your slippage tolerance. Raise the tolerance or try again.",
    category: "slippage",
  },
  VenueSlippage: {
    message: "The trading desk could not fill this at an acceptable price.",
    category: "liquidity",
  },
  InsufficientLiquidity: {
    message: "The trading desk does not have enough liquidity for this size right now.",
    category: "liquidity",
  },
  SwapTooLarge: {
    message: "This amount is above the per-trade limit. Try a smaller amount, or redeem in kind.",
    category: "limit",
  },
  NotConfigured: { message: "The trading desk is not configured for one of the holdings.", category: "liquidity" },
  UnsupportedPair: { message: "The trading desk does not support one of the holdings.", category: "liquidity" },
  ChildRedeemFailed: {
    message: "A nested strategy inside this one could not be unwound into USDG.",
    category: "child",
  },
  ExceedsMaxWeight: {
    message: "This deposit would push one holding above the strategy's maximum weight.",
    category: "weight",
  },
  EnforcedPause: { message: "Deposits are paused for this strategy. You can still redeem.", category: "paused" },
  ExpectedPause: { message: "This strategy is not paused.", category: "paused" },
  FeedNotSet: { message: "A price feed is not set for one of the holdings.", category: "feed" },
  InvalidPrice: { message: "A price feed returned an invalid price.", category: "feed" },
  ZeroAmount: { message: "Enter an amount greater than zero.", category: "amount" },
  ZeroShares: { message: "This amount is too small to mint any shares.", category: "amount" },
  ZeroAssets: { message: "This amount is too small to return any USDG.", category: "amount" },
  NoValueAdded: { message: "This deposit would add no value to the strategy.", category: "amount" },
  TokenNotConstituent: { message: "That token is not held by this strategy.", category: "input" },
  InvalidSkipMask: { message: "That selection of tokens to skip is not valid.", category: "input" },
  ERC20InsufficientBalance: { message: "Your balance is lower than this amount.", category: "balance" },
  ERC20InsufficientAllowance: { message: "The allowance is lower than this amount. Approve first.", category: "allowance" },
  CheckpointTooSoon: { message: "A checkpoint was recorded recently. Try again later.", category: "other" },
  RebalanceNotNeeded: { message: "This strategy does not need a rebalance right now.", category: "other" },
  NotGuardian: { message: "Only the guardian can do that.", category: "other" },
  EmptyConstituents: { message: "Pick at least one token.", category: "input" },
  TooManyConstituents: { message: "A strategy can hold at most six constituents.", category: "input" },
  ZeroAddressConstituent: { message: "One constituent has no address.", category: "input" },
  DuplicateConstituent: { message: "Each constituent can only be added once.", category: "input" },
  ConstituentIsUsdg: { message: "USDG cannot be a constituent. It is the base asset.", category: "input" },
  UnsupportedConstituent: {
    message: "One of the tokens has no price feed or desk market yet, so it cannot be used.",
    category: "input",
  },
  WeightsMustSumTo10000: { message: "Weights must add up to exactly 100%.", category: "input" },
  WeightTooSmall: { message: "Each weight must be at least 1%.", category: "input" },
  MaxWeightExceeded: { message: "A weight is above the maximum weight you chose.", category: "input" },
  InvalidMaxWeight: { message: "The maximum weight is not valid.", category: "input" },
  InvalidInterval: { message: "The rebalance interval is outside the allowed range.", category: "input" },
  InvalidMaxSlippage: { message: "The max slippage must be between 0.01% and 5%.", category: "input" },
  InvalidName: { message: "The strategy name must be 1 to 48 bytes.", category: "input" },
  InvalidSymbol: { message: "The symbol must be 2 to 10 bytes.", category: "input" },
  UnknownStrategyToken: { message: "A nested strategy token is not from this marketplace.", category: "input" },
  DepthExceeded: { message: "Strategies can nest at most two levels deep.", category: "input" },
  NestedTokenNotLeaf: { message: "Only a strategy without nested strategies can be nested.", category: "input" },
  UnsupportedUsdgDecimals: { message: "The base asset uses an unsupported number of decimals.", category: "other" },
  VenueUsdgMismatch: { message: "The trading desk uses a different base asset.", category: "other" },
  DescriptionTooLong: { message: "The description is longer than 160 bytes.", category: "input" },
  TooManyTags: { message: "Use at most three tags.", category: "input" },
  InvalidTag: { message: "Tags use lowercase letters, digits and dashes, up to 16 bytes each.", category: "input" },
  DuplicateTag: { message: "Each tag can only be used once.", category: "input" },
  AlreadyRegistered: { message: "This strategy is already registered.", category: "other" },
  NotRegistered: { message: "This strategy is not registered in the marketplace.", category: "other" },
  NotRegisteredVault: { message: "This strategy is not registered in the marketplace.", category: "other" },
  AlreadyClaimed: { message: "This wallet already claimed test funds.", category: "other" },
  DailyCapReached: { message: "The faucet reached its daily limit. Try again tomorrow.", category: "other" },
  FaucetEmpty: { message: "The faucet is out of ETH right now.", category: "other" },
  ReentrancyGuardReentrantCall: { message: "The contract rejected a re-entrant call.", category: "other" },
  CannotFollowSelf: { message: "You cannot follow yourself.", category: "input" },
  AlreadyFollowing: { message: "You already follow this.", category: "other" },
  NotFollowing: { message: "You are not following this yet.", category: "other" },
  InvalidHandleLength: { message: "Handles are 3 to 20 characters.", category: "input" },
  InvalidHandleChar: { message: "Handles use lowercase letters, digits, dashes and underscores.", category: "input" },
  HandleTaken: { message: "That handle is already taken.", category: "input" },
  BioTooLong: { message: "The bio is longer than 160 bytes.", category: "input" },
};

type AbiErrorItem = Extract<Abi[number], { type: "error" }>;

function collectErrorItems(abis: readonly Abi[]): AbiErrorItem[] {
  const bySignature = new Map<string, AbiErrorItem>();
  for (const abi of abis) {
    for (const item of abi) {
      if (item.type !== "error") continue;
      bySignature.set(`${item.name}(${item.inputs.map((input) => input.type).join(",")})`, item);
    }
  }
  return [...bySignature.values()];
}

const KNOWN_ERRORS_ABI: Abi = collectErrorItems([
  strategyVaultV2Abi,
  strategyVaultAbi,
  strategyFactoryV2Abi,
  strategyFactoryAbi,
  marketplaceRegistryV2Abi,
  rebalanceEngineV2Abi,
  oracleDeskAbi,
  chainlinkPriceOracleV2Abi,
  strategyTokenV2Abi,
  fengFaucetAbi,
  socialRegistrySketchAbi,
]);

function clip(message: string): string {
  const firstLine = message.split("\n")[0]?.trim() ?? "";
  return firstLine.length > MAX_MESSAGE_LENGTH ? `${firstLine.slice(0, MAX_MESSAGE_LENGTH - 1)}…` : firstLine;
}

function isHex(value: unknown): value is Hex {
  return typeof value === "string" && value.startsWith("0x");
}

function rawRevertData(error: BaseError): Hex | undefined {
  const revert = error.walk((cause) => cause instanceof ContractFunctionRevertedError);
  if (revert instanceof ContractFunctionRevertedError && isHex(revert.raw)) return revert.raw;
  const rawError = error.walk((cause) => cause instanceof RawContractError);
  if (rawError instanceof RawContractError) {
    const data = typeof rawError.data === "object" ? rawError.data?.data : rawError.data;
    if (isHex(data)) return data;
  }
  return undefined;
}

interface DecodedRevert {
  name: string;
  args: readonly unknown[];
}

function decodeKnown(data: Hex): DecodedRevert | undefined {
  try {
    const decoded = decodeErrorResult({ abi: KNOWN_ERRORS_ABI, data });
    return { name: decoded.errorName, args: Array.isArray(decoded.args) ? decoded.args : [] };
  } catch {
    return undefined;
  }
}

function decodeRevert(error: BaseError): DecodedRevert | undefined {
  const revert = error.walk((cause) => cause instanceof ContractFunctionRevertedError);
  if (revert instanceof ContractFunctionRevertedError && revert.data?.errorName) {
    return { name: revert.data.errorName, args: revert.data.args ?? [] };
  }
  const data = rawRevertData(error);
  return data ? decodeKnown(data) : undefined;
}

function unwrapChildRevert(decoded: DecodedRevert): DecodedRevert {
  if (decoded.name !== "ChildRedeemFailed") return decoded;
  const reason = decoded.args[1];
  if (!isHex(reason)) return decoded;
  return decodeKnown(reason) ?? decoded;
}

export function revertName(error: unknown): string | undefined {
  if (!(error instanceof BaseError)) return undefined;
  return decodeRevert(error)?.name;
}

export function isNetworkError(error: unknown): boolean {
  if (!(error instanceof BaseError)) return false;
  return error.walk((cause) => cause instanceof HttpRequestError || cause instanceof TimeoutError) !== null;
}

export function isRevertError(error: unknown): boolean {
  if (!(error instanceof BaseError)) return false;
  return error.walk((cause) => cause instanceof ContractFunctionRevertedError) !== null;
}

export function explainError(error: unknown, fallback = "Something went wrong."): DescribedError {
  if (error instanceof BaseError) {
    if (error.walk((cause) => cause instanceof UserRejectedRequestError)) {
      return { message: "The request was cancelled in your wallet.", category: "rejected" };
    }
    const decoded = decodeRevert(error);
    const unwrapped = decoded ? unwrapChildRevert(decoded) : undefined;
    const name = unwrapped?.name;
    if (name) {
      const copy = REVERT_COPY[name];
      if (copy) {
        const limit = name === "SwapTooLarge" ? unwrapped?.args[1] : undefined;
        return { ...copy, name, ...(typeof limit === "bigint" ? { limitUsdg: limit } : {}) };
      }
    }
    const revert = error.walk((cause) => cause instanceof ContractFunctionRevertedError);
    if (revert instanceof ContractFunctionRevertedError) {
      return {
        message: clip(revert.reason ?? revert.data?.errorName ?? "The contract rejected this request."),
        category: "other",
        name,
      };
    }
    if (isNetworkError(error)) return { message: NETWORK_UNREACHABLE_MESSAGE, category: "network" };
    if (error.shortMessage) return { message: clip(error.shortMessage), category: "other" };
  }
  if (error instanceof Error && error.message) return { message: clip(error.message), category: "other" };
  return { message: fallback, category: "other" };
}

export function swapLimitMessage(limitUsdg: bigint, usdgDecimals: number): string {
  const limit = Number(formatUnits(limitUsdg, usdgDecimals)).toLocaleString("en-US", { maximumFractionDigits: 2 });
  return `This amount is above the per-trade limit of ${limit} USDG. Try a smaller amount, or redeem in kind.`;
}

export function withUsdgDecimals(error: DescribedError | undefined, usdgDecimals: number | undefined): DescribedError | undefined {
  if (!error || error.limitUsdg === undefined || usdgDecimals === undefined) return error;
  return { ...error, message: swapLimitMessage(error.limitUsdg, usdgDecimals) };
}

export function describeError(error: unknown, fallback = "Something went wrong."): string {
  return explainError(error, fallback).message;
}
