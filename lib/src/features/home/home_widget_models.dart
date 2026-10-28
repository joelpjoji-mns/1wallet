import 'package:flutter/material.dart';

enum HomeDashboardWidgetId {
  balanceHero('balanceHero'),
  plannedPaymentsTile('plannedPaymentsTile'),
  loansTile('loansTile'),
  accountGrid('accountGrid'),
  recentRecords('recentRecords'),
  upcomingScheduled('upcomingScheduled'),
  emiTracker('emiTracker'),
  cardDebt('cardDebt'),
  accountGroups('accountGroups'),
  cardPaymentPlan('cardPaymentPlan'),
  loanPayoff('loanPayoff'),
  balanceTrend('balanceTrend'),
  topCategories('topCategories'),
  currencyValues('currencyValues'),
  creditUtilization('creditUtilization'),
  netWorth('netWorth');

  const HomeDashboardWidgetId(this.storageKey);

  final String storageKey;
}

const defaultHomeWidgetOrder = [
  HomeDashboardWidgetId.balanceHero,
  HomeDashboardWidgetId.accountGrid,
  HomeDashboardWidgetId.recentRecords,
  HomeDashboardWidgetId.balanceTrend,
  HomeDashboardWidgetId.currencyValues,
  HomeDashboardWidgetId.topCategories,
  HomeDashboardWidgetId.netWorth,
  HomeDashboardWidgetId.upcomingScheduled,
  HomeDashboardWidgetId.creditUtilization,
];

const standardHomeDateFilterOptions = [
  'This week',
  'This month',
  'Last month',
  '30 days',
  '6 months',
  'This year',
  'All time',
];

const recentRecordsDateFilterOptions = [
  'Today',
  'This week',
  '2 weeks',
  'This month',
];

const futureHomeDateFilterOptions = [
  'This week',
  'This month',
  '30 days',
  '6 months',
  'This year',
  'All time',
];

const homeWidgetDatePresets = [
  'thisWeek',
  'thisMonth',
  'lastMonth',
  '30Days',
  '6Months',
  'thisYear',
  'allTime',
];

const homeWidgetDateLabels = {
  'thisWeek': 'This week',
  'thisMonth': 'This month',
  'lastMonth': 'Last month',
  '30Days': '30 days',
  '6Months': '6 months',
  '1Year': '1 year',
  'thisYear': 'This year',
  'allTime': 'All time',
  'This week': 'This week',
  'This month': 'This month',
  'Last month': 'Last month',
  '30 days': '30 days',
  '6 months': '6 months',
  '1 year': '1 year',
  'This year': 'This year',
  'All time': 'All time',
  'today': 'Today',
  'Today': 'Today',
  '1_week': 'This week',
  '2_weeks': '2 weeks',
  '2 weeks': '2 weeks',
  '1_month': 'This month',
};

const balanceHeroDatePresets = standardHomeDateFilterOptions;
const currencyRateDatePresets = standardHomeDateFilterOptions;

DateTimeRange homeWidgetDateRange(String period) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (period) {
    case 'Today':
    case 'today':
      return DateTimeRange(
        start: today,
        end: today.add(const Duration(days: 1)),
      );
    case 'This week':
    case 'thisWeek':
      final diff = now.weekday - 1;
      final start = today.subtract(Duration(days: diff));
      return DateTimeRange(
        start: start,
        end: start.add(const Duration(days: 7)),
      );
    case '2 weeks':
    case '2_weeks':
      return DateTimeRange(
        start: today.subtract(const Duration(days: 14)),
        end: today.add(const Duration(days: 1)),
      );
    case 'This month':
    case 'thisMonth':
      return DateTimeRange(
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      );
    case 'Last month':
    case 'lastMonth':
    case 'last_month':
      return DateTimeRange(
        start: DateTime(now.year, now.month - 1),
        end: DateTime(now.year, now.month),
      );
    case '30 days':
    case '30_days':
    case '30Days':
      return DateTimeRange(
        start: today.subtract(const Duration(days: 30)),
        end: today.add(const Duration(days: 1)),
      );
    case '6 months':
    case '6_months':
    case '6Months':
      return DateTimeRange(
        start: DateTime(now.year, now.month - 6, now.day),
        end: today.add(const Duration(days: 1)),
      );
    case '1 year':
    case '1_year':
    case '1Year':
      return DateTimeRange(
        start: today.subtract(const Duration(days: 365)),
        end: today.add(const Duration(days: 1)),
      );
    case 'This year':
    case 'thisYear':
      return DateTimeRange(
        start: DateTime(now.year, 1, 1),
        end: DateTime(now.year + 1, 1, 1),
      );
    case 'All time':
    case 'allTime':
    case 'all':
      return DateTimeRange(
        start: DateTime(1970, 1, 1),
        end: DateTime(2100, 1, 1),
      );
    default:
      return DateTimeRange(
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      );
  }
}

