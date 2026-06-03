# QA Status And Evidence Map

This page maps the app handbook to existing QA scenario and run-log evidence. It does not replace `docs/mobile-qa-scenarios.csv` or `docs/mobile-qa-run-log.csv`; those remain the detailed catalog and execution log.

## Latest Broad Validation

Most recent cleanup/release run: `2026-05-30-cleanup-major` rows in `docs/mobile-qa-run-log.csv`.

Validated in that run:

- `pnpm inventory` wrote `docs/code-inventory.csv` with 2,288 rows for 297 Git-visible non-generated files after release QA screenshots were added.
- `pnpm --filter @1wallet/mobile typecheck` passed.
- `pnpm --filter @1wallet/mobile lint` passed.
- `pnpm typecheck` passed.
- `pnpm test` passed.
- `pnpm lint` passed.
- `pnpm build` passed.
- `git diff --check` passed with line-ending warnings only.
- Android x86_64 release APK built, installed on `emulator-5554`, and cold-launched.
- Local-auth first-run onboarding completed with disposable account `qa@onewallet.test`.
- Focused release logcat showed no app AndroidRuntime fatal, FATAL EXCEPTION, or ReactNativeJS crash signatures.

## Release Screenshot Evidence

| Area                                   | Evidence                                                                                                                                                                                                                                                                                                                                                     |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Launch/startup                         | `screenshots/window-cleanup-release-cleanboot.png`, `screenshots/window-cleanup-release-launch.png`                                                                                                                                                                                                                                                          |
| Login/create account                   | `screenshots/window-cleanup-release-create-mode.png`, `screenshots/window-cleanup-release-after-create.png`                                                                                                                                                                                                                                                  |
| Onboarding profile/account/permissions | `screenshots/window-cleanup-release-onboarding-profile.png`, `screenshots/window-cleanup-release-profile-bottom.png`, `screenshots/window-cleanup-release-main-account.png`, `screenshots/window-cleanup-release-main-account-bottom.png`, `screenshots/window-cleanup-release-permissions.png`, `screenshots/window-cleanup-release-permissions-bottom.png` |
| Home                                   | `screenshots/window-cleanup-release-home-ui.png`                                                                                                                                                                                                                                                                                                             |
| Notifications                          | `screenshots/window-cleanup-release-notifications-ui.png`                                                                                                                                                                                                                                                                                                    |
| Add Record                             | `screenshots/window-cleanup-release-add-ui.png`                                                                                                                                                                                                                                                                                                              |
| Transactions                           | `screenshots/window-cleanup-release-transactions-ui.png`                                                                                                                                                                                                                                                                                                     |
| Calendar                               | `screenshots/window-cleanup-release-calendar-ui.png`                                                                                                                                                                                                                                                                                                         |
| Planner                                | `screenshots/window-cleanup-release-planner-ui.png`                                                                                                                                                                                                                                                                                                          |
| Accounts                               | `screenshots/window-cleanup-release-accounts-ui.png`                                                                                                                                                                                                                                                                                                         |
| Drawer                                 | `screenshots/window-cleanup-release-drawer-ui.png`, `screenshots/window-cleanup-release-drawer-planning-ui.png`                                                                                                                                                                                                                                              |
| Settings                               | `screenshots/window-cleanup-release-settings-ui.png`, `screenshots/window-cleanup-release-settings-lower-ui.png`                                                                                                                                                                                                                                             |
| Currencies                             | `screenshots/window-cleanup-release-currencies-ui.png`                                                                                                                                                                                                                                                                                                       |
| Imports                                | `screenshots/window-cleanup-release-imports-ui.png`                                                                                                                                                                                                                                                                                                          |
| Review                                 | `screenshots/window-cleanup-release-review-ui.png`                                                                                                                                                                                                                                                                                                           |

## Scenario Coverage By Area

