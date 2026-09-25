// Stable per-browser-profile device identifier, mirroring the role of
// `CloudSyncMetadata.deviceId` on the Flutter side (used as `lastWriterDeviceId`
// so peers can tell whether the latest cloud write came from this device).

const STORAGE_KEY = '1wallet:web-device-id';

function randomId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return `web-${crypto.randomUUID()}`;
  }
  return `web-${Math.random().toString(36).slice(2)}${Date.now().toString(36)}`;
}

export function getDeviceId(): string {
  try {
    const existing = localStorage.getItem(STORAGE_KEY);
    if (existing && existing.length >= 8) return existing;
    const created = randomId();
    localStorage.setItem(STORAGE_KEY, created);
    return created;
  } catch {
    // localStorage unavailable (private mode / SSR) — fall back to a
    // session-only id so sync can still function without persistence.
    return randomId();
  }
}
