import { MaterialCommunityIcons } from '@expo/vector-icons';
import type { ComponentProps } from 'react';
import type { MD3Theme } from 'react-native-paper';
import { withColorAlpha } from './colorAlpha';
import { readableTextColorForBackground } from './colorContrast';
import { normalizeHexColor } from './theme';

export type AppIconName = ComponentProps<typeof MaterialCommunityIcons>['name'];

export type IconVisual = {
  icon: AppIconName;
  iconLabel: string;
  backgroundColor: string;
  iconColor: string;
};

export type IconSurface = Pick<IconVisual, 'backgroundColor' | 'iconColor'>;

export type IconSurfaceTone =
  | 'default'
  | 'primary'
  | 'secondary'
  | 'tertiary'
  | 'positive'
  | 'income'
  | 'expense'
  | 'transfer'
  | 'adjustment'
  | 'account'
  | 'category'
  | 'record'
  | 'plan'
  | 'loan'
  | 'widget'
  | 'warning'
  | 'danger'
  | 'neutral';

export const TEXT_ON_ICON_COLOR = {
  light: '#FFFFFF',
  dark: '#1B1B1F',
} as const;

export const ICON_LAYER_ALPHA = {
  lightContent: 0.22,
  darkContent: 0.1,
  subtle: 0.13,
  semantic: 0.16,
  semanticDark: 0.22,
} as const;

const DEFAULT_ICON_BACKGROUND = '#315DA8';
const INCOME_ICON_COLOR = '#2F6B4F';
const EXPENSE_ICON_COLOR = '#A83246';
const TRANSFER_ICON_COLOR = '#5C5AA8';
const WARNING_ICON_COLOR = '#8A5A00';
const NEUTRAL_ICON_COLOR = '#475569';

export const APP_ICONS = {
  navigation: {
    menu: 'menu',
    home: 'view-dashboard-outline',
    transactions: 'format-list-bulleted',
    addRecord: 'plus-circle-outline',
    review: 'clipboard-check-outline',
    accounts: 'wallet-outline',
    widgets: 'view-dashboard-outline',
    categories: 'shape-outline',
    cards: 'credit-card-outline',
    currencies: 'currency-usd',
    planner: 'view-week-outline',
    calendar: 'calendar-month-outline',
    plannedPayments: 'calendar-sync-outline',
    loans: 'bank-outline',
    loanForecast: 'chart-timeline-variant',
    sync: 'cloud-sync-outline',
    autoCapture: 'message-processing-outline',
    imports: 'tray-arrow-down',
    dataBackup: 'backup-restore',
    notifications: 'bell-outline',
    updates: 'update',
    settings: 'cog-outline',
  },
  action: {
    add: 'plus',
    back: 'arrow-left',
    check: 'check',
    markAllRead: 'check-all',
    reset: 'restart',
    search: 'magnify',
  },
  brand: {
    wallet: 'wallet-outline',
  },
  status: {
    archive: 'archive-outline',
    ready: 'check-circle-outline',
    session: 'shield-check-outline',
    wallet: 'database-outline',
  },
} as const satisfies Record<string, Record<string, AppIconName>>;

const appIconNames = new Set<string>(Object.keys(MaterialCommunityIcons.glyphMap));

export function isAppIconName(name?: string | null): name is AppIconName {
  return Boolean(name && appIconNames.has(name));
}

export function resolveAppIconName(
  name?: string | null,
  fallback: AppIconName = 'shape-outline',
): AppIconName {
  return isAppIconName(name) ? name : fallback;
}

export function iconTextColorForBackground(color?: string | null): string {
  return readableTextColorForBackground(color);
}

export function normalizeIconBackgroundColor(
  color?: string | null,
  fallbackColor = DEFAULT_ICON_BACKGROUND,
): string {
  return normalizeHexColor(color ?? undefined) ?? fallbackColor;
}

export function translucentIconLayerColor(contentColor: string): string {
  return contentColor.toUpperCase() === TEXT_ON_ICON_COLOR.light
    ? withColorAlpha(TEXT_ON_ICON_COLOR.light, ICON_LAYER_ALPHA.lightContent)
    : withColorAlpha('#000000', ICON_LAYER_ALPHA.darkContent);
}

export function subtleIconBackgroundColor(color: string): string {
  return withColorAlpha(color, ICON_LAYER_ALPHA.subtle);
}

