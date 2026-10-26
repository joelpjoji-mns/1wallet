# `scripts/` — Build, Release & Update Automation

## 🎯 Role & Overview
Contains Node.js automation scripts supporting CI/CD, in-app update manifest generation, release note validation, and Firebase hosting deployments.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `mobile-release-info.mjs` | Extracts app version, build number, and commit hash from `pubspec.yaml` and git logs. |
| `mobile-release-notes.mjs` | Formats and cleans markdown changelogs for in-app updates and GitHub releases. |
| `mobile-update-manifest.mjs` | Generates `mobile-update-manifest.json` pointing to release APKs, minimum required versions, and release hashes. |
| `publish-mobile-update-to-firebase.mjs` | Publishes update manifests and assets to Firebase Remote Config or Hosting. |
| `validate-pr-release-notes.mjs` | CI check verifying that pull requests contain appropriate changelog entries. |

---

## 🛡️ Critical Invariants & Architecture

1. **Manifest Integrity**:
   - `mobile-update-manifest.json` must contain valid semantic versions and secure HTTPS download URLs.
2. **CI Safety**:
   - Scripts exit with non-zero exit codes if validation fails, preventing broken release assets from deploying.

---

## 🔍 LLM / Developer Checklist

- [ ] When modifying release scripts, test run with `node scripts/<script_name>.mjs` in dry-run mode before triggering GitHub Actions workflows.
