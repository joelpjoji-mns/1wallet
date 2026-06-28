import 'package:flutter/material.dart';

@immutable
class Money {
  const Money({required this.amountMinor, required this.currency});

  final int amountMinor;
  final String currency;

  Money copyWith({int? amountMinor, String? currency}) {
    return Money(
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
    );
  }
}

const kRnDefaultHomeWidgetOrder = <String>[
  'balanceHero',
  'accountGrid',
  'recentRecords',
  'balanceTrend',
  'currencyValues',
  'upcomingScheduled',
  'reviewQueue',
  'topCategories',
  'budgetPressure',
  'goalProgress',
];

@immutable
class FutureGenerationRule {
  const FutureGenerationRule({
    required this.id,
    required this.name,
    required this.enabled,
    this.kind,
    this.postMode,
    required this.type,
    required this.accountId,
    this.counterAccountId,
    this.categoryId,
    required this.amountMinor,
    required this.currency,
    required this.frequency,
    required this.interval,
    this.dayOfMonth,
    this.daysOfWeek,
    required this.startsOn,
    this.endsOn,
    this.occurrences,
    this.skippedOccurrences,
    this.paymentMethod,
    this.notes,
    this.tags,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final bool enabled;
  final String? kind;
  final String? postMode;
  final String type;
  final String accountId;
  final String? counterAccountId;
  final String? categoryId;
  final int amountMinor;
  final String currency;
  final String frequency;
  final int interval;
  final int? dayOfMonth;
  final List<int>? daysOfWeek;
  final DateTime startsOn;
  final DateTime? endsOn;
  final int? occurrences;
  final List<String>? skippedOccurrences;
  final String? paymentMethod;
  final String? notes;
  final List<String>? tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  FutureGenerationRule copyWith({
    String? id,
    String? name,
    bool? enabled,
    String? kind,
    String? postMode,
    String? type,
    String? accountId,
    String? counterAccountId,
    String? categoryId,
    int? amountMinor,
    String? currency,
    String? frequency,
    int? interval,
    int? dayOfMonth,
    List<int>? daysOfWeek,
    DateTime? startsOn,
    DateTime? endsOn,
    int? occurrences,
    List<String>? skippedOccurrences,
    String? paymentMethod,
    String? notes,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FutureGenerationRule(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      kind: kind ?? this.kind,
      postMode: postMode ?? this.postMode,
      type: type ?? this.type,
      accountId: accountId ?? this.accountId,
      counterAccountId: counterAccountId ?? this.counterAccountId,
      categoryId: categoryId ?? this.categoryId,
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      startsOn: startsOn ?? this.startsOn,
      endsOn: endsOn ?? this.endsOn,
      occurrences: occurrences ?? this.occurrences,
      skippedOccurrences: skippedOccurrences ?? this.skippedOccurrences,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const kDefaultCurrency = 'USD';
const kDefaultLocale = 'en_US';

@immutable
class LedgerPreferences {
  const LedgerPreferences({
    this.baseCurrency = kDefaultCurrency,
    this.displayCurrency = kDefaultCurrency,
    this.enabledCurrencies = const [kDefaultCurrency],
    this.locale = kDefaultLocale,
    this.startDayOfMonth = 1,
    this.homeWidgetOrder = kRnDefaultHomeWidgetOrder,
    this.homeWidgetHidden = const [],
    this.homeWidgetSizes = const {},
    this.homeWidgetFilters = const {},
    this.futureGenerationRules,
    this.glassSpecularOpacity = 1.0,
    this.glassSpecularSaturation = 2.0,
    this.glassRefractionLevel = 1.0,
    this.glassBlurLevel = 9.0,
    this.glassProgressiveBlurStrength = 0.0,
    this.glassBackgroundOpacity = 0.15,
    this.notificationInboxEnabled = true,
    this.deviceNotificationsEnabled = false,
    this.quietHoursEnabled = false,
    this.channelScheduledEnabled = true,
    this.channelBudgetsEnabled = true,
    this.channelGoalsEnabled = true,
    this.readNotificationIds = const [],
    this.dismissedNotificationIds = const [],
    this.privacyModeEnabled = false,
    this.biometricLockEnabled = false,
    this.forecastEmergencyCashMinor = 100000,
    this.forecastExtraAllocationPercent = 0.5,
    this.loanPriorityIds = const [],
  });

  final String baseCurrency;
  final String displayCurrency;
  final List<String> enabledCurrencies;
  final String locale;
  final int startDayOfMonth;
  final List<String> homeWidgetOrder;
  final List<String> homeWidgetHidden;
  final Map<String, String> homeWidgetSizes;
  final Map<String, String> homeWidgetFilters;
  final List<FutureGenerationRule>? futureGenerationRules;
  final double glassSpecularOpacity;
  final double glassSpecularSaturation;
  final double glassRefractionLevel;
  final double glassBlurLevel;
  final double glassProgressiveBlurStrength;
  final double glassBackgroundOpacity;
  final bool notificationInboxEnabled;
  final bool deviceNotificationsEnabled;
  final bool quietHoursEnabled;
  final bool channelScheduledEnabled;
  final bool channelBudgetsEnabled;
  final bool channelGoalsEnabled;
  final List<String> readNotificationIds;
  final List<String> dismissedNotificationIds;
  final bool privacyModeEnabled;
  final bool biometricLockEnabled;
  final int forecastEmergencyCashMinor;
  final double forecastExtraAllocationPercent;
  final List<String> loanPriorityIds;

  LedgerPreferences copyWith({
    String? baseCurrency,
    String? displayCurrency,
    List<String>? enabledCurrencies,
    String? locale,
    int? startDayOfMonth,
    List<String>? homeWidgetOrder,
    List<String>? homeWidgetHidden,
    Map<String, String>? homeWidgetSizes,
    Map<String, String>? homeWidgetFilters,
    List<FutureGenerationRule>? futureGenerationRules,
    double? glassSpecularOpacity,
    double? glassSpecularSaturation,
    double? glassRefractionLevel,
    double? glassBlurLevel,
    double? glassProgressiveBlurStrength,
    double? glassBackgroundOpacity,
    bool? notificationInboxEnabled,
    bool? deviceNotificationsEnabled,
    bool? quietHoursEnabled,
    bool? channelScheduledEnabled,
    bool? channelBudgetsEnabled,
    bool? channelGoalsEnabled,
    List<String>? readNotificationIds,
    List<String>? dismissedNotificationIds,
    bool? privacyModeEnabled,
    bool? biometricLockEnabled,
    int? forecastEmergencyCashMinor,
    double? forecastExtraAllocationPercent,
    List<String>? loanPriorityIds,
  }) {
    return LedgerPreferences(
      baseCurrency: baseCurrency ?? this.baseCurrency,
      displayCurrency: displayCurrency ?? this.displayCurrency,
      enabledCurrencies: enabledCurrencies ?? this.enabledCurrencies,
      locale: locale ?? this.locale,
      startDayOfMonth: startDayOfMonth ?? this.startDayOfMonth,
      homeWidgetOrder: homeWidgetOrder ?? this.homeWidgetOrder,
      homeWidgetHidden: homeWidgetHidden ?? this.homeWidgetHidden,
      homeWidgetSizes: homeWidgetSizes ?? this.homeWidgetSizes,
      homeWidgetFilters: homeWidgetFilters ?? this.homeWidgetFilters,
      futureGenerationRules:
          futureGenerationRules ?? this.futureGenerationRules,
      glassSpecularOpacity: glassSpecularOpacity ?? this.glassSpecularOpacity,
      glassSpecularSaturation:
          glassSpecularSaturation ?? this.glassSpecularSaturation,
      glassRefractionLevel: glassRefractionLevel ?? this.glassRefractionLevel,
      glassBlurLevel: glassBlurLevel ?? this.glassBlurLevel,
      glassProgressiveBlurStrength:
          glassProgressiveBlurStrength ?? this.glassProgressiveBlurStrength,
      glassBackgroundOpacity:
          glassBackgroundOpacity ?? this.glassBackgroundOpacity,
      notificationInboxEnabled:
          notificationInboxEnabled ?? this.notificationInboxEnabled,
      deviceNotificationsEnabled:
          deviceNotificationsEnabled ?? this.deviceNotificationsEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      channelScheduledEnabled:
          channelScheduledEnabled ?? this.channelScheduledEnabled,
      channelBudgetsEnabled:
          channelBudgetsEnabled ?? this.channelBudgetsEnabled,
      channelGoalsEnabled: channelGoalsEnabled ?? this.channelGoalsEnabled,
      readNotificationIds: readNotificationIds ?? this.readNotificationIds,
      dismissedNotificationIds:
          dismissedNotificationIds ?? this.dismissedNotificationIds,
      privacyModeEnabled: privacyModeEnabled ?? this.privacyModeEnabled,
      biometricLockEnabled: biometricLockEnabled ?? this.biometricLockEnabled,
      forecastEmergencyCashMinor:
          forecastEmergencyCashMinor ?? this.forecastEmergencyCashMinor,
      forecastExtraAllocationPercent:
          forecastExtraAllocationPercent ?? this.forecastExtraAllocationPercent,
      loanPriorityIds: loanPriorityIds ?? this.loanPriorityIds,
    );
  }
}

@immutable
class AccountLoanDetails {
  const AccountLoanDetails({
    this.loanKind,
    this.principal,
    this.repaymentAmount,
    this.interestRatePercent,
    this.repaymentCount,
    this.repaymentStartsOn,
    this.repaymentSourceAccountId,
    this.recurrenceFrequency = 'monthly',
    this.recurrenceInterval = 1,
    this.recurrenceDaysOfWeek,
    this.recurrenceDaysOfMonth,
    this.hideInterestInLedger = true,
  });

  final String? loanKind;
  final Money? principal;
  final Money? repaymentAmount;
  final double? interestRatePercent;
  final int? repaymentCount;
  final DateTime? repaymentStartsOn;
  final String? repaymentSourceAccountId;
  final String recurrenceFrequency;
  final int recurrenceInterval;
  final List<int>? recurrenceDaysOfWeek;
  final List<int>? recurrenceDaysOfMonth;
  final bool hideInterestInLedger;

  AccountLoanDetails copyWith({
    String? loanKind,
    Money? principal,
    Money? repaymentAmount,
    double? interestRatePercent,
    int? repaymentCount,
    DateTime? repaymentStartsOn,
    String? repaymentSourceAccountId,
    String? recurrenceFrequency,
    int? recurrenceInterval,
    List<int>? recurrenceDaysOfWeek,
    List<int>? recurrenceDaysOfMonth,
    bool? hideInterestInLedger,
  }) {
    return AccountLoanDetails(
      loanKind: loanKind ?? this.loanKind,
      principal: principal ?? this.principal,
      repaymentAmount: repaymentAmount ?? this.repaymentAmount,
      interestRatePercent: interestRatePercent ?? this.interestRatePercent,
      repaymentCount: repaymentCount ?? this.repaymentCount,
      repaymentStartsOn: repaymentStartsOn ?? this.repaymentStartsOn,
      repaymentSourceAccountId:
          repaymentSourceAccountId ?? this.repaymentSourceAccountId,
      recurrenceFrequency: recurrenceFrequency ?? this.recurrenceFrequency,
      recurrenceInterval: recurrenceInterval ?? this.recurrenceInterval,
      recurrenceDaysOfWeek: recurrenceDaysOfWeek ?? this.recurrenceDaysOfWeek,
      recurrenceDaysOfMonth:
          recurrenceDaysOfMonth ?? this.recurrenceDaysOfMonth,
      hideInterestInLedger: hideInterestInLedger ?? this.hideInterestInLedger,
    );
  }
}

@immutable
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.openingBalance,
    this.color,
    this.institution,
    this.groupName,
    this.cardLast4,
    this.accountLast4,
    this.loanDetails,
    this.encryptedDetails,
    this.includeInTotals = true,
    this.includeInReports = true,
    this.includeInNetWorth = true,
    this.showOnHome = true,
    this.isArchived = false,
    this.sortOrder = 0,
    this.creditLimit,
  });

  final String id;
  final String name;
  final String type;
  final String currency;
  final Money openingBalance;
  final Color? color;
  final String? institution;
  final String? groupName;
  final String? cardLast4;
  final String? accountLast4;
  final AccountLoanDetails? loanDetails;
  final Map<String, String>? encryptedDetails;
  final bool includeInTotals;
  final bool includeInReports;
  final bool includeInNetWorth;
  final bool showOnHome;
  final bool isArchived;
  final int sortOrder;
  final Money? creditLimit;

  String? get displayLast4 => cardLast4 ?? accountLast4;

  String? get displayLast4Label {
    if (displayLast4 == null) return null;
    if (type == 'card') return 'Card ending in';
    return 'Account ending in';
  }

  Account copyWith({
    String? id,
    String? name,
    String? type,
    String? currency,
    Money? openingBalance,
    Color? color,
    String? institution,
    String? groupName,
    String? cardLast4,
    String? accountLast4,
    AccountLoanDetails? loanDetails,
    Map<String, String>? encryptedDetails,
    bool? includeInTotals,
    bool? includeInReports,
    bool? includeInNetWorth,
    bool? showOnHome,
    bool? isArchived,
    int? sortOrder,
    Money? creditLimit,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      openingBalance: openingBalance ?? this.openingBalance,
      color: color ?? this.color,
      institution: institution ?? this.institution,
      groupName: groupName ?? this.groupName,
      cardLast4: cardLast4 ?? this.cardLast4,
      accountLast4: accountLast4 ?? this.accountLast4,
      loanDetails: loanDetails ?? this.loanDetails,
      encryptedDetails: encryptedDetails ?? this.encryptedDetails,
      includeInTotals: includeInTotals ?? this.includeInTotals,
      includeInReports: includeInReports ?? this.includeInReports,
      includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
      showOnHome: showOnHome ?? this.showOnHome,
      isArchived: isArchived ?? this.isArchived,
      sortOrder: sortOrder ?? this.sortOrder,
      creditLimit: creditLimit ?? this.creditLimit,
    );
  }
}

@immutable
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.color,
    this.parentId,
    this.isArchived = false,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String kind;
  final Color? color;
  final String? parentId;
  final bool isArchived;
  final int sortOrder;

  Category copyWith({
    String? id,
    String? name,
    String? kind,
    Color? color,
    String? parentId,
    bool? isArchived,
    int? sortOrder,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      color: color ?? this.color,
      parentId: parentId ?? this.parentId,
      isArchived: isArchived ?? this.isArchived,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

@immutable
class TransactionAttachment {
  const TransactionAttachment({
    required this.id,
    required this.source,
    required this.name,
    required this.uri,
    this.mimeType,
  });

  final String id;
  final String source;
  final String name;
  final String uri;
  final String? mimeType;

  TransactionAttachment copyWith({
    String? id,
    String? source,
    String? name,
    String? uri,
    String? mimeType,
  }) {
    return TransactionAttachment(
      id: id ?? this.id,
      source: source ?? this.source,
      name: name ?? this.name,
      uri: uri ?? this.uri,
      mimeType: mimeType ?? this.mimeType,
    );
  }
}

@immutable
class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.type,
    required this.status,
    required this.source,
    required this.accountId,
    required this.amount,
    required this.baseAmount,
    required this.occurredAt,
    this.counterAccountId,
    this.counterAmount,
    this.originalAmount,
    this.fxRate,
    this.originalFxRate,
    this.categoryId,
    this.locationLabel,
    this.paymentMethod,
    this.name,
    this.notes,
    this.importBatchId,
    this.recurrenceFrequency,
    this.recurrenceInterval = 1,
    this.recurrenceDaysOfWeek,
    this.recurrenceDaysOfMonth,
    this.attachments = const [],
    this.isReimbursable = false,
    this.isTaxDeductible = false,
    this.isExcludedFromReports = false,
    this.sourceConfidence,
    this.externalRef,
    this.originalTransactionId,
    this.postMode,
  });

  final String id;
  final String type;
  final String status;
  final String source;
  final String accountId;
  final String? counterAccountId;
  final Money amount;
  final Money baseAmount;
  final Money? counterAmount;
  final Money? originalAmount;
  final double? fxRate;
  final double? originalFxRate;
  final String? categoryId;
  final DateTime occurredAt;
  final String? locationLabel;
  final String? paymentMethod;
  final String? name;
  final String? notes;
  final String? importBatchId;
  final String? recurrenceFrequency;
  final int recurrenceInterval;
  final List<int>? recurrenceDaysOfWeek;
  final List<int>? recurrenceDaysOfMonth;
  final List<TransactionAttachment> attachments;
  final bool isReimbursable;
  final bool isTaxDeductible;
  final bool isExcludedFromReports;
  final double? sourceConfidence;
  final String? externalRef;
  final String? originalTransactionId;
  final String? postMode;

  TransactionRecord copyWith({
    String? id,
    String? type,
    String? status,
    String? source,
    String? accountId,
    String? counterAccountId,
    Money? amount,
    Money? baseAmount,
    Money? counterAmount,
    Money? originalAmount,
    double? fxRate,
    double? originalFxRate,
    String? categoryId,
    DateTime? occurredAt,
    String? locationLabel,
    String? paymentMethod,
    String? name,
    String? notes,
    String? importBatchId,
    String? recurrenceFrequency,
    int? recurrenceInterval,
    List<int>? recurrenceDaysOfWeek,
    List<int>? recurrenceDaysOfMonth,
    List<TransactionAttachment>? attachments,
    bool? isReimbursable,
    bool? isTaxDeductible,
    bool? isExcludedFromReports,
    double? sourceConfidence,
    String? externalRef,
    String? originalTransactionId,
    String? postMode,
  }) {
    return TransactionRecord(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      source: source ?? this.source,
      accountId: accountId ?? this.accountId,
      counterAccountId: counterAccountId ?? this.counterAccountId,
      amount: amount ?? this.amount,
      baseAmount: baseAmount ?? this.baseAmount,
      counterAmount: counterAmount ?? this.counterAmount,
      originalAmount: originalAmount ?? this.originalAmount,
      fxRate: fxRate ?? this.fxRate,
      originalFxRate: originalFxRate ?? this.originalFxRate,
      categoryId: categoryId ?? this.categoryId,
      occurredAt: occurredAt ?? this.occurredAt,
      locationLabel: locationLabel ?? this.locationLabel,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      importBatchId: importBatchId ?? this.importBatchId,
      recurrenceFrequency: recurrenceFrequency ?? this.recurrenceFrequency,
      recurrenceInterval: recurrenceInterval ?? this.recurrenceInterval,
      recurrenceDaysOfWeek: recurrenceDaysOfWeek ?? this.recurrenceDaysOfWeek,
      recurrenceDaysOfMonth:
          recurrenceDaysOfMonth ?? this.recurrenceDaysOfMonth,
      attachments: attachments ?? this.attachments,
      isReimbursable: isReimbursable ?? this.isReimbursable,
      isTaxDeductible: isTaxDeductible ?? this.isTaxDeductible,
      isExcludedFromReports:
          isExcludedFromReports ?? this.isExcludedFromReports,
      sourceConfidence: sourceConfidence ?? this.sourceConfidence,
      externalRef: externalRef ?? this.externalRef,
      originalTransactionId:
          originalTransactionId ?? this.originalTransactionId,
      postMode: postMode ?? this.postMode,
    );
  }
}

@immutable
class Budget {
  const Budget({
    required this.id,
    required this.name,
    required this.amount,
    required this.spent,
    this.targetDate,
    this.frequency = 'monthly',
    this.interval = 1,
    this.daysOfWeek,
    this.daysOfMonth,
  });

  final String id;
  final String name;
  final Money amount;
  final Money spent;
  final DateTime? targetDate;
  final String frequency;
  final int interval;
  final List<int>? daysOfWeek;
  final List<int>? daysOfMonth;

  Budget copyWith({
    String? id,
    String? name,
    Money? amount,
    Money? spent,
    DateTime? targetDate,
    String? frequency,
    int? interval,
    List<int>? daysOfWeek,
    List<int>? daysOfMonth,
  }) {
    return Budget(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      spent: spent ?? this.spent,
      targetDate: targetDate ?? this.targetDate,
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      daysOfMonth: daysOfMonth ?? this.daysOfMonth,
    );
  }
}

@immutable
class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.target,
    required this.saved,
    this.targetDate,
    this.frequency = 'once',
    this.interval = 1,
    this.daysOfWeek,
    this.daysOfMonth,
  });

  final String id;
  final String name;
  final Money target;
  final Money saved;
  final DateTime? targetDate;
  final String frequency;
  final int interval;
  final List<int>? daysOfWeek;
  final List<int>? daysOfMonth;

  Goal copyWith({
    String? id,
    String? name,
    Money? target,
    Money? saved,
    DateTime? targetDate,
    String? frequency,
    int? interval,
    List<int>? daysOfWeek,
    List<int>? daysOfMonth,
  }) {
    return Goal(
      id: id ?? this.id,
      name: name ?? this.name,
      target: target ?? this.target,
      saved: saved ?? this.saved,
      targetDate: targetDate ?? this.targetDate,
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      daysOfMonth: daysOfMonth ?? this.daysOfMonth,
    );
  }
}

