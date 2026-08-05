"use client";

import dynamic from "next/dynamic";

// WebRTC/getUserMedia are browser-only; render client-side only, consistent
// with the go-board-spike page.
const VoiceSpikeInner = dynamic(() => import("./VoiceSpikeInner"), {
  ssr: false,
});

export default function VoiceSpike() {
  return <VoiceSpikeInner />;
}
