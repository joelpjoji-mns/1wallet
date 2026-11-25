# Flutter UI/UX and engineering audit

## Current expanded audit: findings and release status

**Status: substantial fixes verified; not a production-readiness certification.**
The automated route inventory is broad, but not every screen, overlay, interaction,
platform, and backend failure has been manually verified. The historical normalization
inventory below is retained separately and must not be interpreted as current native
device coverage.

### Login and filter layout correction

The first fixed-login layout compacted standard phones too aggressively and left
too much empty space below the actions. Standard phones now retain full welcome
branding, with spare height distributed before the action card and footer.
Short screens retain compact branding and genuine overflow keeps its scroll fallback.

History uses six equal filter positions in three columns. Tags is disabled when
there are no tags; date previous/next actions remain beside search and the date
pill retains swipe navigation. At enlarged text sizes, compact triggers use
icons with full accessible names/tooltips instead of heavily truncated labels.
Calendar's category/account cards stay side by side, with concise enlarged-text
captions and full semantic selection labels.

Verification: 27 focused login/date-filter/calendar/picker tests passed, including
three-column geometry at 320, 360, and 430 dp, 200% text, disabled Tags semantics,
filter selection, and both Calendar pickers. Nine selected route-matrix tests
passed across normal light/dark, compact normal/200%, and phone 200% presentations.
Fixture screenshots and the populated emulator's History/Calendar screenshots
were inspected. Android debug and web builds passed. Refreshed browser checks
at 360 x 780 and 320 x 568 measured no heading movement after a 400 px wheel
gesture and kept the complete footer visible. The Android ledger-file hash
matched immediately across replacement installation; no sign-out, data clearing,
or wallet edits were performed. Current app logs showed no matching framework
overflow/unhandled-exception entries. The full suite and iOS build were not rerun
for this correction; the existing analyzer informational finding remains.

### Entry-screen viewport follow-up

The welcome page previously used a scrolling list with large decorative gaps.
It now fills the safe viewport, uses compact branding/spacing on shorter screens,
and anchors the full "Secure / Private / Local First" footer at the bottom.
Real-font regressions verify zero scroll extent and fully visible controls/footer
at 320 x 568, 360 x 780, 430 x 932, and 1024 x 800 with simulated safe-area insets.
Long errors, landscape, and 200% text retain overflow scrolling rather than
clipping content or disabling text scaling.

The same audit covered startup loading/recovery, cloud-wallet recovery, all four
onboarding steps, permission setup, account-deletion status, and the lock gate.
Startup progress could be pushed off-screen by a long message, and the lock gate
reproduced a 32 dp bottom overflow in large-text landscape. Both now keep their
content/actions reachable. Onboarding, permissions, and deletion pages do not
overscroll when their content fits; long forms and keyboard states remain scrollable.

Verification: 25 focused tests passed, followed by 73 entry-route, onboarding,
cloud-recovery, and overlay matrix tests across the selected 13 presentation
variants. Phone light/dark, compact normal/200% text, and startup fixture screenshots
were inspected. This is fixture coverage, not an iOS/physical-device sign-off.
Android debug and web builds passed. In the refreshed browser preview, a 400 px
wheel gesture moved the welcome heading by 0 px at both 360 x 780 and 320 x 568,
and the full privacy footer remained inside each viewport. Android replacement
installation preserved the ledger-file hash; no sign-out or data clearing was
performed. The full test suite was not rerun for this follow-up, and the existing
analyzer informational finding remains.

### Button-placement follow-up

The populated loan detail used uneven, left-aligned action rows. Related actions
now use equal columns, with a full-width final action and a single column when
space or text size requires it. The same layout is used for planned-payment,
capture-detail, and device-permission actions. The loan's View plan button and
Next EMI tile also now navigate to the actual planned-payment route; the prior
path opened the not-found page. Planned-payment names and amounts no longer
compete for the same narrow row.

The route-matrix and design-system tests passed (101 tests, including
845 fixture presentations), as did 40 focused layout, loan, recurring, and route
tests. After the final account-name adjustment, normal and 200% route variants
were rerun successfully. The populated Android loan and plan were checked without
saving changes, including 200% text. The matrix tests rendered labels and
scrolling; they do not establish that every button placement, overlay, or
interaction has been manually reviewed.

A follow-up review of the remaining phone fixture screenshots reproduced three
layout issues. Review Queue actions could be squeezed into uneven rows, a large
transaction amount wrapped its final digit, and History's horizontal filter strip
left controls clipped at the viewport edge. The queue now uses the shared action
group and stacks when its two-column layout cannot preserve one-line labels.
Transaction amounts scale down only as needed to remain on one line. History
filters wrap into visible rows. Targeted screenshots were regenerated for these
routes at normal and compact 200% text scales; these are fixture renders, not
populated-wallet screenshots or a substitute for native manual testing.

### Application overview and inventory

- **34 public `*Screen` classes** in the feature tree, including the four shell tabs.
  Editor/detail modes reuse screen classes; a screen-class count is not a count of
  unique navigation states.
- **At least 41 public widget classes** directly extending Flutter/Riverpod widget
  base classes in `lib/src/widgets`, including 33 in `app_kit.dart`. Feature-local
  widgets, helper functions, private classes, and inherited component types are
  additional; this is a reproducible lower bound rather than a total component count.
- **Architecture:** Riverpod controllers/providers, GoRouter, immutable local ledger
  state, derived ledger selectors, optional Firebase Auth/Firestore synchronization,
  shared page frames and glass design tokens. Providers supply dependencies.
  Native integrations include OCR, capture/permissions, home widgets, and updates.
- **Preserved:** integer minor-unit money, wallet ownership gates, offline operation,
  data contracts, and the existing design direction. No financial model rewrite.

| Screen group | Public screen classes inventoried |
|---|---|
| Startup and access | Launch, Login, Onboarding, PermissionsSetup, AccountDeletion |
| Main tabs | Home, Transactions, Calendar, Accounts |
| Transaction editors/details | AddRecord, TransactionDetail |
| Account editors/cards | AccountEditor, SecureAccountDetails, Cards |
| Planning | Loans, Recurring |
| Money setup | Categories, Currencies |
| Dashboard configuration | WidgetsManager |
| Capture | ReviewQueue, CaptureDetail, SmsCapture, NotificationCapture, NotificationApps, CaptureDiagnostics |
| Imports | ImportStatement, ImportBatchDetail |
| Settings | Settings, DataBackup, DevicePermissions, GlassEffect, ThemeMode, Feedback |
| Cloud management | Sync |

The route list in `test/ui_route_matrix_test.dart` explicitly records **48 populated
route/tab variants, 12 empty-wallet variants, and 5 startup routes**. Across 13
presentation variants this gives **845 fixture render cases**, plus representative
onboarding, cloud-recovery, dialog, keyboard, and offline-consent checks. Some
routes are aliases or reuse the same screen. The matrix includes light/AMOLED dark,
selected phone, landscape and tablet sizes, and 100%, 115%, 130%, 150%, and 200%
text scaling. It is not the full Cartesian product of every size, theme, scale, and
state.
The button audit examines rendered Material/shared actions and calculator keys
while scrolling reachable vertical viewports, including nested viewports discovered
during scrolling. It does not cover every custom control or horizontal page.

Shared interactions inventoried include drawer navigation, full-screen/category
pickers, confirmation/form dialogs, calendar day sheets, capture result sheets,
backup passphrase flows, offline-consent/upgrade sheets, menus, snackbars, and the
app-lock overlay. Their entire interaction/state space was not manually exercised.

### Populated-account follow-up

A read-only Android emulator pass used an existing populated wallet. It covered
Home, History, Calendar, Accounts, record details, day sheets, account/category
pickers, the add-record form, account editing, Cards, Loans, planned payments,
forecast, Review, Auto Capture, Categories, Currencies, Widgets, Sync, Import,
Backup, Settings, Theme, and Glass. Search, keyboard entry, picker selection,
scrolling, and navigation were exercised without saving. The four main tabs were
also inspected at 200% system font scale; the original 1.0 setting was restored.

The interactions did not clear, sign out, edit, import, or restore the wallet.
However, the later integration-test attempt uninstalled the app and erased its
private data, as documented below. Screenshots and accessibility dumps contain
private account information and remain local to the session, not in this report.
This pass did not exercise every dialog, status, backend failure, live integration,
or platform. Earlier Android logs showed native home-widget rendering errors;
the bounded-render fix and latest device verification are documented below.

After the accidental uninstall, Google sign-in loaded a populated cloud wallet.
Displayed account and transaction names matched earlier screenshots, but complete
recovery and the decryptability of the surviving encrypted backups remain
unverified. Camera, notification, and SMS permissions were declined.

The final debug APK was installed with `adb install -r`, without uninstalling or
clearing the app. In-memory comparisons confirmed that account and transaction
content was unchanged immediately after replacement and after relaunch. The
installed APK hash matched the build. The original loan's repayment list was
revisited at 100% and 200% system text size, with the setting restored to 1.0.
Repayments now share History's gutters and trailing amount alignment, and tapping
a repayment still opens transaction details. The populated forecast was also
revisited: date ticks are distinct and zoom controls sit below the axis.
This controlled check does not establish complete recovery from the earlier loss.

For the latest layout follow-up, the debug APK was again installed with
`adb install -r`; the emulator still showed its populated History screen and all
filter chips were visible. The `1wallet_ledger_state.json` hash matched
immediately after the first replacement install, then changed after normal
launch/navigation; this follow-up does not claim byte-identical state after
runtime activity. No user-initiated transaction edit, restore, sign-out, or clear
was performed. The final replacement install also preserved the ledger-file
hash across installation. The system font scale remained at 1.0.

### Integration-test safety

An earlier integration-test command automatically selected the Android emulator
and its default cleanup uninstalled the app, deleting private app data. This was
an operator error, not a successful test. A subsequent synthetic integration
test was run on an empty emulator with cleanup disabled.