@immutable
class ExchangeRateRecord {
  const ExchangeRateRecord({
    required this.base,
    required this.quote,
    required this.rate,
    required this.asOfDate,
    this.updatedAt,
    this.provider,
    this.source,
  });

  final String base;
  final String quote;
  final double rate;
  final DateTime asOfDate;
  final DateTime? updatedAt;
  final String? provider;
  final String? source;

  ExchangeRateRecord copyWith({
    String? base,
    String? quote,
    double? rate,
    DateTime? asOfDate,
    DateTime? updatedAt,
    String? provider,
    String? source,
  }) {
    return ExchangeRateRecord(
      base: base ?? this.base,
      quote: quote ?? this.quote,
      rate: rate ?? this.rate,
      asOfDate: asOfDate ?? this.asOfDate,
      updatedAt: updatedAt ?? this.updatedAt,
      provider: provider ?? this.provider,
      source: source ?? this.source,
    );
  }
}

@immutable
class CaptureCandidate {
  const CaptureCandidate({
    required this.id,
    required this.source,
    required this.status,
    required this.createdAt,
    this.rawText,
    this.parsedAmount,
    this.merchant,
    this.transactionType,
    this.suggestedAccountId,
    this.suggestedCategoryId,
  });

  final String id;
  final String source;
  final String status;
  final DateTime createdAt;
  final String? rawText;
  final Money? parsedAmount;
  final String? merchant;
  final String? transactionType;
  final String? suggestedAccountId;
  final String? suggestedCategoryId;

