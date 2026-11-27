# 1Wallet Screen Studio

A phone-sized, interactive reference workspace that renders the **actual Flutter
app**, not a separately styled PWA or an approximation. The screen library
contains all distinct routed screens, including main tabs, editors, details,
setup screens, and settings. Dialogs, sheets, pickers and app-tour replays remain
accessible through their real app controls.

## Run locally (Windows)

From the repository root:

```powershell
.\scripts\build-prototype.ps1
node scripts\serve-prototype.mjs
```

Open <http://127.0.0.1:4173>. Keep the server command running while viewing.
If the port is occupied, use `node scripts\serve-prototype.mjs 4174`; do not stop
another service.
The generated output is ignored by git and can be rebuilt after UI changes.
No changes to the production entrypoint, Firebase configuration or app routes
are needed.

## Visual testing workflow (required for UI changes)

Every change that affects what a screen looks like or how it behaves must be
checked visually in Screen Studio, in addition to the automated Flutter tests.
Widget tests catch overflows and missing widgets. They do not catch misaligned
amounts, uneven spacing, awkwardly wrapped labels, orphaned buttons or content
that looks wrong with real data. The Screen Studio pass is part of "done", not
an optional extra.

### 1. Run it during development

Keep Screen Studio running while you work on UI:

```powershell
.\scripts\build-prototype.ps1        # build the real app for the browser (1-2 minutes)
node scripts\serve-prototype.mjs     # leave running; serves http://127.0.0.1:4173
```

- Before starting the server, check whether <http://127.0.0.1:4173> already
  responds and reuse it. Never stop another process to free the port; use
  `node scripts\serve-prototype.mjs 4174` instead.
- The server reads `build\prototype` on each request. After a Dart change,
  rerun `.\scripts\build-prototype.ps1` and reload the browser page. The
  server does not need a restart.
- The browser shows the last build. Always rebuild after your final edit
  before judging a screen, otherwise you are looking at old code.

### 2. Check every screen you touched

Check each changed screen. Also check each screen that uses a changed shared
widget (anything in `lib/src/widgets/`, `lib/src/design/` or `lib/src/theme/`):

| Check | How |
| :--- | :--- |
| Phone sizes | **Phone size** 390 x 844, 360 x 780 and Compact 320 x 568. |
| Themes | **App theme** AMOLED and Light. |
| Data states | **Wallet state** Sample wallet and Empty wallet (empty states, first-run copy). |
| Whole screen | Scroll to the bottom; open every dialog, sheet, picker and menu the change affects. |
| Real interaction | Tap through the flow (save, edit, delete, confirm, skip) and check the resulting screens, not just the first frame. |
| Long and edge data | Long names and notes, large amounts, foreign currencies, overdue, paused and completed items. Add sample data if a case is missing (see step 4). |

Look specifically for:

- Overflow stripes, clipped text, or text cut off with an ellipsis where it
  should fit.
- Button labels on more than one line, or one button alone on its own row.
  Labels must stay on one line; see `lib/src/widgets/AGENTS.md`.
- Amounts, dates and status pills that don't line up with their title, or
  that drop onto a new line when there is room beside the title.
- Padding, gaps or card heights that differ from neighbouring cards and the
  rest of the app.
- Wrong colours or contrast in either theme, and icons that don't match their
  meaning.
- Regressions on neighbouring screens that share the same widget.

### 3. Turn visual bugs into tests

When the visual pass finds a bug, add a focused widget test (or a route-matrix
case) that fails because of it, then fix the bug so the regression can't
return. Rebuild Screen Studio and check the screen again.

### 4. Keep Screen Studio complete

- **New route or screen:** add it to the `screens` list in
  `web/prototype/studio.js` (group, name, route, description) so it appears
  in the sidebar and in **All screens**. Add workflow steps to `flows` when
  relevant.
- **New scenario or data shape:** add fictitious sample data in
  `lib/src/app/prototype_sample.dart` so the screen shows realistic content,
  including the edge cases above. Keep `test/prototype_runtime_test.dart`
  passing (sample references must resolve to real sample entities).
