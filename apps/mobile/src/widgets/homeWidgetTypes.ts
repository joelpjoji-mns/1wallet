import type { AppIconName } from '../components/AppKit';
import type { IconSurfaceTone } from '../iconSystem';

export type HomeWidgetId =
  | 'balanceHero'
  | 'accountGrid'
  | 'summaryTiles'
  | 'recentRecords'
  | 'upcomingScheduled'
  | 'dueNow'
  | 'emiTracker'
  | 'cardDebt'
  | 'accountGroups'
  | 'reviewQueue'
  | 'automationHealth'
  | 'cashflowForecast'
  | 'billWatch'
  | 'cardPaymentPlan'
  | 'loanPayoff'
  | 'savingsRunway'
  | 'cashflowBook'
  | 'balanceTrend'
  | 'topCategories'
  | 'incomeMix'
  | 'currencyValues'
  | 'budgetPressure'
  | 'goalProgress'
  | 'currencyExposure';

export type HomeWidgetSize = 'compact' | 'medium' | 'wide';
export type HomeWidgetDatePreset =
  | 'today'
  | 'thisWeek'
  | 'thisMonth'
  | 'lastMonth'
  | 'thisYear'
  | 'allTime';

export type StoredHomeWidgetPreferences = {
  order?: string[];
  hidden?: string[];
  sizes?: Record<string, HomeWidgetSize>;
  filters?: Record<string, HomeWidgetDatePreset>;
};

export type NormalizedHomeWidgetPreferences = {
  order: HomeWidgetId[];
  hidden: HomeWidgetId[];
  sizes: Record<HomeWidgetId, HomeWidgetSize>;
  filters: Record<HomeWidgetId, HomeWidgetDatePreset>;
};

export type HomeWidgetMeta = {
  id: HomeWidgetId;
  title: string;
  body: string;
  icon: AppIconName;
  iconTone: IconSurfaceTone;
  defaultSize: HomeWidgetSize;
};

