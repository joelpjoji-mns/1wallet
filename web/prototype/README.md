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
