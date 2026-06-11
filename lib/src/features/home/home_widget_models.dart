enum HomeDashboardWidgetId {
  balanceHero('balanceHero'),
  plannedPaymentsTile('plannedPaymentsTile'),
  loansTile('loansTile'),
  accountGrid('accountGrid'),
  summaryTiles('summaryTiles'),
  recentRecords('recentRecords'),
  upcomingScheduled('upcomingScheduled'),
  dueNow('dueNow'),
  emiTracker('emiTracker'),
  cardDebt('cardDebt'),
  accountGroups('accountGroups'),
  reviewQueue('reviewQueue'),
  automationHealth('automationHealth'),
  cashflowForecast('cashflowForecast'),
  billWatch('billWatch'),
  cardPaymentPlan('cardPaymentPlan'),
  loanPayoff('loanPayoff'),
  savingsRunway('savingsRunway'),
  cashflowBook('cashflowBook'),
  balanceTrend('balanceTrend'),
  topCategories('topCategories'),
  incomeMix('incomeMix'),
  currencyValues('currencyValues'),
  budgetPressure('budgetPressure'),
  goalProgress('goalProgress'),
  currencyExposure('currencyExposure');

  const HomeDashboardWidgetId(this.storageKey);

  final String storageKey;
}

const defaultHomeWidgetOrder = [
  HomeDashboardWidgetId.balanceHero,
  HomeDashboardWidgetId.accountGrid,
  HomeDashboardWidgetId.summaryTiles,
  HomeDashboardWidgetId.recentRecords,
  HomeDashboardWidgetId.upcomingScheduled,
  HomeDashboardWidgetId.dueNow,
  HomeDashboardWidgetId.emiTracker,
  HomeDashboardWidgetId.cardDebt,
  HomeDashboardWidgetId.accountGroups,
  HomeDashboardWidgetId.plannedPaymentsTile,
  HomeDashboardWidgetId.loansTile,
  HomeDashboardWidgetId.reviewQueue,
  HomeDashboardWidgetId.automationHealth,
  HomeDashboardWidgetId.cashflowForecast,
  HomeDashboardWidgetId.billWatch,
  HomeDashboardWidgetId.cardPaymentPlan,
  HomeDashboardWidgetId.loanPayoff,
  HomeDashboardWidgetId.savingsRunway,
  HomeDashboardWidgetId.cashflowBook,
  HomeDashboardWidgetId.balanceTrend,
  HomeDashboardWidgetId.topCategories,
  HomeDashboardWidgetId.incomeMix,
  HomeDashboardWidgetId.currencyValues,
  HomeDashboardWidgetId.budgetPressure,
  HomeDashboardWidgetId.goalProgress,
  HomeDashboardWidgetId.currencyExposure,
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
    'summaryTiles',
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
    'financeSummary': HomeDashboardWidgetId.summaryTiles,
    'upcomingDue': HomeDashboardWidgetId.upcomingScheduled,
    'loansAndEmis': HomeDashboardWidgetId.emiTracker,
    'cards': HomeDashboardWidgetId.cardDebt,
    'automationReview': HomeDashboardWidgetId.reviewQueue,
  };
  return byKey[key];
}

String defaultDatePresetForHomeWidget(String id) {
  return switch (id) {
    'balanceHero' => 'thisMonth',
    'accountGrid' || 'accountGroups' || 'currencyExposure' => 'allTime',
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