Never run integration tests against a populated wallet. Use a disposable device
and specify the intended device explicitly. Flutter's test runner defaults to
uninstalling the app unless `--no-uninstall` is supplied; `flutter drive` also
uninstalls by default unless `--keep-app-running` is supplied.

### Reproduced issues and implemented fixes

| Screen / component | Issue | Severity | Root cause | Fix applied |
|---|---|---|---|---|
| Startup | Intermittent deferred-setup assertion; Android showed an error fallback | P1 | Microtask used a provider `Ref` after a dependency changed | Flush current startup state through the container and cancel superseded/disposed actions; regression reproduces the old assertion |
| Web startup | Native-widget synchronization threw a platform exception | P1 | Native platform checks executed on web | Explicit web guard |
| Native home widgets | Offscreen previews failed with infinite-height constraints | P1 | The plugin renders previews inside a Column while preview roots expand without a bounded height | Give each preview its declared logical size before rendering; renderer-shaped regression passes and all 18 nonempty bitmap files were generated on Android |
| Main navigation | Invalid indexes and changed/repeated tab links selected the wrong tab | P1 | Unsanitized indexes and retained route/page state | Validate indexes, synchronize link intent, preserve local tabs on router refresh |
| Global feedback | Success/error snackbars were invisible | P1 | Transparent theme styling | Restore readable theme colors and shell clearance |
| Calendar | Short/landscape layouts overflowed or hid content | P1 | Non-scrollable column and constrained header/summary rows | Sliver scrolling and responsive headers, totals, and filters |
| Calendar day grid | Floating add action covered the last cells when large labels prevented docking | P1 | Scroll extent only cleared the bottom bar | Add trailing scroll clearance using the shared floating-action size, without shrinking the normal grid |
| Empty transaction history | Landscape empty state overflowed | P1 | Non-scrollable fixed-viewport content | Let the existing empty-state content scroll |
| Home balance | Currency pill clipped at 200% on Android | P1 | Fixed 24 dp viewport height | Preserve minimum height but allow natural content height |
| Home accounts | Names/balances and subtitles truncated with enlarged text | P2 | Fixed column count, height constraints, and shrunken currency badge | Scale-aware columns, uniform growing tiles, one-line names with two-dot truncation, and naturally sized badges |
| Home account accessibility | Full account name and selection action were separate screen-reader stops | P2 | An explicit semantics container prevented the painted name from joining the tappable tile | Merge the complete name into the selectable tile; regression invokes its accessibility tap action |
| Planned payments | Long names were reduced to a few characters; narrow rows could overflow | P1 | Name, urgency badge, amount, and due status competed in one row | Give the name and badge their own row; stack amount/status when measured space is insufficient |
| Loan forecast | Currency and date labels overlapped or repeated when zoomed or enlarged; zoom controls covered the date axis | P1 | Fixed axis dimensions and tick spacing, compact rounding, endpoint ticks, and controls overlaid the chart | Measure labels, adapt precision and tick spacing to the visible range, and place 48 dp zoom controls below the chart |
| Loan and plan actions | Forecast and other action labels wrapped on narrow phones | P1 | Equal-width action rows squeezed labels beside their icons | Allow action groups to reflow and use concise labels while retaining the related amount and accessible descriptions |
| Review Queue | Compact actions could be crowded or wrap within uneven rows | P2 | A local `Wrap` assigned widths without considering button labels | Reuse `AppActionGroup`; it aligns the actions when possible and stacks them when needed |
| Planned/loan detail headers | Summary boxes left empty space, the 0% progress bar was invisible, and the loan balance and "Custom payment" label truncated or wrapped | P2 | Glass progress track was 15% white; header and action rows used fixed width heuristics | `AppProgressBar` with a themed track; shared three-line `AppDetailHeader` (name · subtitle + amount · status meta); `AppActionGroup` pairs actions only when every label's intrinsic width fits; compact metric tiles in loan detail |
| Summary metric tiles | Amounts ellipsised ("$46,500…") and labels clipped to "Lo…" at 200% text | P2 | Fixed side-by-side `Row`s of compact tiles | `AppMetricRow` pairs tiles at equal height and stacks them at large text; single-line values scale down instead of ellipsising |
| Section headers, info rows, card tiles | Titles/labels broke mid-word at 200% ("currenc·y", "Statu·s"); card names collapsed to "A…"; "Pending upload" wrapped at 100% | P2 | Trailing actions/values took fixed shares of the row | `SectionCard` moves its action beneath the heading and `InfoRow` stacks label/value at large text; `InfoRow` values take natural width (≤60%); card balances move under the name at large text |
| Transaction detail | A large currency amount wrapped its last digit to another line | P2 | The hero amount had no single-line fit behavior | Scale the amount down only when the available width requires it; a narrow-phone regression verifies one line |
| History filters | A horizontally scrolling strip left filter chips clipped at the screen edge without a strong cue | P2 | All filters competed for a single horizontal row | Wrap the filters into visible rows and constrain long account labels |
| Loan repayment history | Transaction cards were narrower than History and unnecessarily truncated the same details | P2 | Default route padding, extra section padding, and individually surfaced rows compounded the inset | Reduce row inset from 52 dp to History's 16 dp, reuse grouped rows, and retain trailing amount alignment; regression compares actual screens at 360 dp/100% and 320 dp/200% text |
| Cards | Dark or light custom account colors made icons nearly invisible on matching surfaces | P2 | Icon color was reused without checking its contrast against the tinted panel | Preserve legible custom colors and use the themed foreground when contrast is insufficient |
| Drawer privacy switch | The label truncated even at normal text size | P2 | Redundant on/off text competed with the switch for width | Show the complete label and retain the switch's accessible state |
| Home headers | Titles truncated beside actions | P2 | Single-line text constraint | Wrap headings within available space |
| Loan/recurring editors | Amount/currency fields and labels became unusably narrow | P1 | Side-by-side controls retained at small widths/large text | Responsive stacking/reflow |
| Dashboard summaries and transaction rows | Amounts, payment details, and card actions crowded or overflowed at enlarged text | P1 | Fixed side-by-side arrangements and single-line constraints | Stack the affected content and allow labels and values to wrap while preserving row actions |
| Transaction editor | Transaction types, keypad, and details crowded short screens and enlarged text | P1 | Inflexible controls and a non-scrollable column containing a fixed viewport | Responsive selectors and a scrollable sliver layout with minimum keypad touch targets; keep detail fields reachable with the keyboard open |
| Onboarding and glass previews | Progress and preview labels overflowed on compact phones at 200% text | P1 | Unconstrained rows and fixed icon spacing | Constrain and wrap labels and reduce decorative preview spacing |
| Cloud recovery and unknown route | Recovery and return-home buttons wrapped at 200% text | P2 | Long labels competed with icons and panel padding | Use concise visible labels and retain full accessible descriptions |
| Offline consent | The confirmation label wrapped at 200% text on a compact phone | P2 | Large sheet padding left insufficient button width | Use compact inner padding at enlarged text while retaining the complete label |
| Backup/recurring controls | Button/chip labels wrapped at large text | P2 | Wording exceeded available control width | Shorter action copy with explanatory text retained |
| Appearance settings | Controls overflowed; unselected finish badges lacked contrast | P2 | Fixed horizontal arrangements and unsuitable text color | Reflow and theme-appropriate badge foregrounds |
| Account editor | Opening-balance guidance truncated | P2 | Constrained explanatory text | Allow complete wrapping |
| Calculator | Backspace lacked an accessible name | P2 | Icon-only action without a label | Explicit backspace semantics |
| Bottom navigation | Labels announced twice and clipped at 200% | P2 | Duplicate descendant semantics and insufficient label width | Single semantic action per tab; undock FAB as needed; retain the selected readable label and icon-only unselected targets |
| Calendar menu | Menu action merged with the page title in Android accessibility | P2 | Semantic grouping crossed the action boundary | Separate menu semantics container and action |
| Compact action buttons | `Manage` announced twice; target only 28 dp high on Android | P2 | Explicit semantic label duplicated visible text; padding alone determined height | Use the visible label once and enforce 48 dp minimum bounds |

Buttons were not globally forced to a smaller font or stripped of text scaling.
The fixes use the existing design system and do not claim that every remaining
button label or user-generated string is clipping-free.

### UI/UX and engineering improvements

- Headings, subtitles, explanatory text, amounts, and account tiles can use their
  natural height instead of being clipped or squeezed.
- Compact/landscape views retain intentional scrolling; no global scroll-view
  wrapper or text-scaling disablement was introduced.
- Navigation labels are measured with the current font/scaler. Measurements are
  outside the page-animation callback rather than repeated every animation frame.
- Forecast charts measure localized currency/date labels, retain distinct values
  for narrow ranges, and reduce date-label density when the plot is too narrow.
  Their zoom controls remain available without covering the plotted axis.
- Tests use real Inter metrics for navigation geometry. Native accessibility trees
  confirm distinct menu/tab actions and a single `Manage` label with a 48 dp target;
  they do not prove complete TalkBack behavior.
- Startup tasks now respect the lifecycle of the provider build that scheduled them.
  Regression tests preserve offline ownership and interrupted-upgrade behavior.
- Shared components were reused; no new dependencies or broad architecture rewrite.
  No measured production frame-time, memory, or battery improvement is claimed.

### Verification evidence

Environment: Windows, Flutter 3.47.7 / Dart 3.13.5, widget-test fixtures with real
fonts, a local Flutter web session, and Android API 37 emulator `emulator-5554`
(1280 x 2856 physical pixels, 480 dpi). No iOS runtime/macOS build environment.

