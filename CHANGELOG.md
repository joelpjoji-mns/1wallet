# Changelog

All notable changes to **1Wallet** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [1.0.18] - 2026-11-27

### Added
- Payday countdown home widget: days until the next active salary plan (calendar-day counts, late salaries with a 7-day grace before rolling forward and flagging missed pay), pay-cycle progress, bills due before payday and what is left after them, with Record/View actions and an option to pin one of several salary plans.
- Next card bill home widget: the soonest unpaid credit-card bill with due-in/overdue/paid status, a warning when it falls before payday, and other cards' upcoming bills.
- Unusual spending home widget: categories whose month-to-date spend is well above or below their average for the same point in recent months, ignoring transfers and tiny categories and waiting for two months of history.
- The new widgets appear at the bottom of the dashboard, including for existing layouts, and can be reordered or hidden from Manage widgets.
- Browser Screen Studio with phone-sized previews and grouped live artboards of the actual Flutter screens, searchable routes, workflow shortcuts, appearance and empty-wallet controls, and disposable offline sample data.
- Rich Screen Studio sample wallet with multi-year activity, multicurrency accounts, linked planned-payment history, active and paid-off loans, populated capture review, and all supported bill-notification scenarios.

### Changed
- Custom date ranges (History, home widgets, balance period and widget manager) now open a compact calendar popup instead of a full-screen picker. Tap a start and end day, switch months or jump to a year, then Apply; a single day selects a one-day range. Days between the start and end are highlighted as one continuous band, and Clear, Cancel and Apply are equal-width buttons.
- Every app button (filled, outlined, text and elevated, including dialog actions such as Apply, Cancel and Post now) now uses the accent glass pill style of the home widget "Manage" action. Primary actions use a slightly stronger tint, and destructive actions use the same glass in the error colour.

### Fixed
- Loan repayment history and payment counts exclude paused and completed EMI plan templates instead of displaying them as additional posted repayments.
- Review & Inbox notification cards: overdue planned payments are flagged and styled as overdue with "was due" wording, alerts show their actual due date instead of "just now", titles wrap to two lines, large amounts scale down instead of truncating, card-due alerts keep the full account name and amount, action buttons are spread across the card, the unread accent spans the full card height, and transfer cards drop the redundant chip and orphaned arrow.
- Review capture and planned-payment actions now wrap to available phone width instead of isolating Confirm or Post now on a full-width row.
- Planned-payment lists, details and payment history share consistent header sizing and alignment, keeping amounts and due dates beside titles rather than moving them onto separate full-width rows. Titles stay on one line and truncate with an ellipsis.
- Planned details align the schedule status and cadence across the header and combine payment totals, next payment and accounts into one compact information panel.
- The planned summary again shows Net, Income and Expense on a single row in three separate boxes instead of wrapping onto a second line; only accessibility text sizes stack them.
- Deleted accounts no longer come back: editing a deleted loan from Past loans used to clear its deleted flag and resurface it under Accounts. Deleted loans are no longer listed, and saving an account always preserves deletion.
- Deleting an account is no longer blocked by planned payments you cannot see (EMIs of paid-off or archived loans, or plans tied to deleted accounts). The "Cannot delete account" dialog now names the blocking plans and links to Planned payments.
- Plans tied to deleted accounts are hidden from Planned payments, CSV imports never land in deleted accounts, and the web app hides deleted accounts instead of offering to unarchive them.

## [1.0.17] - 2026-11-26

### Added
- Complete rewrite of the app tour into an uninterrupted, interactive story flow guiding first-time setup across Dashboard, Logging, History, Calendar, Accounts, and Settings.
- Compact glass coach marks with illuminated neon spotlight beacons, animated pointers, and inline interactive sample previews on every core screen.
- Interactive Calendar month-end net forecasting allowing users to jump to the next month to see planned balance projections, plus one-tap day cell inspection opening sample transactions.

### Changed
- App tour is now a non-optional guided onboarding experience ensuring all users learn core capabilities before managing live finances.
- Replaced separated "basics" vs "phase 2" flows with a single cohesive narrative.

### Fixed
- Smooth anchoring and responsive card positioning for coach marks on all device viewport heights.
- Proper clean-up and navigation handling during sample day transactions sheet dismissal.

## [1.0.16] - 2026-11-26

### Added
- A skippable, resumable overlay tour introduces the dashboard, accounts, records, history, calendar and settings after first-account setup. Compact measured coach marks guide real actions; Settings offers full and individual workflow replays.
- Tour progress is isolated per account and syncs introductory steps and dismissed hints through an owner-only Firestore document for signed-in users; individual replays remain device-local.
- Optional feature guides introduce the review inbox, statement imports and planned payments without unsolicited first-visit popups.

### Changed
- New offline and signed-in wallets complete setup with at least one account before an optional tour. Existing wallets no longer receive unsolicited welcome, first-visit or resume popups.
- Replaced large tour panels with compact, measured coach marks and animated arrows. Added real-route guides and isolated interactive samples for plans, loans, forecast, credentials, account matching, inbox notifications and calendar day sheets; all workflows are replayable from Settings.
- Permission setup explains that access is optional and can be skipped without requesting device permissions.
- Raised the floating island navigation bar by 4 logical pixels on mobile.

### Fixed
- Onboarding accepts negative opening balances, explains invalid entries, protects existing wallets, and keeps drafts available if setup cannot be saved.
- Added breathing room to onboarding and dashboard cards; account forms, picker rows, and capture diagnostics adapt to large text instead of squeezing controls together. Empty account and history actions can scroll clear of the bottom navigation.
- Onboarding account colors have larger touch targets and announce their names and selection to screen readers.
- The custom color picker fits compact and landscape screens without clipping its controls and keeps edits when the viewport changes.
- Settings profile and privacy controls, appearance previews, and the planned-payment summary keep labels and amounts readable on compact screens and with larger text.
- Calendar historical balances use the correct local-day boundaries, and calendar dates and navigation actions have clearer screen-reader labels.
- Dashboard currency breakdowns retain negative balances, while dashboard summaries and transaction selectors reflow for larger text.
- Opening an add-record link with different draft parameters now opens the requested draft instead of retaining the previous one.
- Reduced-motion settings are respected during launch transitions, and permission failures provide recoverable feedback.

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
