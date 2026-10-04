import { PageHead } from "@/components/page-head";
import { PositionsList } from "@/components/positions-list";

export default function PositionsPage() {
  return (
    <>
      <PageHead introKey="positions" eyebrow="Your wallet" title="Portfolio" accent="Portfolio">
        Every strategy you&apos;ve participated in, plus the ones you follow.
      </PageHead>
      <div className="page-body">
        <PositionsList />
      </div>
    </>
  );
}
