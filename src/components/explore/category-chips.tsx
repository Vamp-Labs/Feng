"use client";

import { CATEGORIES } from "@/lib/discovery/categories";

export function CategoryChips({
  selected,
  onChange,
}: {
  selected: string | undefined;
  onChange: (slug: string | undefined) => void;
}) {
  return (
    <div className="market-filters__chips" role="group" aria-label="Filter by category">
      <button type="button" className="filter-chip" aria-pressed={selected === undefined} onClick={() => onChange(undefined)}>
        All
      </button>
      {CATEGORIES.map((category) => (
        <button
          key={category.slug}
          type="button"
          className="filter-chip"
          aria-pressed={selected === category.slug}
          onClick={() => onChange(selected === category.slug ? undefined : category.slug)}
        >
          {category.label}
        </button>
      ))}
    </div>
  );
}
