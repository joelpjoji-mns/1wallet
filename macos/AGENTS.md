# `macos/` — macOS Desktop Platform Layer

## 🎯 Role & Overview
Houses the native macOS desktop runner, window management, entitlement declarations, and CocoaPods configurations.

---

## 📜 Key Configuration & Files

- **`Runner/DebugProfile.entitlements` & `Release.entitlements`**:
  - Sandboxing entitlements (network client, file access, camera access if enabled).
- **`Podfile`**:
  - macOS CocoaPods dependencies and deployment target.
- **`Runner/Configs/`**:
  - App name, version, and copyright definitions.

---

## 🛡️ Critical Invariants & Architecture

1. **App Sandbox Entitlements**:
   - macOS apps run in a sandbox. Network communication (`com.apple.security.network.client`) and file selection must have appropriate entitlements declared.

---

## 🔍 LLM / Developer Checklist

- [ ] Ensure that desktop window resizing handles responsive layouts gracefully without overflow errors.
