# `android/` — Android Platform Layer

## 🎯 Role & Overview
Contains the Android native runner, Gradle build scripts, AndroidManifest configurations, permissions, and native service hooks for 1Wallet on Android devices.

---

## 📜 Key Configuration & Files

- **`app/build.gradle` / `build.gradle`**:
  - Configures `minSdkVersion`, `targetSdkVersion`, `compileSdkVersion`, Gradle dependencies, and signing configurations for release builds.
- **`app/src/main/AndroidManifest.xml`**:
  - Permissions declarations:
    - `RECEIVE_SMS` & `READ_SMS` (for offline expense extraction).
    - `BIND_NOTIFICATION_LISTENER_SERVICE` (for banking push notification ingestion).
    - `POST_NOTIFICATIONS` (Android 13+ push alerts).
    - `CAMERA` (receipt OCR scanning).
    - `USE_BIOMETRIC` & `USE_FINGERPRINT` (app lock).
- **`app/src/main/kotlin/com/joelpjoji/one/wallet/`**:
  - Native Kotlin `MainActivity` class and platform channel integrations if any.

---

## 🛡️ Critical Invariants & Architecture

1. **Permission Granularity**:
   - Sensitive permissions (`READ_SMS`, `BIND_NOTIFICATION_LISTENER_SERVICE`) must be guarded by runtime checks in Flutter and never assumed granted.
2. **Release Keystores**:
   - Production keystores and credentials are kept out of version control and injected during GitHub Actions releases.

---

## 🔍 LLM / Developer Checklist

- [ ] When bumping Flutter SDK or dependencies, ensure Gradle compatibility with the current Kotlin and Android Gradle Plugin (AGP) versions.
- [ ] Verify that notification icons are present in `res/drawable` to prevent notification crashes on Android.
