import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useState, type ComponentProps, type ReactNode } from 'react';
import {
    KeyboardAvoidingView,
    Platform,
    ScrollView,
    StyleSheet,
    View,
    type StyleProp,
    type TextStyle,
    type ViewStyle,
} from 'react-native';
import {
    Appbar,
    Button,
    TextInput as PaperTextInput,
    Searchbar,
    Surface,
    Text,
    TouchableRipple,
    useTheme,
    type MD3Theme,
} from 'react-native-paper';
import { withColorAlpha } from '../colorAlpha';
import { numericMediumFontFamily } from '../fonts';
import {
    APP_ICONS,
    iconSurfaceForCustomColor,
    iconSurfaceForThemeTone,
    iconTextColorForBackground,
    isAppIconName,
    resolveAppIconName,
    type AppIconName,
    type IconSurfaceTone,
} from '../iconSystem';
import { useOptionalAppDrawer } from './AppDrawerHost';

export { APP_ICONS, iconTextColorForBackground, isAppIconName, resolveAppIconName };
export type { AppIconName };

export const TAB_BAR_OVERLAY_CLEARANCE = tokens.size.bottomBar + tokens.space.xl + tokens.space.lg;
export const TAB_FAB_BOTTOM_OFFSET = 18;

export function goBackOrHome() {
  if (router.canGoBack()) {
    router.back();
    return;
  }
  router.replace('/(tabs)/home' as never);
}

export function AppMenuAction({ onPress }: { onPress: () => void }) {
  const theme = useTheme();

  return (
    <TouchableRipple
      accessibilityLabel="Open navigation"
      accessibilityRole="button"
      borderless
      hitSlop={8}
      onPress={onPress}
      rippleColor={withColorAlpha(theme.colors.primary, theme.dark ? 0.2 : 0.12)}
      style={[
        s.menuAction,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: withColorAlpha(theme.colors.outline, theme.dark ? 0.34 : 0.22),
        },
      ]}
    >
      <View style={s.menuActionInner}>
        <MaterialCommunityIcons
          name={APP_ICONS.navigation.menu}
          size={22}
          color={theme.colors.primary}
        />
      </View>
    </TouchableRipple>
  );
}

type AppScreenAction = {
  icon: AppIconName;
  label: string;
  onPress: () => void;
};

type SurfaceTone = Extract<
  IconSurfaceTone,
  'default' | 'primary' | 'secondary' | 'tertiary' | 'danger' | 'warning'
>;

type PremiumFieldState = {
  focused?: boolean;
  error?: boolean;
  disabled?: boolean;
  selected?: boolean;
};

type PremiumTextInputProps = ComponentProps<typeof PaperTextInput>;
type PremiumSearchInputProps = ComponentProps<typeof Searchbar>;

export function premiumFieldColors(theme: MD3Theme, state: PremiumFieldState = {}) {
  if (state.disabled) {
    return {
      background: theme.colors.surfaceDisabled,
      border: withColorAlpha(theme.colors.outline, 0.22),
      activeBorder: withColorAlpha(theme.colors.outline, 0.32),
      text: theme.colors.onSurfaceDisabled,
      placeholder: theme.colors.onSurfaceDisabled,
    };
  }

  if (state.error) {
    return {
      background: theme.colors.elevation.level1,
      border: withColorAlpha(theme.colors.error, 0.72),
      activeBorder: theme.colors.error,
      text: theme.colors.onSurface,
      placeholder: theme.colors.onSurfaceVariant,
    };
  }

  if (state.selected || state.focused) {
    return {
      background: theme.colors.elevation.level2,
      border: withColorAlpha(theme.colors.primary, state.focused ? 0.9 : 0.58),
      activeBorder: theme.colors.primary,
      text: theme.colors.onSurface,
      placeholder: theme.colors.onSurfaceVariant,
    };
  }

  return {
    background: theme.colors.elevation.level1,
    border: withColorAlpha(theme.colors.outline, 0.34),
    activeBorder: theme.colors.primary,
    text: theme.colors.onSurface,
    placeholder: theme.colors.onSurfaceVariant,
  };
}

export function premiumSurfaceBorder(theme: MD3Theme, selected = false) {
  return selected
    ? withColorAlpha(theme.colors.primary, 0.72)
    : withColorAlpha(theme.colors.outline, 0.28);
}

