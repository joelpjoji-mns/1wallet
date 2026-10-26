# `pwa/src/pages/` — PWA Page Views & Screens

## 🎯 Role & Overview
Contains the top-level route views in the React PWA client.

---

## 📜 Key Files

- **`HomePage.tsx`**: Dashboard displaying net worth, total balance, quick stats, and recent transaction list.
- **`AccountsPage.tsx`**: List and breakdown of all accounts with balance cards and add account triggers.
- **`HistoryPage.tsx`**: Transaction history list with search, filter chips, and transaction modal triggers.
- **`CalendarPage.tsx`**: Monthly financial calendar view showing daily cash flow.
- **`PlannerPage.tsx`**: Category budget planning and allowance tracker.

---

## 🛡️ Critical Invariants & Architecture

1. **Responsive Glass Design**:
   - Uses Tailwind CSS classes and frosted glass panels matching the Flutter client's aesthetic.
2. **Selector Consumption**:
   - Pages consume `ledgerSelectors.ts` functions rather than calculating balances inline.

---

## 🔍 LLM / Developer Checklist

- [ ] Confirm pages handle empty states (zero accounts or zero transactions) cleanly with friendly illustration / call-to-action prompts.
