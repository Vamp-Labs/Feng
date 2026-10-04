import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  outputFileTracingIncludes: {
    "/*": ["deployments/**/*.json", "src/lib/dev/*.json"],
  },
};

export default nextConfig;
