import type { NextConfig } from "next";

const BACKEND_URL = process.env.BACKEND_INTERNAL_URL || "http://localhost:8000";

const nextConfig: NextConfig = {
  // Next.js 16 dev server rejects requests whose Host header doesn't match a
  // known dev origin (DNS-rebinding protection) -- nginx proxies with the
  // real Host header (games.cyberiad.ai), which this dev server didn't
  // recognize, silently breaking every request through the real domain.
  allowedDevOrigins: ["games.cyberiad.ai"],

  // @sabaki/shudan (the Go board component) is a Preact component; its
  // docs' documented React-compatibility trick is aliasing preact -> react
  // (confirmed working in the Phase 0 spike, see spikes/web/next.config.ts
  // and spikes/SPIKE_NOTES.md).
  turbopack: {
    resolveAlias: {
      preact: "react",
      "preact/hooks": "react",
    },
  },

  // Proxy /api/* to the Phoenix backend server-to-server (Next.js server ->
  // backend, both on this machine) instead of having the browser call the
  // backend's own port directly. This sidesteps needing port 8000 open to
  // the outside world at all -- the browser only ever needs to reach
  // whatever port Next.js itself is on, which already works -- and it
  // eliminates CORS entirely (same-origin requests from the browser's POV).
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: `${BACKEND_URL}/api/:path*`,
      },
    ];
  },
};

export default nextConfig;