export const HOME_WIDGETS: HomeWidgetMeta[] = [
  {
    id: 'balanceHero',
    title: 'Balance hero',
    body: 'Current balance with period income and expense.',
    icon: 'wallet-outline',
    iconTone: 'account',
    defaultSize: 'wide',
  },
  {
    id: 'accountGrid',
    title: 'All accounts',
    body: 'Compact 3-column account tiles with balances and status badges.',
    icon: 'view-grid-outline',
    iconTone: 'account',
    defaultSize: 'wide',
  },
  {
    id: 'recentRecords',
    title: 'Recent records',
    body: 'Latest cleared transactions from the ledger.',
    icon: 'format-list-bulleted',
    iconTone: 'record',
    defaultSize: 'wide',
  },
  {
    id: 'summaryTiles',
    title: 'Finance summary',
    body: 'Planned payments, debt, and net worth summary tiles.',
    icon: 'view-dashboard-outline',
    iconTone: 'widget',
    defaultSize: 'medium',
  },
  {
    id: 'upcomingScheduled',
    title: 'Upcoming planned',
    body: 'Scheduled records and subscriptions sorted by due date.',
    icon: 'calendar-clock-outline',
    iconTone: 'plan',
    defaultSize: 'wide',
  },
  {
    id: 'dueNow',
    title: 'Due now',
    body: 'Bills, EMIs, and card payments due today or overdue.',
    icon: 'calendar-alert',
    iconTone: 'warning',
    defaultSize: 'medium',
  },
  {
    id: 'emiTracker',
    title: 'EMI tracker',
    body: 'Loan repayment timeline, next EMI, and planned principal EMI total.',
    icon: 'bank-transfer-out',
    iconTone: 'loan',
    defaultSize: 'medium',
  },
  {
    id: 'cardDebt',
    title: 'Card debt',
    body: 'Credit card exposure and highest outstanding card.',
    icon: 'credit-card-outline',
    iconTone: 'danger',
    defaultSize: 'medium',
  },
  {
    id: 'accountGroups',
    title: 'Account groups',
    body: 'Balances grouped by bank, wallet, card, forex, and archived rows.',
    icon: 'folder-table-outline',
    iconTone: 'account',
    defaultSize: 'wide',
  },
  {
    id: 'reviewQueue',
    title: 'Review queue',
    body: 'Pending capture candidates and source breakdown.',
    icon: 'robot-outline',
    iconTone: 'warning',
    defaultSize: 'medium',
  },
  {
    id: 'automationHealth',
    title: 'Automation health',
    body: 'Review queue, import warnings, scheduled work, and message parser readiness.',
    icon: 'shield-check-outline',
    iconTone: 'positive',
    defaultSize: 'medium',
  },
  {
    id: 'cashflowForecast',
    title: '30-day forecast',
    body: 'Upcoming scheduled income, bills, EMIs, cards, and transfers.',
    icon: 'calendar-month-outline',
    iconTone: 'plan',
    defaultSize: 'wide',
  },
  {
    id: 'billWatch',
    title: 'Bills watch',
    body: 'Subscriptions, utilities, card dues, and auto-debit bills coming up.',
    icon: 'clipboard-text-clock-outline',
    iconTone: 'warning',
    defaultSize: 'medium',
  },
  {
    id: 'cardPaymentPlan',
    title: 'Card payment plan',
    body: 'Scheduled card payments and card debt readiness.',
    icon: 'credit-card-clock-outline',
    iconTone: 'danger',
    defaultSize: 'medium',
  },
  {
    id: 'loanPayoff',
    title: 'Loan payoff',
    body: 'Loan balances, upcoming EMIs, and monthly repayment pressure.',
    icon: 'bank-minus',
    iconTone: 'loan',
    defaultSize: 'medium',
  },
  {
    id: 'savingsRunway',
    title: 'Savings runway',
    body: 'Liquid balance compared with the last 30 days of spending.',
    icon: 'timer-sand',
    iconTone: 'warning',
    defaultSize: 'medium',
  },
  {
    id: 'cashflowBook',
    title: 'Cashflow book',
    body: 'Current period income, expenses, net, and dates.',
    icon: 'book-open-outline',
    iconTone: 'record',
    defaultSize: 'medium',
  },
  {
    id: 'balanceTrend',
    title: 'Balance trend',
    body: 'Running balance line chart for the selected period.',
    icon: 'chart-bar',
    iconTone: 'tertiary',
    defaultSize: 'wide',
  },
  {
    id: 'topCategories',
    title: 'Top categories',
    body: 'Top spending categories for the current period.',
    icon: 'shape-outline',
    iconTone: 'category',
    defaultSize: 'wide',
  },
  {
    id: 'incomeMix',
    title: 'Income mix',
    body: 'Income records grouped by category, like salary, refunds, interest, and cashback.',
    icon: 'chart-donut',
    iconTone: 'income',
    defaultSize: 'wide',
  },
  {
    id: 'currencyValues',
    title: 'Currency values',
    body: 'Exchange-rate trend and quick converter.',
    icon: 'currency-gbp',
    iconTone: 'transfer',
    defaultSize: 'wide',
  },
  {
    id: 'budgetPressure',
    title: 'Budget pressure',
    body: 'Budget utilization and overrun warnings.',
    icon: 'gauge',
    iconTone: 'warning',
    defaultSize: 'wide',
  },
  {
    id: 'goalProgress',
    title: 'Goal progress',
    body: 'Goal progress and required monthly pace.',
    icon: 'bullseye-arrow',
    iconTone: 'positive',
    defaultSize: 'wide',
  },
  {
    id: 'currencyExposure',
    title: 'Currency exposure',
    body: 'Non-base currency balances like forex cards.',
    icon: 'currency-gbp',
    iconTone: 'transfer',
    defaultSize: 'medium',
  },
];

