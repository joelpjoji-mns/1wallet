# `lib/src/features/launch/` — Launch Screen & Motion Sequence

## 🎯 Role & Overview
Handles the animated splash and launch experience when the app opens, coordinating the handoff from native splash to Flutter and routing into the dashboard or onboarding.

---

## 📜 Key Files

- **`launch_screen.dart`**: Animated screen displaying brand logo, tagline, and progress state while local databases and encryption stores hydrate. Recovery actions use `AuthState.ownerId` and "Try again" also re-runs the offline ownership check (`retryLocalOwnershipCheck`).
- **`brand_widgets.dart`**: Shared brand logo, frosted glass badges, and typographic headers used across launch and marketing screens.

---

## 🛡️ Critical Invariants & Architecture

1. **Fluid Handoff**:
   - The launch animation must complete smoothly and transition without frame stutter or white flashes into `HomeScreen` (if authenticated) or `OnboardingScreen` / `LoginScreen`.
2. **Deterministic Completion**:
   - The launch screen must listen to `startupStateProvider` to know when database hydration is complete before triggering router transitions.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/launch_brand_widgets_motion_test.dart`.
- [ ] Ensure reduced-motion accessibility settings (`MediaQuery.disableAnimationsOf(context)`) are respected.
