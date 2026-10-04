import { isAddress } from "viem";
import { notFound } from "next/navigation";
import { StrategyDetail } from "@/components/strategy-detail";

export default async function StrategyDetailPage({ params }: PageProps<"/strategy/[vault]">) {
  const { vault } = await params;

  if (!isAddress(vault)) {
    notFound();
  }

  return (
    <div className="page-body page-body--detail">
      <StrategyDetail vault={vault} />
    </div>
  );
}
