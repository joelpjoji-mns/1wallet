# Changelog

All notable changes to **1Wallet** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [1.0.15] - 2026-11-25

### Added
- Planned details show the actual amount spent, paid, received, or transferred so far. Count-limited plans show payment progress; ongoing plans show totals without a progress bar, and date-limited plans show their end date. Existing loan payoff progress is preserved, and amounts/date/account details remain readable at enlarged text sizes.
- Offline-only mode ("Use without an account"):
  - Run 1Wallet entirely on the device with no Google sign-in, Firebase account, or cloud sync.
  - Includes an explicit consent sheet, offline status in Settings and Sync, and encrypted backup export/import shortcuts.
- "Back up & sync with Google" upgrade for offline wallets:
  - Moves the wallet to a Google account with no data loss.
  - If the account already has a cloud wallet, the user explicitly chooses to keep this device's wallet, use the cloud wallet, or merge both.
- Offline wallets can sign out from Settings or the drawer. After confirmation, this erases the device-only wallet and returns to sign-in, so you no longer need to clear app data in system settings.

### Changed
- The Clear glass finish is now the default for every component, including the island bar, menus, and toolbars. Menus keep a denser tint for legibility.

### Fixed
- Planned-payment and loan details use a compact three-line header (name; subtitle with the amount on the right; status/frequency), a tighter "…so far" summary with a visible progress track, and compact metric tiles. The payment count and end date sit flush with the summary's right edge. Loan actions pair only when their labels fit on one line.
- Summary tiles on Loans, Categories, Currencies, Cards, Imports, Data & Sync, and Data backup keep amounts whole instead of ellipsising, share equal heights, and stack at large text. Section headers, label/value rows, and card tiles no longer break words mid-way at 200% text.
- Login restores full welcome branding on standard phones and balances the action placement without hiding the footer or adding unnecessary scrolling. History uses three equal filter columns and drops the period arrows beside search (swipe the date filter to step periods); Calendar keeps category/account filters side by side. Large-text controls retain full accessible names, and Tags is disabled when no tags exist.
- The welcome screen fits normal phone viewports without scrolling and keeps its privacy footer visible. Short/large-text entry, recovery, and lock screens retain a safe overflow fallback; onboarding and setup pages no longer overscroll when their content fits.
- Loan, planned-payment, capture, and permission actions use aligned, responsive button groups instead of uneven rows.
- Review-queue actions use the same responsive grouping and stack when narrow widths would wrap their labels.
- History filters wrap into visible rows instead of clipping the horizontally scrolling filter strip; large transaction-detail amounts stay on one line.
- Loan detail's scheduled-payment button and next-EMI tile open the correct planned-payment screen.
- Planned-payment details give the name, status, and amounts room to wrap instead of squeezing or truncating them at enlarged text sizes.
- Loan repayment history uses the same full-width grouped rows and page gutters as History, rather than nesting smaller transaction cards inside another panel.
- Native home-widget previews receive explicit render dimensions so Android can generate their bitmaps without infinite-height layout errors.
- Loan, planned-payment, review, capture, feedback, import, and settings actions reflow or use clearer short labels so their text stays on one line in the tested compact layouts.
- Dashboard summaries and transaction rows reflow at larger text sizes instead of squeezing payment details and amounts together.
- Transaction entry keeps the keypad and detail fields reachable on short screens and when the keyboard is open; calculator keys retain usable touch targets.
- Onboarding, cloud-wallet recovery, glass previews, offline consent, and the unknown-route screen adapt to narrow screens and enlarged text.
- Account tiles expose their full names and selection action together to screen readers.
- Planned-payment names have more room, with amounts and due status reflowing on narrow screens.
- Forecast charts keep currency and date labels readable and distinguishable, including multiple dates in the same year. Grouped payoff markers fit their labels at larger text sizes, and zoom controls no longer cover the axis.
- Card icons remain visible when a custom account color has poor contrast with the current theme.
- The drawer privacy switch shows its full label without a redundant on/off suffix.
- Clearing or signing out of an offline wallet no longer fails on Android when an auto-backup left by a previous install cannot be deleted.
- Prevented a startup race when permissions, onboarding, or wallet ownership change before deferred setup runs.
- Prevented an Android widget-sync exception during Flutter web startup.
- Error and status messages are visible again in light and dark themes.
- Appearance settings and transaction-type controls adapt to narrow screens and larger text.
- The calendar scrolls on compact and landscape screens, and the balance header adapts to narrow widths.
- Calendar days can scroll clear of the floating add action when large navigation labels prevent docking.
- Calendar filter and dashboard headings wrap instead of truncating, and the calculator backspace has an accessible label.
- Shortened backup and recurring controls, and restored contrast to unselected glass-finish badges.
- Loan amount fields stack on narrow screens so their labels remain readable.
- Recurring amount and currency controls reflow at large text sizes.
- Opening-balance guidance wraps fully at larger text sizes.
- Currency breakdown chips grow with accessibility text instead of clipping.
- Dashboard account tiles keep account names on one line, use two-dot truncation to show more of long names, and share a uniform height; tiles grow with larger text instead of clipping, and dashboard subtitles reflow.
- The "Cloud wallet found" recovery screen now offers sign-out, and erasing or resetting the local wallet clears stale unsynced-change flags so cloud restore is no longer blocked.
- The Google sign-in label keeps comfortable button padding at larger text sizes.
- Picker rows such as onboarding currency selection are announced as separate buttons.
- Navigation tabs announce their labels once to screen readers.
- Compact action buttons provide 48 dp minimum targets without duplicating their accessible labels.
- At large text sizes, navigation keeps the selected label readable and exposes every tab to screen readers.
- The calendar menu and title are exposed as separate accessibility elements.
- The empty transaction history remains accessible in landscape.
- Tab deep links now select the requested tab and safely fall back to the first tab for invalid indexes.
- Reopening the same tab deep link selects that tab even after switching locally.
- Importing a backup created by another account now re-owns it to the importing offline wallet instead of keeping the foreign account id.
- Background SMS/notification polling now follows the active device wallet owner.

## [2.1.0] - 2026-10-26

### Added
- Comprehensive hierarchical `AGENTS.md` and architectural playbooks across all repository directories.
- Three workspace AI skills in `.agents/skills/`: `1wallet-architecture`, `1wallet-state-and-sync`, and `1wallet-test-runner`.
- Granular domain rules in `.agents/rules/` for financial math, Riverpod state, and offline synchronization.
- Architectural Decision Records (`doc/adr/`) documenting integer minor units, offline sync, and encryption.
- GitHub issue templates for bug reporting and feature requests.
- Centered empty-state components with contextual action icons across accounts, search, and transactions.

### Changed
- Improved `AppTopFadeMask` passthrough layout behavior during list scrolling.
- Hardened Firestore security rules with comprehensive emulator test coverage.

### Fixed
- Fixed empty search view clipping on narrow mobile screens.
- Prevented potential divide-by-zero errors in credit card utilization calculations when credit limit is zero.

---

## [2.0.0] - 2026-09-20

### Added
- Complete Flutter 3.x cross-platform rewrite with Material 3 styling and liquid glass widgets.
- Companion Progressive Web App (React 19 + TypeScript + Vite) in `pwa/`.
- Offline-first Cloud Firestore snapshot synchronization engine with `CloudSyncWriteGuard`.
- On-device Google ML Kit text recognition for camera and gallery receipt capture.
- Android SMS and banking notification spooler with comprehensive regex extraction engine.
- Multi-currency portfolio consolidation with historical and real-time exchange rate caching.
- Biometric hardware app lock (`local_auth`) and AES-256-GCM local encrypted backups.
