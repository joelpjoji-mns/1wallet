import 'dart:convert';

import 'package:flutter/material.dart';

import 'ledger_models.dart';

const currentLedgerStateVersion = 14;

String encodeLedgerState(LedgerState state) {
  return jsonEncode(_ledgerToJson(state));
}

LedgerState decodeLedgerState(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Ledger archive root must be a JSON object.');
  }
  return _ledgerFromJson(decoded);
}

Map<String, Object?> _ledgerToJson(LedgerState state) {
  return {
    'version': state.version,
    'userId': state.userId,
    'preferences': _preferencesToJson(state.preferences),
    'accounts': state.accounts.map(_accountToJson).toList(),
    'categories': state.categories.map(_categoryToJson).toList(),
    'transactions': state.transactions.map(_transactionToJson).toList(),
    'budgets': state.budgets.map(_budgetToJson).toList(),
    'goals': state.goals.map(_goalToJson).toList(),
    'captureCandidates': state.captureCandidates
        .map(_captureCandidateToJson)
        .toList(),
    'importBatches': state.importBatches.map(_importBatchToJson).toList(),
    'exchangeRates': state.exchangeRates.map(_exchangeRateToJson).toList(),
  };
}

LedgerState _ledgerFromJson(Map<String, dynamic> json) {
  return LedgerState(
    version: _int(json['version'], fallback: currentLedgerStateVersion),
    userId: _string(json['userId'], fallback: 'local-user'),
    preferences: _preferencesFromJson(_map(json['preferences'])),
    accounts: _list(json['accounts']).map(_accountFromJson).toList(),
    categories: _list(json['categories']).map(_categoryFromJson).toList(),
    transactions: _list(
      json['transactions'],
    ).map(_transactionFromJson).toList(),
    budgets: _list(json['budgets']).map(_budgetFromJson).toList(),
    goals: _list(json['goals']).map(_goalFromJson).toList(),
    captureCandidates: _list(
      json['captureCandidates'],
    ).map(_captureCandidateFromJson).toList(),
    importBatches: _list(
      json['importBatches'],
    ).map(_importBatchFromJson).toList(),
    exchangeRates: _list(
      json['exchangeRates'],
    ).map(_exchangeRateFromJson).toList(),
  );
}

Map<String, Object?> _moneyToJson(Money money) {
  return {'amountMinor': money.amountMinor, 'currency': money.currency};
}

Money _moneyFromJson(Object? value, {Money? fallback}) {
  final json = _map(value);
  return Money(
    amountMinor: _int(
      json['amountMinor'],
      fallback: fallback?.amountMinor ?? 0,
    ),
    currency: _string(json['currency'], fallback: fallback?.currency ?? 'INR'),
  );
}

Map<String, Object?> _preferencesToJson(LedgerPreferences preferences) {
  return {
    'baseCurrency': preferences.baseCurrency,
    'displayCurrency': preferences.displayCurrency,
    'enabledCurrencies': preferences.enabledCurrencies,
    'locale': preferences.locale,
    'startDayOfMonth': preferences.startDayOfMonth,
    'homeWidgetOrder': preferences.homeWidgetOrder,
    'homeWidgetHidden': preferences.homeWidgetHidden,
    'homeWidgetSizes': preferences.homeWidgetSizes,
    'homeWidgetFilters': preferences.homeWidgetFilters,
    'homeWidgets': {
      'order': preferences.homeWidgetOrder,
      'hidden': preferences.homeWidgetHidden,
      'sizes': preferences.homeWidgetSizes,
      'filters': preferences.homeWidgetFilters,
    },
    if (preferences.futureGenerationRules != null)
      'futureGenerationRules': preferences.futureGenerationRules!.map(_ruleToJson).toList(),
  };
}