- **Native-only behaviour** (SMS, notification capture, biometrics, Google
  sign-in, cloud sync, Play updates) isn't simulated. When the UI can be shown
  with fake state, add a preview hook such as
  `/settings?updatePreview=available`. Test the native part with widget tests
  or on a disposable device.

### 5. Record the evidence

In the PR **Verification Evidence** section, or in the task summary, list the
screens, phone sizes, themes and wallet states you checked. Attach screenshots
of changed screens, with before and after when the change is visual.

### Automating the check (agents and Playwright)

- The first load after a rebuild can take 30-40 seconds; wait before judging.
- Select a size with
  `page.locator('[aria-label="Phone size"]').selectOption({index})`
  (0 = 390, 1 = 360, 2 = 320). Open screens with the sidebar buttons, for
  example `getByRole('button', {name: 'Planned payments', exact: true})`.
- Call `locator('iframe').scrollIntoViewIfNeeded()` before taking a
  screenshot of the phone frame. Scroll inside the app with the mouse wheel in
  steps of about 100 pixels.
- To read widget positions, enable Flutter semantics inside the iframe with
  `document.querySelector('flt-semantics-placeholder').click()`. Then query
  roles through `page.frameLocator('iframe')`.
- **Reset this preview** restores the sample data after destructive taps such
  as delete or "Mark all read".
## Explore

- **Phone preview:** tap, type, scroll, save records, inspect details, and navigate
  using the real app. The sidebar opens any reference screen.
- **All screens:** grouped, viewport-loaded live artboards, similar to a design board.
  Each frame is independent and unloaded off-screen to limit GPU use; use
  **Open** to inspect it at full phone size.
- Search screen names, switch between AMOLED and light, choose phone sizes, or
  inspect a populated versus empty wallet.
- **Monochrome** applies a grayscale filter to the real UI; it is not a newly
  authored low-fidelity wireframe.
- Workflow shortcuts select representative steps. Continue inside the phone
  to preserve demo edits; jumping to another reference step reloads its frame.
- App-tour flows are available from the real Settings screen.

## Populated wallet

Choose **Sample wallet** and reload after rebuilding to load the richer dataset:

- Thirty months of activity, with salaries, bills, shopping, travel, savings,
  investments, refunds and transfers throughout the previous calendar year.
- Bank, cash, wallet, savings, investment, credit-card, loan and overdraft
  accounts in INR, USD, EUR, GBP, AED and CAD.
- Ongoing, count-limited, date-limited, paused and completed plans; their past
  payments link to the original plan and populate its history and paid totals.
- Home, car and education loans with repayments, a paid-off laptop loan, and
  an outstanding overdraft.
- Review candidates for expenses, salary, refunds, foreign-currency spending,
  paired transfers, uncertain categories, duplicates and unmatched accounts.
- Every alert currently supported by the app: overdue/upcoming plans, overdue
  card bills, cards due soon, and newly generated card statements. Read and
  unread examples are included.

Use **Calendar** to browse previous months and years, or **Past planned
payments** and **Past loans** to inspect historical payments. The screen library
also contains direct shortcuts to populated plan, loan and capture scenarios.
Sample exchange rates are illustrative manual rates, not market quotes.

## Fidelity and safety

The Flutter widgets, typography, routes, glass rendering and business logic are
shared with the app. Browser rendering and simulated status/home bars are not
pixel-identical to Android/iOS system chrome. This is not a Figma file.

The separate prototype entrypoint uses in-memory preferences, encryption-key
storage and sample ledger data. Every reload resets changes. It never initializes Firebase, reads an
existing wallet, or enables automatic backups. The build script removes the
unused environment asset from the output.

Google sign-in, cloud sync, native SMS/notification access, biometrics, native
updates and device permissions are not simulated. Their screens show the app's
actual unavailable/offline states. Files manually selected for import affect
only the demo; use fictitious data. Some detail screens naturally show missing
items in empty-wallet mode. Onboarding protects populated wallets.

The application stays interactive inside sandboxed same-origin frames. Serve
on localhost only; do not deploy this unrestricted screen-inspection runtime as
the production application.
