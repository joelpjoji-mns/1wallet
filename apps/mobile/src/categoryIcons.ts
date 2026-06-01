import type { Category, CategoryKind } from '@1wallet/domain/types';
import { categoryBreadcrumb } from './categoryTree';
import type { OptionListItem } from './components/OptionListOverlay';
import {
    isAppIconName,
    normalizeIconBackgroundColor,
    resolveAppIconName,
    solidIconSurfaceForColor,
    type AppIconName,
} from './iconSystem';

type CategoryIconOption = OptionListItem<AppIconName> & {
  keywords: readonly string[];
};

type CategoryIconRule = {
  icon: AppIconName;
  terms: readonly string[];
};

type CategoryIconSource = Pick<Category, 'id' | 'name' | 'kind' | 'icon' | 'parentId'> &
  Partial<Pick<Category, 'color'>>;

type CategoryColorSource = Pick<Category, 'id' | 'kind' | 'parentId'> &
  Partial<Pick<Category, 'color'>>;

export type CategoryIconVisual = {
  icon: AppIconName;
  iconLabel: string;
  backgroundColor: string;
  iconColor: string;
};

const GENERIC_CATEGORY_ICONS = new Set<AppIconName>([
  'shape-outline',
  'dots-horizontal-circle-outline',
  'help-circle-outline',
]);

export const CATEGORY_KIND_COLOR_FALLBACKS: Record<CategoryKind, string> = {
  expense: '#315DA8',
  income: '#2F6B4F',
  transfer: '#5C5AA8',
  system: '#475569',
};

