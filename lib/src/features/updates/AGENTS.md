# `lib/src/features/updates/` — In-App Updates & Release Notes

## 🎯 Role & Overview
Checks for newer application releases via Firebase or GitHub releases manifest, presents what's new changelogs, and prompts users to update.

---

## 📜 Key Files

- **`app_update_provider.dart`**:
  - Compares current semantic version (`package_info_plus`) with the remote manifest (`mobile-update-manifest.json`).
  - Emits update availability status (optional vs mandatory update).
- **`updates_screen.dart`**:
  - Modal or screen displaying formatted release notes, version tags, and download action button.

---

## 🛡️ Critical Invariants & Architecture

1. **Semantic Versioning Comparison**:
   - Version comparison must parse SemVer strings (`major.minor.patch+build`) correctly.
2. **Non-Blocking UI**:
   - Update checks must fail silently on network unavailability without blocking normal app usage unless marked as a critical breaking update.
3. **No Account Dependency**:
   - Update checks must keep working in offline mode (no Firebase user). They read public `appUpdates/*` documents (unauthenticated `get` is allowed by `firebase/firestore.rules`) and fall back to the GitHub Releases API. Never gate update checks on `authControllerProvider`.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/updates_screen_test.dart`.
- [ ] Confirm that release notes parser safely handles Markdown headings, bullet points, and hyperlinks.
