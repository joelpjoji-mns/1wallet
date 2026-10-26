# `android/app/` — Android Application Module

## 🎯 Role & Overview
Contains the Android application module configuration, Gradle build configurations, signing keys injection, Kotlin MainActivity, and Android manifest definitions.

---

## 📜 Key Files

- **`build.gradle`**:
  - Defines `compileSdkVersion`, `minSdkVersion` (21+), `targetSdkVersion`, `versionCode`, and `versionName`.
  - Configures Proguard / R8 code shrinking and resource optimization for release APKs.
- **`src/main/AndroidManifest.xml`**:
  - Declares all Android permissions (`RECEIVE_SMS`, `READ_SMS`, `BIND_NOTIFICATION_LISTENER_SERVICE`, `CAMERA`, `POST_NOTIFICATIONS`, `USE_BIOMETRIC`).
  - Registers the Flutter `MainActivity` and notification receiver services.
- **`src/main/kotlin/com/joelpjoji/one/wallet/MainActivity.kt`**:
  - Kotlin entrypoint subclassing `FlutterActivity`. Handles platform channel calls if native bridges are invoked.

---

## 🛡️ Critical Invariants & Architecture

1. **Gradle Build Reproducibility**:
   - `versionCode` and `versionName` are populated dynamically via Flutter CLI parameters (`--build-name` and `--build-number`).
2. **Proguard Obfuscation**:
   - When enabling Proguard/R8 shrinking, ensure rules do not strip serialization reflection or ML Kit model binaries.
