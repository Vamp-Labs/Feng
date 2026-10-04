import { isAddress } from "viem";
import { notFound } from "next/navigation";
import { CreatorProfile } from "@/components/creator-profile";

export default async function CreatorProfilePage({ params }: PageProps<"/creator/[address]">) {
  const { address } = await params;

  if (!isAddress(address)) {
    notFound();
  }

  return (
    <div className="page-body">
      <CreatorProfile address={address} />
    </div>
  );
}
