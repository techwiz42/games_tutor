"use client";

import { ProtectedRoute } from "@/lib/protected-route";
import { useAuth } from "@/lib/auth-context";
import { pageWrap, navBar, navBrand, navBrandAccent, card, buttonPrimary, buttonSecondary, mutedText, linkButton } from "@/lib/auth-ui";

function DashboardContent() {
  const { user, logout } = useAuth();

  return (
    <div className={pageWrap}>
      <header className={navBar}>
        <span className={navBrand}>
          games<span className={navBrandAccent}>_tutor</span>
        </span>
        <button onClick={logout} className={buttonSecondary}>
          Log out
        </button>
      </header>

      <main className="max-w-5xl mx-auto grid gap-6 sm:grid-cols-2">
        <section className={`${card} sm:col-span-2`}>
          <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-50">
            Welcome back{user?.display_name ? `, ${user.display_name}` : ""}
          </h1>
          <p className={`${mutedText} mt-1`}>Signed in as {user?.email}</p>
          <div className="flex gap-3 mt-5">
            <a href="/games" className={buttonPrimary}>
              Play now
            </a>
            {user?.is_admin && (
              <a href="/admin" className={buttonSecondary}>
                Admin
              </a>
            )}
          </div>
        </section>

        <section className={card}>
          <h2 className="text-sm font-semibold text-zinc-900 dark:text-zinc-50 mb-2">Links</h2>
          <div className="flex flex-col gap-1 items-start">
            <a href="/attribution" className={linkButton}>
              Attribution
            </a>
            <a href="/terms" className={linkButton}>
              Terms
            </a>
            <a href="/privacy" className={linkButton}>
              Privacy
            </a>
          </div>
        </section>
      </main>
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
