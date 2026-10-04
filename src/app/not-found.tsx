import { StateCard } from "@/components/ui/state-card";
import { ButtonLink } from "@/components/ui/button";

export default function NotFound() {
  return (
    <div className="page-body page-body--detail">
      <div className="mx-auto max-w-2xl">
        <StateCard
          art="empty"
          title="Nothing here"
          actions={<ButtonLink href="/marketplace">Back to marketplace</ButtonLink>}
        >
          <p>This page or strategy address does not exist.</p>
        </StateCard>
      </div>
    </div>
  );
}
