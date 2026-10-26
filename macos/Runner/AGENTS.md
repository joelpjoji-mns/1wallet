# `macos/Runner/` — macOS Desktop Runner Target

## 🎯 Role & Overview
Contains the native macOS application target: MainFlutterWindow, AppDelegate, and sandboxing entitlement configurations.

---

## 📜 Key Files

- **`MainFlutterWindow.swift`**:
  - Manages the desktop window frame, minimum dimensions, transparency styles, and FlutterViewController embedding.
- **`AppDelegate.swift`**:
  - macOS application lifecycle management.
- **`DebugProfile.entitlements` & `Release.entitlements`**:
  - Apple sandbox permissions (outgoing network client, user-selected files).

---

## 🛡️ Critical Invariants & Architecture

1. **Sandboxing Safety**:
   - macOS apps must run sandboxed with explicit file access entitlements (`com.apple.security.files.user-selected.read-write`) for importing/exporting statement files.
