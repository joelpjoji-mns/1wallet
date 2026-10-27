# `lib/src/features/common/` — Shared Feature Widgets & Scaffolds

## 🎯 Role & Overview
Houses reusable screens, scaffolds, and pickers shared across multiple features, ensuring a unified visual hierarchy and accessibility standards.

---

## 📜 Key Files

- **`route_scaffold.dart`**: The canonical frame for every pushed route: glass app bar (titleLarge/w800 title), automatic `AppBackAction` or drawer `AppMenuAction` (via `DrawerConfig`, or the nullable `hasDrawer` override), optional custom `leading` (a `HeaderIconButton`), `automaticallyImplyLeading: false` for blocking flows, `SafeArea`, an 800 dp content cap and the top fade mask. Pass `child` for a padded list or `scrollView` for a custom scrollable/column.
- **`full_screen_picker.dart`**: Full-screen modal picker for searching and selecting accounts, categories, tags, or payment methods. Built on `RouteScaffold` + `PremiumRow`.
- **`category_hierarchy_picker.dart`**: Drill-down parent/subcategory picker built on `RouteScaffold` with a custom `leading` that steps up one level (system back does the same).
- **`file_picker_utils.dart`**: Cross-platform wrapper around `file_picker` for selecting PDF statements, CSV files, and backup bundles.

---

## 🛡️ Critical Invariants & Architecture

1. **Accessibility & Semantics**:
   - Every interactive control must have an appropriate `Semantics` label or tooltip for screen reader compatibility.
2. **Glass Header Consistency**:
   - App bars must utilize frosted glass headers that smoothly blend with content scrolled underneath without clipping or flickering.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/route_scaffold_glass_app_bar_test.dart` and `test/full_screen_picker_navigation_chrome_test.dart`.
- [ ] Ensure that pickers handle keyboard focus and text search dismissal smoothly.
