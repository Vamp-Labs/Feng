import { ExploreView } from "@/components/explore/explore-view";
import { PageHead } from "@/components/page-head";

export default function HomePage() {
  return (
    <>
      <PageHead
        introKey="explore"
        eyebrow="Explore"
        title="Turn a thesis into a strategy"
        accent="thesis"
      >
        Read what creators believe, check the allocation, follow it, and participate with test funds.
      </PageHead>
      <div className="page-body">
        <ExploreView />
      </div>
    </>
  );
}
