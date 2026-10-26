# `lib/src/security/` — App Lock, Biometrics & Gatekeeper

## 🎯 Role & Overview
Implements application locking mechanisms, biometric verification (Face ID / Fingerprint / Touch ID via `local_auth`), user PIN passcode protection, and inactivity timeout detection.

---

## 📜 Key Files

- **`app_lock.dart`**:
  - `AppAuthenticator`: Abstract authentication interface with `LocalAppAuthenticator` implementation.
  - `AppLockState`: Tracks whether the app is currently unlocked, locked, or authenticating.
  - `AppLockController`: StateNotifier managing timeout timers, app lifecycle states (`paused`, `resumed`), and authentication attempts.
  - `AppLockGate`: High-level widget that blankets child views with an opaque biometric unlock prompt whenever `isLocked == true`.

---

## 🛡️ Critical Invariants & Architecture

1. **Zero Data Leakage**:
   - `AppLockGate` must obscure the screen immediately when the app moves to background or locks, preventing screenshots in the OS task switcher from showing financial balances.
2. **Deterministic Fallback**:
   - If biometrics fail or hardware is unavailable, the user can authenticate with the configured backup PIN.
3. **Lifecycle Management**:
   - Automatically re-locks when `inactivityTimeout` expires after backgrounding.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/app_lock_preferences_test.dart`.
- [ ] Ensure `AppAuthenticator` can be mocked cleanly in tests using `FakeAppAuthenticator` without requiring native platform channels.
