"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { setTokens, API_URL } from "@/lib/api";
import { useAuth } from "@/lib/auth-context";

function ConfirmEmailInner() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { refreshUser } = useAuth();
  const [status, setStatus] = useState<"confirming" | "success" | "error">("confirming");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const token = searchParams.get("token");
    if (!token) {
      setStatus("error");
      setError("Missing confirmation token.");
      return;
    }

    fetch(`${API_URL}/api/auth/confirm-email`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token }),
    })
      .then(async (res) => {
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "Confirmation failed");
        setTokens(data.access_token, data.refresh_token);
        setStatus("success");
        await refreshUser();
        setTimeout(() => router.push("/dashboard"), 1200);
      })
      .catch((err) => {
        setStatus("error");
        setError(err instanceof Error ? err.message : "Confirmation failed");
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div style={{ maxWidth: 400, margin: "80px auto", padding: 24, textAlign: "center" }}>
      {status === "confirming" && <p>Confirming your account...</p>}
      {status === "success" && <p>Your account is confirmed! Taking you to your dashboard...</p>}
      {status === "error" && (
        <>
          <p style={{ color: "red" }}>{error}</p>
          <p>
            The link may have expired. <a href="/login">Back to login</a>, or request a new
            confirmation email from there.
          </p>
        </>
      )}
    </div>
  );
}

export default function ConfirmEmailPage() {
  return (
    <Suspense fallback={<div style={{ padding: 24 }}>Loading...</div>}>
      <ConfirmEmailInner />
    </Suspense>
  );
}
