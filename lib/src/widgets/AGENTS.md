# `lib/src/widgets/` — Reusable Glass UI Components

## 🎯 Role & Overview
Contains shared visual widgets designed around 1Wallet's signature frosted glass aesthetic (`liquid_glass_widgets`), custom navigation islands, privacy text masking, and credit card visualizers. `app_kit.dart` is the canonical UI kit: feature screens compose these primitives instead of re-building frames, cards, rows, dialogs, sheets or feedback.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `app_glass_page.dart` | Page wrapper applying background gradient, soft blur overlays, and standard padding. |
| `app_kit.dart` | UI design kit: headers, cards, rows, buttons, inputs, states and the canonical helpers listed below. |
| `bottom_island_nav.dart` | Floating frosted glass bottom navigation bar with fluid active indicator animation. |
| `credit_card_view.dart` | Realistic card visualizer with chip, card network logo, gradient reflections, and masked numbers (card art: allowed raw colours/sizes). |
| `privacy_text.dart` | Text widget that automatically masks monetary amounts with bullet symbols (`••••••`) when privacy mode is enabled. |
| `color_picker_dialog.dart` | Dialog allowing users to select colors from presets or custom HSV color wheels. |
| `currency_picker.dart` | Modal selector with search for global fiat and crypto currency codes. |
| `liquid_progress_indicator.dart` | Smooth liquid/wave style progress bar for budget and loan payoff tracking. |
| `user_identity_widgets.dart` | User avatar, account badges, and sign-in status indicators. |

---

## 🧭 Canonical UI primitives — "use X, never Y"

| Concept | Use | Never |
| :--- | :--- | :--- |
| Page frame | `RouteScaffold` (`features/common/route_scaffold.dart`) for every pushed route; `AppScreen` for MainShell tab pages. Custom back handling → `leading:`; blocking flows → `automaticallyImplyLeading: false`. | Raw `Scaffold` + `GlassAppBar`, Material `AppBar` (only MainShell and the launch/login/onboarding brand screens own a `Scaffold`). |
| Header actions | `HeaderIconButton` (with `semanticLabel` + `tooltip`), `HeaderSaveAction`, `AppBackAction`, `AppMenuAction` | Material `IconButton` or bare `GlassIconButton` in app bars |
| Content container | `SectionCard` (titled); untitled glass panel = `GlassCard` with `LiquidRoundedSuperellipse(AppRadii.md)`; opaque panel = `surfaceContainerLow` + `AppRadii.md` + `outlineVariant` border (SectionCard `glass: false`) | Material `Card`, ad-hoc radii/borders, glass nested in glass, `BrandFrostedPanel` outside launch/login/onboarding |
| Grouped settings list | `AppGroupedSection` + `AppGroupedTile` / `AppGroupedTile.toggle`, rows separated by `GlassDivider` | Raw `GlassGroupedSection` / `GlassListTile` (they drop the app font) |
| Content rows | `PremiumRow` (navigable/selectable), `InfoRow` (label/value), `MetricTile`, `IconBubble` | Material `ListTile` / `SwitchListTile` |
| Toggles | `AppSwitchListTile` (content cards) or `AppGroupedTile.toggle` (grouped lists) — one merged, row-tappable semantics node | Bare `GlassSwitch` in a row, Material `Switch` |
| Buttons | `FilledButton` primary · `FilledButton.tonal`/`OutlinedButton` secondary · `TextButton` tertiary/cancel · `AppButtonStyles.cta` full-width CTA · `AppButtonStyles.compact(context)` dense · `AppButtonStyles.destructive{Filled,Outlined,Text}(context)` · `AppActionButton` for glass chrome actions | Ad-hoc `styleFrom` colours/radii/heights, raw `GlassButton` |
| Confirm dialog | `showAppConfirmDialog(...)` → `Future<bool>` (`AppConfirmDialog`: TextButton cancel + FilledButton confirm, error-filled when `destructive`) | Hand-built confirmation `AlertDialog`s; form dialogs stay `AlertDialog` with the same action order |
| Sheets | `showAppSheet(...)`; draggable/full-height content in `AppSheetSurface` (handle via `AppSheetHandle`) | Raw `showModalBottomSheet`, copied drag-handle/DecoratedBox surfaces |
| Feedback | `showAppSnackBar(context, msg)` / `messenger.showAppSnackBar(msg)` (floating, replaces the current one; the theme intentionally renders snackbars visually suppressed) | Inline `SnackBar(...)` |
| Loading | `AppLoadingState(message:)` for an empty page/section; `AppInlineSpinner` in buttons/rows/headers | `Center(child: CircularProgressIndicator())`, hand-sized spinners |
| Empty / error | `EmptyState(...)`; errors use `tone: MetricTone.danger` | Ad-hoc centred icon + text columns |
| Amounts | `PrivacyText` + `formatMoney` / `NumberFormatter` (integer minor units) | Raw `Text` for money |
| Inputs | `AppGlassTextField`, `PremiumSearchInput`, `GlassDropdownPill` | Unthemed `TextField` styling |

---

## 🛡️ Critical Invariants & Architecture

1. **Privacy Mode Respect**:
   - Any widget rendering monetary amounts must wrap the text in `PrivacyText` or listen to `privacyModeProvider` to ensure values are masked when requested by the user.
2. **Accessibility & Contrast**:
   - Frosted panels must maintain a high enough contrast ratio between text and underlying blurs.
   - Toggle rows expose one merged semantics node with the toggled state; header buttons always carry a `semanticLabel`.
3. **Font plumbing**: several `liquid_glass_widgets` components replace the inherited text style and drop the font family. The kit wrappers (`AppGroupedSection/Tile`, `PremiumSearchInput`, `AppGlassTextField`, `BottomIslandNavBar`) pass the theme's Inter family back in — use them rather than the raw package widgets.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/app_kit_helpers_test.dart`, `test/ui_design_system_guard_test.dart`, `test/ui_route_matrix_test.dart`, `test/brand_frosted_panel_test.dart`, `test/home_dashboard_tiles_opaque_surface_test.dart`, and `test/main_shell_privacy_toggle_semantics_test.dart`.
- [ ] Ensure `BottomIslandNav` hit testing does not capture touches outside its floating pill boundaries.
- [ ] A new shared widget belongs in `app_kit.dart` only if at least two screens need it; wrap existing glass/Material primitives instead of building a parallel style.
