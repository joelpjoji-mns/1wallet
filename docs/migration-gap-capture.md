# 1Wallet React Native To Flutter Migration Capture

Captured: 2026-06-09

This document captures the current migration gap between the complete React Native/Expo app in `../1wallet/apps/mobile` and the Flutter app in this folder. It combines route inventory, business-rule parity, native capability parity, visual notes, and current Flutter test status.

## Overall State

Flutter has a wide first-pass port: auth, launch/login, onboarding, home, transactions, add record, accounts, categories, currencies, calendar, planner, cards, loans, recurring, imports, SMS parsing, CSV parsing, review queue, notifications inbox, backup/restore, sync snapshot screens, drawer, theme, and tests all exist.

The remaining gap is mostly deeper product behavior and native integration. Several Flutter screens are real but simplified compared with the RN app because the Flutter ledger model and controller are much smaller than the RN ledger/domain packages.

## Route Parity

| RN route / surface | Flutter status | Gap |
| --- | --- | --- |
| `/` startup gate | Present via `/launch` and startup redirect | Different routing shape, but functional gate exists. |
| `/login` | Present | First-pass parity. |
| `/signup` | Redirects to `/login` | RN has a dedicated redirect/create-mode route; Flutter collapses it. |
| `/onboarding` | Present | Simplified vs RN profile/use-case/multiple-account depth. |
| Home tab | Present | In-app widget surface exists; deeper widget calculations still thinner. |
| Transactions tab | Present | Filtering/list exists; full RN edit/delete/status/currency matrix not fully verified. |
| Calendar tab | Present | Calendar exists; future-generation/occurrence behavior is partial. |
| Planner tab | Present | Budget/goal/planned-payment overview exists, but budget/goal models are simplified. |
| Accounts tab | Present | Account CRUD exists; account types and match hints are incomplete. |
| `/add` | Present | Core save/edit exists; advanced RN matrix missing or unverified. |
| `/transaction/:id` | Present | Detail/edit/delete present; tests currently failing around edit flow. |
| `/account/new`, `/account/:id` | Present | Basic account editor exists; fewer account fields than RN. |
| `/widgets` | Present | In-app home-widget manager exists; OS widgets missing. |
| `/reports` | Missing | Flutter redirects `/reports` to `/widgets`; reports are not ported. |
| `/review` | Present | Candidate list/actions exist; candidate model is thinner. |
| `/capture/:id` | Present | Edit/approve candidate exists; fewer candidate fields than RN. |
| `/notifications` | Present | In-app inbox exists; native delivery/channels not equivalent. |
| `/settings` | Present | Settings exist; RN theme/accent/notification/locale depth is partial. |
| `/recurring` and child routes | Present | Consolidated screen; future-generation rule engine is partial. |
| `/cards` | Present | Card account view exists; scheduled card-payment behavior is partial. |
| `/loans` and child routes | Present | Loan screens exist; detailed forecast/setup parity is partial. |
| `/budgets/new` | Present | Simple budget create; RN period/threshold/rollover rules missing. |
| `/goals/new` | Present | Simple goal create; RN kind/target date/priority/pause/completion missing. |
| `/categories` | Present | Hierarchy exists; icon/color/hidden-in-stats/manager depth partial. |
| `/currencies` | Present | Display currency exists; live FX refresh/freshness parity partial. |
| `/sync` | Present | Cloud restore/snapshot exists; Flutter README says upload is intentionally not automatic. |
| `/imports` | Present | Hub exists. |
| `/imports/:id` | Present | Batch details/rollback exist. |
| `/import-wallet-csv` | Present | CSV parse/import exists; RN duplicate/provision/transfer-pair depth partial. |
| `/import-sms` | Present | Manual paste/inbox scan exists; RN rule/preferences depth partial. |
| `/auto-capture` | Present as SMS import title | Not equivalent to RN Auto Capture settings/background feature. |
| `/updates` | Present | Tracks sync/channel metadata only; not RN OTA/APK/TestFlight updater. |
| `/device-permissions` | Present | UI exists; platform manifest/runtime parity incomplete. |
| `/permissions-setup` | Present | First-pass permission setup exists. |
| `/rules`, `/wallet-snapshot` | Missing as explicit Flutter routes | Related features are folded into recurring/data backup/imports, but no route parity. |