export function PremiumTextInput({
  mode = 'outlined',
  style,
  outlineStyle,
  activeOutlineColor,
  outlineColor,
  textColor,
  placeholderTextColor,
  onFocus,
  onBlur,
  error,
  disabled,
  editable,
  ...props
}: PremiumTextInputProps) {
  const theme = useTheme();
  const [focused, setFocused] = useState(false);
  const muted = Boolean(disabled) || editable === false;
  const colors = premiumFieldColors(theme, { focused, error: Boolean(error), disabled: muted });

  return (
    <PaperTextInput
      {...props}
      mode={mode}
      error={error}
      disabled={disabled}
      editable={editable}
      outlineColor={outlineColor ?? colors.border}
      activeOutlineColor={activeOutlineColor ?? colors.activeBorder}
      textColor={textColor ?? colors.text}
      placeholderTextColor={placeholderTextColor ?? colors.placeholder}
      style={[s.premiumTextInput, { backgroundColor: colors.background }, style]}
      outlineStyle={[s.premiumTextInputOutline, outlineStyle]}
      onFocus={(event) => {
        setFocused(true);
        onFocus?.(event);
      }}
      onBlur={(event) => {
        setFocused(false);
        onBlur?.(event);
      }}
    />
  );
}

export function PremiumSearchInput({
  style,
  inputStyle,
  iconColor,
  ...props
}: PremiumSearchInputProps) {
  const theme = useTheme();
  const colors = premiumFieldColors(theme);

  return (
    <Searchbar
      {...props}
      iconColor={iconColor ?? theme.colors.primary}
      inputStyle={[s.premiumSearchInputText, inputStyle]}
      style={[
        s.premiumSearchInput,
        {
          backgroundColor: colors.background,
          borderColor: colors.border,
        },
        style,
      ]}
    />
  );
}

export function AppScreen({
  title,
  subtitle,
  children,
  scroll = true,
  back = true,
  drawer = false,
  actions = [],
  contentStyle,
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
  scroll?: boolean;
  back?: boolean;
  drawer?: boolean;
  actions?: AppScreenAction[];
  contentStyle?: ViewStyle;
}) {
  const theme = useTheme();
  const appDrawer = useOptionalAppDrawer();
  const showDrawerButton = drawer && !back && Boolean(appDrawer);

  return (
    <View style={[s.screen, { backgroundColor: theme.colors.background }]}>
      <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
        {back ? <Appbar.BackAction onPress={goBackOrHome} /> : null}
        {showDrawerButton ? <AppMenuAction onPress={() => appDrawer?.openDrawer()} /> : null}
        <Appbar.Content title={title} titleStyle={s.appbarTitle} />
        {actions.map((action) => (
          <Appbar.Action
            key={action.label}
            icon={action.icon}
            accessibilityLabel={action.label}
            onPress={action.onPress}
          />
        ))}
      </Appbar.Header>
      {scroll ? (
        <KeyboardAvoidingView
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
          keyboardVerticalOffset={0}
          style={s.fill}
        >
          <ScrollView
            contentContainerStyle={[s.content, contentStyle]}
            keyboardDismissMode="on-drag"
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            {subtitle ? (
              <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                {subtitle}
              </Text>
            ) : null}
            {children}
          </ScrollView>
        </KeyboardAvoidingView>
      ) : (
        <View style={[s.content, s.fill, contentStyle]}>{children}</View>
      )}
    </View>
  );
}

export function SectionCard({
  title,
  subtitle,
  actionLabel,
  actionIcon = 'chevron-right',
  onAction,
  children,
  variant = 'filled',
  compact = false,
}: {
  title: string;
  subtitle?: string;
  actionLabel?: string;
  actionIcon?: AppIconName;
  onAction?: () => void;
  children: ReactNode;
  variant?: 'filled' | 'elevated' | 'outlined';
  compact?: boolean;
}) {
  const theme = useTheme();
  const sectionBackground =
    variant === 'outlined' ? theme.colors.elevation.level0 : theme.colors.elevation.level1;

  return (
    <Surface
      style={[
        s.section,
        {
          backgroundColor: sectionBackground,
          borderColor: premiumSurfaceBorder(theme, variant === 'elevated'),
        },
        compact && s.sectionCompact,
      ]}
      elevation={variant === 'elevated' ? 2 : 1}
    >
      <View style={s.sectionHeader}>
        <View style={s.fill}>
          <Text variant="titleMedium" style={s.sectionTitle}>
            {title}
          </Text>
          {subtitle ? (
            <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
              {subtitle}
            </Text>
          ) : null}
        </View>
        {actionLabel && onAction ? (
          <Button compact mode="text" icon={actionIcon} onPress={onAction}>
            {actionLabel}
          </Button>
        ) : null}
      </View>
      {children}
    </Surface>
  );
}

