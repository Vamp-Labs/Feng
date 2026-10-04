import Link from "next/link";
import { PixelWordmark } from "@/components/art/pixel-wordmark";
import { NavLinks } from "@/components/nav-links";
import { NetworkBanner } from "@/components/network-banner";
import { WalletConnect } from "@/components/wallet-connect";
import { getActiveNetworkDefinition } from "@/lib/networks";

export function NavBar() {
  const network = getActiveNetworkDefinition();

  return (
    <header className="site-header">
      <nav className="nav" aria-label="Primary">
        <Link href="/" className="nav__brand" aria-label="Feng home">
          <PixelWordmark className="nav__logo" />
        </Link>
        <NavLinks />
        <div className="nav__end">
          <span className="nav__network">{network.label}</span>
          <WalletConnect />
        </div>
      </nav>
      <NetworkBanner />
    </header>
  );
}