| Test | Result | Details |
|---|---|---|
| `flutter test --no-pub --reporter compact --concurrency=1` | **Passed** | Latest full serial run: 777 passed, 2 skipped; includes unit/widget regressions and the route matrix. The final formatting-only pass was followed by 46 focused passes |
| Focused layout, route, filter, and shared-widget tests | **Passed** | 46 passed after formatting the final changed Dart files |
| `flutter test --no-pub --reporter expanded test\loans_screen_form_bugfix_test.dart test\transaction_row_recurring_row_opaque_surface_test.dart` | **Passed** | 14 passed, including cross-screen repayment geometry, trailing amount alignment, forecast labels, and loan-form guards |
| Startup/ownership regression subset | **Passed** | `flutter test --no-pub --reporter expanded test/offline_mode_startup_test.dart test/offline_upgrade_migration_test.dart test/notification_capture_flow_test.dart`: 22 passed |
| Dashboard regression subset | **Passed** | `flutter test --no-pub --reporter expanded test/home_account_tile_large_text_overflow_test.dart`: 3 passed |
| `flutter analyze --no-pub` | **Not clean** | One existing `prefer_const_constructors` info in `test/loan_plan_transaction_integration_test.dart:313`; no analyzer errors/warnings in the last completed run |
| `dart format --output=none --set-exit-if-changed lib test integration_test` | **Not clean, earlier baseline** | 24 files had formatting differences; broad pre-existing formatter churn deliberately avoided |
| Changed Dart files formatting | **Passed** | Final modified Dart files formatted directly with `dart format` |
| `git -c core.whitespace=cr-at-eol --no-pager diff --check` | **Passed** | Accommodates existing CRLF files |
| `flutter build apk --debug --no-pub --target lib\main.dart` | **Passed** | Final APK built and installed with `adb install -r`; ledger-file hash matched across install. Kotlin plugin migration warnings remain |
| Android native interaction | **Passed, limited scope** | Repayment rows and forecast rechecked earlier; latest replacement install and populated History filter layout inspected read-only |
| Android 200% text | **Passed, limited scope** | Repayment descriptions/amounts reflow without overlap; earlier Home/Calendar checks passed; system scale restored to 1.0 |
| Android native-widget rendering | **Passed, limited scope** | All 18 nonempty bitmap outputs generated; latest app-PID log sample has no renderer errors. Launcher placement, appearance, and interactions remain unverified |
| Manual web interaction | **Passed, limited scope** | Offline onboarding, Home/History/Calendar, calendar day sheet, disposable transaction; not every web screen |
| Overflow/responsiveness | **Passed within fixtures** | Selected sizes/scales and focused geometry assertions; not all clipping or native states |
| `flutter test --no-pub --reporter expanded integration_test/perf_timeline_test.dart` | **Failed; destructive cleanup** | VM-service connection refused; the runner selected the populated Android emulator and uninstalled the app afterward. The benchmark is a synthetic list, not an app performance test |
| `flutter drive --debug --no-pub --no-dds --keep-app-running --timeout=180 -d emulator-5554 --driver test_driver\integration_test.dart --target integration_test\perf_timeline_test.dart` | **Passed** | Synthetic-list integration benchmark passed on the empty emulator; the test app was retained |
| iOS build/device, physical Android devices, other Android API levels | **Unavailable/not run** | No cross-platform release certification |
| Release build, full backend-failure matrix, production performance profile | **Not run** | Debug build and mocked tests are not substitutes |

Earlier runs had intermittent runner-load connection failures and a crypto-test
timeout. A later concurrency-2 run ended with 772 passed, 2 skipped, and one
credit-utilization test-file load failure; that file's 2 tests passed on retry.
The final serial suite above completed successfully without concurrent Flutter
build/analysis.

Sixty fixture screenshots plus selected subsequent captures were generated during
the audit; not every one of the 845 fixture renders was manually reviewed. Native
Home/Calendar/loan screenshots and accessibility XML are retained with the session
artifacts, not committed as golden baselines. Android system font scale was restored
to its original 1.0 after each enlarged-text check. The disposable wallet from the
earlier audit was removed after its verification; the later populated app was
uninstalled by the failed integration-test attempt described above.

The latest app-PID log sample contained zero RenderFlex overflow, infinite-height,
native-widget rendering, unhandled-exception, or secure-storage decryption matches.
Earlier logs did contain native-widget and secure-storage errors. A clean sampled
log is not an exhaustive native-console or persistence sign-off.

### Remaining issues and release blockers

1. **Integration tests can remove app data.** Use a disposable device and the
   explicit cleanup safeguards described above. No further integration tests
   were run against the restored populated wallet.
2. **Native launcher presentation remains unverified.** The infinite-height
   rendering failure was reproduced and fixed, and all 18 bitmap files now
   generate. Placement, sizing, refresh, and actions on actual launcher widgets
   still need verification.
3. **Secure-storage/persistence anomaly needs investigation.** Key-decryption
   errors appeared in earlier native logs, but not the latest sample. The earlier disposable account
   was absent after a reinstall; subsequent controlled save/reinstall/relaunch
   checks retained a new account. The cause and recovery behavior are not isolated;
   the final controlled populated-wallet replacement retained accounts and transactions,
   but this is not general proof of upgrade persistence or complete recovery. Resetting
   keys or suppressing the error would not be a safe audit fix.
4. **Accessibility is incomplete.** Core tab/menu/action duplication was fixed.
   Calendar day semantics still identify days only by number, which is ambiguous
   for adjacent-month cells. Full TalkBack/VoiceOver,
   focus order, every form label, contrast, and target size were not certified.
5. **Liquid-glass grouped-layer warnings remain.** Per-widget settings can be
   ignored without an own layer. Do not assume intended blur/contrast/performance
   from fixture renders, or enable costly independent layers globally.
6. **Coverage limits remain:** every overlay/keyboard state, large user-generated
   strings, all loading/error/retry combinations, auth expiry, real cloud conflicts,
   live OCR/capture, biometric hardware, and store-delivered update flows were not
   exercised end-to-end. Some other labels may still truncate.
7. Analyzer/format baseline issues and Kotlin plugin migration warnings remain.
   The route matrix deliberately excludes a known `semantics.parentDataDirty`
   harness error and uses bounded pumping; it cannot detect every semantic,
   animation, clipping, or interaction defect.
8. Debug-emulator skipped-frame logs were observed. Without profile/release traces,
   production performance, memory behavior, and battery impact remain unverified.

### Provisional quality scores

These are subjective engineering estimates for the inspected implementation, not
measured compliance or release approval. Performance and production-readiness
scores carry especially low confidence because of the verification gaps.

| Category | Score / 10 |
|---|---:|
| UI consistency | 8 |
| Visual design | 8 |
| Responsiveness | 8 |
| Overflow safety | 7.5 |
| Typography | 8 |
| Navigation | 8 |
| Accessibility | 6.5 |
| Performance | 5.5 |
| Code quality | 8 |
| Production readiness | 5 |
| **Overall** | **7.3** |

Release sign-off remains blocked by the unresolved secure-storage/recovery anomaly
and missing launcher/platform/device/accessibility coverage.

## Historical UI consistency audit and normalization

1Wallet grew one feature at a time, and the same UI concept ended up built several different ways:
page frames, cards, rows, buttons, dialogs, sheets, feedback, loading/empty/error states, colours,
radii, spacing and type. This document records the audit (Phase 1), the canonical choice made for
each concept (Phase 2), the migration (Phase 3) and how it was verified (Phase 4).

The inventory and baseline below describe that earlier migration. The current route matrix covers
representative populated, empty and startup routes at additional phone sizes and text scales; it
does not exercise every overlay or interaction, and it excludes a known test-harness
`semantics.parentDataDirty` error. Widget screenshots are not a substitute for device testing.

- **Baseline:** commit `d5507405` (`feat(offline): add offline-only local wallet mode…`).
  `flutter analyze` reported no issues; `flutter test` passed 479 tests and skipped 2.
- **Scope:** all UI files under `lib/src/features/**` and `lib/src/widgets/**`, plus the theme
  (`lib/src/theme/app_theme.dart`) and the design tokens (`lib/src/design/tokens.dart`). The work
  changed presentation only; no data, routing, provider, persistence or sync behaviour changed.
- **Method:**
  - A scripted inventory scanned every `.dart` file in `lib/src` for 60 concept patterns and
    recorded file:line references.
  - Every screen in the checklist was then reviewed manually.
  - `test/ui_route_matrix_test.dart` rendered every route in light and AMOLED dark, at 1.0× and
    1.3× text, on a 360 dp phone and on a tablet, with the real Inter and Material Icons fonts.
    It also rendered every route with an empty wallet.
  - The test ran first against the baseline, to find existing breakage, and again after each
    migration batch.

## 1. Inventory: routes and overlays (Phase 1)

### Routes (`lib/src/routing/app_router.dart`)