export function IconBubble({
  icon,
  tone = 'default',
  size = 40,
  backgroundColor,
  iconColor,
}: {
  icon: AppIconName;
  tone?: SurfaceTone;
  size?: 36 | 40 | 44 | 48 | 56;
  backgroundColor?: string;
  iconColor?: string;
}) {
  const theme = useTheme();
  const colors = resolveToneColors(theme, tone);
  const resolvedBackgroundColor = backgroundColor ?? colors.container;
  const resolvedIconColor =
    iconColor ??
    (backgroundColor ? iconSurfaceForCustomColor(backgroundColor).iconColor : colors.content);

  return (
    <View
      style={[
        s.iconBubble,
        {
          width: size,
          height: size,
          borderRadius: size / 2,
          backgroundColor: resolvedBackgroundColor,
        },
      ]}
    >
      <MaterialCommunityIcons name={icon} size={size >= 48 ? 24 : 20} color={resolvedIconColor} />
    </View>
  );
}

export function PremiumRow({
  icon,
  title,
  subtitle,
  meta,
  titleNumberOfLines = 1,
  selected = false,
  disabled = false,
  tone = 'default',
  style,
  iconBackgroundColor,
  iconColor,
  onPress,
}: {
  icon: AppIconName;
  title: string;
  subtitle?: string;
  meta?: string;
  titleNumberOfLines?: number;
  selected?: boolean;
  disabled?: boolean;
  tone?: SurfaceTone;
  style?: ViewStyle;
  iconBackgroundColor?: string;
  iconColor?: string;
  onPress: () => void;
}) {
  const theme = useTheme();
  const colors = resolveToneColors(theme, selected ? 'primary' : tone);
  const fieldColors = premiumFieldColors(theme, { selected, disabled });

  return (
    <TouchableRipple
      disabled={disabled}
      style={[
        s.premiumRow,
        {
          backgroundColor: selected ? theme.colors.primaryContainer : fieldColors.background,
          borderColor: selected ? fieldColors.activeBorder : fieldColors.border,
        },
        disabled && s.disabled,
        style,
      ]}
      rippleColor={colors.container}
      onPress={onPress}
      borderless
    >
      <View style={s.premiumRowInner}>
        <IconBubble
          icon={icon}
          tone={selected ? 'primary' : tone}
          backgroundColor={iconBackgroundColor}
          iconColor={iconColor}
        />
        <View style={s.fill}>
          <Text variant="titleSmall" numberOfLines={titleNumberOfLines} style={s.premiumRowTitle}>
            {title}
          </Text>
          {subtitle ? (
            <Text
              variant="bodySmall"
              numberOfLines={2}
              style={{ color: theme.colors.onSurfaceVariant }}
            >
              {subtitle}
            </Text>
          ) : null}
        </View>
        {meta ? (
          <Text variant="labelMedium" numberOfLines={1} style={{ color: colors.content }}>
            {meta}
          </Text>
        ) : null}
        <MaterialCommunityIcons
          name={selected ? 'check-circle' : 'chevron-right'}
          size={tokens.icon.lg}
          color={selected ? theme.colors.primary : theme.colors.onSurfaceVariant}
        />
      </View>
    </TouchableRipple>
  );
}

