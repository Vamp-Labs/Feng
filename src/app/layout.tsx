import type { Metadata, Viewport } from "next";
import { Poppins } from "next/font/google";
import "./globals.css";
import { Providers } from "@/app/providers";
import { loadActiveNetworkConfig } from "@/lib/addresses";
import { NavBar } from "@/components/nav-bar";
import { SiteFooter } from "@/components/site-footer";

const poppins = Poppins({
  variable: "--font-poppins",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
  display: "swap",
});

const SITE_NAME = "Feng";
const SITE_DESCRIPTION = "Rule-based, composable Strategy Tokens over tokenized stocks on Robinhood Chain.";

export const metadata: Metadata = {
  metadataBase: new URL("https://feng-thesis-launchpad.vercel.app"),
  applicationName: SITE_NAME,
  title: { default: `${SITE_NAME}: composable strategy tokens`, template: `%s | ${SITE_NAME}` },
  description: SITE_DESCRIPTION,
  openGraph: {
    type: "website",
    siteName: SITE_NAME,
    title: `${SITE_NAME}: composable strategy tokens`,
    description: SITE_DESCRIPTION,
    images: [{ url: "/img/feng-logo.png", width: 401, height: 150, alt: SITE_NAME }],
  },
  twitter: {
    card: "summary",
    title: `${SITE_NAME}: composable strategy tokens`,
    description: SITE_DESCRIPTION,
    images: ["/img/feng-logo.png"],
  },
};

export const viewport: Viewport = {
  themeColor: "#000718",
  colorScheme: "dark",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  const { network, addresses } = loadActiveNetworkConfig();

  return (
    <html lang="en" className={poppins.variable} suppressHydrationWarning>
      <body className="site antialiased">
        <a className="skip-link" href="#main">
          Skip to main content
        </a>
        <Providers network={network} addresses={addresses}>
          <NavBar />
          <main id="main" className="site-main">
            {children}
          </main>
          <SiteFooter />
        </Providers>
      </body>
    </html>
  );
}