LedgerPreferences _preferencesFromJson(Map<String, dynamic> json) {
  const fallback = LedgerPreferences();
  final homeWidgets = _map(json['homeWidgets']);
  return LedgerPreferences(
    baseCurrency: _string(
      json['baseCurrency'],
      fallback: fallback.baseCurrency,
    ),
    displayCurrency: _string(
      json['displayCurrency'],
      fallback: fallback.displayCurrency,
    ),
    enabledCurrencies: _stringList(
      json['enabledCurrencies'],
      fallback: fallback.enabledCurrencies,
    ),
    locale: _string(json['locale'], fallback: fallback.locale),
    startDayOfMonth: _int(
      json['startDayOfMonth'],
      fallback: fallback.startDayOfMonth,
    ),
    homeWidgetOrder: _stringList(
      json['homeWidgetOrder'],
      fallback: _stringList(
        homeWidgets['order'],
        fallback: fallback.homeWidgetOrder,
      ),
    ),
    homeWidgetHidden: _stringList(
      json['homeWidgetHidden'],
      fallback: _stringList(
        homeWidgets['hidden'],
        fallback: fallback.homeWidgetHidden,
      ),
    ),
    homeWidgetSizes: _stringMap(
      json['homeWidgetSizes'],
      fallback: _stringMap(
        homeWidgets['sizes'],
        fallback: fallback.homeWidgetSizes,
      ),
    ),
    homeWidgetFilters: _stringMap(
      json['homeWidgetFilters'],
      fallback: _stringMap(
        homeWidgets['filters'],
        fallback: fallback.homeWidgetFilters,
      ),
    ),
    futureGenerationRules: json['futureGenerationRules'] != null
        ? (json['futureGenerationRules'] as List)
            .whereType<Map<String, dynamic>>()
            .map(_ruleFromJson)
            .toList()
        : null,
  );
}

Map<String, Object?> _ruleToJson(FutureGenerationRule rule) {
  return {
    'id': rule.id,
    'name': rule.name,
    'enabled': rule.enabled,
    if (rule.kind != null) 'kind': rule.kind,
    if (rule.postMode != null) 'postMode': rule.postMode,
    'type': rule.type,
    'accountId': rule.accountId,
    if (rule.counterAccountId != null) 'counterAccountId': rule.counterAccountId,
    if (rule.categoryId != null) 'categoryId': rule.categoryId,
    'amountMinor': rule.amountMinor,
    'currency': rule.currency,
    'frequency': rule.frequency,
    'interval': rule.interval,
    if (rule.dayOfMonth != null) 'dayOfMonth': rule.dayOfMonth,
    if (rule.daysOfWeek != null) 'daysOfWeek': rule.daysOfWeek,
    'startsOn': rule.startsOn.toIso8601String(),
    if (rule.endsOn != null) 'endsOn': rule.endsOn!.toIso8601String(),
    if (rule.occurrences != null) 'occurrences': rule.occurrences,
    if (rule.skippedOccurrences != null) 'skippedOccurrences': rule.skippedOccurrences,
    if (rule.paymentMethod != null) 'paymentMethod': rule.paymentMethod,
    if (rule.notes != null) 'notes': rule.notes,
    if (rule.tags != null) 'tags': rule.tags,
    'createdAt': rule.createdAt.toIso8601String(),
    'updatedAt': rule.updatedAt.toIso8601String(),
  };
}

FutureGenerationRule _ruleFromJson(Map<String, dynamic> json) {
  return FutureGenerationRule(
    id: _string(json['id']),
    name: _string(json['name']),
    enabled: _bool(json['enabled'], fallback: true),
    kind: _nullableString(json['kind']),
    postMode: _nullableString(json['postMode']),
    type: _string(json['type']),
    accountId: _string(json['accountId']),
    counterAccountId: _nullableString(json['counterAccountId']),
    categoryId: _nullableString(json['categoryId']),
    amountMinor: _int(json['amountMinor']),
    currency: _string(json['currency']),
    frequency: _string(json['frequency']),
    interval: _int(json['interval'], fallback: 1),
    dayOfMonth: _nullableInt(json['dayOfMonth']),
    daysOfWeek: _nullableIntList(json['daysOfWeek']),
    startsOn: _date(json['startsOn']),
    endsOn: json['endsOn'] != null ? _date(json['endsOn']) : null,
    occurrences: _nullableInt(json['occurrences']),
    skippedOccurrences: _nullableStringList(json['skippedOccurrences']),
    paymentMethod: _nullableString(json['paymentMethod']),
    notes: _nullableString(json['notes']),
    tags: _nullableStringList(json['tags']),
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
  );
}