export const CATEGORY_ICON_OPTIONS = [
  {
    value: 'food-fork-drink',
    label: 'Food',
    description: 'Meals, dining, and daily food spending',
    icon: 'food-fork-drink',
    keywords: ['food', 'meal', 'restaurant', 'dining', 'lunch', 'dinner'],
  },
  {
    value: 'cart-outline',
    label: 'Groceries',
    description: 'Supermarket and household grocery runs',
    icon: 'cart-outline',
    keywords: ['grocery', 'groceries', 'supermarket', 'market'],
  },
  {
    value: 'coffee-outline',
    label: 'Coffee',
    description: 'Cafe, tea, snacks, and breakfast stops',
    icon: 'coffee-outline',
    keywords: ['coffee', 'cafe', 'tea', 'breakfast', 'snack'],
  },
  {
    value: 'truck-delivery-outline',
    label: 'Delivery',
    description: 'Food delivery and courier charges',
    icon: 'truck-delivery-outline',
    keywords: ['delivery', 'swiggy', 'zomato', 'courier'],
  },
  {
    value: 'bus',
    label: 'Transit',
    description: 'Bus, metro, train, and local commute',
    icon: 'bus',
    keywords: ['transport', 'transit', 'commute', 'bus', 'metro'],
  },
  {
    value: 'car-outline',
    label: 'Vehicle',
    description: 'Car, bike, parking, repairs, and maintenance',
    icon: 'car-outline',
    keywords: ['vehicle', 'car', 'bike', 'maintenance', 'parking'],
  },
  {
    value: 'gas-station-outline',
    label: 'Fuel',
    description: 'Petrol, diesel, charging, and gas station spends',
    icon: 'gas-station-outline',
    keywords: ['fuel', 'petrol', 'diesel', 'gas', 'charging'],
  },
  {
    value: 'home-outline',
    label: 'Home',
    description: 'Household, supplies, furniture, and repairs',
    icon: 'home-outline',
    keywords: ['home', 'house', 'household', 'furniture', 'maintenance'],
  },
  {
    value: 'home-city-outline',
    label: 'Rent',
    description: 'Rent, housing society, council tax, and property dues',
    icon: 'home-city-outline',
    keywords: ['rent', 'flat', 'apartment', 'property', 'council'],
  },
  {
    value: 'receipt',
    label: 'Bills',
    description: 'Utilities, fees, invoices, and monthly bills',
    icon: 'receipt',
    keywords: ['bill', 'bills', 'invoice', 'fee', 'receipt'],
  },
  {
    value: 'flash-outline',
    label: 'Electricity',
    description: 'Electricity and power bills',
    icon: 'flash-outline',
    keywords: ['electricity', 'power', 'energy'],
  },
  {
    value: 'wifi',
    label: 'Internet',
    description: 'Broadband, mobile data, and network plans',
    icon: 'wifi',
    keywords: ['internet', 'wifi', 'broadband', 'network'],
  },
  {
    value: 'cellphone-charging',
    label: 'Mobile',
    description: 'Mobile recharge, phone bill, and data pack',
    icon: 'cellphone-charging',
    keywords: ['mobile', 'phone', 'cellphone', 'recharge'],
  },
  {
    value: 'calendar-sync-outline',
    label: 'Subscription',
    description: 'Recurring subscriptions and memberships',
    icon: 'calendar-sync-outline',
    keywords: ['subscription', 'membership', 'prime', 'netflix'],
  },
  {
    value: 'shopping-outline',
    label: 'Shopping',
    description: 'Shopping, clothing, electronics, and online orders',
    icon: 'shopping-outline',
    keywords: ['shopping', 'clothes', 'electronics', 'order'],
  },
  {
    value: 'medical-bag',
    label: 'Health',
    description: 'Doctor visits, pharmacy, fitness, and dental care',
    icon: 'medical-bag',
    keywords: ['health', 'medical', 'doctor', 'pharmacy', 'medicine'],
  },
  {
    value: 'heart-pulse',
    label: 'Care',
    description: 'Healthcare, wellness, and personal care',
    icon: 'heart-pulse',
    keywords: ['care', 'wellness', 'personal care'],
  },
  {
    value: 'movie-open-outline',
    label: 'Entertainment',
    description: 'Movies, events, games, tickets, and hobbies',
    icon: 'movie-open-outline',
    keywords: ['entertainment', 'movie', 'games', 'ticket', 'fun'],
  },
  {
    value: 'airplane',
    label: 'Travel',
    description: 'Flights, hotels, trips, visas, and holidays',
    icon: 'airplane',
    keywords: ['travel', 'flight', 'hotel', 'trip', 'holiday'],
  },
  {
    value: 'school-outline',
    label: 'Education',
    description: 'School, classes, courses, books, and exams',
    icon: 'school-outline',
    keywords: ['education', 'school', 'course', 'class', 'book'],
  },
  {
    value: 'account-heart-outline',
    label: 'Family',
    description: 'Family, kids, giving, and personal support',
    icon: 'account-heart-outline',
    keywords: ['family', 'kids', 'children', 'support'],
  },
  {
    value: 'gift-outline',
    label: 'Gift',
    description: 'Gifts, celebrations, and joy spends',
    icon: 'gift-outline',
    keywords: ['gift', 'gifts', 'joy', 'celebration'],
  },
  {
    value: 'briefcase-outline',
    label: 'Work',
    description: 'Salary, freelance, business, and work income',
    icon: 'briefcase-outline',
    keywords: ['work', 'salary', 'job', 'business', 'freelance'],
  },
  {
    value: 'cash-multiple',
    label: 'Cash income',
    description: 'Cash, allowance, salary, and direct income',
    icon: 'cash-multiple',
    keywords: ['cash', 'income', 'allowance', 'salary'],
  },
  {
    value: 'cash-refund',
    label: 'Refund',
    description: 'Refunds, cashback, rebates, and reversals',
    icon: 'cash-refund',
    keywords: ['refund', 'cashback', 'rebate', 'return'],
  },
  {
    value: 'bank-outline',
    label: 'Banking',
    description: 'Finance, banking, investments, and accounts',
    icon: 'bank-outline',
    keywords: ['bank', 'finance', 'account'],
  },
  {
    value: 'credit-card-check-outline',
    label: 'Card bill',
    description: 'Credit card payments and card settlements',
    icon: 'credit-card-check-outline',
    keywords: ['card bill', 'credit card', 'card payment'],
  },
  {
    value: 'calendar-clock-outline',
    label: 'EMI',
    description: 'EMI, loan repayment, and scheduled finance dues',
    icon: 'calendar-clock-outline',
    keywords: ['emi', 'loan', 'repayment', 'scheduled'],
  },
  {
    value: 'hand-coin-outline',
    label: 'Lending',
    description: 'Money lent, borrowed, and personal loans',
    icon: 'hand-coin-outline',
    keywords: ['lend', 'lending', 'borrow', 'loan'],
  },
  {
    value: 'chart-line',
    label: 'Investment',
    description: 'Investments, trading, and portfolio movement',
    icon: 'chart-line',
    keywords: ['investment', 'investments', 'trading', 'portfolio'],
  },
  {
    value: 'arrow-up-circle-outline',
    label: 'Income',
    description: 'General money coming in',
    icon: 'arrow-up-circle-outline',
    keywords: ['income', 'inflow', 'credit'],
  },
  {
    value: 'arrow-down-circle-outline',
    label: 'Expense',
    description: 'General money going out',
    icon: 'arrow-down-circle-outline',
    keywords: ['expense', 'spend', 'debit'],
  },
  {
    value: 'swap-horizontal-circle-outline',
    label: 'Transfer',
    description: 'Movement between accounts',
    icon: 'swap-horizontal-circle-outline',
    keywords: ['transfer', 'move', 'internal'],
  },
  {
    value: 'tune-variant',
    label: 'Adjustment',
    description: 'Corrections and system adjustments',
    icon: 'tune-variant',
    keywords: ['adjustment', 'correction', 'system'],
  },
  {
    value: 'shape-outline',
    label: 'General',
    description: 'Fallback for categories without a specific symbol',
    icon: 'shape-outline',
    keywords: ['general', 'other', 'unknown'],
  },
] satisfies readonly CategoryIconOption[];

