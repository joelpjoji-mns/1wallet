# `ios/` — iOS Platform Layer

## 🎯 Role & Overview
Houses the native Xcode project, CocoaPods configurations, and iOS-specific permissions (Face ID, Camera, Photos) for 1Wallet on iPhones and iPads.

---

## 📜 Key Configuration & Files

- **`Runner/Info.plist`**:
  - `NSFaceIDUsageDescription`: Required explanation for biometric app lock.
  - `NSCameraUsageDescription`: Required explanation for scanning receipts via OCR.
  - `NSPhotoLibraryUsageDescription`: Required explanation for picking receipt images from the gallery.
- **`Podfile`**:
  - CocoaPods dependency declarations, iOS deployment target specification (`platform :ios, '13.0'`).
- **`Runner.xcodeproj` / `Runner.xcworkspace`**:
  - Xcode project schemes, bundle identifiers (`com.joelpjoji.one.wallet`), and build configurations.

---

## 🛡️ Critical Invariants & Architecture

1. **Permission Descriptions**:
   - iOS will immediately reject app submissions or crash at runtime if usage description strings (`NSFaceIDUsageDescription`, `NSCameraUsageDescription`) are missing when APIs are accessed.

---

## 🔍 LLM / Developer Checklist

- [ ] When adding native iOS plugins, run `pod install` within `ios/` to regenerate `Podfile.lock`.
- [ ] Confirm `Info.plist` strings are clear and user-friendly for App Store review compliance.