## Data Model And Business Logic Gaps

RN persisted ledger version is `14`. Flutter currently has a custom, narrower ledger model. Missing or reduced areas:

- `transactionSplits`
- `tags`
- `merchants`
- user profile preferences
- theme preference and theme accent inside ledger preferences
- notification preferences and native delivered IDs
- auto-capture preferences, trigger keywords, ignored senders, run summary
- message category keyword rules
- future generation rules
- richer import batch statuses and metadata
- richer capture candidate fields
- richer account metadata, match identifiers, icons, notes, opening date, nickname, visibility flags parity
- richer loan details, interest method, period, setup mode, linked planned-payment rule metadata
- budget periods, thresholds, rollover, carry overspend, pause state
- goal kind, target date, priority, pause, completion state

Current Flutter controller behavior is good for a local MVP, but not equivalent to the RN shared ledger logic. The next migration pass should either port the RN rules exactly into Dart or define a compatibility layer that preserves RN archive semantics.

## Feature Gaps By Domain

### Reports

Reports are the clearest missing screen. RN has net worth, cashflow, account balance, category reports, display-currency conversion, and report inclusion rules. Flutter redirects `/reports` to `/widgets`.

### Add Record And Transactions

Flutter supports basic add/edit with type, account, category, amount, notes, status, and simple receipt OCR entry. RN supports a much larger matrix: expense, income, transfer, adjustment, card payment, loan repayment, pending, scheduled, receipt attachments, tags, date/time, category, account, currency fields, foreign purchase currency, note autocomplete, reimbursement/tax flags, and richer payment method handling.

### Currency And FX

Flutter stores exchange-rate records and supports display currency. Missing or incomplete versus RN:

- frankfurter.app refresh workflow
- one-hour freshness checks
- stale/missing rate handling before saves
- manual rate fallback in all foreign purchase paths
- cross-currency transfer counter-rate semantics
- historical conversion preservation in reports/widgets

### Recurring And Planned Payments

Flutter recurring screens exist, but RN planned payments include robust future-generation rules: daily/weekly/monthly/yearly, intervals, start/end, occurrence count, skipped dates, manual/automatic post mode, forecast occurrences, due scheduled records, card payments, loan EMI, bills, subscriptions, savings transfers, and calendar/planner/home integrations.

### Budgets And Goals

Flutter currently creates simple budget/goal records. RN business rules include periods, thresholds, rollover, carry overspend, pause state, goal kinds, target dates, priority, completion, and linked planning/report behavior.

### Loans And Cards

Flutter has loan/card views and a simple loan form/forecast. RN includes loan kinds, interest period/method, setup mode, repayment schedule, linked planned payment rule, EMI forecast, principal/interest split, payoff timing, and scenario comparison. Card payments in RN are transfer-like scheduled records with reminder/widget integration.

### Imports And Capture

Flutter has useful first-pass CSV and SMS flows. Missing or reduced areas:

- transfer pair detection strong enough to prevent double-counting
- full duplicate matching based on external references/raw hashes
- account provisioning/matching depth
- category matching precedence: custom rules, default rules, merchant defaults, generic fallback, category name
- import batch statuses: previewed, queued, partially_posted, posted, rolled_back
- capture sources beyond SMS/import
- confidence, warnings, source metadata, external refs, suggested counter account, location, payment method, tags

### Notifications

Flutter has an in-app notification inbox generator. RN has preferences, channels, quiet hours, read/dismiss/snooze persistence, native delivery IDs, native Expo notifications, tap routing, and channel-level user settings.

### Settings And Theme

Flutter has theme mode and app settings surfaces. RN additionally stores richer preferences in ledger state, supports Material You/dynamic source color behavior, notification channel settings, locale/preference controls, and broader destructive/reset maintenance actions.

## Native Android Gaps

RN Android manifest includes:

- `POST_NOTIFICATIONS`
- `READ_MEDIA_IMAGES`
- `READ_MEDIA_VISUAL_USER_SELECTED`
- `READ_EXTERNAL_STORAGE`
- `REQUEST_INSTALL_PACKAGES`
- `VIBRATE`
- foreground service permissions
- deep-link intent filters
- file provider for update APK install
- native app widget providers
- SMS receiver
- SMS headless service
- foreground service

Flutter Android manifest currently includes only basic internet/camera/SMS permissions and no native receivers/services/providers/widgets/deep links. Native parity is therefore incomplete.

Native files present in RN but not ported to Flutter equivalents:

- `OneWalletWidgets.kt`
- `OneWalletSmsCapture.kt`
- `OneWalletPackageInstallerModule.kt`
- `OneWalletForegroundService.kt`
- `OneWalletBackLayer.kt`
- app widget XML layouts/provider metadata
- update APK file-provider XML

## Update System Gap

RN update stack includes Expo OTA, Firebase release manifests, native APK download/install, installer settings, iOS TestFlight/App Store links, update channels, progress, cancellation, and native update notifications.

Flutter `UpdatesScreen` currently shows stable channel, ledger schema, sync metadata, and a check button that uploads/checks sync state. It does not implement RN update behavior.

## Auto Capture Gap

Flutter has `processIncomingSmsHeadlessTask`, but it currently logs parsed results and contains comments saying the real background load/write path is not implemented. RN has a native SMS receiver and headless service wired through Android.

## Visual Capture Status

Existing visual parity notes live in `docs/visual-parity-checklist.md`. Current state from that file:

- Login: improved toward RN.
- Dashboard tabs: captured and improved.
- Transactions filters: improved.
- Calendar filters: improved.
- Accounts filters: improved.
- Drawer: improved.
- Shared picker overlays: improved.
- Add Record account/category pickers: improved.
- Import hub/SMS import: improved but pending capture.
- Wallet CSV import: improved but pending capture.

Still pending:

- fresh RN Add Record keypad/details capture
- Flutter Add Record keypad/details comparison
- import/native file-picker smoke captures
- report screen capture after implementation
- real-device capture for permissions, SMS background capture, native notifications, OS widgets, updates

## Current Flutter Test Status

Command used:

```powershell
C:\Users\Joel\development\flutter\bin\flutter.bat test --no-pub
```

Result: 46 passing checks, 4 failing widget-flow tests.

Failures:

- `test/add_record_flow_test.dart`: `Add Record UI saves a transaction to the ledger`
  - Expected transaction count `10`, actual `9`.
- `test/add_record_flow_test.dart`: `Add Record edit route updates an existing transaction`
  - Finder path failed with `Bad state: No element`.
- `test/import_sms_flow_test.dart`: `Import SMS screen queues parsed capture candidate`
  - Could not find a widget with text `Parse`.
- `test/backup_widgets_flow_test.dart`: `Widgets screen persists home widget order changes`
  - Finder predicate found no matching widget.

These look like UI/test drift failures rather than compile failures, but they should be fixed before claiming the Flutter port is stable.

## Recommended Migration Order

1. Fix the four failing Flutter widget tests so the current port has a green baseline.
2. Port the RN ledger model gaps or create explicit RN archive compatibility fields for all missing ledger entities.
3. Implement Reports instead of redirecting `/reports` to `/widgets`.
4. Port future-generation/planned-payment rules and wire them into Calendar, Planner, Home widgets, Loans, Cards, and Notifications.
5. Expand Add Record and Transaction Detail to match RN transaction types, statuses, currency logic, tags, attachments, and metadata.
6. Port notification preferences and native notification delivery.
7. Port Android native SMS receiver/headless service and auto-capture preferences.
8. Port Android OS widgets.
9. Replace the Flutter Updates screen with the desired Flutter-native release/update strategy.
10. Do a real-device visual and behavior pass for permission denial, SMS, camera/photo, notifications, update, backup/restore, and widget flows.

## Bottom Line

Flutter has the shape of the app and many usable flows. The remaining work is to keep closing RN finance-logic and native Android behavior gaps until Flutter is a full replacement for the working RN app.
