"use client";

import { useEffect } from "react";
import { Button } from "@/components/ui/button";
import { StateCard } from "@/components/ui/state-card";
import { describeError } from "@/lib/errors";

export default function ErrorPage({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <div className="page-body page-body--detail">
      <div className="mx-auto max-w-2xl">
        <StateCard
          art="error"
          role="alert"
          title="Something went wrong"
          actions={<Button onClick={() => retry()}>Try again</Button>}
        >
          <p>{describeError(error)}</p>
        </StateCard>
      </div>
    </div>
  );
}
