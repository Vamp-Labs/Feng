import Image from "next/image";
import Link from "next/link";
import { FooterMotion } from "@/components/motion/footer-motion";
import { HealthBadge } from "@/components/health-badge";
import { ArrowUpRight, GridIcon, PlusIcon, WalletIcon } from "@/components/ui/icons";
import { loadActiveNetworkConfig } from "@/lib/addresses";
import { getActiveNetworkDefinition } from "@/lib/networks";
import { shortenAddress } from "@/lib/format";
import { IS_V2 } from "@/lib/protocol";

const YEAR = new Date().getFullYear();

const INTERNAL_LINKS = [
  { href: "/marketplace", label: "Marketplace", Icon: GridIcon },
  { href: "/create", label: "Create a strategy", Icon: PlusIcon },
  { href: "/positions", label: "Your positions", Icon: WalletIcon },
] as const;

export function SiteFooter() {
  const network = getActiveNetworkDefinition();
  const { addresses } = loadActiveNetworkConfig();
  const registryHref = network.explorerUrl
    ? `${network.explorerUrl}/address/${addresses.marketplaceRegistry}`
    : undefined;

  return (
    <footer className="site-footer" data-anim="pending" data-footer>
      <div className="site-footer__edge" aria-hidden="true">
        <svg className="site-footer__notch" viewBox="0 0 80 52" preserveAspectRatio="xMinYMin meet" focusable="false" data-footer-notch data-reveal>
          <path d="M 79.1 0.5 L 71.2 3.1 L 67.3 5.8 L 63.3 9.7 L 59.3 17.6 L 55.4 30.8 L 51.4 34.8 L 47.5 38.7 L 43.5 40.1 L 15.8 41.4 L 11.9 42.7 L 7.9 45.3 L 4 48 L 0 51.9" />
        </svg>
        <span className="site-footer__line" data-footer-line data-reveal />
      </div>
      <div className="site-footer__inner">
        <Link className="site-footer__logo" href="/" aria-label="Feng home" data-footer-item="logo" data-reveal>
          <Image src="/img/feng-logo.png" alt="Feng" width={401} height={150} className="site-footer__wordmark" />
        </Link>
        <ul className="site-footer__links">
          {INTERNAL_LINKS.map(({ href, label, Icon }) => (
            <li key={href} data-footer-item="social" data-reveal>
              <Link className="site-footer__social" href={href} aria-label={label} title={label}>
                <Icon className="site-footer__icon" />
              </Link>
            </li>
          ))}
          {network.explorerUrl ? (
            <li data-footer-item="social" data-reveal>
              <a
                className="site-footer__social"
                href={network.explorerUrl}
                target="_blank"
                rel="noreferrer"
                aria-label={`${network.label} explorer`}
                title={`${network.label} explorer`}
              >
                <ArrowUpRight className="site-footer__icon" />
              </a>
            </li>
          ) : null}
        </ul>
        <p className="site-footer__copy" data-footer-item="copy" data-reveal>
          © {YEAR} Feng. Composable Strategy Tokens over tokenized stocks.
        </p>
        <ul className="site-footer__legal">
          <li data-footer-item="legal" data-reveal>
            {network.label}
          </li>
          <li data-footer-item="legal" data-reveal>
            Max depth 2, cycle-checked
          </li>
          {registryHref ? (
            <li data-footer-item="legal" data-reveal>
              <a className="site-footer__legal-link" href={registryHref} target="_blank" rel="noreferrer">
                Registry {shortenAddress(addresses.marketplaceRegistry)}
              </a>
            </li>
          ) : null}
        </ul>
        {IS_V2 ? (
          <p className="site-footer__health">
            <HealthBadge />
          </p>
        ) : null}
      </div>
      <FooterMotion />
    </footer>
  );
}
