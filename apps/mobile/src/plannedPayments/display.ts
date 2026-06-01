import type { Account, Category, Transaction } from '@1wallet/domain/types';
import {
    plannedPaymentKindForRule,
    plannedPaymentKindForTransactionType,
} from '@1wallet/ledger/rules/futureGeneration';
import type {
    FutureGenerationRule,
    LedgerState,
    PlannedPaymentKind,
} from '@1wallet/ledger/store/types';
import type { MD3Theme } from 'react-native-paper';
import { resolveAccountIconVisual } from '../accountOptions';
import { inferCategoryIcon, resolveCategoryIconVisual } from '../categoryIcons';
import { categoryBreadcrumb } from '../categoryTree';
import { resolveAppIconName, type AppIconName } from '../components/AppKit';
import { positiveAmountColor } from '../financeColors';
import { solidIconSurfaceForColor } from '../iconSystem';

export type PlannedPaymentKindMeta = {
  label: string;
  description?: string;
  icon: AppIconName;
};

type PlannedPaymentIconVisual = {
  icon: AppIconName;
  backgroundColor: string;
  iconColor: string;
};

type PlannedPaymentIconRule = {
  terms: readonly string[];
  icon: string;
  fallbackIcon: AppIconName;
  color: string;
};

export const PLANNED_PAYMENT_ICON_FOREGROUND_COLOR = '#FFFFFF';

const PLANNED_PAYMENT_ICON_RULES: readonly PlannedPaymentIconRule[] = [
  {
    terms: ['jio stb', 'jiofiber', 'set top', 'stb', 'broadband', 'internet'],
    icon: 'television-classic',
    fallbackIcon: 'wifi',
    color: '#2563EB',
  },
  {
    terms: ['jio recharge', 'recharge', 'mobile', 'phone', 'truecaller'],
    icon: 'cellphone-charging',
    fallbackIcon: 'cellphone-charging',
    color: '#0EA5E9',
  },
  {
    terms: ['spotify', 'music'],
    icon: 'music-note',
    fallbackIcon: 'movie-open-outline',
    color: '#1DB954',
  },
  {
    terms: ['netflix', 'youtube', 'prime video', 'crunchyroll', 'streaming', 'tv'],
    icon: 'movie-open-outline',
    fallbackIcon: 'movie-open-outline',
    color: '#7C3AED',
  },
  {
    terms: ['google one', 'icloud', 'cloud storage', 'storage'],
    icon: 'cloud-outline',
    fallbackIcon: 'calendar-sync-outline',
    color: '#4285F4',
  },
  {
    terms: ['electricity', 'power', 'energy'],
    icon: 'flash-outline',
    fallbackIcon: 'flash-outline',
    color: '#7C3AED',
  },
  {
    terms: ['rent', 'housing', 'suniya'],
    icon: 'home-city-outline',
    fallbackIcon: 'home-city-outline',
    color: '#C65A00',
  },
  {
    terms: ['maintenance', 'society', 'apartment maintenance'],
    icon: 'home-wrench-outline',
    fallbackIcon: 'home-outline',
    color: '#64748B',
  },
  {
    terms: ['church', 'charity', 'donation', 'giving'],
    icon: 'church',
    fallbackIcon: 'gift-outline',
    color: '#8B5CF6',
  },
  {
    terms: ['insurance', 'vehicle insurance', 'car insurance', 'bike insurance'],
    icon: 'shield-car',
    fallbackIcon: 'car-outline',
    color: '#D97706',
  },
  {
    terms: ['salary', 'payroll', 'tcs'],
    icon: 'briefcase-outline',
    fallbackIcon: 'cash-multiple',
    color: '#2F6B4F',
  },
  {
    terms: ['amazon prime', 'amazon'],
    icon: 'shopping-outline',
    fallbackIcon: 'shopping-outline',
    color: '#C65A00',
  },
];

export function transactionTypeForPlannedKind(
  kind: PlannedPaymentKind,
  preferredType?: Transaction['type'],
): Transaction['type'] {
  if (preferredType && plannedPaymentKindForTransactionType(preferredType) === kind) {
    return preferredType;
  }
  if (kind === 'income') return 'income';
  if (kind === 'transfer') return 'transfer';
  if (kind === 'adjustment') return 'adjustment';
  return 'expense';
}