export function EmptyState({
  icon,
  title,
  body,
  actionLabel,
  onAction,
}: {
  icon: AppIconName;
  title: string;
  body: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  const theme = useTheme();
  const iconSurface = iconSurfaceForThemeTone(theme, 'neutral');

  return (
    <View style={s.emptyState}>
      <View style={[s.emptyIcon, { backgroundColor: iconSurface.backgroundColor }]}>
        <MaterialCommunityIcons name={icon} size={28} color={iconSurface.iconColor} />
      </View>
      <Text variant="titleMedium" style={s.centerText}>
        {title}
      </Text>
      <Text variant="bodyMedium" style={[s.centerText, { color: theme.colors.onSurfaceVariant }]}>
        {body}
      </Text>
      {actionLabel && onAction ? (
        <Button mode="contained-tonal" onPress={onAction}>
          {actionLabel}
        </Button>
      ) : null}
    </View>
  );
}

export function InfoRow({
  label,
  value,
  icon,
  iconBackgroundColor,
  iconColor,
  tone = 'default',
}: {
  label: string;
  value: string;
  icon?: AppIconName;
  iconBackgroundColor?: string;
  iconColor?: string;
  tone?: 'default' | 'positive' | 'danger' | 'warning';
}) {
  const theme = useTheme();
  const iconSurface = iconBackgroundColor
    ? iconSurfaceForCustomColor(iconBackgroundColor)
    : iconSurfaceForThemeTone(theme, infoToneToIconTone(tone));
  const color =
    tone === 'positive'
      ? theme.colors.tertiary
      : tone === 'danger'
        ? theme.colors.error
        : tone === 'warning'
          ? theme.colors.secondary
          : theme.colors.onSurface;

  return (
    <View style={s.infoRow}>
      <View style={s.infoLabelWrap}>
        {icon ? (
          <View style={[s.infoIconBubble, { backgroundColor: iconSurface.backgroundColor }]}>
            <MaterialCommunityIcons
              name={icon}
              size={tokens.icon.sm}
              color={iconColor ?? iconSurface.iconColor}
            />
          </View>
        ) : null}
        <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
          {label}
        </Text>
      </View>
      <Text variant="bodyMedium" style={[s.infoValue, { color }]}>
        {value}
      </Text>
    </View>
  );
}

export function InlineMeta({
  items,
  numberOfLines = 1,
  style,
}: {
  items: Array<string | null | undefined | false>;
  numberOfLines?: number;
  style?: StyleProp<TextStyle>;
}) {
  const theme = useTheme();
  const values = items
    .map((item) => (typeof item === 'string' ? item.trim() : ''))
    .filter((item) => item.length > 0);

  if (!values.length) return null;

  return (
    <Text
      variant="labelMedium"
      numberOfLines={numberOfLines}
      style={[s.inlineMeta, { color: theme.colors.onSurfaceVariant }, style]}
    >
      {values.join(' / ')}
    </Text>
  );
}

export function QuickLink({
  icon,
  title,
  body,
  badge,
  onPress,
}: {
  icon: AppIconName;
  title: string;
  body: string;
  badge?: string;
  onPress: () => void;
}) {
  const theme = useTheme();
  const iconSurface = iconSurfaceForThemeTone(theme, 'secondary');

  return (
    <TouchableRipple style={s.quickLink} onPress={onPress} borderless>
      <View style={s.quickLinkInner}>
        <View style={[s.quickLinkIcon, { backgroundColor: iconSurface.backgroundColor }]}>
          <MaterialCommunityIcons name={icon} size={22} color={iconSurface.iconColor} />
        </View>
        <View style={s.fill}>
          <Text variant="titleSmall">{title}</Text>
          <Text
            variant="bodySmall"
            style={{ color: theme.colors.onSurfaceVariant }}
            numberOfLines={2}
          >
            {body}
          </Text>
        </View>
        {badge ? (
          <Text variant="labelMedium" style={{ color: theme.colors.secondary }}>
            {badge}
          </Text>
        ) : null}
        <MaterialCommunityIcons
          name="chevron-right"
          size={20}
          color={theme.colors.onSurfaceVariant}
        />
      </View>
    </TouchableRipple>
  );
}

export function MetricTile({
  label,
  value,
  icon,
  tone = 'default',
  compact = false,
  onPress,
}: {
  label: string;
  value: string;
  icon: AppIconName;
  tone?: 'default' | 'positive' | 'danger' | 'warning';
  compact?: boolean;
  onPress?: () => void;
}) {
  const theme = useTheme();
  const iconSurface = iconSurfaceForThemeTone(theme, metricToneToIconTone(tone));
  const iconColor =
    tone === 'positive'
      ? theme.colors.tertiary
      : tone === 'danger'
        ? theme.colors.error
        : tone === 'warning'
          ? theme.colors.secondary
          : theme.colors.primary;

  const content = (
    <Surface
      style={[
        s.metricTile,
        compact && s.metricTileCompact,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: premiumSurfaceBorder(theme),
        },
      ]}
      elevation={1}
    >
      <View
        style={[
          s.metricIconBubble,
          compact && s.metricIconBubbleCompact,
          { backgroundColor: iconSurface.backgroundColor },
        ]}
      >
        <MaterialCommunityIcons
          name={icon}
          size={compact ? 16 : 18}
          color={iconSurface.iconColor || iconColor}
        />
      </View>
      <Text
        variant={compact ? 'labelSmall' : 'labelMedium'}
        style={{ color: theme.colors.onSurfaceVariant }}
      >
        {label}
      </Text>
      <Text
        variant={compact ? 'titleSmall' : 'titleMedium'}
        style={s.metricValue}
        numberOfLines={1}
        adjustsFontSizeToFit
        minimumFontScale={0.72}
      >
        {value}
      </Text>
    </Surface>
  );

  if (!onPress) return content;

  return (
    <TouchableRipple onPress={onPress} style={s.metricTileAction} borderless>
      {content}
    </TouchableRipple>
  );
}

