"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { setTokens } from "@/lib/api";
import { useAuth } from "@/lib/auth-context";

export default function AuthCallbackPage() {
  const router = useRouter();
  const { refreshUser } = useAuth();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Tokens arrive in the URL fragment (never sent to any server), not a query
    // string -- see backend/api/auth.py's google_callback for why.
    const hash = window.location.hash.startsWith("#") ? window.location.hash.slice(1) : "";
    const params = new URLSearchParams(hash);
    const accessToken = params.get("access_token");
    const refreshToken = params.get("refresh_token");

    if (!accessToken || !refreshToken) {
      setError("Missing tokens in OAuth callback.");
      return;
    }

    setTokens(accessToken, refreshToken);
    // Clear the fragment from the URL bar before navigating away.
    window.history.replaceState(null, "", "/auth/callback");

    refreshUser().then(() => router.push("/dashboard"));
  }, [router, refreshUser]);

  if (error) {
    return <div style={{ padding: 24 }}>{error} <a href="/login">Back to login</a></div>;
  }

  return <div style={{ padding: 24 }}>Signing you in...</div>;
}
