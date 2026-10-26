# `lib/src/features/home/` — Home Dashboard & Modular Widgets

## 🎯 Role & Overview
The flagship screen of 1Wallet. Provides a customizable, modular financial dashboard displaying balance heroes, account grids, recent transactions, charts, spending breakdowns, upcoming scheduled bills, and loan trackers.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `home_screen.dart` | Main dashboard view assembling widgets based on user reordering preferences. |
| `home_components.dart` | Header components, greeting, quick action buttons, privacy eye toggle. |
| `home_widgets.dart` & `home_widgets_extra.dart` | Modular widgets: `balanceHero`, `accountGrid`, `recentRecords`, `balanceTrend`, `currencyValues`, `upcomingScheduled`, `loanPayoff`, `topCategories`, `netWorth`. |
| `home_widget_card.dart` & `home_widget_models.dart` | Widget container styling, drag handles, card wrappers, and visibility configurations. |
| `home_dashboard_selectors.dart` | Highly optimized selectors aggregating daily balances, 7-day spending trends, and top categories. |
| `home_async_providers.dart` | Asynchronous loaders and cached view-models for dashboard metrics. |
| `widgets_manager_screen.dart` | Reordering and toggle screen allowing users to show, hide, and sort home widgets. |

---

## 🛡️ Critical Invariants & Architecture

1. **Reorder Stability**:
   - Widget ordering is persisted in `LedgerPreferences.homeWidgetOrder`. Adding new widget IDs must append cleanly without breaking existing user orders.
2. **Privacy Toggle Mode**:
   - When the user activates the privacy eye toggle, all monetary balances across all home cards must mask numbers with bullets or blur (`••••••`).
3. **Selector Optimization**:
   - Dashboard selectors must use memoization to avoid re-aggregating thousands of records on every minor UI rebuild.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/home_widget_reorder_test.dart`, `test/home_dashboard_selectors_test.dart`, and `test/balance_hero_animation_test.dart`.
- [ ] Check text contrast and overflow behavior when large currency amounts are displayed (`test/home_account_tile_large_text_overflow_test.dart`).