export function iconSurfaceForThemeTone(theme: MD3Theme, tone: IconSurfaceTone): IconSurface {
  const sourceColor = iconSourceColorForThemeTone(theme, tone);
  return {
    backgroundColor: withColorAlpha(
      sourceColor,
      theme.dark ? ICON_LAYER_ALPHA.semanticDark : ICON_LAYER_ALPHA.semantic,
    ),
    iconColor: sourceColor,
  };
}

export function iconSurfaceForCustomColor(
  color?: string | null,
  fallbackColor = DEFAULT_ICON_BACKGROUND,
): IconSurface {
  return solidIconSurfaceForColor(color, fallbackColor);
}

export function iconSurfaceForUserColor(
  theme: MD3Theme,
  color?: string | null,
  tone: IconSurfaceTone = 'primary',
): IconSurface {
  if (color) return iconSurfaceForCustomColor(color, iconSourceColorForThemeTone(theme, tone));
  return iconSurfaceForThemeTone(theme, tone);
}

export function insetIconSurfaceForThemeColor(theme: MD3Theme, color?: string | null): IconSurface {
  const resolvedBackground = normalizeIconBackgroundColor(color, theme.colors.primary);
  const plateColor = iconTextColorForBackground(resolvedBackground);
  return {
    backgroundColor: withColorAlpha(
      plateColor,
      plateColor === TEXT_ON_ICON_COLOR.light ? 0.92 : 0.82,
    ),
    iconColor: resolvedBackground,
  };
}

export function solidIconSurfaceForColor(
  color?: string | null,
  fallbackColor = DEFAULT_ICON_BACKGROUND,
): IconSurface {
  const backgroundColor = normalizeIconBackgroundColor(color, fallbackColor);
  return {
    backgroundColor,
    iconColor: iconTextColorForBackground(backgroundColor),
  };
}

export function insetIconSurfaceForBackground(
  background?: string | null,
  fallbackColor = DEFAULT_ICON_BACKGROUND,
): IconSurface {
  const resolvedBackground = normalizeIconBackgroundColor(background, fallbackColor);
  const plateColor = iconTextColorForBackground(resolvedBackground);
  return {
    backgroundColor: plateColor,
    iconColor: resolvedBackground,
  };
}

export function resolveIconVisual({
  icon,
  iconLabel,
  backgroundColor,
  fallbackIcon = 'shape-outline',
  fallbackBackgroundColor = '#315DA8',
}: {
  icon?: string | null;
  iconLabel: string;
  backgroundColor?: string | null;
  fallbackIcon?: AppIconName;
  fallbackBackgroundColor?: string;
}): IconVisual {
  const resolvedSurface = solidIconSurfaceForColor(backgroundColor, fallbackBackgroundColor);
  return {
    icon: resolveAppIconName(icon, fallbackIcon),
    iconLabel,
    backgroundColor: resolvedSurface.backgroundColor,
    iconColor: resolvedSurface.iconColor,
  };
}

function iconSourceColorForThemeTone(theme: MD3Theme, tone: IconSurfaceTone): string {
  if (tone === 'primary') return theme.colors.primary;
  if (tone === 'secondary') return theme.colors.secondary;
  if (tone === 'tertiary') return theme.colors.tertiary;
  if (tone === 'positive' || tone === 'income') return theme.dark ? '#8ED99F' : INCOME_ICON_COLOR;
  if (tone === 'expense' || tone === 'danger') return theme.colors.error || EXPENSE_ICON_COLOR;
  if (tone === 'transfer' || tone === 'adjustment' || tone === 'plan')
    return theme.colors.tertiary || TRANSFER_ICON_COLOR;
  if (tone === 'account' || tone === 'loan')
    return theme.colors.secondary || DEFAULT_ICON_BACKGROUND;
  if (tone === 'category' || tone === 'record') return theme.colors.primary;
  if (tone === 'widget') return theme.colors.primary;
  if (tone === 'warning') return theme.dark ? '#FFD36E' : WARNING_ICON_COLOR;
  if (tone === 'neutral') return theme.colors.onSurfaceVariant || NEUTRAL_ICON_COLOR;
  return theme.colors.onSurfaceVariant || NEUTRAL_ICON_COLOR;
}
