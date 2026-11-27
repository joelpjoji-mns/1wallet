# `web/` — Flutter Web Platform Layer

## 🎯 Role & Overview
Houses the web shell for running 1Wallet as a Flutter Web application: HTML entrypoint, PWA service worker, web app manifest, icons, and splash animation.

---

## 📜 Key Files

- **`index.html`**:
  - Web entrypoint configuring Flutter Web bootstrap script (`flutter.js`), meta viewport, theme color, and splash screen HTML/CSS.
- **`manifest.json`**:
  - Web App Manifest specifying app name (`1Wallet`), icons, start URL, display mode (`standalone`), and theme colors.
- **`prototype/`**:
  - Screen Studio shell (`index.html`, `studio.js`). It hosts the real app, built from `lib/src/app/prototype_main.dart`, at phone sizes for visual testing. It is local-only and never deployed. See `prototype/README.md`.
- **`splash/`**:
  - Native CSS splash assets ensuring a smooth loading screen while the WebAssembly / JavaScript engine downloads.

---

## 🛡️ Critical Invariants & Architecture

1. **Service Worker Caching**:
   - Flutter web service workers cache static assets for offline use. Any update to asset URLs must invalidate old caches gracefully.
2. **Platform Checks**:
   - Web execution uses `web` package (Wasm-ready) rather than legacy `dart:html`.

---

## 🔍 LLM / Developer Checklist

- [ ] Check responsive meta tags and viewport definitions to ensure mobile browser bars don't clip content.
- [ ] Confirm web builds run cleanly via `flutter build web --release`.
- [ ] For UI changes, rebuild and check Screen Studio (`.\scripts\build-prototype.ps1`, `node scripts\serve-prototype.mjs`) following `prototype/README.md`.
- [ ] Add new app routes to the `screens` list in `prototype/studio.js`.
