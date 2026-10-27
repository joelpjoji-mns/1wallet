# `lib/src/design/` — Design Tokens & Visual Styling

## 🎯 Role & Overview
`tokens.dart` is the single source of truth for spacing, radii, fixed sizes, brand/semantic
colours and non-Material font families. Feature screens never hard-code these values; they use
the tokens below together with `Theme.of(context).textTheme` / `colorScheme` and the shared
widgets in `lib/src/widgets/app_kit.dart`.

---

## 📜 Tokens (`tokens.dart`)

| Token | Values | Use for |
| :--- | :--- | :--- |
| `AppSpacing` | `xxxs` 2 · `xxs` 4 · `xs` 8 · `sm` 12 · `md` 16 · `lg` 20 · `xl` 24 · `xxl` 32 | Every padding, margin and gap (`EdgeInsets`, `SizedBox` gaps, `Gap`). Widget *sizes* (icon/avatar/spinner dimensions) are not spacing. |
| `AppRadii` | `xs` 4 · `sm` 8 · `md` 14 · `lg` 22 · `xl` 28 · `pill` 999 | `xs` bars/tracks/swatches/tiny tags · `sm` chips, small tiles, icon bubbles · `md` cards, rows, panels (default) · `lg` hero panels and sheet tops · `xl` dialogs · `pill` capsules/buttons. |
| `AppSizes` | `bottomBarClearance`, `rowLarge`, `islandMaxWidth`, `ctaHeight` 56, … | Layout constants (bottom island clearance, full-width CTA height). |
| `AppColors` | brand red, `positiveLight/Dark`, `dangerLight/Dark`, backgrounds, `launch*`, `accountPalette` | Theme construction, brand art (`launch*`) and user-pickable account colours. Feature screens read colours through `ColorScheme`, not `AppColors`, except `accountPalette`. |
| `ColorScheme.positive` (`AppSemanticColors`) | `positiveLight` / `positiveDark` by brightness | Income, gains, success, "installed/healthy". Negative/danger is `scheme.error`. |
| `AppFonts.mono` | `'monospace'` | Machine-readable text only: version strings, raw SMS/notification bodies, logs, diagnostics. |
| `ColorAlpha.withAlphaFactor` | — | Translucency helper; equivalent to `withValues(alpha:)`. `withAlpha(int)` is not used. |

Typography comes from `lib/src/theme/app_theme.dart`: Material 3 type scale in **Inter**
(applied to the text theme itself — `ThemeData.fontFamily` alone does not reach an explicit
`textTheme`). Use `textTheme.<role>.copyWith(fontWeight/color/letterSpacing/height)`; never a raw
`fontSize`.

---

## 🧭 Canonical choices — "use X, never Y"

| Concept | Use | Never |
| :--- | :--- | :--- |
| Spacing | `AppSpacing.*` | numeric `EdgeInsets`/`SizedBox` gaps |
| Corner radius | `AppRadii.*` | `BorderRadius.circular(<number>)` |
| Text size / family | `textTheme.<role>`; `AppFonts.mono` for monospace | `fontSize: <number>`, `fontFamily: 'Inter'` |
| Colour | `colorScheme.*`, `scheme.positive`, `AppColors.accountPalette` | `Colors.<hue>`, `Color(0x…)` in feature screens |
| Translucency | `withValues(alpha:)` / `withAlphaFactor` | `withAlpha(int)` |
| Icons | `_rounded` (actions, navigation, status) · `_outlined` (content, categories) | plain/sharp glyphs |

Allowed exceptions (enforced by `test/ui_design_system_guard_test.dart`):
`features/launch/brand_widgets.dart` (launch brand art), the Google sign-in button in
`features/login/login_screen.dart` (Google branding: fixed Inter 17sp, #3C4043 text, white
surface), `widgets/credit_card_view.dart` (realistic card art).

---

## 🛡️ Critical Invariants & Architecture

1. **Consistent spacing & radii**: no magic numbers in feature screens; map to the nearest token
   (the mapping table used for the 2026 consistency pass lives in `doc/ui-audit.md`).
2. **Glassmorphism performance**: `BackdropFilter`/glass surfaces must not be deeply stacked. Never
   nest a refractive `GlassCard` inside another glass surface (use the opaque variants of
   `SectionCard`/`PremiumRow`/`MetricTile` instead).
3. **Contrast**: semantic and palette colours must keep WCAG AA contrast in light, dark and AMOLED.

---

## 🔍 LLM / Developer Checklist

- [ ] New spacing/radius/size/colour need? Reuse a token first; add one only for a genuine,
      repeated gap and document it in the table above.
- [ ] Run `flutter test test/ui_design_system_guard_test.dart test/ui_route_matrix_test.dart`.
- [ ] When adjusting token values, check 360 dp phones, 1.3× text and tablet widths (the route
      matrix test covers all three in light and AMOLED dark).