| Route | Screen | Frame (before → after) |
|---|---|---|
| `/launch` | `LaunchScreen` | brand `Scaffold` (allowed brand frame) |
| `/login` (`/signup` → `/login`) | `LoginScreen` | brand `Scaffold` + `BrandFrostedPanel` (allowed) |
| `/onboarding` | `OnboardingScreen` | brand `Scaffold` (allowed) |
| `/permissions-setup` | `PermissionsSetupScreen` | raw `Scaffold`+`GlassAppBar` → `RouteScaffold` |
| `/account-deletion` | `AccountDeletionScreen` | raw `Scaffold` + **Material `AppBar`** → `RouteScaffold(automaticallyImplyLeading: false)` |
| `/` | `MainShell` with tabs Home, History, Calendar, Accounts (`AppScreen`), drawer `AppMainDrawer`, bottom island + FAB | shell `Scaffold` (allowed) |
| `/add`, `/add?transactionId=…` | `AddRecordScreen` | raw `Scaffold`+`GlassAppBar`, Material back/camera `IconButton`s → `RouteScaffold` + `HeaderIconButton`s |
| `/transaction/:id` | `TransactionDetailScreen` | `RouteScaffold` (header `IconButton`s → `HeaderIconButton`) |
| `/account/new`, `/account/:id`, `/account/:id/secure` | `AccountEditorScreen`, `SecureAccountDetailsScreen` | `RouteScaffold` |
| `/accounts` | `AccountsScreen` (stand-alone) | `AppScreen` (no `Material` ancestor → fixed) |
| `/widgets` (`/reports` → `/widgets`) | `WidgetsManagerScreen` | `RouteScaffold` (drawer) |
| `/review` (`/notifications` → `/review`) | `ReviewQueueScreen` | raw `Scaffold`+`GlassAppBar`+Material `IconButton`s → `RouteScaffold(hasDrawer: false)` |
| `/capture/:id` | `CaptureDetailScreen` | `RouteScaffold` |
| `/settings` | `SettingsScreen` | `RouteScaffold` (drawer) |
| `/recurring`, `/recurring/new`, `/recurring/past`, `/recurring/:id`, `/recurring/:id/edit` | `RecurringScreen` | `RouteScaffold` |
| `/cards` | `CardsScreen` | `RouteScaffold` |
| `/loans`, `/loans/new`, `/loans/past`, `/loans/forecast`, `/loans/:id`, `/loans/:id/edit` | `LoansScreen` | `RouteScaffold` |
| `/categories`, `/currencies`, `/sync`, `/updates` | Categories, Currencies, Sync, Updates | `RouteScaffold` (drawer) |
| `/import-statement`, `/imports/:id` (`/imports` → `/sync`) | `ImportStatementScreen`, `ImportBatchDetailScreen` | `RouteScaffold` |
| `/capture-settings`, `/import-sms`, `/auto-capture`, `/auto-capture/debug` | capture settings, SMS capture, diagnostics | `RouteScaffold` |
| `/notification-capture`, `/notification-capture/apps` | notification capture, target apps | `RouteScaffold`; apps: raw `Scaffold` → `RouteScaffold` |
| `/data-backup`, `/device-permissions` | backup, permissions | `RouteScaffold` |

### Overlays reachable from those routes

- **Pushed pickers:**
  - `showFullScreenPicker` (`common/full_screen_picker.dart`, used by locale, theme, account, currency and payment-method pickers).
  - `CategoryHierarchyPicker`.
  - Before: both used a raw `Scaffold` with a bare `GlassIconButton` back. After: `RouteScaffold` with `HeaderIconButton`.
- **Drawer:**
  - `AppMainDrawer` (`main/main_drawer_components.dart`) with the privacy toggle, which moved from a bare `GlassSwitch` to `AppSwitchListTile`.
  - `DrawerSection`/`DrawerRouteTile` navigation chrome is kept.
- **Lock overlay:** `AppLockGate` (`security/app_lock.dart`) still wraps the whole router. Its unlock spinner is now `AppInlineSpinner`.
- **Bottom sheets (7):**
  - calendar day sheet;
  - account day-of-month picker;
  - merge-transactions sheet;
  - SMS and notification scan results;
  - offline-mode acknowledgement sheet (login);
  - offline upgrade sheet (settings).
  - Before: 7 different `showModalBottomSheet` configurations (maxWidth 460/540/640/none, `useSafeArea` vs inner `SafeArea`, 3 copy-pasted drag-handle surfaces). After: all use `showAppSheet` + `AppSheetSurface`.
- **Dialogs:** 31 `AlertDialog`s + 2 `Dialog`s + 1 `GlassDialog` before.
  - Confirmations (delete/close/reopen account, delete record or selection, delete/archive plan and loan, reset/delete category, restore/force restore, import/replace wallet, assign/approve/dismiss captures, clear diagnostics, sync overwrite/discard/rollback, offline upgrade choices) moved to `showAppConfirmDialog`.
  - Form, list and info dialogs that stay `AlertDialog`, now with the canonical action order and button types:
    - cannot-delete info;
    - add custom field;
    - block pattern;
    - category editor;
    - set rate;
    - PDF password;
    - backup passphrase;
    - delete account (with input + progress);
    - category filter;
    - cannot merge;
    - colour picker.
- **Snackbars:** 49 inline `SnackBar`s with five behaviour variants (floating or fixed, queued or replacing, explicit durations) → `showAppSnackBar`. The original audit preserved visual suppression; the current theme now displays this feedback.
- **Menus:** `GlassDropdownPill` (glass menu) and the categories `PopupMenuButton` (kept).

## 2. Concept × screen matrix

Counts are non-canonical variants per file: **baseline → now**. `·` means none in either state. Columns:

- **Frame:** raw `Scaffold`/`AppBar` outside the allowed owners.
- **Card:** Material `Card`, direct `GlassCard`, or `BrandFrostedPanel` outside the brand screens.
- **Rows:** Material `ListTile`, raw `GlassListTile`/`GlassGroupedSection`.
- **Toggle:** bare `GlassSwitch` or Material `Switch`.
- **Btn:** raw `GlassButton` or Material `IconButton`.
- **Dialog:** `AlertDialog`/`Dialog`.
- **Sheet:** `showModalBottomSheet`.
- **Load:** `CircularProgressIndicator`.
- **Snack:** `SnackBar(`.
- **Colour:** `Colors.<hue>` or `Color(0x…)`.
- **Alpha:** `withAlpha(int)`.
- **Radius:** `Radius.circular(<n>)`.
- **Space:** numeric `EdgeInsets`/`SizedBox` gap.
- **Type:** raw `fontSize`/`fontFamily`.
- **Icon:** plain (non rounded/outlined) glyph.

Inside `app_kit.dart` the canonical implementations themselves are excluded. Baseline line references are listed per file in §3.

**What the non-zero "now" counts are:**

- **Btn:** content `IconButton`s inside cards and sheets (calendar month arrows, copy/remove/close, chart zoom), all now with tooltips.
- **Dialog:** the form/info `AlertDialog`s listed above.
- **Card:** hero `GlassCard`s kept on the canonical spec (balance hero, loan detail header, recurring summary, update download progress) and `BrandFrostedPanel` on login/onboarding.
- **Load:** the determinate download ring and the account-deletion status spinner.
- **Colour:** user-colour contrast (white/black via `estimateBrightnessForColor`), shadows, Google branding, launch brand art and card art.
- **Space:** widget sizes (48 dp header balancers, 320 dp drawer, 2.5 px avatar ring, 7 px optical bullet offset).
- **Type:** `AppFonts.mono`/theme-derived families, brand art, the Google sign-in label and card art.

