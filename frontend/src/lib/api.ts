/**
 * Authenticated fetch wrapper: attaches the access token, and on a 401
 * transparently tries exactly one refresh + retry before giving up (avoids an
 * infinite retry loop if the refresh token itself is invalid/revoked).
 */

// Relative/same-origin -- Next.js proxies /api/* to the backend server-to-server
// (see next.config.ts's rewrites()), so the browser never needs to know the
// backend's own host/port at all. Robust regardless of what host/port the
// frontend itself is served from.
const API_URL = "";

const ACCESS_TOKEN_KEY = "games_tutor_access_token";
const REFRESH_TOKEN_KEY = "games_tutor_refresh_token";

export function getAccessToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(ACCESS_TOKEN_KEY);
}

export function getRefreshToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(REFRESH_TOKEN_KEY);
}

export function setTokens(accessToken: string, refreshToken: string) {
  localStorage.setItem(ACCESS_TOKEN_KEY, accessToken);
  localStorage.setItem(REFRESH_TOKEN_KEY, refreshToken);
}

export function clearTokens() {
  localStorage.removeItem(ACCESS_TOKEN_KEY);
  localStorage.removeItem(REFRESH_TOKEN_KEY);
}

export function isAuthenticated(): boolean {
  return getAccessToken() !== null;
}

async function doRefresh(): Promise<boolean> {
  const refreshToken = getRefreshToken();
  if (!refreshToken) return false;

  const res = await fetch(`${API_URL}/api/auth/refresh`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });

  if (!res.ok) {
    clearTokens();
    return false;
  }

  const data = await res.json();
  setTokens(data.access_token, data.refresh_token);
  return true;
}

export async function apiFetch(path: string, options: RequestInit = {}): Promise<Response> {
  const doFetch = () => {
    const accessToken = getAccessToken();
    const headers = new Headers(options.headers);
    if (accessToken) headers.set("Authorization", `Bearer ${accessToken}`);
    if (options.body && !headers.has("Content-Type")) {
      headers.set("Content-Type", "application/json");
    }
    return fetch(`${API_URL}${path}`, { ...options, headers });
  };

  let res = await doFetch();

  if (res.status === 401 && getRefreshToken()) {
    const refreshed = await doRefresh();
    if (refreshed) {
      res = await doFetch();
    }
  }

  return res;
}

export async function logout(): Promise<void> {
  const refreshToken = getRefreshToken();
  if (refreshToken) {
    await fetch(`${API_URL}/api/auth/logout`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: refreshToken }),
    }).catch(() => {
      // Best-effort -- clear local tokens regardless of network failure.
    });
  }
  clearTokens();
}

export { API_URL };
