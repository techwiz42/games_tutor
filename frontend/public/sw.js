const CACHE_NAME = "games-tutor-static-v1";

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

// This app's core value -- real chess/Go engines, real-time voice tutoring --
// requires a live server connection, so there's no meaningful "offline mode"
// to build here. The only thing worth intercepting is Next's fingerprinted
// static assets (content-hashed, safe to cache indefinitely): everything
// else (pages, /api/*, auth) passes straight through to the network
// untouched. This makes repeat loads fast on flaky mobile connections and
// makes the app installable.
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== "GET" || url.origin !== self.location.origin) return;
  if (!url.pathname.startsWith("/_next/static/")) return;

  event.respondWith(
    caches.open(CACHE_NAME).then(async (cache) => {
      const cached = await cache.match(event.request);
      if (cached) return cached;
      const response = await fetch(event.request);
      if (response.ok) cache.put(event.request, response.clone());
      return response;
    })
  );
});