| Screen file | Frame | Card | Rows | Toggle | Btn | Dialog | Sheet | Load | Snack | Colour | Alpha | Radius | Space | Type | Icon |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **Entry / auth** | | | | | | | | | | | | | | | |
| `launch/launch_screen.dart` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `launch/brand_widgets.dart` | · | 1→1 | · | · | · | · | · | · | · | 14→7 | · | 1→0 | 3→0 | 6→2 | · |
| `login/login_screen.dart` | · | · | · | · | · | · | · | 1→0 | 1→0 | 8→7 | · | 3→2 | 15→2 | 18→2 | · |
| `login/offline_mode_sheet.dart` | · | 1→1 | · | · | · | · | 1→0 | 1→0 | · | · | · | · | · | · | 1→0 |
| `onboarding/onboarding_screen.dart` | · | 1→0 | 2→0 | · | 1→0 | · | · | · | 1→0 | 1→0 | · | 1→0 | 30→2 | 5→0 | · |
| **Shell / navigation** | | | | | | | | | | | | | | | |
| `main/main_shell.dart` | · | · | · | 1→0 | · | · | · | · | 2→0 | 1→1 | 8→0 | · | 2→1 | · | · |
| `main/main_drawer_components.dart` | · | · | · | · | · | · | · | · | · | · | 16→0 | · | 3→0 | 1→0 | · |
| **Home / dashboard** | | | | | | | | | | | | | | | |
| `home/home_screen.dart` | · | · | · | · | 1→0 | · | · | · | · | · | · | · | 2→0 | · | · |
| `home/home_components.dart` | · | · | · | · | · | · | · | · | · | · | 4→0 | · | 3→0 | 1→0 | · |
| `home/home_widgets.dart` | · | 1→1 | · | · | · | · | · | · | · | 4→2 | 9→0 | 7→0 | 27→0 | 25→0 | 2→0 |
| `home/home_widgets_extra.dart` | · | · | · | · | · | · | · | · | · | · | · | · | · | 2→0 | · |
| `home/home_widget_card.dart` | · | 1→1 | · | · | · | · | · | · | · | 3→0 | 4→0 | 1→0 | 2→0 | 2→0 | · |
| `home/widgets_manager_screen.dart` | · | · | · | 1→0 | 1→0 | · | · | · | 1→0 | · | · | · | 1→1 | · | 1→0 |
| **Transactions** | | | | | | | | | | | | | | | |
| `transactions/transactions_screen.dart` | · | 2→0 | 1→0 | · | 1→1 | 3→2 | 1→0 | · | 2→0 | 1→0 | 9→0 | 1→0 | 2→0 | · | 1→0 |
| `transactions/transactions_components.dart` | · | 1→1 | · | · | · | · | · | · | · | · | · | · | 1→0 | 3→0 | 3→0 |
| `transactions/transaction_row.dart` | · | 1→1 | · | · | · | · | · | · | · | · | 2→0 | · | 1→0 | 2→0 | · |
| `transactions/transaction_detail_screen.dart` | · | · | · | · | 2→0 | 1→0 | · | 1→0 | 3→0 | · | · | · | 2→0 | · | · |
| `transactions/add_record_screen.dart` | 1→0 | 1→1 | 3→0 | · | 2→0 | · | · | 1→0 | 1→0 | · | 1→0 | · | 7→0 | 4→0 | 4→0 |
| `transactions/add_record_widgets.dart` | · | · | · | · | · | · | · | · | · | · | 7→0 | 1→0 | 2→0 | 6→0 | · |
| **Accounts / cards / money setup** | | | | | | | | | | | | | | | |
| `accounts/accounts_screen.dart` | · | 1→0 | · | · | · | · | · | · | · | 1→0 | 1→0 | · | 1→0 | 2→0 | · |
| `accounts/account_editor_screen.dart` | · | 1→0 | · | · | 3→2 | 5→2 | 1→0 | · | 2→0 | 5→2 | 3→0 | 3→0 | 4→0 | 4→0 | 2→0 |
| `accounts/secure_account_details_screen.dart` | · | · | · | · | 2→2 | 2→1 | · | · | 6→0 | 1→0 | 2→0 | · | 8→0 | 1→0 | 3→0 |
| `cards/cards_screen.dart` | · | · | · | · | 1→0 | · | · | · | · | 2→0 | · | 3→0 | 9→0 | 6→0 | · |
| `categories/categories_screen.dart` | · | · | 2→0 | · | 1→0 | 3→1 | · | · | 2→0 | · | 3→0 | · | 3→0 | 1→0 | · |
| `currencies/currencies_screen.dart` | · | · | · | · | 3→0 | 1→1 | · | · | 7→0 | · | · | · | · | · | 3→0 |
| **Planning / forecasting** | | | | | | | | | | | | | | | |
| `calendar/calendar_screen.dart` | · | 2→0 | · | · | 3→3 | 1→1 | 1→0 | · | · | 4→0 | 5→0 | · | 4→0 | 3→0 | 1→0 |
| `loans/loans_screen.dart` | · | 9→1 | 1→0 | · | 2→1 | 1→0 | · | · | 1→0 | 7→2 | · | 1→0 | 25→0 | 18→0 | 4→0 |
| `recurring/recurring_screen.dart` | · | 3→2 | · | · | 3→0 | 1→0 | · | · | 2→0 | 0→2 | · | 2→0 | 13→0 | 21→0 | · |
| **Capture / ingestion** | | | | | | | | | | | | | | | |
| `capture/capture_detail_screen.dart` | · | · | · | · | 1→0 | · | · | · | 1→0 | · | · | · | · | · | · |
| `capture/capture_diagnostics_screen.dart` | · | · | · | · | · | 1→0 | · | 1→0 | 2→0 | · | 4→0 | · | 1→0 | 1→1 | 1→0 |
| `capture/capture_settings_screen.dart` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `capture/notification_apps_screen.dart` | 1→0 | · | · | · | · | · | · | 2→0 | · | · | · | · | 1→0 | 1→0 | 1→0 |
| `capture/notification_capture_screen.dart` | · | 1→0 | · | · | 1→1 | · | 1→0 | 1→0 | 1→0 | 1→0 | 12→0 | 2→0 | 4→0 | 5→0 | · |
| `capture/review_queue_screen.dart` | 1→0 | 1→0 | · | · | 5→2 | 3→1 | · | · | 6→0 | 2→0 | 1→0 | 2→0 | 15→0 | 6→2 | 1→0 |
| `capture/sms_capture_screen.dart` | · | 1→0 | · | · | 1→1 | · | 1→0 | 1→0 | 1→0 | 1→0 | 12→0 | 2→0 | 9→0 | 4→0 | 3→0 |
| `imports/import_statement_screen.dart` | · | · | · | · | · | 1→1 | · | 1→0 | 1→0 | · | · | 2→0 | · | 3→1 | 7→0 |
| **Settings / system** | | | | | | | | | | | | | | | |
| `settings/settings_screen.dart` | · | · | 15→0 | 7→0 | · | 1→1 | · | 1→0 | 1→0 | · | · | · | · | 2→0 | 2→0 |
| `settings/settings_components.dart` | · | 1→0 | 6→0 | 1→0 | · | · | · | · | · | 1→0 | · | · | 2→0 | 3→0 | 3→0 |
| `settings/data_backup_screen.dart` | · | · | · | · | · | 6→1 | · | · | 1→0 | · | · | · | · | · | · |
| `settings/device_permissions_screen.dart` | · | · | · | · | · | · | · | · | 1→0 | · | · | · | 1→0 | · | · |
| `settings/permissions_setup_screen.dart` | 1→0 | · | · | · | · | · | · | · | 1→0 | · | · | 2→0 | 7→0 | 5→0 | 1→0 |
| `settings/account_deletion_screen.dart` | 2→0 | · | · | · | · | · | · | 1→1 | · | · | · | · | 4→0 | · | · |
| `settings/offline_mode_section.dart` | · | 1→0 | 6→0 | · | · | 1→0 | 1→0 | 1→0 | · | · | · | · | · | · | 3→0 |
| `sync/sync_screen.dart` | · | · | · | · | · | 1→0 | · | 2→0 | 2→0 | · | · | 3→0 | 15→0 | · | 1→0 |
| `updates/updates_screen.dart` | · | 2→1 | · | · | 2→0 | · | · | 2→2 | · | 12→0 | · | 5→0 | 16→1 | 9→2 | · |
| **Common / shared chrome** | | | | | | | | | | | | | | | |
| `common/route_scaffold.dart` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `common/full_screen_picker.dart` | 1→0 | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `common/category_hierarchy_picker.dart` | 1→0 | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| **Shared widgets** | | | | | | | | | | | | | | | |
| `widgets/app_glass_page.dart` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `widgets/app_kit.dart` | · | · | 0→2 | · | · | 0→1 | 0→1 | · | 0→1 | 0→1 | 4→0 | · | 6→0 | 10→2 | · |
| `widgets/bottom_island_nav.dart` | · | · | · | · | · | · | · | · | · | · | · | · | · | 0→2 | · |
| `widgets/credit_card_view.dart` | · | · | · | · | · | · | · | · | · | 13→5 | · | 2→1 | 7→0 | 8→8 | 3→0 |
| `widgets/privacy_text.dart` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `widgets/color_picker_dialog.dart` | · | · | · | · | · | 1→1 | · | · | · | · | · | · | · | · | · |
| `widgets/currency_picker.dart` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| `widgets/liquid_progress_indicator.dart` | · | · | · | · | · | · | · | · | · | 1→0 | · | · | · | · | · |
| `widgets/user_identity_widgets.dart` | · | · | · | · | · | · | · | · | · | 14→4 | 10→0 | · | 4→1 | · | · |
| **Total** | **8→0** | **33→11** | **36→2** | **10→0** | **36→13** | **33→14** | **7→1** | **17→3** | **49→1** | **97→33** | **117→0** | **44→3** | **262→8** | **188→22** | **51→0** |


## 3. Baseline deviations with file:line references

Line numbers refer to baseline commit `d5507405`.

#### Entry / auth

- `lib/src/features/launch/launch_screen.dart`: no deviations
- `lib/src/features/launch/brand_widgets.dart`: Card L297; Colour L11, L12, L13, L14, L15, L16, L17, L78, L83, L85, L88, L136, L184, L184; Radius L647; Space L280, L629, L643; Type L568, L579, L636, L762, L773, L805
- `lib/src/features/login/login_screen.dart`: Load L216; Snack L29; Colour L111, L179, L180, L190, L193, L200, L247, L250; Radius L169, L226, L270; Space L48, L51, L66, L72, L74, L88, L104, L118, L136, L151, L233, L262, L264, L291, L312; Type L56, L58, L79, L80, L94, L95, L128, L129, L142, L143, L239, L240, L276, L280, L304, L305, L317, L318
- `lib/src/features/login/offline_mode_sheet.dart`: Card L70; Sheet L11; Load L154; Icon L156
- `lib/src/features/onboarding/onboarding_screen.dart`: Card L619; Rows L377, L624; Btn L288; Snack L161; Colour L80; Radius L384; Space L233, L242, L249, L259, L284, L293, L305, L332, L345, L356, L364, L369, L405, L441, L454, L475, L480, L497, L510, L523, L557, L573, L599, L612, L618, L621, L635, L647, L660, L686; Type L338, L447, L503, L605, L653

#### Shell / navigation

- `lib/src/features/main/main_shell.dart`: Toggle L779; Snack L105, L367; Colour L433; Alpha L425, L428, L433, L456, L458, L462, L732, L733; Space L492, L693
- `lib/src/features/main/main_drawer_components.dart`: Alpha L26, L28, L37, L86, L88, L158, L160, L170, L254, L256, L257, L261, L262, L267, L305, L307; Space L52, L84, L94; Type L342

#### Home / dashboard

- `lib/src/features/home/home_screen.dart`: Btn L75; Space L98, L172
- `lib/src/features/home/home_components.dart`: Alpha L91, L93, L206, L207; Space L39, L50, L105; Type L46
- `lib/src/features/home/home_widgets.dart`: Card L2975; Colour L190, L2716, L2717, L2969; Alpha L190, L192, L2638, L2663, L2666, L2673, L2689, L2702, L2969; Radius L1480, L2323, L2409, L2445, L2958, L2968, L3082; Space L235, L872, L1145, L1153, L1158, L1475, L1526, L1560, L2325, L2339, L2363, L2372, L2381, L2397, L2398, L2422, L2464, L2477, L2488, L2498, L2625, L2641, L2682, L3042, L3076, L3084, L3099; Type L252, L285, L905, L929, L954, L1120, L1149, L1162, L1536, L1545, L1552, L2347, L2359, L2427, L2472, L2485, L2649, L2674, L2690, L2703, L3053, L3063, L3071, L3094, L3107; Icon L230, L1192
- `lib/src/features/home/home_widgets_extra.dart`: Type L127, L132
- `lib/src/features/home/home_widget_card.dart`: Card L169; Colour L149, L706, L728; Alpha L149, L164, L344, L346; Radius L725; Space L248, L370; Type L571, L708
- `lib/src/features/home/widgets_manager_screen.dart`: Toggle L240; Btn L95; Snack L73; Space L157; Icon L235

