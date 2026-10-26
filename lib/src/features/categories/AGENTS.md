# `lib/src/features/categories/` — Categories Taxonomy & Budgets

## 🎯 Role & Overview
Provides UI for managing category hierarchies (parent/subcategories), icons, colors, monthly budget limits, and rollover rules.

---

## 📜 Key Files

- **`categories_screen.dart`**:
  - Tree-view and list representation of income and expense categories.
  - Category creator/editor dialogs for icon selection, color customization, and parent category reassignment.

---

## 🛡️ Critical Invariants & Architecture

1. **Cycle Prevention in Hierarchy**:
   - A category cannot have itself or any of its descendants as its `parentId`.
2. **Category Deletion**:
   - When deleting a category that has transactions, transactions must either be reassigned to an "Uncategorized" bucket or prompt the user.
3. **Usage Sorting**:
   - Categories support sorting by alphabetical order, custom order, or historical frequency of usage.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/categories_screen_editor_test.dart` and `test/category_hierarchy_picker_test.dart`.
- [ ] Ensure category color picker conforms to accessible contrast tokens.
