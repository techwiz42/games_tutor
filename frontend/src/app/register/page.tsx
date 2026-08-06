"use client";

import { useState } from "react";
import { useAuth } from "@/lib/auth-context";

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
      <div style={{ maxWidth: 400, margin: "80px auto", padding: 24, textAlign: "center" }}>
        <h1>Check your email</h1>
        <p>
          We sent a confirmation link to <strong>{email}</strong>. Click it to activate your
          account and log in.
        </p>
        <p style={{ marginTop: 16 }}>
          <a href="/login">Back to login</a>
        </p>
      </div>
    );
  }

  return (
    <div style={{ maxWidth: 360, margin: "80px auto", padding: 24 }}>
      <h1>Create an account</h1>
      <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        <input
          type="email"
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <input
          type="text"
          placeholder="Display name (optional)"
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
        />
        <input
          type="password"
          placeholder="Password (min 8 characters)"
          minLength={8}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />
        {error && <p style={{ color: "red" }}>{error}</p>}
        <button type="submit" disabled={submitting}>
          {submitting ? "Creating account..." : "Register"}
        </button>
      </form>
      <p style={{ marginTop: 16 }}>
        Already have an account? <a href="/login">Log in</a>
      </p>
    </div>
  );
}