Map<String, Object?> _accountToJson(Account account) {
  return {
    'id': account.id,
    'name': account.name,
    'type': account.type,
    'currency': account.currency,
    'openingBalance': _moneyToJson(account.openingBalance),
    'color': account.color?.toARGB32(),
    'institution': account.institution,
    'groupName': account.groupName,
    'loanDetails': account.loanDetails == null
        ? null
        : _loanDetailsToJson(account.loanDetails!),
    'cardLast4': account.cardLast4,
    'accountLast4': account.accountLast4,
    'includeInTotals': account.includeInTotals,
    'includeInReports': account.includeInReports,
    'includeInNetWorth': account.includeInNetWorth,
    'showOnHome': account.showOnHome,
    'isArchived': account.isArchived,
    'sortOrder': account.sortOrder,
  };
}

Map<String, Object?> _loanDetailsToJson(AccountLoanDetails details) {
  return {
    'loanKind': details.loanKind,
    'principal': details.principal == null
        ? null
        : _moneyToJson(details.principal!),
    'repaymentAmount': details.repaymentAmount == null
        ? null
        : _moneyToJson(details.repaymentAmount!),
    'interestRatePercent': details.interestRatePercent,
    'repaymentCount': details.repaymentCount,
    'repaymentStartsOn': details.repaymentStartsOn?.toIso8601String(),
    'repaymentSourceAccountId': details.repaymentSourceAccountId,
    'hideInterestInLedger': details.hideInterestInLedger,
  };
}

Account _accountFromJson(Map<String, dynamic> json) {
  final currency = _string(json['currency'], fallback: 'INR');
  return Account(
    id: _string(json['id'], fallback: _generatedId('acc')),
    name: _string(json['name'], fallback: 'Account'),
    type: _string(json['type'], fallback: 'bank'),
    currency: currency,
    openingBalance: _moneyFromJson(
      json['openingBalance'],
      fallback: Money(amountMinor: 0, currency: currency),
    ),
    color: _color(json['color']),
    institution: _nullableString(json['institution']),
    groupName: _nullableString(json['groupName']),
    cardLast4: _nullableString(json['cardLast4']),
    accountLast4: _nullableString(json['accountLast4']),
    loanDetails: _loanDetailsFromJson(json['loanDetails'], currency),
    includeInTotals: _bool(json['includeInTotals'], fallback: true),
    includeInReports: _bool(json['includeInReports'], fallback: true),
    includeInNetWorth: _bool(json['includeInNetWorth'], fallback: true),
    showOnHome: _bool(json['showOnHome'], fallback: true),
    isArchived: _bool(json['isArchived']),
    sortOrder: _int(json['sortOrder']),
  );
}

AccountLoanDetails? _loanDetailsFromJson(Object? value, String currency) {
  if (value == null) return null;
  final json = _map(value);
  if (json.isEmpty) return null;
  return AccountLoanDetails(
    loanKind: _nullableString(json['loanKind']),
    principal: json['principal'] == null
        ? null
        : _moneyFromJson(
            json['principal'],
            fallback: Money(amountMinor: 0, currency: currency),
          ),
    repaymentAmount: json['repaymentAmount'] == null
        ? null
        : _moneyFromJson(
            json['repaymentAmount'],
            fallback: Money(amountMinor: 0, currency: currency),
          ),
    interestRatePercent: _nullableDouble(json['interestRatePercent']),
    repaymentCount: _nullableInt(json['repaymentCount']),
    repaymentStartsOn: json['repaymentStartsOn'] == null
        ? null
        : _date(json['repaymentStartsOn']),
    repaymentSourceAccountId: _nullableString(json['repaymentSourceAccountId']),
    hideInterestInLedger: _bool(json['hideInterestInLedger'], fallback: true),
  );
}

Map<String, Object?> _categoryToJson(Category category) {
  return {
    'id': category.id,
    'name': category.name,
    'kind': category.kind,
    'color': category.color?.toARGB32(),
    'parentId': category.parentId,
    'isArchived': category.isArchived,
    'sortOrder': category.sortOrder,
  };
}

