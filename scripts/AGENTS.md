# `scripts/` — Build, Release & Update Automation

## 🎯 Role & Overview
Contains Node.js automation scripts supporting CI/CD, in-app update manifest generation, release note validation, and Firebase hosting deployments.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `mobile-release-info.mjs` | Extracts app version, build number, and commit hash from `pubspec.yaml` and git logs. |
| `generate-play-store-release-notes.mjs` | Extracts changelog from in-app update history or git commits, validates <= 500 characters, and produces Play Store `whatsnew-en-US` and fastlane changelog metadata. |
| `mobile-release-notes.mjs` | Formats and cleans markdown changelogs for GitHub releases. |
| `validate-pr-release-notes.mjs` | CI check verifying that pull requests contain appropriate changelog entries. |
| `validate-android-notification-resources.mjs` | Validates Android APK icons and notification resources. |
| `android-apk-tools.mjs` | Utilities for inspecting and parsing Android APK badging and build tools. |

---

## 🛡️ Critical Invariants & Architecture

1. **Release Notes Integrity**:
   - `whatsnew-en-US` and fastlane changelogs must not exceed 500 characters and must match the target version code.
2. **CI Safety**:
   - Scripts exit with non-zero exit codes if validation fails, preventing broken release assets from deploying.

---

## 🔍 LLM / Developer Checklist

- [ ] When modifying release scripts, test run with `node scripts/<script_name>.mjs` in dry-run mode before triggering GitHub Actions workflows.
