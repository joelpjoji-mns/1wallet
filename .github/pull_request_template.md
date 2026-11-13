## Summary

-

## Release Scope

- [ ] Android stable release after merge to `main`
- [ ] iOS stable release after merge to `main`
- [ ] Skip release (`skip-release` label required)

## Release Notes

Fill at least one item below unless this PR is labeled `skip-release`. These entries become the GitHub Release notes and in-app OTA changelog.

### New Features

-

### Bug Fixes

-

### Notes

-

## Verification Checklist

- [ ] Financial Invariant: All money representations use integer minor units (`amountMinor`). No `double` math.
- [ ] Offline Guarantee: Offline mode verified with zero network calls or Firestore operations.
- [ ] Observability: No unredacted monetary figures, tokens, or PII in logs or analytics.
- [ ] Test Pyramid: Unit, widget, BDD executable specs (`flutter test test/bdd_suite_test.dart`), and a11y tests pass cleanly.

## Verification Evidence

-
