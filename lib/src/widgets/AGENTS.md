# `lib/src/widgets/` — Reusable Glass UI Components

## 🎯 Role & Overview
Contains shared visual widgets designed around 1Wallet's signature frosted glass aesthetic (`liquid_glass_widgets`), custom navigation islands, privacy text masking, and credit card visualizers.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `app_glass_page.dart` | Page wrapper applying background gradient, soft blur overlays, and standard padding. |
| `app_kit.dart` | UI design kit: standard cards, metric tiles, pill badges, and buttons. |
| `bottom_island_nav.dart` | Floating frosted glass bottom navigation bar with fluid active indicator animation. |
| `credit_card_view.dart` | Realistic card visualizer with chip, card network logo, gradient reflections, and masked numbers. |
| `privacy_text.dart` | Text widget that automatically masks monetary amounts with bullet symbols (`••••••`) when privacy mode is enabled. |
| `color_picker_dialog.dart` | Dialog allowing users to select colors from presets or custom HSV color wheels. |
| `currency_picker.dart` | Modal selector with search for global fiat and crypto currency codes. |
| `liquid_progress_indicator.dart` | Smooth liquid/wave style progress bar for budget and loan payoff tracking. |
| `user_identity_widgets.dart` | User avatar, account badges, and sign-in status indicators. |

---

## 🛡️ Critical Invariants & Architecture

1. **Privacy Mode Respect**:
   - Any widget rendering monetary amounts must wrap the text in `PrivacyText` or listen to `privacyModeProvider` to ensure values are masked when requested by the user.
2. **Accessibility & Contrast**:
   - Frosted panels must maintain a high enough contrast ratio between text and underlying blurs.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/brand_frosted_panel_test.dart`, `test/home_dashboard_tiles_opaque_surface_test.dart`, and `test/main_shell_privacy_toggle_semantics_test.dart`.
- [ ] Ensure `BottomIslandNav` hit testing does not capture touches outside its floating pill boundaries.
