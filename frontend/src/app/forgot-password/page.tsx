"use client";

import { useState } from "react";
import { API_URL } from "@/lib/api";
import { authPageWrap, authCard, authBrand, authTitle, authSubtitle, authInput, authButtonPrimary, authLink } from "@/lib/auth-ui";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      await fetch(`${API_URL}/api/auth/forgot-password`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
    } finally {
      // Always show the same confirmation, whether or not the account
      // exists -- the backend intentionally returns the same response either
      // way to avoid leaking account existence.
      setSubmitting(false);
      setSubmitted(true);
    }
  };

  if (submitted) {
    return (
      <div className={authPageWrap}>
        <div className={`${authCard} text-center`}>
          <div className={authBrand}>games_tutor</div>
          <h1 className={authTitle}>Check your email</h1>
          <p className="mt-3 text-sm text-zinc-600 dark:text-zinc-300">
            If that email is registered, a password reset link has been sent.
          </p>
          <p className="mt-6 text-sm">
            <a href="/login" className={authLink}>
              Back to login
            </a>
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className={authPageWrap}>
      <div className={authCard}>
        <div className={authBrand}>games_tutor</div>
        <h1 className={authTitle}>Forgot your password?</h1>
        <p className={authSubtitle}>Enter your email and we&apos;ll send you a reset link.</p>
        <form onSubmit={handleSubmit} className="flex flex-col gap-3">
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className={authInput}
            required
          />
          <button type="submit" disabled={submitting} className={authButtonPrimary}>
            {submitting ? "Sending..." : "Send reset link"}
          </button>
        </form>
        <p className="mt-6 text-center text-sm text-zinc-500 dark:text-zinc-400">
          <a href="/login" className={authLink}>
            Back to login
          </a>
        </p>
      </div>
    </div>
  );
}