Category _categoryFromJson(Map<String, dynamic> json) {
  return Category(
    id: _string(json['id'], fallback: _generatedId('cat')),
    name: _string(json['name'], fallback: 'Category'),
    kind: _string(json['kind'], fallback: 'expense'),
    color: _color(json['color']),
    parentId: _nullableString(json['parentId']),
    isArchived: _bool(json['isArchived']),
    sortOrder: _int(json['sortOrder']),
  );
}

Map<String, Object?> _transactionToJson(TransactionRecord transaction) {
  return {
    'id': transaction.id,
    'type': transaction.type,
    'status': transaction.status,
    'source': transaction.source,
    'accountId': transaction.accountId,
    'counterAccountId': transaction.counterAccountId,
    'amount': _moneyToJson(transaction.amount),
    'baseAmount': _moneyToJson(transaction.baseAmount),
    'counterAmount': transaction.counterAmount == null
        ? null
        : _moneyToJson(transaction.counterAmount!),
    'originalAmount': transaction.originalAmount == null
        ? null
        : _moneyToJson(transaction.originalAmount!),
    'fxRate': transaction.fxRate,
    'originalFxRate': transaction.originalFxRate,
    'categoryId': transaction.categoryId,
    'occurredAt': transaction.occurredAt.toIso8601String(),
    'locationLabel': transaction.locationLabel,
    'paymentMethod': transaction.paymentMethod,
    'notes': transaction.notes,
    'importBatchId': transaction.importBatchId,
    'recurrenceFrequency': transaction.recurrenceFrequency,
    'attachments': transaction.attachments
        .map(_transactionAttachmentToJson)
        .toList(),
    'isReimbursable': transaction.isReimbursable,
    'isTaxDeductible': transaction.isTaxDeductible,
    'isExcludedFromReports': transaction.isExcludedFromReports,
    'sourceConfidence': transaction.sourceConfidence,
    'externalRef': transaction.externalRef,
    'originalTransactionId': transaction.originalTransactionId,
  };
}

TransactionRecord _transactionFromJson(Map<String, dynamic> json) {
  final amount = _moneyFromJson(json['amount']);
  return TransactionRecord(
    id: _string(json['id'], fallback: _generatedId('tx')),
    type: _string(json['type'], fallback: 'expense'),
    status: _string(json['status'], fallback: 'cleared'),
    source: _string(json['source'], fallback: 'manual'),
    accountId: _string(json['accountId'], fallback: ''),
    counterAccountId: _nullableString(json['counterAccountId']),
    amount: amount,
    baseAmount: _moneyFromJson(json['baseAmount'], fallback: amount),
    counterAmount: json['counterAmount'] == null
        ? null
        : _moneyFromJson(json['counterAmount'], fallback: amount),
    originalAmount: json['originalAmount'] == null
        ? null
        : _moneyFromJson(json['originalAmount'], fallback: amount),
    fxRate: _nullableDouble(json['fxRate']),
    originalFxRate: _nullableDouble(json['originalFxRate']),
    categoryId: _nullableString(json['categoryId']),
    occurredAt: _date(json['occurredAt']),
    locationLabel: _nullableString(json['locationLabel']),
    paymentMethod: _nullableString(json['paymentMethod']),
    notes: _nullableString(json['notes']),
    importBatchId: _nullableString(json['importBatchId']),
    recurrenceFrequency: _nullableString(json['recurrenceFrequency']) ?? _extractFrequencyFromTags(json['tags']),
    attachments: _list(
      json['attachments'],
    ).map(_transactionAttachmentFromJson).toList(),
    isReimbursable: _bool(json['isReimbursable']),
    isTaxDeductible: _bool(json['isTaxDeductible']),
    isExcludedFromReports: _bool(json['isExcludedFromReports']),
    sourceConfidence: _nullableDouble(json['sourceConfidence']),
    externalRef: _nullableString(json['externalRef']),
    originalTransactionId: _nullableString(json['originalTransactionId']),
  );
}

Map<String, Object?> _transactionAttachmentToJson(
  TransactionAttachment attachment,
) {
  return {
    'id': attachment.id,
    'source': attachment.source,
    'name': attachment.name,
    'uri': attachment.uri,
    'mimeType': attachment.mimeType,
  };
}

