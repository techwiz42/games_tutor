"use client";

import { useState } from "react";
import { API_URL } from "@/lib/api";

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
      <div style={{ maxWidth: 360, margin: "80px auto", padding: 24, textAlign: "center" }}>
        <h1>Check your email</h1>
        <p>If that email is registered, a password reset link has been sent.</p>
        <p>
          <a href="/login">Back to login</a>
        </p>
      </div>
    );
  }

  return (
    <div style={{ maxWidth: 360, margin: "80px auto", padding: 24 }}>
      <h1>Forgot your password?</h1>
      <p>Enter your email and we&apos;ll send you a reset link.</p>
      <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        <input
          type="email"
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <button type="submit" disabled={submitting}>
          {submitting ? "Sending..." : "Send reset link"}
        </button>
      </form>
      <p style={{ marginTop: 16 }}>
        <a href="/login">Back to login</a>
      </p>
    </div>
  );
}
