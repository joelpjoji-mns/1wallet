# `lib/src/features/main/` — Main Shell & Adaptive Navigation

## 🎯 Role & Overview
Provides the root application frame and shell layout, managing the bottom floating island navigation bar on mobile, navigation rail on desktop/tablet, and the quick-access side drawer.

---

## 📜 Key Files

- **`main_shell.dart`**: Root scaffold managing child route placement, tab selection state, and adaptive layout transitions based on screen width breakpoints. Confirms a completed offline → Google upgrade with a snackbar (the post-upgrade redirect closes the upgrade sheet). In offline mode the drawer's "Sign out" tile becomes "Back up with Google" (→ Settings), because signing out would wipe the device-only wallet.
- **`main_drawer_components.dart`**: Right/left swipeable drawer with quick shortcuts to Settings, Categories, Currencies, Backup, and Diagnostics.

---

## 🛡️ Critical Invariants & Architecture

1. **Adaptive Navigation**:
   - On screens `< 640px` wide: Render the floating bottom island navigation (`BottomIslandNav`).
   - On screens `>= 640px` wide: Render an ergonomic side navigation rail (`NavigationRail`).
2. **Tab State Preservation**:
   - Switching tabs must preserve scroll positions and state across main top-level destinations (Home, Transactions, Accounts, Analytics).

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/main_shell_glass_nav_test.dart` and `test/right_swipe_drawer_test.dart`.
- [ ] Verify that privacy mode toggles within the shell update all visible child screens reactively.