TransactionAttachment _transactionAttachmentFromJson(
  Map<String, dynamic> json,
) {
  return TransactionAttachment(
    id: _string(json['id'], fallback: _generatedId('att')),
    source: _string(json['source'], fallback: 'file'),
    name: _string(json['name'], fallback: 'Attachment'),
    uri: _string(json['uri']),
    mimeType: _nullableString(json['mimeType']),
  );
}

Map<String, Object?> _budgetToJson(Budget budget) {
  return {
    'id': budget.id,
    'name': budget.name,
    'amount': _moneyToJson(budget.amount),
    'spent': _moneyToJson(budget.spent),
  };
}

Budget _budgetFromJson(Map<String, dynamic> json) {
  final amount = _moneyFromJson(json['amount']);
  return Budget(
    id: _string(json['id'], fallback: _generatedId('budget')),
    name: _string(json['name'], fallback: 'Budget'),
    amount: amount,
    spent: _moneyFromJson(
      json['spent'],
      fallback: amount.copyWith(amountMinor: 0),
    ),
  );
}

Map<String, Object?> _goalToJson(Goal goal) {
  return {
    'id': goal.id,
    'name': goal.name,
    'target': _moneyToJson(goal.target),
    'saved': _moneyToJson(goal.saved),
  };
}

Goal _goalFromJson(Map<String, dynamic> json) {
  final target = _moneyFromJson(json['target']);
  return Goal(
    id: _string(json['id'], fallback: _generatedId('goal')),
    name: _string(json['name'], fallback: 'Goal'),
    target: target,
    saved: _moneyFromJson(
      json['saved'],
      fallback: target.copyWith(amountMinor: 0),
    ),
  );
}

Map<String, Object?> _exchangeRateToJson(ExchangeRateRecord rate) {
  return {
    'base': rate.base,
    'quote': rate.quote,
    'rate': rate.rate,
    'asOfDate': rate.asOfDate.toIso8601String(),
    'updatedAt': rate.updatedAt?.toIso8601String(),
    'provider': rate.provider,
    'source': rate.source,
  };
}

ExchangeRateRecord _exchangeRateFromJson(Map<String, dynamic> json) {
  return ExchangeRateRecord(
    base: _string(json['base'], fallback: 'INR').toUpperCase(),
    quote: _string(json['quote'], fallback: 'INR').toUpperCase(),
    rate: _double(json['rate'], fallback: 1),
    asOfDate: _date(json['asOfDate']),
    updatedAt: json['updatedAt'] == null ? null : _date(json['updatedAt']),
    provider: _nullableString(json['provider']),
    source: _nullableString(json['source']),
  );
}

Map<String, Object?> _captureCandidateToJson(CaptureCandidate candidate) {
  return {
    'id': candidate.id,
    'source': candidate.source,
    'status': candidate.status,
    'createdAt': candidate.createdAt.toIso8601String(),
    'rawText': candidate.rawText,
    'parsedAmount': candidate.parsedAmount == null
        ? null
        : _moneyToJson(candidate.parsedAmount!),
    'merchant': candidate.merchant,
    'transactionType': candidate.transactionType,
    'suggestedAccountId': candidate.suggestedAccountId,
    'suggestedCategoryId': candidate.suggestedCategoryId,
    'warnings': candidate.warnings,
  };
}

CaptureCandidate _captureCandidateFromJson(Map<String, dynamic> json) {
  return CaptureCandidate(
    id: _string(json['id'], fallback: _generatedId('cap')),
    source: _string(json['source'], fallback: 'manual'),
    status: _string(json['status'], fallback: 'pending'),
    createdAt: _date(json['createdAt']),
    rawText: _nullableString(json['rawText']),
    parsedAmount: json['parsedAmount'] == null
        ? null
        : _moneyFromJson(json['parsedAmount']),
    merchant: _nullableString(json['merchant']),
    transactionType: _nullableString(json['transactionType']),
    suggestedAccountId: _nullableString(json['suggestedAccountId']),
    suggestedCategoryId: _nullableString(json['suggestedCategoryId']),
    warnings: _stringList(json['warnings']),
  );
}

