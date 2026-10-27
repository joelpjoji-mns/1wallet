# `lib/src/theme/` — Theme Controller & Material 3 Styling

## 🎯 Role & Overview
Controls application styling, dark/light/system theme modes, custom accent colors, high-contrast surfaces, and dynamic Android 12+ wallpaper color extraction.

---

## 📜 Key Files

- **`app_theme.dart`**:
  - Factory methods building `ThemeData` for light and AMOLED dark with Material 3 styling and component themes (app bar, cards, inputs, dialogs, progress, snackbars, page transitions).
  - Typography: the Material 3 type scale in **Inter**, applied to the text theme itself (`ThemeData.fontFamily` alone does not reach an explicit `textTheme`; before this the app silently rendered Roboto/SF everywhere except screens that hard-coded `'Inter'`).
  - Colours come from tokens (`AppColors.*`, including the named AMOLED surface ramp and light background); never add hex literals here.
  - `snackBarTheme` intentionally renders snackbars visually suppressed (no floating popups over the bottom island); `showAppSnackBar` still exposes the message to assistive tech.
- **`theme_controller.dart`**:
  - `ThemeController`: StateNotifier managing `ThemeMode` (light, dark, system), selected primary accent color, and persistence to `SharedPreferences`.

---

## 🛡️ Critical Invariants & Architecture

1. **Persistence Safety**:
   - Theme changes must persist immediately to `SharedPreferences` so the correct theme loads on cold start without flashes of unstyled light theme.
2. **Accessible Contrast**:
   - Accent colors must guarantee sufficient contrast against dark and light backgrounds for text readability.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/theme_controller_persistence_test.dart` and `test/app_theme_system_color_test.dart`.
- [ ] Ensure that custom accent palettes generate compliant color schemes via `ColorScheme.fromSeed(...)`.
