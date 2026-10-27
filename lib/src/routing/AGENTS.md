# `lib/src/routing/` — Routing & Navigation Guards

## 🎯 Role & Overview
Configures declarative routing for the application using `go_router`, handling deep links, authentication guards, and path redirect logic.

---

## 📜 Key Files

- **`app_router.dart`**:
  - `appRouterProvider`: Provides the configured `GoRouter` instance.
  - `_RouterRefreshNotifier`: Listens to `authControllerProvider` and `ledgerLoadStateProvider` to trigger route re-evaluation.
  - Route tree: `/`, `/login`, `/onboarding`, `/add`, `/transaction/:id`, `/account/:id`, `/review`, `/cards`, `/loans`, `/settings`, etc.

---

## 🛡️ Critical Invariants & Architecture

1. **Authentication & Onboarding Guards**:
   - If user has not completed onboarding, any path redirect must funnel to `/onboarding`.
   - If app lock is triggered, the route is held under `AppLockGate`.
   - Redirects follow `startupStateProvider` only. Offline mode (`AuthPhase.localOnly`) is a first-class session: it never redirects to `/login`. Like a signed-in account, it may open `/data-backup` from a recoverable startup error.
2. **Deep Link Safety**:
   - Deep links into subroutes (e.g. `/transaction/xyz`) must handle non-existent IDs gracefully by falling back to the parent route without crashing.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/routes_smoke_test.dart` and `test/app_navigation_geometry_test.dart`.
- [ ] Confirm that route transitions preserve browser history on web.
