// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => '1Wallet';

  @override
  String get offlineMode => 'Offline Mode';

  @override
  String get offlineModeDescription =>
      'All transactions and account balances stay strictly stored on this device.';

  @override
  String get totalBalance => 'Total Balance';

  @override
  String get addTransaction => 'Add Transaction';

  @override
  String get transferFunds => 'Transfer Funds';

  @override
  String get expense => 'Expense';

  @override
  String get income => 'Income';

  @override
  String get transfer => 'Transfer';

  @override
  String get accountDeleted => 'Account archived successfully';
}
