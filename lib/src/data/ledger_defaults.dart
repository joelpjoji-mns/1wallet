import 'ledger_codec.dart';
import 'ledger_models.dart';

LedgerState emptyLedgerState({
  String userId = 'local-user',
  LedgerPreferences preferences = const LedgerPreferences(),
}) {
  return LedgerState(
    version: currentLedgerStateVersion,
    userId: userId,
    preferences: preferences,
    accounts: const [],
    categories: defaultCategories(),
    transactions: const [],
    budgets: const [],
    goals: const [],
    captureCandidates: const [],
  );
}

List<Category> defaultCategories() {
  return const [
    Category(id: 'cat-salary', name: 'Salary', kind: 'income', sortOrder: 1),
    Category(id: 'cat-food', name: 'Food', kind: 'expense', sortOrder: 2),
    Category(
      id: 'cat-grocery',
      name: 'Groceries',
      kind: 'expense',
      sortOrder: 3,
    ),
    Category(id: 'cat-travel', name: 'Travel', kind: 'expense', sortOrder: 4),
    Category(id: 'cat-bills', name: 'Bills', kind: 'expense', sortOrder: 5),
    Category(id: 'cat-emi', name: 'EMI', kind: 'expense', sortOrder: 6),
  ];
}
