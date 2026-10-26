# `.github/workflows/` — Continuous Integration & Deployment Workflows

## 🎯 Role & Overview
Defines GitHub Actions automated pipelines for testing, validating pull requests, building beta binaries, and generating signed production releases for Android and iOS.

---

## 📜 Key Workflow Files

| Workflow | Triggers & Responsibilities |
| :--- | :--- |
| `pr-validation.yml` | Triggered on pull requests to `main`. Executes `flutter analyze`, `flutter test`, and validates release notes with `scripts/validate-pr-release-notes.mjs`. |
| `android-release.yml` | Full Android release pipeline: sets up Java 17, Flutter SDK, decodes signing keystore from secrets, builds signed APK & AAB bundles, generates release tags, and updates the in-app update manifest. |
| `android-stable-release.yml` | Stable production track deployment for Google Play / GitHub Releases. |
| `beta-release.yml` | Fast-track release workflow building preview APKs for internal testers. |
| `ios-release.yml` | macOS runner workflow configuring iOS certificates, provisioning profiles, CocoaPods, and compiling IPA artifacts. |
| `dependabot-auto-merge.yml` | Automatically validates and merges safe Dependabot minor version updates. |

---

## 🛡️ Critical Invariants & Architecture

1. **Deterministic Version Extraction**:
   - Workflows derive versions directly from `pubspec.yaml` (`scripts/mobile-release-info.mjs`). Release tags must match `v<version>`.
2. **Keystore Decoding**:
   - Android release keystores are base64-decoded from secrets during runtime into a temporary runner file and purged upon job completion.

---

## 🔍 LLM / Developer Checklist

- [ ] When adding dependencies to `pubspec.yaml`, check if native setup steps are required in `android-release.yml` or `ios-release.yml`.
- [ ] Ensure any CI script modifications fail gracefully with clear diagnostic annotations.
