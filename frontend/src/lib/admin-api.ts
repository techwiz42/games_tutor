import { apiFetch } from "./api";

export type AdminUserRow = {
  id: string;
  email: string;
  last_login_ip: string | null;
  chess_games_played: number;
  chess_rating: number | null;
  go_games_played: number;
  total_tokens_used: number;
  is_admin: boolean;
  banned_at: string | null;
  ban_reason: string | null;
};

async function asJson<T>(res: Response): Promise<T> {
  const data = await res.json();
  if (!res.ok) {
    const error = new Error(data.detail || "Request failed") as Error & { code?: string };
    error.code = data.code;
    throw error;
  }
  return data as T;
}

export async function listAdminUsers(): Promise<AdminUserRow[]> {
  const res = await apiFetch("/api/admin/users");
  const data = await asJson<{ users: AdminUserRow[] }>(res);
  return data.users;
}

export async function banUser(id: string, reason: string): Promise<Pick<AdminUserRow, "id" | "banned_at" | "ban_reason">> {
  const res = await apiFetch(`/api/admin/users/${id}/ban`, {
    method: "POST",
    body: JSON.stringify({ reason }),
  });
  return asJson(res);
}
