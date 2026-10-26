# `ios/Runner/` — iOS Native Runner Target

## 🎯 Role & Overview
Contains the native iOS application target: AppDelegate entrypoint, launch storyboards, asset catalogs, and runtime configuration (`Info.plist`).

---

## 📜 Key Files

- **`Info.plist`**:
  - Configures app display name, bundle ID, orientation support, and permission descriptions (`NSFaceIDUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`).
- **`AppDelegate.swift`**:
  - Swift application delegate initializing Flutter plugins and handling background tasks.
- **`Assets.xcassets/`**:
  - Platform asset catalogs containing the AppIcon set and native launch images.

---

## 🛡️ Critical Invariants & Architecture

1. **Permission Descriptions**:
   - `Info.plist` usage strings must clearly articulate user privacy benefits to ensure App Store compliance.
2. **Background Modes**:
   - Background tasks must respect iOS execution limits to avoid aggressive battery termination.