const CATEGORY_ICON_LABELS = new Map<AppIconName, string>(
  CATEGORY_ICON_OPTIONS.map((option) => [option.value, option.label]),
);

const CATEGORY_ICON_RULES: readonly CategoryIconRule[] = CATEGORY_ICON_OPTIONS.flatMap((option) =>
  option.value === 'shape-outline' ? [] : [{ icon: option.value, terms: option.keywords }],
);

export function categoryIconLabel(icon?: string | null): string {
  const resolvedIcon = resolveAppIconName(icon, 'shape-outline');
  return CATEGORY_ICON_LABELS.get(resolvedIcon) ?? readableIconName(resolvedIcon);
}

export function inferCategoryIcon(
  name: string,
  kind: CategoryKind = 'expense',
  context = '',
): AppIconName {
  const haystack = normalizeCategoryText(`${context} ${name}`);
  for (const rule of CATEGORY_ICON_RULES) {
    if (rule.terms.some((term) => haystack.includes(normalizeCategoryText(term)))) return rule.icon;
  }

  if (kind === 'income') return 'arrow-up-circle-outline';
  if (kind === 'transfer') return 'swap-horizontal-circle-outline';
  if (kind === 'system') return 'tune-variant';
  return 'arrow-down-circle-outline';
}

export function resolveCategoryIcon(
  category: CategoryIconSource | null | undefined,
  categories?: readonly CategoryIconSource[],
): AppIconName {
  if (!category) return 'shape-outline';
  const context = categories
    ? (categoryBreadcrumb(categories as Category[], category.id) ?? '')
    : '';
  const inferred = inferCategoryIcon(category.name, category.kind, context);
  if (!category.icon || !isAppIconName(category.icon)) return inferred;
  const resolvedIcon = resolveAppIconName(category.icon, inferred);
  return GENERIC_CATEGORY_ICONS.has(resolvedIcon) ? inferred : resolvedIcon;
}

export function resolveCategoryColor(
  category?: CategoryColorSource | null,
  categories?: readonly CategoryColorSource[],
  fallbackColor = CATEGORY_KIND_COLOR_FALLBACKS.system,
): string {
  if (!category) return fallbackColor;
  const categoriesById = new Map((categories ?? []).map((item) => [item.id, item]));
  const visited = new Set<string>([category.id]);
  let current: CategoryColorSource | undefined = category;
  let color = normalizeIconColor(category.color);

  while (current?.parentId) {
    if (visited.has(current.parentId)) break;
    const parent = categoriesById.get(current.parentId);
    if (!parent) break;
    visited.add(parent.id);
    color = normalizeIconColor(parent.color) ?? color;
    current = parent;
  }

  return color ?? CATEGORY_KIND_COLOR_FALLBACKS[category.kind] ?? fallbackColor;
}

export function resolveCategoryIconVisual(
  category?: CategoryIconSource | null,
  categories?: readonly CategoryIconSource[],
  fallbackColor?: string,
): CategoryIconVisual {
  const icon = resolveCategoryIcon(category, categories);
  const iconSurface = solidIconSurfaceForColor(
    resolveCategoryColor(
      category,
      categories,
      fallbackColor ?? CATEGORY_KIND_COLOR_FALLBACKS.system,
    ),
  );
  return {
    icon,
    iconLabel: categoryIconLabel(icon),
    backgroundColor: iconSurface.backgroundColor,
    iconColor: iconSurface.iconColor,
  };
}

export function shouldSuggestCategoryIcon(icon?: string | null): boolean {
  if (!icon || !isAppIconName(icon)) return true;
  return GENERIC_CATEGORY_ICONS.has(icon);
}

function normalizeCategoryText(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function normalizeIconColor(color?: string | null) {
  return color ? normalizeIconBackgroundColor(color, '') || undefined : undefined;
}

function readableIconName(icon: AppIconName) {
  return icon
    .replace(/-outline$/u, '')
    .replace(/-/gu, ' ')
    .replace(/\b\w/gu, (letter) => letter.toUpperCase());
}
