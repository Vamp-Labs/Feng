import type { StrategySummary } from "@/lib/hooks/use-marketplace";

export interface Category {
  slug: string;
  label: string;
}

export const CATEGORIES: readonly Category[] = [
  { slug: "ai", label: "AI" },
  { slug: "robotics", label: "Robotics" },
  { slug: "space", label: "Space" },
  { slug: "energy", label: "Energy" },
  { slug: "technology", label: "Technology" },
  { slug: "semiconductors", label: "Semiconductors" },
];

export function categorySlugOf(strategy: Pick<StrategySummary, "tags">): string | undefined {
  return strategy.tags?.[0]?.toLowerCase();
}

export function categoryLabel(slug: string): string {
  return CATEGORIES.find((category) => category.slug === slug)?.label ?? slug;
}
