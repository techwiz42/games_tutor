"use client";

import { useEffect, useState } from "react";
import { ProtectedRoute } from "@/lib/protected-route";
import { listAdminUsers, banUser, AdminUserRow } from "@/lib/admin-api";
import { pageWrap, navBar, navBrand, navBrandAccent, card, pageTitle, mutedText, buttonDanger, buttonSecondary, linkButton } from "@/lib/auth-ui";

const bannedBadge = "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-red-100 text-red-700 dark:bg-red-950/50 dark:text-red-400";

function BanModal({
  target,
  onCancel,
  onConfirm,
}: {
  target: AdminUserRow;
  onCancel: () => void;
  onConfirm: (reason: string) => Promise<void>;
}) {
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleConfirm = async () => {
    if (!reason.trim()) {
      setError("A reason is required -- it's included in the email sent to the user.");
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      await onConfirm(reason.trim());
    } catch (err) {
      setError(err instanceof Error ? err.message : "Ban failed");
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className={`${card} w-full max-w-md`}>
        <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-50 mb-1">Ban {target.email}?</h2>
        <p className={`${mutedText} mb-4`}>
          This immediately revokes their access and emails them the reason below, with instructions to appeal to
          pete@cyberiad.ai.
        </p>
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="Reason for the ban (required, shown to the user)"
          rows={3}
          autoFocus
          className="w-full rounded-lg border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-800 px-3 py-2 text-sm text-zinc-900 dark:text-zinc-100 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
        />
        {error && <p className="text-sm text-red-600 dark:text-red-400 mt-2">{error}</p>}
        <div className="flex justify-end gap-2 mt-4">
          <button onClick={onCancel} disabled={submitting} className={buttonSecondary}>
            Cancel
          </button>
          <button onClick={handleConfirm} disabled={submitting} className={buttonDanger}>
            {submitting ? "Banning..." : "Ban account"}
          </button>
        </div>
      </div>
    </div>
  );
}

function AdminContent() {
  const [users, setUsers] = useState<AdminUserRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [banTarget, setBanTarget] = useState<AdminUserRow | null>(null);

  const load = () => {
    listAdminUsers()
      .then(setUsers)
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load users"));
  };

  useEffect(load, []);

  const handleBanConfirm = async (reason: string) => {
    if (!banTarget) return;
    const updated = await banUser(banTarget.id, reason);
    setUsers((prev) => prev?.map((u) => (u.id === updated.id ? { ...u, ...updated } : u)) ?? prev);
    setBanTarget(null);
  };

  return (
    <div className={pageWrap}>
      <header className={navBar}>
        <a href="/dashboard" className={navBrand}>
          games<span className={navBrandAccent}>_tutor</span>
        </a>
        <a href="/dashboard" className={linkButton}>
          Back to dashboard
        </a>
      </header>

      <main className="max-w-5xl mx-auto">
        <h1 className={pageTitle}>Admin: users</h1>

        {error && <p className="text-sm text-red-600 dark:text-red-400 mb-4">{error}</p>}

        <div className={card}>
          {users === null ? (
            <p className={mutedText}>Loading...</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm border-collapse">
                <thead>
                  <tr className={`text-left ${mutedText}`}>
                    <th className="px-2 py-1.5 font-medium">Username</th>
                    <th className="px-2 py-1.5 font-medium">Last login IP</th>
                    <th className="px-2 py-1.5 font-medium">Chess games</th>
                    <th className="px-2 py-1.5 font-medium">Chess rating</th>
                    <th className="px-2 py-1.5 font-medium">Go games</th>
                    <th className="px-2 py-1.5 font-medium">Tokens used</th>
                    <th className="px-2 py-1.5 font-medium"></th>
                  </tr>
                </thead>
                <tbody>
                  {users.map((u) => (
                    <tr key={u.id} className="border-b border-zinc-100 dark:border-zinc-800/60 last:border-0">
                      <td className="px-2 py-2 text-zinc-900 dark:text-zinc-50">
                        {u.email}
                        {u.is_admin && <span className={`${mutedText} ml-1.5`}>(admin)</span>}
                      </td>
                      <td className="px-2 py-2 font-mono text-zinc-700 dark:text-zinc-300">{u.last_login_ip ?? "--"}</td>
                      <td className="px-2 py-2 text-zinc-700 dark:text-zinc-300">{u.chess_games_played}</td>
                      <td className="px-2 py-2 text-zinc-700 dark:text-zinc-300">{u.chess_rating ?? "--"}</td>
                      <td className="px-2 py-2 text-zinc-700 dark:text-zinc-300">{u.go_games_played}</td>
                      <td className="px-2 py-2 text-zinc-700 dark:text-zinc-300">{u.total_tokens_used.toLocaleString()}</td>
                      <td className="px-2 py-2">
                        {u.banned_at ? (
                          <span className={bannedBadge} title={u.ban_reason ?? undefined}>
                            Banned
                          </span>
                        ) : u.is_admin ? null : (
                          <button onClick={() => setBanTarget(u)} className={buttonDanger}>
                            Ban
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </main>

      {banTarget && <BanModal target={banTarget} onCancel={() => setBanTarget(null)} onConfirm={handleBanConfirm} />}
    </div>
  );
}

export default function AdminPage() {
  return (
    <ProtectedRoute requireAdmin>
      <AdminContent />
    </ProtectedRoute>
  );
}