| Area                       | Scenario source                                                  | Current evidence                                                    | Status                                                                    |
| -------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Navigation and tabs        | `NAV-001`, `NAV-REL-001`, `NAV-VISUAL-001`, `VISUAL-CLEAN-001`   | Route smoke, release screenshots, drawer/tabs visual sweep          | QA verified, but mounted deep-link starts are a tooling limitation.       |
| Launch                     | `LAUNCH-*`, `ANDROID-CLEAN-001`                                  | Native splash, React loading surface, release cold launch           | QA verified.                                                              |
| Onboarding/auth            | `ONBOARD-CLEAN-001`                                              | Create account and onboarding screenshots                           | QA verified; permissions screen visual density is follow-up.              |
| Home widgets               | `WIDGET-001`, account-grid runs, calendar stress related widgets | Account grid and release Home screenshots                           | Partially QA verified; every widget combination still needs a final pass. |
| Add Record                 | `ADD-001`, `ADD-PICKER-001`, `NOTE-001`, `RECEIPT-001`           | Add visual, picker, note autocomplete, receipt evidence             | QA verified for key surfaces; full transaction matrix needs focused pass. |
| FX/multi-currency          | `FX-001`, Currencies cleanup row                                 | Currencies screen and Add flow implementation                       | Needs focused save-path QA for cross-currency variants.                   |
| Transactions/edit          | Transactions rows in scenario catalog                            | Transactions visual screenshot                                      | Route verified; edit/delete matrix needs deeper pass.                     |
| Accounts                   | Account scenario rows, `ACC-REORDER-001`                         | Accounts visual and reorder screenshots                             | QA verified for reorder; account-type CRUD matrix needs focused pass.     |
| Categories                 | `CAT-001`                                                        | Taxonomy fixture/test notes                                         | Implemented; manager editing needs focused pass.                          |
| Calendar                   | `CAL-001`, `CAL-GRID-001`, `CAL-PERF-001`                        | Grid fix, heavy forecast stress, cleanup visual                     | QA verified.                                                              |
| Planner/budgets/goals      | Planner scenario rows                                            | Planner visual screenshot                                           | Implemented; workflows need focused pass.                                 |
| Recurring/planned payments | `REC-001`, `REC-002`                                             | Prior recurring/card/loan rows plus cleanup planned screenshot      | Partially QA verified after cleanup.                                      |
| Cards                      | `CARD-001` and card payment scenarios                            | Scheduled card_payment fixes in run log                             | Implemented; current release UI needs focused pass.                       |
| Loans                      | `LOAN-001`, loan test/run rows                                   | Ledger tests and release route runs                                 | Implemented; full setup/edit/forecast UI needs focused pass.              |
| Imports                    | Import rows plus cleanup Imports screenshot                      | Wallet CSV hardening and visual pass                                | Implemented; current CSV import flow needs focused pass.                  |
| SMS Auto Capture           | `SMS-*`, `SMS-REL-*`, `SMS-EMU-001`                              | Parser tests, background SMS, manual scan, duplicate/ignore filters | QA verified for release emulator; Play Store policy remains limitation.   |
| Notifications              | `NOTIF-001`, cleanup notification row                            | Home bell opens list-only inbox, focused logcat clean               | QA verified for inbox visual; native delivery/channel matrix needs pass.  |
| Permissions                | Permission rows, `PERM-001`                                      | Manifest audit and permissions screenshots                          | Partially QA verified; denial/revoke matrix needs focused pass.           |
| Reports                    | Reports route and visual route smoke                             | Earlier route smoke                                                 | Needs focused correctness QA.                                             |
| Settings/theme             | Settings rows, cleanup Settings screenshots                      | Settings upper/lower visual pass                                    | QA verified visually; detailed setting changes need pass.                 |
| Wallet snapshot/reset      | Snapshot route and prior memory                                  | Earlier snapshot smoke                                              | Implemented; destructive path should use demo data only.                  |

## Known QA Tooling Limitations

- UIAutomator XML dumps failed during the latest release pass with `ERROR: could not get idle state`.
- `adb am start VIEW onewallet:///...` returned `Status: ok` but did not reliably move an already-mounted release activity during the cleanup run.
- On this Windows/Intel Arc emulator setup, stale snapshots/gfxstream issues can make screenshots show wallpaper/splash while the app is focused. Clean boot with no snapshots is the reliable path.
- Screenshot-based visual QA plus `dumpsys window` focus/surface and focused logcat were used as the fallback evidence strategy.

## Product And Integration Limitations

- Supabase/Postgres is future sync/backend planning. Current runtime is local-first.
- OCR field extraction from receipts is not complete; receipt capture/attachment paths exist.
- Native bank/open-banking sync is not implemented. Import and capture flows are the current ingestion path.
- Android SMS capture is local-only and permission-gated; Play Store distribution requires policy review.
- Backup/export/restore specs beyond local snapshot/device data workflows need more formal documentation.

## Recommended Next QA Passes

1. Full Add Record matrix: expense, income, transfer, card payment, loan repayment, refund, adjustment, pending, scheduled, receipt, split, foreign purchase, cross-currency transfer.
2. Account CRUD matrix across bank, cash, wallet, credit card, loan, GBP account, archive/reactivate/delete.
3. Transaction detail edit/delete for every high-impact type/status.
4. CSV import current release UI from file pick through Review approval.
5. Notifications native delivery/channel/quiet-hours matrix.
6. Permissions deny/revoke/blocked states for camera, photos, SMS, notifications, and location.
7. Budget and goal creation plus threshold notification behavior.
8. Loan setup/edit/forecast/payoff scenarios with GBP and INR accounts.
