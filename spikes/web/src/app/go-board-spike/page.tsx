"use client";

import dynamic from "next/dynamic";

// Shudan's rendering is non-deterministic between server and client passes
// (a `random` prop used internally for fuzzy stone placement), which produces
// a hydration mismatch under Next.js's default SSR. A go board has no SSR/SEO
// value anyway -- render it client-only.
const GoBoardSpikeInner = dynamic(() => import("./GoBoardSpikeInner"), {
  ssr: false,
});

export default function GoBoardSpike() {
  return <GoBoardSpikeInner />;
}