  CaptureCandidate copyWith({
    String? id,
    String? source,
    String? status,
    DateTime? createdAt,
    String? rawText,
    Money? parsedAmount,
    String? merchant,
    String? transactionType,
    String? suggestedAccountId,
    String? suggestedCategoryId,
  }) {
    return CaptureCandidate(
      id: id ?? this.id,
      source: source ?? this.source,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      rawText: rawText ?? this.rawText,
      parsedAmount: parsedAmount ?? this.parsedAmount,
      merchant: merchant ?? this.merchant,
      transactionType: transactionType ?? this.transactionType,
      suggestedAccountId: suggestedAccountId ?? this.suggestedAccountId,
      suggestedCategoryId: suggestedCategoryId ?? this.suggestedCategoryId,
    );
  }
}

@immutable
class ImportBatch {
  const ImportBatch({
    required this.id,
    required this.source,
    required this.status,
    required this.createdAt,
    required this.rowCount,
    required this.importedCount,
    required this.duplicateCount,
  });

  final String id;
  final String source;
  final String status;
  final DateTime createdAt;
  final int rowCount;
  final int importedCount;
  final int duplicateCount;

  ImportBatch copyWith({
    String? id,
    String? source,
    String? status,
    DateTime? createdAt,
    int? rowCount,
    int? importedCount,
    int? duplicateCount,
  }) {
    return ImportBatch(
      id: id ?? this.id,
      source: source ?? this.source,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      rowCount: rowCount ?? this.rowCount,
      importedCount: importedCount ?? this.importedCount,
      duplicateCount: duplicateCount ?? this.duplicateCount,
    );
  }
}

