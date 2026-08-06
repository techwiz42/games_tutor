"use client";

import { Suspense, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { API_URL } from "@/lib/api";
import { authPageWrap, authCard, authBrand, authTitle, authInput, authButtonPrimary, authLink, authError } from "@/lib/auth-ui";

function ResetPasswordInner() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const token = searchParams.get("token");

  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [success, setSuccess] = useState(false);

  if (!token) {
    return (
      <div className={authPageWrap}>
        <div className={`${authCard} text-center`}>
          <div className={authBrand}>games_tutor</div>
          <div className={authError}>Missing reset token.</div>
          <p className="mt-4 text-sm">
            <a href="/forgot-password" className={authLink}>
              Request a new reset link
            </a>
          </p>
        </div>
      </div>
    );
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (password !== confirmPassword) {
      setError("Passwords don't match.");
      return;
    }

    setSubmitting(true);
    try {
      const res = await fetch(`${API_URL}/api/auth/reset-password`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, password }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "Reset failed");
      setSuccess(true);
      setTimeout(() => router.push("/login"), 1500);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Reset failed");
    } finally {
      setSubmitting(false);
    }
  };

  if (success) {
    return (
      <div className={authPageWrap}>
        <div className={`${authCard} text-center`}>
          <div className={authBrand}>games_tutor</div>
          <p className="text-sm text-zinc-600 dark:text-zinc-300">Password reset. Taking you to login...</p>
        </div>
      </div>
    );
  }

  return (
    <div className={authPageWrap}>
      <div className={authCard}>
        <div className={authBrand}>games_tutor</div>
        <h1 className={authTitle}>Choose a new password</h1>
        <form onSubmit={handleSubmit} className="mt-6 flex flex-col gap-3">
          <input
            type="password"
            placeholder="New password (min 8 characters)"
            minLength={8}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className={authInput}
            required
          />
          <input
            type="password"
            placeholder="Confirm new password"
            minLength={8}
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            className={authInput}
            required
          />
          {error && <div className={authError}>{error}</div>}
          <button type="submit" disabled={submitting} className={authButtonPrimary}>
            {submitting ? "Resetting..." : "Reset password"}
          </button>
        </form>
      </div>
    </div>
  );
}

export default function ResetPasswordPage() {
  return (
    <Suspense fallback={<div style={{ padding: 24 }}>Loading...</div>}>
      <ResetPasswordInner />
    </Suspense>
  );
}
