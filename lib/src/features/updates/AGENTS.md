# `lib/src/features/updates/` — In-App Changelog & Release Notes

## 🎯 Role & Overview
Maintains built-in release history and in-app Changelog, presents what's new changelogs, and supplies release metadata for CI/CD deployment pipelines.

---

## 📜 Key Files

- **`app_update_provider.dart`**:
  - Maintains `kBuiltInReleaseHistory` containing structured release notes (`newFeatures`, `bugFixes`, `notes`) for each version.
  - Serves as the primary source of truth for release changelogs used by CI/CD pipelines.

---

## 🛡️ Critical Invariants & Architecture

1. **Semantic Versioning Comparison**:
   - Version comparison must parse SemVer strings (`major.minor.patch+build`) correctly.
2. **Non-Blocking UI**:
   - Update checks and changelog rendering must never block app usage or freeze UI.
3. **No Account Dependency**:
   - Changelog and release notes must be fully accessible in offline mode without requiring sign-in.
4. **Mandatory Changelog Entry on Version Bump**:
   - Every version bump must prepend a new `AppUpdateRelease` entry to `kBuiltInReleaseHistory` with categorized release notes. CI/CD pipelines derive Play Store release notes directly from this structure.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/app_update_version_check_test.dart`.
- [ ] Confirm that release notes parser safely handles Markdown headings, bullet points, and hyperlinks.
