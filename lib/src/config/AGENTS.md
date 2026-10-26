# `lib/src/config/` — App Configuration & Environment

## 🎯 Role & Overview
This directory centralizes environment configuration, API keys, and Firebase options for the Flutter client.

---

## 📜 Key Files

- **`firebase_env.dart`**:
  - Encapsulates `FirebaseOptions` resolution across Android, iOS, macOS, Web, and Windows.
  - Reads environment variables injected via `.env`, Dart defines (`--dart-define`), or platform manifests.

---

## 🛡️ Critical Invariants & Architecture

1. **No Hardcoded Secrets**:
   - Production secrets and private keys must never be committed to source control.
   - Use `.env.example` as the canonical template for required environment keys.
2. **Platform Parity**:
   - Platform checks (`kIsWeb`, `Platform.isAndroid`, etc.) must fail gracefully when running on platforms where Firebase native services are substituted or unsupported.

---

## 🔍 LLM / Developer Checklist

- [ ] When adding a new config key, update `.env.example` and document its purpose and default value.
- [ ] Ensure that mock/stub options are provided for headless testing environments where Firebase native platform channels are unavailable.
