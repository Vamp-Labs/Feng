import { CreateStrategyForm } from "@/components/create-strategy-form";
import { PageHead } from "@/components/page-head";

export default function CreatePage() {
  return (
    <>
      <PageHead introKey="create" eyebrow="New strategy" title="Turn your thesis into a strategy" accent="strategy">
        Name it, explain what you believe, pick the stocks, and publish it for others to discover and follow.
      </PageHead>
      <div className="page-body">
        <CreateStrategyForm />
      </div>
    </>
  );
}
