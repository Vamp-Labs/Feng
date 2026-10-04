"use client";

import { useCallback, useState } from "react";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import type { Abi, Hash, TransactionReceipt } from "viem";
import { explainError, type DescribedError } from "@/lib/errors";

const TX_FALLBACK_MESSAGE = "Something went wrong submitting the transaction.";
const REVERTED_ON_CHAIN_MESSAGE = "The transaction was mined but reverted on-chain.";

export const GAS_BUFFER_NUMERATOR = 125n;
export const GAS_BUFFER_DENOMINATOR = 100n;

export function bufferGas(estimate: bigint): bigint {
  return (estimate * GAS_BUFFER_NUMERATOR + GAS_BUFFER_DENOMINATOR - 1n) / GAS_BUFFER_DENOMINATOR;
}

export type TxStatus = "idle" | "signing" | "confirming" | "success" | "error";

export interface WriteArgs {
  address: `0x${string}`;
  abi: Abi;
  functionName: string;
  args?: readonly unknown[];
}

interface TxState {
  status: TxStatus;
  hash?: Hash;
  receipt?: TransactionReceipt;
  failure?: DescribedError;
}

const IDLE: TxState = { status: "idle" };

export function useTxFlow() {
  const { address: account } = useAccount();
  const publicClient = usePublicClient();
  const { writeContractAsync, reset: resetWrite } = useWriteContract();
  const [state, setState] = useState<TxState>(IDLE);

  const execute = useCallback(
    async (config: WriteArgs): Promise<TransactionReceipt> => {
      setState({ status: "signing" });
      try {
        if (!publicClient) throw new Error("No network client is available.");
        const estimate = await publicClient.estimateContractGas({
          address: config.address,
          abi: config.abi,
          functionName: config.functionName,
          args: config.args,
          account,
        });
        const hash = await writeContractAsync({ ...config, gas: bufferGas(estimate) });
        setState({ status: "confirming", hash });
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        if (receipt.status !== "success") {
          setState({ status: "error", hash, receipt, failure: { message: REVERTED_ON_CHAIN_MESSAGE, category: "other" } });
          throw new Error(REVERTED_ON_CHAIN_MESSAGE);
        }
        setState({ status: "success", hash, receipt });
        return receipt;
      } catch (error) {
        setState((current) =>
          current.status === "error" ? current : { status: "error", failure: explainError(error, TX_FALLBACK_MESSAGE) },
        );
        throw error;
      }
    },
    [publicClient, account, writeContractAsync],
  );

  const reset = useCallback(() => {
    resetWrite();
    setState(IDLE);
  }, [resetWrite]);

  return {
    send: execute,
    status: state.status,
    hash: state.hash,
    receipt: state.receipt,
    failure: state.failure,
    error: state.failure?.message,
    reset,
  };
}
