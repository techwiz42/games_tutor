"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "./auth-context";

/** Wrap any page's content: redirects to /login if not authenticated, once the
 * initial /me check has resolved (avoids a flash-redirect while still loading).
 * `requireAdmin` additionally redirects non-admins to /dashboard -- a client-side
 * convenience only, the real gate is the backend's RequireAdmin plug. */
export function ProtectedRoute({ children, requireAdmin }: { children: React.ReactNode; requireAdmin?: boolean }) {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    if (!user) {
      router.replace("/login");
    } else if (requireAdmin && !user.is_admin) {
      router.replace("/dashboard");
    }
  }, [loading, user, requireAdmin, router]);

  if (loading) {
    return <div style={{ padding: 24 }}>Loading...</div>;
  }

  if (!user || (requireAdmin && !user.is_admin)) {
    return null;
  }

  return <>{children}</>;
}
