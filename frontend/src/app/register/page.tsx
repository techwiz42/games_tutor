"use client";

import { useState } from "react";
import { useAuth } from "@/lib/auth-context";
import {
  authPageWrap,
  authCard,
  authBrand,
  authTitle,
  authSubtitle,
  authInput,
  authButtonPrimary,
  authLink,
  authError,
} from "@/lib/auth-ui";

export default function RegisterPage() {
  const { register } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [registered, setRegistered] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await register(email, password, displayName || undefined);
      setRegistered(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Registration failed");
    } finally {
      setSubmitting(false);
    }
  };

  if (registered) {
    return (
      <div className={authPageWrap}>
        <div className={`${authCard} text-center`}>
          <div className={authBrand}>games_tutor</div>
          <h1 className={authTitle}>Check your email</h1>
          <p className="mt-3 text-sm text-zinc-600 dark:text-zinc-300">
            We sent a confirmation link to <strong>{email}</strong>. Click it to activate your
            account and log in.
          </p>
          <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-300">
            Don&apos;t see it? Check your spam or junk folder.
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
        <h1 className={authTitle}>Create an account</h1>
        <p className={authSubtitle}>Play chess and Go against real engines, with a tutor that tracks your skill.</p>

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
            type="text"
            placeholder="Display name (optional)"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            className={authInput}
          />
          <input
            type="password"
            placeholder="Password (min 8 characters)"
            minLength={8}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className={authInput}
            required
          />

          {error && <div className={authError}>{error}</div>}

          <button type="submit" disabled={submitting} className={authButtonPrimary}>
            {submitting ? "Creating account..." : "Register"}
          </button>
        </form>

        <p className="mt-4 text-center text-xs text-zinc-500 dark:text-zinc-400">
          By registering you agree to our{" "}
          <a href="/terms" className={authLink}>
            Terms
          </a>{" "}
          and{" "}
          <a href="/privacy" className={authLink}>
            Privacy Policy
          </a>
          .
        </p>
        <p className="mt-4 text-center text-sm text-zinc-500 dark:text-zinc-400">
          Already have an account?{" "}
          <a href="/login" className={authLink}>
            Log in
          </a>
        </p>
      </div>
    </div>
  );
}