#### Transactions

- `lib/src/features/transactions/transactions_screen.dart`: Card L1514, L1677; Rows L842; Btn L1499; Dialog L1011, L1102, L1142; Sheet L1173; Snack L1199, L1210; Colour L1444; Alpha L1444, L1459, L1519, L1521, L1612, L1616, L1617, L1682, L1684; Radius L1460; Space L798, L1455; Icon L479
- `lib/src/features/transactions/transactions_components.dart`: Card L101; Space L386; Type L383, L396, L398; Icon L178, L186, L195
- `lib/src/features/transactions/transaction_row.dart`: Card L182; Alpha L65, L199; Space L124; Type L118, L131
- `lib/src/features/transactions/transaction_detail_screen.dart`: Btn L66, L70; Dialog L459; Load L343; Snack L408, L416, L482; Space L126, L163
- `lib/src/features/transactions/add_record_screen.dart`: Frame L185; Card L1497; Rows L556, L676, L683; Btn L190, L211; Load L216; Snack L1286; Alpha L1512; Space L274, L285, L1428, L1457, L1509, L1525, L1536; Type L770, L1530, L1543, L1550; Icon L632, L685, L760, L787
- `lib/src/features/transactions/add_record_widgets.dart`: Alpha L328, L332, L394, L400, L406, L451, L455; Radius L453; Space L92, L233; Type L104, L257, L267, L280, L469, L524

#### Accounts / cards / money setup

- `lib/src/features/accounts/accounts_screen.dart`: Card L324; Colour L316; Alpha L316; Space L274; Type L283, L296
- `lib/src/features/accounts/account_editor_screen.dart`: Card L1471; Btn L111, L1142, L1363; Dialog L905, L924, L1172, L1196, L1482; Sheet L1494; Snack L648, L976; Colour L399, L437, L1384, L1424, L1465; Alpha L159, L1424, L1465; Radius L1321, L1408, L1419; Space L281, L1112, L1318, L1358; Type L289, L1096, L1382, L1448; Icon L1113, L1143
- `lib/src/features/accounts/secure_account_details_screen.dart`: Btn L427, L567; Dialog L161, L350; Snack L113, L148, L208, L325, L335, L397; Colour L604; Alpha L477, L496; Space L172, L414, L530, L549, L580, L587, L589, L601; Type L604; Icon L428, L568, L583
- `lib/src/features/cards/cards_screen.dart`: Btn L59; Colour L116, L117; Radius L170, L183, L254; Space L186, L193, L204, L219, L233, L244, L260, L284, L296; Type L213, L223, L238, L264, L281, L300
- `lib/src/features/categories/categories_screen.dart`: Rows L217, L262; Btn L39; Dialog L151, L196, L353; Snack L173, L324; Alpha L476, L481, L592; Space L58, L509, L586; Type L520
- `lib/src/features/currencies/currencies_screen.dart`: Btn L38, L60, L91; Dialog L409; Snack L49, L71, L82, L154, L227, L238, L249; Icon L40, L168, L357

#### Planning / forecasting

- `lib/src/features/calendar/calendar_screen.dart`: Card L679, L891; Btn L126, L156, L606; Dialog L690; Sheet L701; Colour L671, L757, L832, L965; Alpha L671, L757, L825, L832, L965; Space L145, L271, L276, L953; Type L980, L1000, L1013; Icon L988
- `lib/src/features/loans/loans_screen.dart`: Card L108, L324, L447, L934, L1161, L1284, L2721, L2892, L2940; Rows L2988; Btn L72, L2024; Dialog L1206; Snack L3223; Colour L1490, L1491, L2331, L2335, L2655, L2662, L2687; Radius L2641; Space L95, L196, L311, L569, L964, L1038, L1107, L1146, L1339, L1350, L1363, L1394, L1445, L1833, L1940, L1957, L2019, L2279, L2299, L2656, L2669, L2708, L2879, L2927, L2997; Type L968, L1018, L1029, L1346, L1358, L1370, L1429, L1438, L1813, L1835, L1860, L1943, L1964, L2283, L2306, L2816, L2857, L3007; Icon L2331, L2335, L2655, L2995
- `lib/src/features/recurring/recurring_screen.dart`: Card L193, L442, L1453; Btn L133, L137, L183; Dialog L141; Snack L169, L1964; Radius L695, L1673; Space L301, L561, L573, L584, L623, L628, L690, L1029, L1493, L1547, L1574, L1668, L1693; Type L231, L508, L529, L550, L569, L580, L592, L675, L683, L1497, L1531, L1541, L1554, L1566, L1581, L1593, L1646, L1660, L1705, L1715, L1734

#### Capture / ingestion

- `lib/src/features/capture/capture_detail_screen.dart`: Btn L69; Snack L324
- `lib/src/features/capture/capture_diagnostics_screen.dart`: Dialog L62; Load L112; Snack L90, L102; Alpha L178, L257, L297, L299; Space L295; Type L266; Icon L114
- `lib/src/features/capture/capture_settings_screen.dart`: no deviations
- `lib/src/features/capture/notification_apps_screen.dart`: Frame L85; Load L116, L236; Space L235; Type L160; Icon L246
- `lib/src/features/capture/notification_capture_screen.dart`: Card L603; Btn L525; Sheet L461; Load L352; Snack L449; Colour L486; Alpha L486, L500, L610, L611, L615, L616, L701, L704, L761, L766, L920, L921; Radius L501, L708; Space L496, L531, L693, L776; Type L136, L333, L342, L719, L790
- `lib/src/features/capture/review_queue_screen.dart`: Frame L139; Card L257; Btn L152, L158, L163, L170, L735; Dialog L58, L951, L993; Snack L92, L104, L751, L978, L1170, L1180; Colour L246, L282; Alpha L246; Radius L636, L1065; Space L325, L491, L517, L564, L623, L654, L805, L868, L888, L1053, L1058, L1060, L1075, L1081, L1098; Type L435, L641, L1051, L1070, L1071, L1088; Icon L890
- `lib/src/features/capture/sms_capture_screen.dart`: Card L809; Btn L746; Sheet L680; Load L478; Snack L669; Colour L705; Alpha L705, L720, L816, L817, L821, L822, L894, L897, L955, L960, L1114, L1115; Radius L721, L901; Space L301, L334, L366, L374, L716, L752, L886, L970, L1027; Type L142, L370, L912, L984; Icon L214, L319, L352
- `lib/src/features/imports/import_statement_screen.dart`: Dialog L586; Load L81; Snack L748; Radius L363, L613; Type L368, L368, L621; Icon L110, L186, L352, L352, L428, L460, L468

#### Settings / system

- `lib/src/features/settings/settings_screen.dart`: Rows L153, L156, L179, L204, L236, L239, L257, L279, L282, L318, L335, L344, L603, L672, L674; Toggle L159, L184, L213, L244, L262, L290, L687; Dialog L749; Load L815; Snack L483; Type L793, L839; Icon L324, L360
- `lib/src/features/settings/settings_components.dart`: Card L31; Rows L161, L164, L172, L180, L213, L225; Toggle L230; Colour L84; Space L87, L101; Type L64, L95, L115; Icon L168, L176, L221
- `lib/src/features/settings/data_backup_screen.dart`: Dialog L62, L99, L330, L367, L428, L499; Snack L421
- `lib/src/features/settings/device_permissions_screen.dart`: Snack L83; Space L117
- `lib/src/features/settings/permissions_setup_screen.dart`: Frame L84; Snack L68; Radius L139, L202; Space L119, L131, L194, L230, L235, L242, L254; Type L112, L127, L209, L251, L259; Icon L205
- `lib/src/features/settings/account_deletion_screen.dart`: Frame L13, L14; Load L24; Space L20, L25, L41, L47
- `lib/src/features/settings/offline_mode_section.dart`: Card L180; Rows L21, L24, L33, L45, L53, L381; Dialog L151; Sheet L69; Load L350; Icon L41, L49, L57
- `lib/src/features/sync/sync_screen.dart`: Dialog L814; Load L109, L515; Snack L415, L839; Radius L102, L210, L445; Space L75, L80, L92, L124, L135, L281, L282, L283, L304, L305, L306, L359, L365, L407, L409; Icon L171
- `lib/src/features/updates/updates_screen.dart`: Card L234, L1199; Btn L417, L1297; Load L1232, L1242; Colour L214, L226, L300, L328, L654, L675, L728, L738, L833, L853, L927, L937; Radius L468, L968, L1013, L1136, L1497; Space L267, L465, L707, L858, L942, L965, L1010, L1066, L1105, L1113, L1127, L1163, L1261, L1283, L1493, L1494; Type L438, L460, L479, L863, L884, L976, L1146, L1331, L1506

#### Common / shared chrome

- `lib/src/features/common/route_scaffold.dart`: no deviations
- `lib/src/features/common/full_screen_picker.dart`: Frame L113
- `lib/src/features/common/category_hierarchy_picker.dart`: Frame L80

#### Shared widgets

- `lib/src/widgets/app_glass_page.dart`: no deviations
- `lib/src/widgets/app_kit.dart`: Alpha L295, L789, L891, L1233; Space L194, L576, L660, L750, L1153, L1362; Type L189, L618, L985, L1149, L1158, L1176, L1186, L1290, L1355, L1365
- `lib/src/widgets/bottom_island_nav.dart`: no deviations
- `lib/src/widgets/credit_card_view.dart`: Colour L25, L26, L52, L110, L125, L137, L144, L167, L175, L203, L215, L240, L247; Radius L60, L102; Space L63, L100, L151, L157, L188, L195, L254; Type L138, L145, L167, L176, L204, L216, L241, L248; Icon L64, L124, L124
- `lib/src/widgets/privacy_text.dart`: no deviations
- `lib/src/widgets/color_picker_dialog.dart`: Dialog L14
- `lib/src/widgets/currency_picker.dart`: no deviations
- `lib/src/widgets/liquid_progress_indicator.dart`: Colour L12
- `lib/src/widgets/user_identity_widgets.dart`: Colour L31, L32, L33, L34, L89, L91, L94, L149, L152, L336, L341, L346, L351, L363; Alpha L50, L91, L92, L94, L95, L149, L150, L152, L153, L234; Space L42, L119, L183, L220

