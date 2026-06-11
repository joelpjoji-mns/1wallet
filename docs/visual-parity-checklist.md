# 1Wallet Flutter Visual Parity Checklist

Baseline date: 2026-06-07

## Capture status

| Area | React Native baseline | Flutter baseline | Status | Notes |
| --- | --- | --- | --- | --- |
| RN startup/loading | `build/rn-baseline/rn-start.png`, `build/rn-baseline/rn-debug-preview-check.png` | — | Captured | RN debug build installed and Metro launched. Initial capture shows native bundle loading. |
| RN login | `build/rn-baseline/rn-after-bundle-check.png` | pending | Captured | Real RN login screen captured before debug-preview cache reset. Flutter `/login` was upgraded to a matching first-pass screen in this batch. |
| RN dashboard tabs | `rn-home.png`, `rn-transactions.png`, `rn-calendar.png`, `rn-planner.png`, `rn-accounts.png` | `flutter-home-warm-final.png`, `flutter-transactions-warm-final.png`, `flutter-calendar-warm-final.png`, `flutter-planner-final-parity.png`, `flutter-accounts-warm-final.png` | Captured | RN dashboard unlocked through debug preview onboarding after warming Metro. Flutter recaptured after instant tab navigation and warm theme fixes. |
| Transactions filters | `rn-transactions.png` | `flutter-transactions-warm-final.png` | Improved | Flutter now uses RN-style filter cards, `This year` default, `x of y records shown`, and Add transaction empty CTA. |
| Calendar filters | `rn-calendar.png` | `flutter-calendar-warm-final.png` | Improved | Flutter now uses centered month navigation, compact summary metric row, `Actual records only`, and RN-style side-by-side Category/Accounts filter cards. |
| Add record account/category pickers | RN `RecordPickers.tsx` account/category overlays | `flutter-add-record-account-picker-retry.png`, `flutter-add-record-category-picker-retry.png` | Improved | Flutter Add Record account/category pickers now use RN-style full-screen picker overlays, account search, selected rows, and add-account appbar action. |
| Accounts filters | `rn-accounts.png` | `flutter-accounts-warm-final.png` | Improved | Flutter Accounts filter toggles now use RN-style cards with title/value/subtitle and chevrons. |
| Main drawer | `rn-drawer-stable.png` | `flutter-drawer-final-next.png` | Improved | Flutter drawer now uses RN-like 80% width, live wallet/user header, Daily grouping, active rail, dimmed app backdrop, and pinned Settings/Sign out footer. |
| Filter picker overlays | RN `OptionListOverlay.tsx`, `RecordPickers.tsx` | `flutter-transactions-type-picker-retry.png`, `flutter-calendar-category-picker-retry.png` | Improved | Flutter shared picker now uses RN-style full-screen appbar with back arrow, matching titles/search hints, premium selected rows, and warm surface spacing. |
| Import hub / SMS import | RN `imports.tsx`, `import-sms.tsx`, parser services | pending capture | Improved | Flutter now has a real Imports hub and manual SMS paste/parser flow that persists capture candidates for review; Capture Detail can edit parsed fields before confirming a transaction. |
| Wallet CSV import | RN `import-wallet-csv.tsx`, `walletCsv.ts` | pending capture | Improved | Flutter now has file-pick or paste/preview/import CSV flow with header detection, manual column mapping, warnings, account/category matching, duplicate skipping, import batch history, rollback, and persisted imported transactions. |

## RN run notes

- Installed RN debug APK with `pnpm android:hot:install`.
- Started Metro with the standard command `pnpm android:hot`; captured real login screen.
- Restarted Metro with debug data preview enabled: `EXPO_PUBLIC_ONEWALLET_DEBUG_DATA_PREVIEW=true` and `ONEWALLET_METRO_CLEAR=1`.
- Metro dev source-map generation initially failed on `metro-runtime/src/polyfills/require.js`; a local ignored `node_modules` workaround was used to complete screenshot capture only.
- Dashboard screenshots were captured after warming the Metro bundle and completing the safe migration-preview onboarding flow.

## Flutter fixes made from first comparison

- Added a real RN-inspired `/login` screen instead of a generic feature overview.
- Converted Add Record account, transfer destination, and category pickers to the shared full-screen picker overlay.
- Removed the obsolete Add Record bottom-sheet picker helper.
- Replaced a hidden transaction-detail no-op with visible staged-action feedback.
- Matched RN Transactions filter cards/defaults and empty CTA.
- Matched RN Calendar month/filter card layout.
- Matched RN Home `All accounts`/`Manage`/`Add account` card semantics.
- Matched RN Accounts filter-card presentation.
- Switched Flutter tab navigation to instant jumps to match RN and avoid mid-transition screenshots.
- Warmed the Flutter light theme to the RN cream/gold palette.
- Matched the main drawer width, header, Daily rows, active state, and pinned footer to the RN drawer reference.
- Matched the shared full-screen picker appbar, labels, spacing, and selected row behavior to RN `OptionListOverlay`/record picker overlays.
- Matched Add Record account/category picker labels, search hints, selected rows, and account add action to RN record picker overlays.
- Added real Import hub and SMS paste/parser first pass with persisted capture candidates and parsed amount/merchant/type preview; Capture Detail can edit amount/type/account/category/merchant before posting a transaction.
- Added Wallet CSV file-pick or paste/preview/import first pass with manual column mapping, duplicate detection, import batch history/rollback, and persisted imported transactions.

## Next capture targets

1. RN: capture Add Record keypad/details panel if more exact input-flow parity is needed.
2. Flutter: compare Add Record keypad/details panel against fresh RN captures.
3. Next import pass: stronger duplicate matching and native file-picker smoke captures.