DateTime homeWidgetFutureLimit(String period) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (period) {
    case 'This week':
    case 'thisWeek':
      final diff = 7 - now.weekday;
      return today.add(Duration(days: diff + 1));
    case '30 days':
    case '30_days':
    case '30Days':
      return today.add(const Duration(days: 30));
    case '6 months':
    case '6_months':
    case '6Months':
      return DateTime(now.year, now.month + 6, now.day);
    case '1 year':
    case '1_year':
    case '1Year':
      return DateTime(now.year + 1, now.month, now.day);
    case 'This year':
    case 'thisYear':
      return DateTime(now.year + 1, 1, 1);
    case 'All time':
    case 'allTime':
    case 'all':
      return DateTime(2100, 1, 1);
    case 'This month':
    case 'thisMonth':
    default:
      return DateTime(now.year, now.month + 1);
  }
}

List<HomeDashboardWidgetId> resolveHomeWidgetOrder(
  List<String> persisted, {
  List<String> hidden = const [],
}) {
  if (persisted.isEmpty) {
    return defaultHomeWidgetOrder
        .where((item) => !hidden.contains(item.storageKey))
        .toList();
  }

  final resolved = <HomeDashboardWidgetId>[];
  for (final key in persisted) {
    final item = homeWidgetIdFromStorageKey(key);
    if (item != null &&
        !hidden.contains(item.storageKey) &&
        !resolved.contains(item)) {
      resolved.add(item);
    }
  }
  for (final item in defaultHomeWidgetOrder) {
    if (!hidden.contains(item.storageKey) && !resolved.contains(item)) {
      resolved.add(item);
    }
  }
  return resolved;
}

HomeDashboardWidgetId? homeWidgetIdFromStorageKey(String key) {
  final byKey = {
    for (final item in HomeDashboardWidgetId.values) item.storageKey: item,
    'upcomingDue': HomeDashboardWidgetId.upcomingScheduled,
    'loansAndEmis': HomeDashboardWidgetId.emiTracker,
    'cards': HomeDashboardWidgetId.cardDebt,
    'cardPaymentPlan': HomeDashboardWidgetId.cardDebt,
  };
  return byKey[key];
}

String defaultDatePresetForHomeWidget(String id) {
  return switch (id) {
    'balanceHero' => 'This month',
    'accountGrid' || 'accountGroups' => 'allTime',
    'currencyValues' => 'This month',
    'balanceTrend' => 'This month',
    _ => 'This month',
  };
}

List<String> allowedDatePresetsForHomeWidget(String id) {
  return switch (id) {
    'balanceHero' => balanceHeroDatePresets,
    'currencyValues' => currencyRateDatePresets,
    _ => homeWidgetDatePresets,
  };
}

String homeWidgetDateLabel(String preset) {
  return homeWidgetDateLabels[preset] ?? preset;
}

List<String> restoreHomeWidgetStorageKey(List<String> order, String id) {
  final current = order.where((item) => item != id).toList();
  final target = defaultHomeWidgetOrder.indexWhere(
    (item) => item.storageKey == id,
  );
  if (target < 0) return [...current, id];
  for (var index = target - 1; index >= 0; index -= 1) {
    final previous = defaultHomeWidgetOrder[index].storageKey;
    final existingIndex = current.indexOf(previous);
    if (existingIndex >= 0) {
      return [
        ...current.take(existingIndex + 1),
        id,
        ...current.skip(existingIndex + 1),
      ];
    }
  }
  for (
    var index = target + 1;
    index < defaultHomeWidgetOrder.length;
    index += 1
  ) {
    final next = defaultHomeWidgetOrder[index].storageKey;
    final existingIndex = current.indexOf(next);
    if (existingIndex >= 0) {
      return [
        ...current.take(existingIndex),
        id,
        ...current.skip(existingIndex),
      ];
    }
  }
  return [...current, id];
}

String getHomeWidgetFilter(
  Map<String, String> homeWidgetFilters,
  String widgetKey, {
  String defaultValue = 'This month',
}) {
  final val = homeWidgetFilters[widgetKey];
  if (val == null || val.isEmpty) return defaultValue;
  return homeWidgetDateLabels[val] ?? val;
}

String getHomeWidgetFilterForWidget(
  Map<String, String> homeWidgetFilters,
  String widgetKey,
) {
  final defaultValue = switch (widgetKey) {
    'recentRecords' => 'This week',
    _ => 'This month',
  };
  return getHomeWidgetFilter(
    homeWidgetFilters,
    widgetKey,
    defaultValue: defaultValue,
  );
}