## 4. Canonical choice per concept (Phase 2)

| Concept | Canonical (use) | Retired variants (never) | Why this one |
|---|---|---|---|
| Page frame | `RouteScaffold` for pushed routes; `AppScreen` for MainShell tabs. New: `leading`, nullable `hasDrawer`, `automaticallyImplyLeading` | raw `Scaffold`+`GlassAppBar`, Material `AppBar` | Most used (28). It already bundles the glass app bar, back/menu logic, SafeArea, 800 dp cap and top fade. |
| Header actions | `HeaderIconButton` (+ new `tooltip`, `destructive`), `HeaderSaveAction`, `AppBackAction` | Material `IconButton`, bare `GlassIconButton` in headers | Already used by most headers; carries semantic labels; one size and position. |
| Content card | `SectionCard` (titled), `AppPanel` (untitled; opaque by default, `glass:` with AMOLED fallback), `AppSurfaces.panel` decoration | Material `Card`, hand-built panels (5 radius/border variants), copied `isAmoled ? opaque : GlassCard` branches, `BrandFrostedPanel` outside the brand screens | SectionCard is the most used container (62). `AppPanel` names the opaque surface that SectionCard, PremiumRow and MetricTile already shared. |
| Grouped settings list | `AppGroupedSection` + `AppGroupedTile` / `.toggle` | raw `GlassGroupedSection`/`GlassListTile` + trailing `GlassSwitch` | Keeps the existing grouped look but fixes the font (the package drops the family) and merges switch semantics. |
| Content rows | `PremiumRow`, `InfoRow`, `AppSwitchListTile`, `MetricTile`; one row type scale (titleMedium w700 / bodySmall) | Material `ListTile`/`CheckboxListTile`/`SwitchListTile` | These primitives were already the most used rows (85); one type treatment replaces the 15/w800, 16/w700, 16/w500 and 13/12/14 mix. |
| Toggles | `AppSwitchListTile` / `AppGroupedTile.toggle` | bare `GlassSwitch` rows, Material `Switch` | Single merged semantics node; the row toggles on tap. |
| Buttons | Material buttons themed by M3: `FilledButton` primary, `.tonal`/`OutlinedButton` secondary, `TextButton` tertiary; `AppButtonStyles.cta`, `.compact`, `.destructive{Filled,Outlined,Text}`; `AppActionButton` for glass chrome | ad-hoc `styleFrom` heights, radii and colours; `primaryContainer` hacks; raw `GlassButton` | `FilledButton`/`TextButton` are by far the most used (77/56) and tests find them by type. |
| Confirm dialog vs action sheet | `showAppConfirmDialog` (TextButton cancel + FilledButton confirm, error-filled when destructive); dialog theme pinned to `AppRadii.xl`/`surfaceContainerHigh` | hand-built `AlertDialog`s with TextButton-red, tonal or filled confirms; `GlassDialog` | `AlertDialog` was the most used (31); one helper gives a consistent hierarchy. Data-removing or overwriting confirmations are always destructive. |
| Sheets | `showAppSheet` + `AppSheetSurface`/`AppSheetHandle` | raw `showModalBottomSheet`, copied drag-handle surfaces | One presentation (transparent route, safe area, 640 dp cap). |
| Loading / empty / error | `AppLoadingState`, `AppInlineSpinner`, `EmptyState`, and `EmptyState(tone: MetricTone.danger)` for errors | `Center(CircularProgressIndicator())`, hand-sized spinners, ad-hoc icon+text columns, red text errors | EmptyState was already canonical (31 uses). |
| Snackbar helper | `showAppSnackBar` / `messenger.showAppSnackBar` (floating, replaces current) | inline `SnackBar` (49) | Most call sites already used floating + hideCurrentSnackBar. |
| Amount text | `PrivacyText` / `maskMoneyIfPrivate` + `formatMoney` | raw `Text(formatMoney(...))` | Privacy invariant; this pass found and fixed several leaks. |
| Status colour | `scheme.positive`, `scheme.error`, `scheme.warning` (= secondary), `MetricTone.resolve(scheme)` | `AppColors.positiveLight/Dark` ternaries, 8 local tone switches, `Colors.green`, hex greens/blues/reds | One semantic mapping; warning keeps the app-wide existing `secondary` mapping. |
| Icon style | `_rounded` for actions, navigation and status; `_outlined` for content and categories | plain/sharp glyphs (52) | The app chrome already used rounded; plain → rounded keeps the filled silhouette. |
| Alpha | `withValues(alpha:)` / `withAlphaFactor` | `withAlpha(int)` (117) | Modern Flutter API; one style. |
| Typography | `Theme.textTheme` roles in **Inter**; `AppFonts.mono` | raw `fontSize` (174), `fontFamily: 'Inter'` (11), `'monospace'` literals | The documented design system. |
| Radius / spacing | `AppRadii` (+ `xs`) / `AppSpacing` (+ `xxxs`) | numeric literals | Existing tokens; the two additions cover genuinely repeated micro values. |

### Token additions (gaps that were genuinely missing)

| Token | Value | Reason |
|---|---|---|
| `AppSpacing.xxxs` | 2 | 34 title/subtitle stacking gaps of exactly 2 dp; no token existed |
| `AppRadii.xs` | 4 | 10 exact uses (bars, tags, badges), plus 2/3/5/6 variants |
| `AppSizes.ctaHeight` | 56 | Full-width CTA height repeated across onboarding, setup, loans and recurring |
| `AppFonts.mono` | `'monospace'` | 6 repeated monospace literals (versions, raw SMS, diagnostics) |
| `ColorScheme.positive` / `.warning` | positiveLight/Dark, secondary | Positive ternary repeated 10+ times; 8 local tone switches |
| `AppColors.amoledSurface*`, `lightBackground` | existing theme values | The theme's raw literals are now named; `lightBackground` had a stale, unused value |
| `AppColors.defaultAccountColor` | `0xFF448AFF` | Persisted onboarding default (was `Colors.blueAccent`); value unchanged |

## 5. Mapping of non-token values (explicit, not silent)

**Radii.**

| Range | Token |
|---|---|
| 2–6 | `xs` (4) |
| 8, 10 | `sm` |
| 12, 14, 16 | `md` |
| 18–24 | `lg` |
| 28, 32 | `xl` |
| ≥ height/2 | `pill` |

Notable cases:

- Cards and tiles at 16 (cards, DashboardCard, add-record selector, accelerated banner) → `md`.
- Permissions panel 24 → `md`, because it is a card.
- The login panel 32 → `xl`.
- The credit-card copy chip 20 → `pill`.

**Spacing.** Exact values map 1:1. Non-exact values were mapped by role:

| Value | Maps to |
|---|---|
| 1, 3 | `xxxs`/`xxs` |
| 5, 6 | `xxs` for inline/badge gaps; `xs` between blocks |
| 7 | `xs` |
| 10 | `xs` for gaps; `sm` for padding |
| 11 | `sm` |
| 14, 15, 18 | `sm`/`md` |
| 28, 30 | `xl`/`xxl` |
| 40, 48, 80 hero gaps | token sums (e.g. `xxl + xs`), so heights are unchanged |

Every non-exact mapping is listed in the batch commit history (`refactor(ui): replace literal radii and spacing with tokens`).

**Typography.**

| Size (sp) | Role |
|---|---|
| 8–11.5 | `labelSmall` (11) |
| 12–13 | `bodySmall`, or `labelMedium` for labels/chips |
| 14–15 | `bodyMedium`/`titleSmall`/`labelLarge` |
| 16–17 | `titleMedium`/`bodyLarge` |
| 18–22 | `titleLarge` |
| 24 | `headlineSmall` |
| 26–28 | `headlineMedium` |
| 32–34 | `headlineLarge` |
| 36–40 | `displaySmall` |
| 45–52 | `displayMedium` |

Layouts that grew got `FittedBox(scaleDown)` (balance hero, calendar day amounts, account-tile currency badge) or ellipsis/`Flexible` (release headers, recurring summary, card badges, payment counters).

## 6. Root-cause findings (beyond token drift)

1. **The app never rendered in Inter.** `ThemeData(fontFamily: 'Inter')` does not reach an explicit `textTheme`, so every themed text used Roboto (Android) or SF (iOS). Only login, which hard-coded `'Inter'`, used the brand face. Fixed in `AppTheme` (`textTheme.apply(fontFamily: 'Inter')`).
2. **Font leaks inside package widgets.** `GlassListTile`, `GlassGroupedSection`, `GlassTabBar` labels, `GlassSearchBar`/`GlassTextField` and `AppSwitchListTile`'s own `DefaultTextStyle` replaced the inherited style without a family. They are now wrapped or fed theme styles.
3. **Stand-alone `/accounts` rendered debug text.** `AppScreen` used a `ColoredBox` instead of a `Material`, so outside the shell scaffold the text fell back to the framework's red/yellow-underline style. Caught by the new empty-wallet route matrix.
4. **360 dp overflows:**
   - the recurring editor's automation and frequency dropdowns;
   - the updates version pills;
   - the Google sign-in label at 1.3× text;
   - the loan "Paid / months left" row;
   - card badges next to "Confirm paid";
   - recurring summary rows.
5. **Privacy-mode leaks:**
   - SMS/notification scan-result amounts and raw message previews;
   - the review queue's raw message preview;
   - the statement-import preview amounts;
   - the diagnostics amount chip;
   - the transactions filtered total and merge sheet;
   - the planned-payments tile value;
   - the cards "Due" amount;
   - the onboarding opening balance.

   All are now masked.