export function plannedKindMeta(kind: PlannedPaymentKind): PlannedPaymentKindMeta {
  if (kind === 'income') {
    return {
      label: 'Income',
      description: 'Salary, refunds, interest, cashback, and planned inflows',
      icon: 'arrow-down-circle-outline',
    };
  }
  if (kind === 'transfer') {
    return {
      label: 'Transfer',
      description: 'Move money between accounts, cards, loans, or goals',
      icon: 'swap-horizontal',
    };
  }
  if (kind === 'adjustment') {
    return {
      label: 'Adjustment',
      description: 'Planned balance correction or account adjustment',
      icon: 'tune-variant',
    };
  }
  return {
    label: 'Expense',
    description: 'Bills, subscriptions, fees, and planned spending',
    icon: 'arrow-up-circle-outline',
  };
}

export function basePlannedPaymentKind(kind: PlannedPaymentKind): PlannedPaymentKind {
  return kind;
}

export function plannedPaymentVisualKind(
  kind: PlannedPaymentKind,
): 'income' | 'expense' | 'transfer' | 'adjustment' {
  if (kind === 'income') return 'income';
  if (kind === 'transfer') return 'transfer';
  if (kind === 'adjustment') return 'adjustment';
  return 'expense';
}

export function requiresCounterAccount(kind: PlannedPaymentKind): boolean {
  return kind === 'transfer';
}

export function categoryApplies(kind: PlannedPaymentKind): boolean {
  return kind === 'income' || kind === 'expense';
}

export function categoryKindForPlanKind(kind: PlannedPaymentKind): 'expense' | 'income' {
  return kind === 'income' ? 'income' : 'expense';
}

export function categoryDisplayName(categories: Category[], category?: Category): string {
  if (!category) return 'No category';
  return categoryBreadcrumb(categories, category.id) ?? category.name;
}

export function categoryForRule(
  state: LedgerState,
  rule: FutureGenerationRule,
): Category | undefined {
  return rule.categoryId ? state.categories.find((item) => item.id === rule.categoryId) : undefined;
}

export function plannedPaymentCategorySummary(
  state: LedgerState,
  rule: FutureGenerationRule,
): string {
  const plannedKind = plannedPaymentKindForRule(rule);
  if (rule.type === 'loan_repayment') {
    const loanAccount = rule.counterAccountId
      ? accountName(state, rule.counterAccountId)
      : undefined;
    return loanAccount ? `${loanAccount} · EMI` : 'Loan EMI';
  }
  if (rule.type === 'card_payment') {
    const cardAccount = rule.counterAccountId
      ? accountName(state, rule.counterAccountId)
      : undefined;
    return cardAccount ? `${cardAccount} · card due` : 'Card due';
  }

  const kind = basePlannedPaymentKind(plannedKind);
  if (kind === 'transfer') {
    const fromAccount = accountName(state, rule.accountId);
    const toAccount = rule.counterAccountId ? accountName(state, rule.counterAccountId) : undefined;
    return (
      [fromAccount ? `from ${fromAccount}` : undefined, toAccount ? `to ${toAccount}` : undefined]
        .filter(Boolean)
        .join(' · ') || 'Transfer'
    );
  }

  return categoryDisplayName(state.categories, categoryForRule(state, rule));
}

export function plannedPaymentTileIcon(
  state: LedgerState,
  rule: FutureGenerationRule,
): AppIconName {
  return plannedPaymentIconVisual(state, rule).icon;
}

export function plannedPaymentTileIconBackgroundColor(
  state: LedgerState,
  rule: FutureGenerationRule,
  fallback: string,
): string {
  return plannedPaymentIconVisual(state, rule, fallback).backgroundColor;
}

export function plannedPaymentTileIconForegroundColor(
  state: LedgerState,
  rule: FutureGenerationRule,
  fallback: string,
): string {
  return plannedPaymentIconVisual(state, rule, fallback).iconColor;
}

export function plannedPaymentLoanAccount(
  state: LedgerState,
  rule: FutureGenerationRule,
): Account | undefined {
  if (rule.type !== 'loan_repayment') return undefined;
  const endpointIds = [rule.counterAccountId, rule.accountId].filter(Boolean);
  return endpointIds
    .map((accountId) => state.accounts.find((account) => account.id === accountId))
    .find(isLoanEndpointAccount);
}