export const HOME_WIDGET_IDS = HOME_WIDGETS.map((widget) => widget.id);
export const DEFAULT_HOME_WIDGET_ORDER: HomeWidgetId[] = HOME_WIDGET_IDS;
const LEGACY_DEFAULT_HOME_WIDGET_ORDER: HomeWidgetId[] = [
  'balanceHero',
  'accountGrid',
  'summaryTiles',
  'recentRecords',
  'upcomingScheduled',
  'dueNow',
  'emiTracker',
  'cardDebt',
  'accountGroups',
  'reviewQueue',
  'automationHealth',
  'cashflowForecast',
  'billWatch',
  'cardPaymentPlan',
  'loanPayoff',
  'savingsRunway',
  'cashflowBook',
  'balanceTrend',
  'topCategories',
  'currencyValues',
  'budgetPressure',
  'goalProgress',
  'currencyExposure',
];
export const HOME_WIDGET_DATE_PRESETS: HomeWidgetDatePreset[] = [
  'today',
  'thisWeek',
  'thisMonth',
  'lastMonth',
  'thisYear',
  'allTime',
];

export const BALANCE_HERO_DATE_PRESETS: HomeWidgetDatePreset[] = [
  'today',
  'thisWeek',
  'thisMonth',
  'thisYear',
];

export const BALANCE_HERO_DEFAULT_DATE_PRESET: HomeWidgetDatePreset = 'thisMonth';

export const CURRENCY_RATE_DATE_PRESETS: HomeWidgetDatePreset[] = [
  'today',
  'thisWeek',
  'thisMonth',
  'lastMonth',
  'thisYear',
];

export const HOME_WIDGET_DATE_LABELS: Record<HomeWidgetDatePreset, string> = {
  today: 'Today',
  thisWeek: 'This week',
  thisMonth: 'This month',
  lastMonth: 'Last month',
  thisYear: 'This year',
  allTime: 'All time',
};

export const HOME_WIDGET_META = Object.fromEntries(
  HOME_WIDGETS.map((widget) => [widget.id, widget]),
) as Record<HomeWidgetId, HomeWidgetMeta>;

export function normalizeHomeWidgetPreferences(
  stored?: StoredHomeWidgetPreferences,
): NormalizedHomeWidgetPreferences {
  const hidden = uniqueKnown(stored?.hidden ?? []);
  const storedOrder = migrateLegacyDefaultOrder(uniqueKnown(stored?.order ?? []));
  const baseOrder = storedOrder.length > 0 ? storedOrder : DEFAULT_HOME_WIDGET_ORDER;
  const order = uniqueKnown([
    ...baseOrder,
    ...DEFAULT_HOME_WIDGET_ORDER.filter((id) => !baseOrder.includes(id)),
  ]).filter((id) => !hidden.includes(id));

  const sizes = {} as Record<HomeWidgetId, HomeWidgetSize>;
  const filters = {} as Record<HomeWidgetId, HomeWidgetDatePreset>;
  for (const widget of HOME_WIDGETS) {
    const size = stored?.sizes?.[widget.id];
    sizes[widget.id] = isWidgetSize(size) ? size : widget.defaultSize;
    const preset = stored?.filters?.[widget.id];
    filters[widget.id] = normalizeDatePresetForWidget(widget.id, preset);
  }

  return { order, hidden, sizes, filters };
}

export function toStoredHomeWidgetPreferences(
  preferences: NormalizedHomeWidgetPreferences,
): Required<StoredHomeWidgetPreferences> {
  return {
    order: preferences.order,
    hidden: preferences.hidden,
    sizes: preferences.sizes,
    filters: preferences.filters,
  };
}

export function resetHomeWidgetPreferences(): NormalizedHomeWidgetPreferences {
  return normalizeHomeWidgetPreferences({
    order: DEFAULT_HOME_WIDGET_ORDER,
    hidden: [],
    sizes: {},
    filters: {},
  });
}

export function isHomeWidgetVisible(
  preferences: NormalizedHomeWidgetPreferences,
  id: HomeWidgetId,
): boolean {
  return preferences.order.includes(id) && !preferences.hidden.includes(id);
}

export function hideHomeWidgetPreference(
  preferences: NormalizedHomeWidgetPreferences,
  id: HomeWidgetId,
): NormalizedHomeWidgetPreferences {
  return normalizeHomeWidgetPreferences({
    ...toStoredHomeWidgetPreferences(preferences),
    order: preferences.order.filter((widgetId) => widgetId !== id),
    hidden: preferences.hidden.includes(id) ? preferences.hidden : [...preferences.hidden, id],
  });
}