6. **Contrast bugs on user-chosen colours.** Account, loan and recurring icon glyphs and credit-card text chose `onSurface`/`surface` by theme rather than by the swatch. That produced light-on-light in dark/AMOLED. They now use `ThemeData.estimateBrightnessForColor`.
7. **Semantics gaps.** Several header actions had no label (add-record camera, transaction edit/delete, recurring add/edit/delete, card add, onboarding back), and grouped settings switches were separate screen-reader stops. All now have labels or merged toggles.
8. **Drift in the newest UI.** The offline-mode upgrade sheet in settings borrowed the login-only `BrandFrostedPanel` and built Material `ListTile`/`Material` choice tiles and its own `AlertDialog` confirmations. It now uses the canonical panel, `PremiumRow` and `showAppConfirmDialog`.

## 7. Exceptions kept (allow-listed in `test/ui_design_system_guard_test.dart`)

| Where | What | Why |
|---|---|---|
| `features/launch/brand_widgets.dart` | literal colours (AMOLED/light backdrops), wordmark/tagline sizes, panel radius | launch brand art (palette now references `AppColors.launch*`) |
| `features/login/login_screen.dart` | Google sign-in button: white surface, `#3C4043` label, Inter 17 sp, radius 28 | Google sign-in branding guidelines |
| `features/login/offline_mode_sheet.dart` | `BrandFrostedPanel`, `CheckboxListTile` | shown from the login screen; a consent acknowledgement must stay a checkbox |
| `features/onboarding/onboarding_screen.dart` | brand `Scaffold`, `BrandFrostedPanel` | brand onboarding flow |
| `features/main/main_shell.dart` | `Scaffold` | owns the drawer and bottom island |
| `widgets/credit_card_view.dart` | card gradients, card-text sizes, 20 dp physical-card corner | realistic card art |
| `widgets/user_identity_widgets.dart` | Google blue/green/yellow/red (declared once) | Google account badge / logo |
| `design/tokens.dart`, `theme/app_theme.dart` | colour literals, theme font family | the token and theme layer itself |

Recommendations not applied (would be redesigns or behaviour changes):

- `AppColors.warning` (#946200) is still unused; status warnings keep the app's `secondary` mapping. Adopting an amber warning hue would be a deliberate palette change.
- `GlassMenu` items (`GlassDropdownPill`) and other package overlays use the package's own text sizes.
- `liquid_glass_widgets` exposes no theme hook for those.
- The review-queue block dialog disposes its text controller as soon as the dialog closes. This predates the pass.
- `_formatAmount` in the statement import preview assumes two-decimal currencies. It is display-only and predates the pass.

## 8. Screenshots (before → after)

Rendered by `flutter test test/ui_route_matrix_test.dart --dart-define=UI_AUDIT_SHOTS=<dir> --dart-define=UI_AUDIT_SHOTS_FILTER=<slugs>` with the bundled Inter and Material Icons fonts. Phone = 360×780 dp, tablet = 1024×1366 dp, large = 1.3× text. Liquid-glass shaders render in the test engine. Glyph boxes (`▯`) are Cupertino icons, which the test engine does not load.

| Screen | Before | After |
|---|---|---|
| Home, light (Inter now applied; opaque record rows)<br>`home@phone-light` | <img src="ui-audit/before/home@phone-light.png" width="240"> | <img src="ui-audit/after/home@phone-light.png" width="240"> |
| Home, AMOLED dark<br>`home@phone-dark` | <img src="ui-audit/before/home@phone-dark.png" width="240"> | <img src="ui-audit/after/home@phone-dark.png" width="240"> |
| Home, 1.3× text<br>`home@phone-light-large` | <img src="ui-audit/before/home@phone-light-large.png" width="240"> | <img src="ui-audit/after/home@phone-light-large.png" width="240"> |
| Home, tablet<br>`home@tablet-light` | <img src="ui-audit/before/home@tablet-light.png" width="240"> | <img src="ui-audit/after/home@tablet-light.png" width="240"> |
| History: grouped day sections<br>`history@phone-light` | <img src="ui-audit/before/history@phone-light.png" width="240"> | <img src="ui-audit/after/history@phone-light.png" width="240"> |
| History, AMOLED dark<br>`history@phone-dark` | <img src="ui-audit/before/history@phone-dark.png" width="240"> | <img src="ui-audit/after/history@phone-dark.png" width="240"> |
| Accounts tab<br>`accounts@phone-light` | <img src="ui-audit/before/accounts@phone-light.png" width="240"> | <img src="ui-audit/after/accounts@phone-light.png" width="240"> |
| Accounts tab, AMOLED dark<br>`accounts@phone-dark` | <img src="ui-audit/before/accounts@phone-dark.png" width="240"> | <img src="ui-audit/after/accounts@phone-dark.png" width="240"> |
| Stand-alone /accounts with an empty wallet: debug-style text (before) fixed by the AppScreen Material ancestor (after)<br>`empty-accounts@phone-light` | <img src="ui-audit/before/empty-accounts@phone-light.png" width="240"> | <img src="ui-audit/after/empty-accounts@phone-light.png" width="240"> |
| Settings: grouped rows were in the wrong font and inset narrower than the cards<br>`settings@phone-light` | <img src="ui-audit/before/settings@phone-light.png" width="240"> | <img src="ui-audit/after/settings@phone-light.png" width="240"> |
| Settings, AMOLED dark<br>`settings@phone-dark` | <img src="ui-audit/before/settings@phone-dark.png" width="240"> | <img src="ui-audit/after/settings@phone-dark.png" width="240"> |
| Settings, tablet<br>`settings@tablet-dark` | <img src="ui-audit/before/settings@tablet-dark.png" width="240"> | <img src="ui-audit/after/settings@tablet-dark.png" width="240"> |
| Login<br>`login@phone-light` | <img src="ui-audit/before/login@phone-light.png" width="240"> | <img src="ui-audit/after/login@phone-light.png" width="240"> |
| Login, dark<br>`login@phone-dark` | <img src="ui-audit/before/login@phone-dark.png" width="240"> | <img src="ui-audit/after/login@phone-dark.png" width="240"> |
| Login, 1.3× text (Google label overflowed before)<br>`login@phone-light-large` | <img src="ui-audit/before/login@phone-light-large.png" width="240"> | <img src="ui-audit/after/login@phone-light-large.png" width="240"> |
| Onboarding<br>`onboarding@phone-light` | <img src="ui-audit/before/onboarding@phone-light.png" width="240"> | <img src="ui-audit/after/onboarding@phone-light.png" width="240"> |
| Onboarding, dark<br>`onboarding@phone-dark` | <img src="ui-audit/before/onboarding@phone-dark.png" width="240"> | <img src="ui-audit/after/onboarding@phone-dark.png" width="240"> |
| Recurring editor (dropdowns overflowed at 360 dp before)<br>`recurring-new@phone-light` | <img src="ui-audit/before/recurring-new@phone-light.png" width="240"> | <img src="ui-audit/after/recurring-new@phone-light.png" width="240"> |
| Updates, 1.3× text (version pills overflowed before)<br>`updates@phone-light-large` | <img src="ui-audit/before/updates@phone-light-large.png" width="240"> | <img src="ui-audit/after/updates@phone-light-large.png" width="240"> |
| Sync<br>`sync@phone-light` | <img src="ui-audit/before/sync@phone-light.png" width="240"> | <img src="ui-audit/after/sync@phone-light.png" width="240"> |
| Data backup, dark<br>`data-backup@phone-dark` | <img src="ui-audit/before/data-backup@phone-dark.png" width="240"> | <img src="ui-audit/after/data-backup@phone-dark.png" width="240"> |
| Review & inbox (Material header icons → glass header actions)<br>`review@phone-light` | <img src="ui-audit/before/review@phone-light.png" width="240"> | <img src="ui-audit/after/review@phone-light.png" width="240"> |
| Calendar, dark<br>`calendar@phone-dark` | <img src="ui-audit/before/calendar@phone-dark.png" width="240"> | <img src="ui-audit/after/calendar@phone-dark.png" width="240"> |

Also captured after only: `empty-home@phone-dark` (Home with an empty wallet, AMOLED dark).


## 9. Verification (Phase 4)

| Command | Result |
|---|---|
| `flutter analyze` | No issues found (baseline: no issues) |
| `flutter test` | **522 passed, 2 skipped, 0 failed** (baseline 479 passed, 2 skipped; +43 new tests) |
| `flutter test test/ui_route_matrix_test.dart` | 30 passed: 6 variants × (sample routes, empty-wallet routes, login, onboarding, permissions setup) |
| `flutter test test/ui_design_system_guard_test.dart` | 2 passed |
| `flutter test test/app_kit_helpers_test.dart` | 11 passed |
| `flutter build apk --release --target-platform android-arm64 --split-per-abi` | Built `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (20.8 MB) |

Existing UI guards that still pass unchanged:
- `routes_smoke_test`
- `*_opaque_surface_test`
- `nav_chrome_glass_app_bar_test`
- `route_scaffold_*_test`
- `header_icon_button_semantic_labels_test`
- `empty_state_centering_test`
- `login_offline_option_test`
- `offline_mode_screens_test`
- `brand_frosted_panel_test`
- `main_shell_privacy_toggle_semantics_test`
- `settings_privacy_quick_card_semantics_test`
- `app_switch_list_tile_semantics_test`
- `home_account_tile_contrast_test`
- `home_account_tile_large_text_overflow_test`

Two tests were updated because they pinned a retired implementation detail, not behaviour:
- `theme_accent_test` expected the old `withAlpha(110)` literal.
- `widgets_manager_screen_lazy_previews_test` looked up the retired Material `Switch`, now `GlassSwitch` via `AppSwitchListTile`.

`dart format` was run only on changed files.


