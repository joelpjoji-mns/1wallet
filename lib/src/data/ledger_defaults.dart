import 'ledger_codec.dart';
import 'ledger_models.dart';
import 'category_taxonomy.dart';

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
  return lifeCategoryTaxonomy();
}