function resolveToneColors(theme: MD3Theme, tone: SurfaceTone) {
  const surface = iconSurfaceForThemeTone(theme, tone === 'danger' ? 'danger' : tone);
  return { container: surface.backgroundColor, content: surface.iconColor };
}

function infoToneToIconTone(tone: 'default' | 'positive' | 'danger' | 'warning'): IconSurfaceTone {
  if (tone === 'positive') return 'income';
  if (tone === 'danger') return 'danger';
  if (tone === 'warning') return 'warning';
  return 'neutral';
}

function metricToneToIconTone(
  tone: 'default' | 'positive' | 'danger' | 'warning',
): IconSurfaceTone {
  if (tone === 'positive') return 'income';
  if (tone === 'danger') return 'danger';
  if (tone === 'warning') return 'warning';
  return 'widget';
}

export const s = StyleSheet.create({
  screen: { flex: 1 },
  fill: { flex: 1 },
  content: { padding: tokens.space.lg, gap: tokens.space.lg, paddingBottom: 96 },
  appbarTitle: { fontWeight: '700' },
  menuAction: {
    width: 48,
    height: 48,
    borderRadius: tokens.radius.pill,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
    marginLeft: tokens.space.xs,
    marginRight: tokens.space.xs,
  },
  menuActionInner: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  section: {
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    padding: tokens.space.lg,
    gap: tokens.space.md,
  },
  sectionCompact: { padding: tokens.space.md, gap: tokens.space.sm },
  sectionHeader: { flexDirection: 'row', alignItems: 'flex-start', gap: 12 },
  sectionTitle: { fontWeight: '700' },
  emptyState: {
    alignItems: 'center',
    justifyContent: 'center',
    gap: tokens.space.md,
    padding: tokens.space.xl,
  },
  emptyIcon: {
    width: 56,
    height: 56,
    borderRadius: tokens.radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
  },
  centerText: { textAlign: 'center' },
  infoRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 16 },
  infoLabelWrap: { flexDirection: 'row', alignItems: 'center', gap: 8, flexShrink: 1 },
  infoIconBubble: {
    width: 26,
    height: 26,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
  },
  infoValue: {
    fontFamily: numericMediumFontFamily,
    fontWeight: '700',
    flexShrink: 1,
    textAlign: 'right',
  },
  inlineMeta: { flexShrink: 1, lineHeight: 18 },
  quickLink: { borderRadius: tokens.radius.lg, overflow: 'hidden' },
  quickLinkInner: {
    minHeight: 56,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    paddingVertical: tokens.space.sm,
  },
  quickLinkIcon: {
    width: 44,
    height: 44,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  iconBubble: { alignItems: 'center', justifyContent: 'center' },
  premiumRow: {
    minHeight: tokens.size.rowLarge,
    borderWidth: 1,
    borderRadius: tokens.radius.lg,
    overflow: 'hidden',
  },
  premiumRowInner: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    paddingHorizontal: tokens.space.md,
    paddingVertical: tokens.space.sm,
  },
  premiumRowTitle: { fontWeight: '700' },
  disabled: { opacity: 0.5 },
  metricTile: {
    flex: 1,
    minWidth: 132,
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 14,
    gap: 6,
  },
  metricTileCompact: {
    minWidth: 0,
    minHeight: 74,
    padding: 10,
    gap: 3,
  },
  metricTileAction: { flex: 1, borderRadius: tokens.radius.lg, overflow: 'hidden' },
  metricIconBubble: {
    width: 30,
    height: 30,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
  },
  metricIconBubbleCompact: {
    width: 26,
    height: 26,
    borderRadius: 13,
  },
  metricValue: { fontFamily: numericMediumFontFamily, fontWeight: '800' },
  premiumTextInput: {
    minHeight: 58,
  },
  premiumTextInputOutline: {
    borderRadius: tokens.radius.lg,
    borderWidth: 1,
  },
  premiumSearchInput: {
    minHeight: 58,
    borderRadius: tokens.radius.lg,
    borderWidth: 1,
    elevation: 0,
  },
  premiumSearchInputText: {
    minHeight: 48,
  },
});
