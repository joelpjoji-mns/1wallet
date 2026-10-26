# `pwa/public/` — PWA Public Static Assets

## 🎯 Role & Overview
Houses static assets served directly by Vite for the PWA client, including `manifest.json`, favicons, app icon PNGs, and offline fallback assets.

---

## 🛡️ Critical Invariants & Architecture

1. **Static Serving**:
   - Files here are served at the root URL path (e.g. `/manifest.json`, `/favicon.ico`).
2. **Web Manifest Consistency**:
   - Ensure color hex values in `manifest.json` align with the design tokens in `lib/src/design/tokens.dart`.
