import type { Metadata } from "next";
import { Leaderboard } from "@/components/leaderboard";

export const metadata: Metadata = {
  title: "Leaderboard | Feng",
  description: "Strategy creators ranked by assets under management and best return.",
};

export default function LeaderboardPage() {
  return (
    <div className="page-body page-body--detail">
      <header className="start-head">
        <span className="text-overline text-ink-muted">Creators</span>
        <h1 className="text-heading text-ink">Leaderboard</h1>
        <p className="text-lead">Creators ranked by assets under management, best return since inception, or a simple score.</p>
      </header>
      <Leaderboard />
    </div>
  );
}
