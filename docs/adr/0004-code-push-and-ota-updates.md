# ADR 0004: Evaluation of Shorebird Code-Push vs Existing In-App Updater

## Status
Accepted

## Context
Over-the-air (OTA) code-push allows mobile applications to patch Dart code dynamically without undergoing full app store review cycles. Shorebird offers an OTA solution for Flutter by replacing the Flutter engine with a custom fork that supports patching AOT Dart binaries.

1Wallet already includes an automated build, validation, and in-app updater pipeline in `scripts/`:
- `scripts/mobile-release-info.mjs` extracts version numbers and commit hashes.
- `scripts/validate-android-notification-resources.mjs` verifies APK resource integrity.
- `scripts/mobile-update-manifest.mjs` generates an update manifest (`mobile-update-manifest.json`) containing cryptographic SHA-256 hashes, release notes, and direct download URLs.
- `scripts/publish-mobile-update-to-firebase.mjs` publishes manifests to Firebase Hosting/Remote Config.
- In-app update dialogs (`lib/src/features/updates/updates_screen.dart`) check for verified update manifests and handle installation.

## Decision
We decide **NOT to adopt Shorebird OTA** at this stage, retaining and reinforcing our existing **in-app release manifest updater**:

1. **Supply Chain & Security Integrity**: As a financial app handling encrypted local ledgers and biometric gates, distributing modified Flutter engine binaries from a third-party hosted cloud increases the supply chain attack surface. 1Wallet requires full binary determinism, reproducible builds, and verified cryptographic signatures.
2. **Platform & Store Compliance**: Google Play and Apple App Store policies impose strict restrictions on dynamically altering executable code in financial and banking categories. Bypassing app review for logic changes creates regulatory and store compliance risks.
3. **No Native Asset Patching**: Shorebird cannot patch native Android/iOS code, Flutter plugins with native hooks (such as `flutter_secure_storage`, `local_auth`, or `syncfusion_flutter_pdf`), or Gradle/build configuration changes.
4. **Existing Robust Updater**: 1Wallet's existing in-app updater already handles seamless APK distribution for direct downloads, F-Droid, and beta channels with full SHA-256 validation. Fastlane pipelines (see Phase 5) provide streamlined staging to Google Play and TestFlight.

## Consequences
- Full binary integrity and cryptographic verifiability are preserved.
- No dependency on third-party proprietary patch distribution infrastructure.
- Releases follow standardized Fastlane deployment tracks with full CI verification.
