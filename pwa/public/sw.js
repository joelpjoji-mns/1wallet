// 1Wallet PWA service worker.
//
// IMPORTANT: this worker caches ONLY the static app shell (the built HTML,
// JS, CSS, and icon assets served from this same origin). It must never
// intercept, cache, or otherwise touch requests for authentication or wallet
// data — those all go to different origins (Firebase Auth,
// firestore.googleapis.com, accounts.google.com, etc.), which are skipped
// below via the same-origin check before anything is cached.

const CACHE_NAME = 'onewallet-shell-v1';
const SHELL_URLS = ['/', '/index.html', '/manifest.webmanifest', '/favicon.svg'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(SHELL_URLS))
      .catch(() => {
        // Best-effort precache; individual assets are still cached on first fetch.
      }),
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;

  // Never cache non-GET requests (writes must always hit the network).
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // Never touch cross-origin requests: this is where all Firebase Auth and
  // Firestore wallet-data traffic lives. Let the browser handle them normally
  // so the service worker can never serve stale/cached auth or wallet data.
  if (url.origin !== self.location.origin) return;

  // Skip Firebase Auth's own same-origin popup/redirect handler path, just in
  // case hosting ever proxies it under this origin.
  if (url.pathname.startsWith('/__/auth')) return;

  // Stale-while-revalidate for the static app shell only.
  event.respondWith(
    caches.match(request).then((cached) => {
      const network = fetch(request)
        .then((response) => {
          if (response && response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => cached);
      return cached || network;
    }),
  );
});