@immutable
class LedgerState {
  const LedgerState({
    required this.version,
    required this.userId,
    required this.preferences,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.budgets,
    required this.goals,
    required this.captureCandidates,
    this.importBatches = const [],
    this.exchangeRates = const [],
  });

  final int version;
  final String userId;
  final LedgerPreferences preferences;
  final List<Account> accounts;
  final List<Category> categories;
  final List<TransactionRecord> transactions;
  final List<Budget> budgets;
  final List<Goal> goals;
  final List<CaptureCandidate> captureCandidates;
  final List<ImportBatch> importBatches;
  final List<ExchangeRateRecord> exchangeRates;

  LedgerState copyWith({
    int? version,
    String? userId,
    LedgerPreferences? preferences,
    List<Account>? accounts,
    List<Category>? categories,
    List<TransactionRecord>? transactions,
    List<Budget>? budgets,
    List<Goal>? goals,
    List<CaptureCandidate>? captureCandidates,
    List<ImportBatch>? importBatches,
    List<ExchangeRateRecord>? exchangeRates,
  }) {
    return LedgerState(
      version: version ?? this.version,
      userId: userId ?? this.userId,
      preferences: preferences ?? this.preferences,
      accounts: accounts ?? this.accounts,
      categories: categories ?? this.categories,
      transactions: transactions ?? this.transactions,
      budgets: budgets ?? this.budgets,
      goals: goals ?? this.goals,
      captureCandidates: captureCandidates ?? this.captureCandidates,
      importBatches: importBatches ?? this.importBatches,
      exchangeRates: exchangeRates ?? this.exchangeRates,
    );
  }
}
