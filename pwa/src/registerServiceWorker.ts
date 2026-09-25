// Registers the app-shell-only service worker (see public/sw.js). Guarded to
// production builds so the dev server's HMR / module graph is never cached.
export function registerServiceWorker(): void {
  if (!('serviceWorker' in navigator)) return;
  if (!import.meta.env.PROD) return;

  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((error: unknown) => {
      console.error('Service worker registration failed', error);
    });
  });
}
