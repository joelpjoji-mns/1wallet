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
  budgetPressure('budgetPressure'),
  goalProgress('goalProgress'),
  creditUtilization('creditUtilization'),
  netWorth('netWorth'),
  cashFlow('cashFlow'),
  financialHealth('financialHealth'),
  monthComparison('monthComparison'),
  spendingHeatmap('spendingHeatmap');

  const HomeDashboardWidgetId(this.storageKey);

  final String storageKey;
}

const defaultHomeWidgetOrder = [
  HomeDashboardWidgetId.balanceHero,
  HomeDashboardWidgetId.accountGrid,
  HomeDashboardWidgetId.recentRecords,
  HomeDashboardWidgetId.balanceTrend,
  HomeDashboardWidgetId.currencyValues,
  HomeDashboardWidgetId.cashFlow,
  HomeDashboardWidgetId.monthComparison,
  HomeDashboardWidgetId.topCategories,
  HomeDashboardWidgetId.financialHealth,
  HomeDashboardWidgetId.netWorth,
  HomeDashboardWidgetId.upcomingScheduled,
  HomeDashboardWidgetId.budgetPressure,
  HomeDashboardWidgetId.goalProgress,
  HomeDashboardWidgetId.creditUtilization,
  HomeDashboardWidgetId.spendingHeatmap,
];

const homeWidgetDatePresets = [
  'today',
  'thisWeek',
  'thisMonth',
  'lastMonth',
  'thisYear',
  'allTime',
];

const homeWidgetDateLabels = {
  'today': 'Today',
  'thisWeek': 'This week',
  'thisMonth': 'This month',
  'lastMonth': 'Last month',
  'thisYear': 'This year',
  'allTime': 'All time',
};

const balanceHeroDatePresets = ['today', 'thisWeek', 'thisMonth', 'thisYear'];
const currencyRateDatePresets = [
  'today',
  'thisWeek',
  'thisMonth',
  'lastMonth',
  'thisYear',
];

List<HomeDashboardWidgetId> resolveHomeWidgetOrder(
  List<String> persisted, {
  List<String> hidden = const [],
}) {
  const legacyDefault = [
    'balanceHero',
    'accountGrid',
    'recentRecords',
    'upcomingScheduled',
  ];
  if (persisted.isEmpty || _sameOrder(persisted, legacyDefault)) {
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
  };
  return byKey[key];
}

String defaultDatePresetForHomeWidget(String id) {
  return switch (id) {
    'balanceHero' => 'thisMonth',
    'accountGrid' || 'accountGroups' => 'allTime',
    'currencyValues' => 'thisMonth',
    'balanceTrend' => 'thisYear',
    _ => 'thisMonth',
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

bool _sameOrder(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