function plannedPaymentIconVisual(
  state: LedgerState,
  rule: FutureGenerationRule,
  fallbackBackgroundColor = '#315DA8',
): PlannedPaymentIconVisual {
  const loanAccount = plannedPaymentLoanAccount(state, rule);
  if (loanAccount) {
    return plannedPaymentIconVisualWithForeground(resolveAccountIconVisual(loanAccount));
  }

  const semantic = plannedPaymentSemanticIconVisual(rule);
  if (semantic) return semantic;

  const category = categoryForRule(state, rule);
  if (category) {
    return plannedPaymentIconVisualWithForeground(
      resolveCategoryIconVisual(category, state.categories, fallbackBackgroundColor),
    );
  }

  return plannedPaymentKindIconVisual(rule);
}

function plannedPaymentSemanticIconVisual(
  rule: FutureGenerationRule,
): PlannedPaymentIconVisual | undefined {
  const haystack = normalizePlannedPaymentIconText(
    [rule.name, rule.notes, rule.paymentMethod].filter(Boolean).join(' '),
  );
  const matchedRule = PLANNED_PAYMENT_ICON_RULES.find((item) =>
    item.terms.some((term) => haystack.includes(normalizePlannedPaymentIconText(term))),
  );
  if (!matchedRule) return undefined;
  return iconVisualFromColor(
    resolveAppIconName(matchedRule.icon, matchedRule.fallbackIcon),
    matchedRule.color,
  );
}

function plannedPaymentKindIconVisual(rule: FutureGenerationRule): PlannedPaymentIconVisual {
  if (rule.type === 'card_payment') {
    return iconVisualFromColor('credit-card-check-outline', '#5C5AA8');
  }
  const kind = plannedPaymentKindForRule(rule);
  if (kind === 'income') return iconVisualFromColor('cash-multiple', '#2F6B4F');
  if (kind === 'transfer') return iconVisualFromColor('swap-horizontal-circle-outline', '#5C5AA8');
  if (kind === 'adjustment') return iconVisualFromColor('tune-variant', '#475569');
  const inferred = inferCategoryIcon(
    rule.name,
    'expense',
    [rule.notes, rule.paymentMethod].filter(Boolean).join(' '),
  );
  const icon = inferred === 'arrow-down-circle-outline' ? 'receipt' : inferred;
  return iconVisualFromColor(icon, '#A83246');
}

function iconVisualFromColor(icon: AppIconName, color: string): PlannedPaymentIconVisual {
  const surface = solidIconSurfaceForColor(color);
  return {
    icon,
    backgroundColor: surface.backgroundColor,
    iconColor: PLANNED_PAYMENT_ICON_FOREGROUND_COLOR,
  };
}

function plannedPaymentIconVisualWithForeground(
  visual: PlannedPaymentIconVisual,
): PlannedPaymentIconVisual {
  return { ...visual, iconColor: PLANNED_PAYMENT_ICON_FOREGROUND_COLOR };
}

export function plannedPaymentAmountColor(
  colors: MD3Theme['colors'],
  rule: FutureGenerationRule,
  dark?: boolean,
): string {
  const visualKind = plannedPaymentVisualKind(plannedPaymentKindForRule(rule));
  if (visualKind === 'income') return positiveAmountColor(dark);
  if (visualKind === 'transfer') return colors.primary;
  if (visualKind === 'adjustment') return colors.secondary;
  return colors.error;
}

export function plannedPaymentRecurrenceSummary(rule: FutureGenerationRule): string {
  const cadence = recurrenceCadence(rule);
  const end = plannedPaymentEndSummary(rule);
  return end === 'Forever' ? cadence : `${cadence} · ${end}`;
}

export function plannedPaymentEndSummary(rule: FutureGenerationRule): string {
  if (rule.endsOn) return `Until ${rule.endsOn}`;
  if (rule.occurrences) {
    return `${rule.occurrences} ${plannedPaymentOccurrenceNoun(rule, rule.occurrences)} total`;
  }
  return 'Forever';
}

export function plannedPaymentOccurrenceNoun(rule: FutureGenerationRule, count: number): string {
  if (rule.type === 'loan_repayment') return count === 1 ? 'EMI' : 'EMIs';
  if (rule.type === 'card_payment') return count === 1 ? 'payment' : 'payments';
  return count === 1 ? 'time' : 'times';
}

