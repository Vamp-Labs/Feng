"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAccount } from "wagmi";

const STATIC_LINKS = [
  { href: "/", label: "Explore", match: (path: string) => path === "/" || path.startsWith("/strategy") },
  { href: "/create", label: "Create", match: (path: string) => path.startsWith("/create") },
  { href: "/positions", label: "Portfolio", match: (path: string) => path.startsWith("/positions") },
];

export function NavLinks() {
  const pathname = usePathname();
  const { address } = useAccount();
  const profileHref = address ? `/creator/${address}` : "/positions";

  return (
    <ul className="nav__links">
      {STATIC_LINKS.map((link) => (
        <li key={link.href}>
          <Link
            href={link.href}
            className="nav__link"
            aria-current={link.match(pathname) ? "page" : undefined}
          >
            {link.label}
          </Link>
        </li>
      ))}
      <li>
        <Link
          href={profileHref}
          className="nav__link"
          aria-current={pathname.startsWith("/creator") ? "page" : undefined}
        >
          Profile
        </Link>
      </li>
    </ul>
  );
}
