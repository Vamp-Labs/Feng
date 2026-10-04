import type { Metadata } from "next";
import { StartGuide } from "@/components/start-guide";

export const metadata: Metadata = {
  title: "Start here | Feng",
  description: "Four steps from a fresh wallet to your first composed strategy.",
};

export default function StartPage() {
  return (
    <div className="page-body page-body--detail">
      <header className="start-head">
        <span className="text-overline text-ink-muted">First run</span>
        <h1 className="text-heading text-ink">Start here</h1>
        <p className="text-lead">Four steps from a fresh wallet to your own composed strategy. Progress is read from the chain.</p>
      </header>
      <StartGuide />
    </div>
  );
}