export function accountName(state: LedgerState, accountId: string): string | undefined {
  return state.accounts.find((account) => account.id === accountId)?.name;
}

export function dueLabel(value: string, locale: string, now = new Date()): string {
  const dueDate = new Date(value);
  if (Number.isNaN(dueDate.getTime())) return 'No date';

  const startOfToday = new Date(now);
  startOfToday.setHours(0, 0, 0, 0);
  const startOfDue = new Date(dueDate);
  startOfDue.setHours(0, 0, 0, 0);
  const daysAway = Math.round(
    (startOfDue.getTime() - startOfToday.getTime()) / (24 * 60 * 60 * 1000),
  );

  if (daysAway < 0) return `Overdue by ${dayCountLabel(Math.abs(daysAway))}`;
  if (daysAway === 0) return 'Due today';
  if (daysAway === 1) return 'Due tomorrow';

  return `Due in ${dayCountLabel(daysAway)}`;
}

function dayCountLabel(days: number): string {
  return `${days} ${days === 1 ? 'day' : 'days'}`;
}

function isLoanEndpointAccount(account?: Account): account is Account {
  return account?.type === 'loan' || account?.type === 'overdraft' || account?.type === 'lent';
}

function normalizePlannedPaymentIconText(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export function generatedTransactionsForRule(
  state: LedgerState,
  rule: FutureGenerationRule,
): Transaction[] {
  const prefix = `future-rule-v1:${rule.id}:`;
  return state.transactions
    .filter(
      (transaction) =>
        transaction.recurringTemplateId === rule.id || transaction.externalRef?.startsWith(prefix),
    )
    .sort((left, right) => left.occurredAt.localeCompare(right.occurredAt));
}

function recurrenceCadence(rule: FutureGenerationRule): string {
  const interval = Math.max(1, rule.interval || 1);
  if (rule.frequency === 'daily') return interval === 1 ? 'Daily' : `Every ${interval} days`;
  if (rule.frequency === 'weekly') {
    const weekdays = weeklyDaysLabel(rule.daysOfWeek, rule.startsOn);
    return interval === 1 ? `Weekly on ${weekdays}` : `Every ${interval} weeks on ${weekdays}`;
  }
  if (rule.frequency === 'yearly') {
    const date = monthDayLabel(rule.startsOn);
    return interval === 1 ? `Yearly on ${date}` : `Every ${interval} years on ${date}`;
  }
  const day = rule.dayOfMonth ?? dateDay(rule.startsOn);
  return interval === 1
    ? `Monthly on ${ordinal(day)}`
    : `Every ${interval} months on ${ordinal(day)}`;
}

function dateDay(value: string): number {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? 1 : date.getDate();
}

function weekdayLabel(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'start day';
  return WEEKDAY_LABELS[date.getDay()] ?? 'start day';
}

function weeklyDaysLabel(daysOfWeek: number[] | undefined, startsOn: string): string {
  const days = normalizeDaysOfWeek(daysOfWeek);
  if (days.length === 0) return weekdayLabel(startsOn);
  return listLabel(days.map((day) => WEEKDAY_LABELS[day] ?? 'start day'));
}

function normalizeDaysOfWeek(values?: number[]): number[] {
  return Array.from(
    new Set(
      (values ?? []).map((value) => Math.floor(value)).filter((value) => value >= 0 && value <= 6),
    ),
  ).sort((left, right) => weekdaySortIndex(left) - weekdaySortIndex(right));
}

function weekdaySortIndex(day: number): number {
  return (day + 6) % 7;
}

function listLabel(values: string[]): string {
  if (values.length <= 1) return values[0] ?? 'start day';
  if (values.length === 2) return `${values[0]} and ${values[1]}`;
  return `${values.slice(0, -1).join(', ')}, and ${values[values.length - 1]}`;
}

function monthDayLabel(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'start date';
  return date.toLocaleDateString('en-IN', { month: 'short', day: 'numeric' });
}

function ordinal(value: number): string {
  const suffix =
    value % 100 >= 11 && value % 100 <= 13 ? 'th' : (['th', 'st', 'nd', 'rd'][value % 10] ?? 'th');
  return `${value}${suffix}`;
}

const WEEKDAY_LABELS = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
