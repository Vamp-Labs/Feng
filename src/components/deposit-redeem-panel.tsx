"use client";

import { DepositRedeemPanelV1 } from "@/components/deposit-redeem-panel-v1";
import { DepositRedeemPanelV2 } from "@/components/deposit-redeem-panel-v2";
import type { DepositRedeemPanelProps } from "@/components/deposit-redeem-panel-props";
import { IS_V2 } from "@/lib/protocol";

export type { DepositRedeemPanelProps } from "@/components/deposit-redeem-panel-props";

export function DepositRedeemPanel(props: DepositRedeemPanelProps) {
  return IS_V2 ? <DepositRedeemPanelV2 {...props} /> : <DepositRedeemPanelV1 {...props} />;
}