export function restoreHomeWidgetPreference(
  preferences: NormalizedHomeWidgetPreferences,
  id: HomeWidgetId,
): NormalizedHomeWidgetPreferences {
  const visibleOrder = preferences.order.filter((widgetId) => widgetId !== id);
  return normalizeHomeWidgetPreferences({
    ...toStoredHomeWidgetPreferences(preferences),
    order: insertWidgetByDefaultOrder(visibleOrder, id),
    hidden: preferences.hidden.filter((widgetId) => widgetId !== id),
  });
}

function insertWidgetByDefaultOrder(order: HomeWidgetId[], id: HomeWidgetId): HomeWidgetId[] {
  const targetDefaultIndex = DEFAULT_HOME_WIDGET_ORDER.indexOf(id);
  if (targetDefaultIndex < 0) return [...order, id];

  for (let index = targetDefaultIndex - 1; index >= 0; index -= 1) {
    const previousDefaultId = DEFAULT_HOME_WIDGET_ORDER[index];
    if (!previousDefaultId) continue;
    const previousVisibleIndex = order.indexOf(previousDefaultId);
    if (previousVisibleIndex >= 0) {
      return [
        ...order.slice(0, previousVisibleIndex + 1),
        id,
        ...order.slice(previousVisibleIndex + 1),
      ];
    }
  }

  for (let index = targetDefaultIndex + 1; index < DEFAULT_HOME_WIDGET_ORDER.length; index += 1) {
    const nextDefaultId = DEFAULT_HOME_WIDGET_ORDER[index];
    if (!nextDefaultId) continue;
    const nextVisibleIndex = order.indexOf(nextDefaultId);
    if (nextVisibleIndex >= 0) {
      return [...order.slice(0, nextVisibleIndex), id, ...order.slice(nextVisibleIndex)];
    }
  }

  return [...order, id];
}

function uniqueKnown(values: string[]): HomeWidgetId[] {
  const seen = new Set<HomeWidgetId>();
  const result: HomeWidgetId[] = [];
  for (const value of values) {
    if (!isHomeWidgetId(value) || seen.has(value)) continue;
    seen.add(value);
    result.push(value);
  }
  return result;
}

function migrateLegacyDefaultOrder(order: HomeWidgetId[]): HomeWidgetId[] {
  if (order.length === 0) return order;
  const legacyDefaultForVisible = LEGACY_DEFAULT_HOME_WIDGET_ORDER.filter((id) =>
    order.includes(id),
  );
  if (!sameWidgetOrder(order, legacyDefaultForVisible)) return order;
  return DEFAULT_HOME_WIDGET_ORDER.filter((id) => order.includes(id));
}

function sameWidgetOrder(left: HomeWidgetId[], right: HomeWidgetId[]): boolean {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function isHomeWidgetId(value: string): value is HomeWidgetId {
  return (HOME_WIDGET_IDS as string[]).includes(value);
}

function isWidgetSize(value: unknown): value is HomeWidgetSize {
  return value === 'compact' || value === 'medium' || value === 'wide';
}

function isDatePreset(value: unknown): value is HomeWidgetDatePreset {
  return typeof value === 'string' && HOME_WIDGET_DATE_PRESETS.includes(value as never);
}

function normalizeDatePresetForWidget(id: HomeWidgetId, value: unknown): HomeWidgetDatePreset {
  if (!isDatePreset(value)) return defaultDatePresetForWidget(id);
  if (id === 'balanceHero' && !BALANCE_HERO_DATE_PRESETS.includes(value)) {
    return defaultDatePresetForWidget(id);
  }
  if (id === 'currencyValues' && !CURRENCY_RATE_DATE_PRESETS.includes(value)) {
    return defaultDatePresetForWidget(id);
  }
  return value;
}

function defaultDatePresetForWidget(id: HomeWidgetId): HomeWidgetDatePreset {
  switch (id) {
    case 'balanceHero':
      return BALANCE_HERO_DEFAULT_DATE_PRESET;
    case 'accountGrid':
    case 'accountGroups':
    case 'currencyExposure':
      return 'allTime';
    case 'currencyValues':
      return 'thisMonth';
    case 'balanceTrend':
      return 'thisYear';
    default:
      return 'thisMonth';
  }
}
