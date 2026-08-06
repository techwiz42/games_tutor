"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth-context";
import { API_URL } from "@/lib/api";
import {
  authPageWrap,
  authCard,
  authBrand,
  authTitle,
  authSubtitle,
  authInput,
  authButtonPrimary,
  authButtonSecondary,
  authLink,
  authError,
  authDivider,
} from "@/lib/auth-ui";

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
    <div className={authPageWrap}>
      <div className={authCard}>
        <div className={authBrand}>games_tutor</div>
        <h1 className={authTitle}>Welcome back</h1>
        <p className={authSubtitle}>Log in to keep playing and tutoring where you left off.</p>

        <form onSubmit={handleSubmit} className="flex flex-col gap-3">
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className={authInput}
            required
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className={authInput}
            required
          />

          {error && (
            <div className={authError}>
              {error}
              {notConfirmed &&
                (resendSent ? (
                  <p className="mt-1">Confirmation email resent -- check your inbox.</p>
                ) : (
                  <button type="button" onClick={handleResendConfirmation} className="mt-1 underline block">
                    Resend confirmation email
                  </button>
                ))}
            </div>
          )}

          <button type="submit" disabled={submitting} className={authButtonPrimary}>
            {submitting ? "Logging in..." : "Log in"}
          </button>
        </form>

        <div className={authDivider}>
          <span className="flex-1 border-t border-zinc-200 dark:border-zinc-800" />
          or
          <span className="flex-1 border-t border-zinc-200 dark:border-zinc-800" />
        </div>

        <button onClick={handleGoogleLogin} className={authButtonSecondary}>
          Continue with Google
        </button>

        <p className="mt-6 text-center text-sm text-zinc-500 dark:text-zinc-400">
          <a href="/forgot-password" className={authLink}>
            Forgot password?
          </a>
        </p>
        <p className="mt-2 text-center text-sm text-zinc-500 dark:text-zinc-400">
          No account?{" "}
          <a href="/register" className={authLink}>
            Register
          </a>
        </p>
      </div>
    </div>
  );
}
