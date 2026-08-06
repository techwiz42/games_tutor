"use client";

import { ProtectedRoute } from "@/lib/protected-route";
import { useAuth } from "@/lib/auth-context";

function DashboardContent() {
  const { user, logout } = useAuth();

  return (
    <div style={{ padding: 24 }}>
      <h1>games_tutor</h1>
      <p>Signed in as {user?.email} {user?.display_name ? `(${user.display_name})` : ""}</p>
      <p>Account: {user?.has_password ? "password" : ""}{user?.has_password && user?.has_google ? " + " : ""}{user?.has_google ? "Google" : ""}</p>
      <p>
        <a href="/games">Play chess</a>
      </p>
      <button onClick={logout}>Log out</button>
    </div>
  );
}

export default function DashboardPage() {
  return (
    <ProtectedRoute>
      <DashboardContent />
    </ProtectedRoute>
  );
}
