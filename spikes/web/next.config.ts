import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // @sabaki/shudan is a Preact component; its docs' documented React
  // compatibility trick is aliasing preact -> react (see spikes/SPIKE_NOTES.md).
  turbopack: {
    resolveAlias: {
      preact: "react",
      "preact/hooks": "react",
    },
  },
};

export default nextConfig;