Map<String, Object?> _importBatchToJson(ImportBatch batch) {
  return {
    'id': batch.id,
    'source': batch.source,
    'status': batch.status,
    'createdAt': batch.createdAt.toIso8601String(),
    'rowCount': batch.rowCount,
    'importedCount': batch.importedCount,
    'duplicateCount': batch.duplicateCount,
    'warningCount': batch.warningCount,
  };
}

ImportBatch _importBatchFromJson(Map<String, dynamic> json) {
  return ImportBatch(
    id: _string(json['id'], fallback: _generatedId('import')),
    source: _string(json['source'], fallback: 'manual'),
    status: _string(json['status'], fallback: 'posted'),
    createdAt: _date(json['createdAt']),
    rowCount: _int(json['rowCount']),
    importedCount: _int(json['importedCount']),
    duplicateCount: _int(json['duplicateCount']),
    warningCount: _int(json['warningCount']),
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value.map(_map).toList();
}

String _string(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) return value;
  return fallback;
}

String? _nullableString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

double _double(Object? value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

List<String> _stringList(Object? value, {List<String> fallback = const []}) {
  if (value is! List) return fallback;
  return value.whereType<String>().toList();
}

List<String>? _nullableStringList(Object? value) {
  if (value == null) return null;
  if (value is! List) return null;
  return value.whereType<String>().toList();
}

List<int>? _nullableIntList(Object? value) {
  if (value == null) return null;
  if (value is! List) return null;
  return value.whereType<num>().map((e) => e.round()).toList();
}

Map<String, String> _stringMap(
  Object? value, {
  Map<String, String> fallback = const {},
}) {
  if (value is! Map) return Map<String, String>.from(fallback);
  final result = <String, String>{};
  value.forEach((key, rawValue) {
    final mapKey = key is String ? key.trim() : '';
    final mapValue = rawValue is String ? rawValue.trim() : '';
    if (mapKey.isNotEmpty && mapValue.isNotEmpty) {
      result[mapKey] = mapValue;
    }
  });
  return result;
}

Color? _color(Object? value) {
  if (value is String) {
    final normalized = value.trim().replaceFirst('#', '');
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) {
      return Color(int.parse('FF$normalized', radix: 16));
    }
    if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(normalized)) {
      return Color(int.parse(normalized, radix: 16));
    }
  }
  final intValue = _int(value, fallback: -1);
  return intValue < 0 ? null : Color(intValue);
}

DateTime _date(Object? value) {
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

String _generatedId(String prefix) {
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

String? _extractFrequencyFromTags(Object? tagsObj) {
  final tags = _stringList(tagsObj);
  for (final tag in tags) {
    if (tag.startsWith('frequency:')) {
      return tag.substring('frequency:'.length);
    }
  }
  return null;
}


// Public wrappers for Firestore serialization
Map<String, Object?> accountToJson(Account account) => _accountToJson(account);
Account accountFromJson(Map<String, dynamic> json) => _accountFromJson(json);

Map<String, Object?> categoryToJson(Category category) => _categoryToJson(category);
Category categoryFromJson(Map<String, dynamic> json) => _categoryFromJson(json);

Map<String, Object?> transactionToJson(TransactionRecord transaction) => _transactionToJson(transaction);
TransactionRecord transactionFromJson(Map<String, dynamic> json) => _transactionFromJson(json);

Map<String, Object?> budgetToJson(Budget budget) => _budgetToJson(budget);
Budget budgetFromJson(Map<String, dynamic> json) => _budgetFromJson(json);

Map<String, Object?> goalToJson(Goal goal) => _goalToJson(goal);
Goal goalFromJson(Map<String, dynamic> json) => _goalFromJson(json);

Map<String, Object?> captureCandidateToJson(CaptureCandidate candidate) => _captureCandidateToJson(candidate);
CaptureCandidate captureCandidateFromJson(Map<String, dynamic> json) => _captureCandidateFromJson(json);

Map<String, Object?> importBatchToJson(ImportBatch batch) => _importBatchToJson(batch);
ImportBatch importBatchFromJson(Map<String, dynamic> json) => _importBatchFromJson(json);

Map<String, Object?> preferencesToJson(LedgerPreferences preferences) => _preferencesToJson(preferences);
LedgerPreferences preferencesFromJson(Map<String, dynamic> json) => _preferencesFromJson(json);
