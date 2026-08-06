"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth-context";
import { API_URL } from "@/lib/api";

export default function LoginPage() {
  const { login } = useAuth();
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notConfirmed, setNotConfirmed] = useState(false);
  const [resendSent, setResendSent] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setNotConfirmed(false);
    setSubmitting(true);
    try {
      await login(email, password);
      router.push("/dashboard");
    } catch (err) {
      const code = (err as Error & { code?: string }).code;
      setNotConfirmed(code === "not_confirmed");
      setError(err instanceof Error ? err.message : "Login failed");
    } finally {
      setSubmitting(false);
    }
  };

  const handleResendConfirmation = async () => {
    await fetch(`${API_URL}/api/auth/resend-confirmation`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email }),
    });
    setResendSent(true);
  };

  const handleGoogleLogin = async () => {
    const res = await fetch(`${API_URL}/api/auth/google/authorize`);
    const data = await res.json();
    window.location.href = data.authorization_url;
  };

  return (
    <div style={{ maxWidth: 360, margin: "80px auto", padding: 24 }}>
      <h1>Log in</h1>
      <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        <input
          type="email"
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <input
          type="password"
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />
        {error && <p style={{ color: "red" }}>{error}</p>}
        {notConfirmed &&
          (resendSent ? (
            <p>Confirmation email resent -- check your inbox.</p>
          ) : (
            <button type="button" onClick={handleResendConfirmation}>
              Resend confirmation email
            </button>
          ))}
        <button type="submit" disabled={submitting}>
          {submitting ? "Logging in..." : "Log in"}
        </button>
      </form>
      <button onClick={handleGoogleLogin} style={{ marginTop: 12, width: "100%" }}>
        Continue with Google
      </button>
      <p style={{ marginTop: 16 }}>
        <a href="/forgot-password">Forgot password?</a>
      </p>
      <p style={{ marginTop: 8 }}>
        No account? <a href="/register">Register</a>
      </p>
    </div>
  );
}
