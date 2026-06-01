import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import {
    Button,
    IconButton,
    Snackbar,
    Surface,
    Text,
    TouchableRipple,
    useTheme,
} from 'react-native-paper';
import { AppScreen } from '../src/components/AppKit';
import { iconSurfaceForThemeTone } from '../src/iconSystem';
import {
    HOME_WIDGETS,
    HOME_WIDGET_IDS,
    HOME_WIDGET_META,
    isHomeWidgetVisible,
    normalizeHomeWidgetPreferences,
    resetHomeWidgetPreferences,
    restoreHomeWidgetPreference,
    toStoredHomeWidgetPreferences,
    type HomeWidgetId,
    type HomeWidgetMeta,
} from '../src/widgets/homeWidgetTypes';

const REPORT_WIDGET_IDS: readonly HomeWidgetId[] = [
  'balanceHero',
  'cashflowBook',
  'topCategories',
  'incomeMix',
  'budgetPressure',
  'goalProgress',
  'accountGroups',
];
const REPORT_WIDGET_ID_SET = new Set<HomeWidgetId>(REPORT_WIDGET_IDS);

const WIDGET_GROUPS: { title: string; ids: HomeWidgetId[] }[] = [
  { title: 'Reports', ids: [...REPORT_WIDGET_IDS] },
  {
    title: 'Dashboard',
    ids: HOME_WIDGET_IDS.filter((id) => !REPORT_WIDGET_ID_SET.has(id)),
  },
];

export default function Widgets() {
  const theme = useTheme();
  const { state, mutate } = useLedger();
  const [snackbar, setSnackbar] = useState<string | null>(null);
  const preferences = useMemo(
    () => normalizeHomeWidgetPreferences(state.preferences.homeWidgets),
    [state.preferences.homeWidgets],
  );

  const addWidget = useCallback(
    (id: HomeWidgetId) => {
      const title = HOME_WIDGET_META[id].title;
      void mutate((draft) => {
        const current = normalizeHomeWidgetPreferences(draft.preferences.homeWidgets);
        draft.preferences.homeWidgets = toStoredHomeWidgetPreferences(
          restoreHomeWidgetPreference(current, id),
        );
      })
        .then(() => setSnackbar(`${title} added to Home`))
        .catch((error) => setSnackbar(`Could not add ${title}: ${(error as Error).message}`));
    },
    [mutate],
  );

  const resetWidgets = useCallback(() => {
    void mutate((draft) => {
      draft.preferences.homeWidgets = toStoredHomeWidgetPreferences(resetHomeWidgetPreferences());
    })
      .then(() => setSnackbar('Home widgets reset'))
      .catch((error) => setSnackbar(`Could not reset widgets: ${(error as Error).message}`));
  }, [mutate]);

  const visibleCount = preferences.order.length;

  return (
    <>
      <AppScreen
        title="Widgets"
        back={false}
        drawer
        subtitle="Choose the tiles that belong on Home."
        actions={[
          { icon: 'home-outline', label: 'Home', onPress: () => router.push('/(tabs)/home') },
        ]}
      >
        <View
          style={[
            styles.summaryBand,
            {
              backgroundColor: theme.colors.elevation.level1,
              borderColor: theme.colors.outlineVariant,
            },
          ]}
        >
          <View style={styles.summaryCopy}>
            <Text variant="titleMedium" style={styles.summaryTitle}>
              {visibleCount} on Home
            </Text>
            <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
              {HOME_WIDGETS.length - visibleCount} available to add
            </Text>
          </View>
          <Button compact mode="contained-tonal" icon="restart" onPress={resetWidgets}>
            Reset
          </Button>
        </View>

        {WIDGET_GROUPS.map((group) => (
          <View key={group.title} style={styles.group}>
            <Text variant="titleMedium" style={styles.groupTitle}>
              {group.title}
            </Text>
            <View style={styles.tileGrid}>
              {group.ids.map((id) => {
                const widget = HOME_WIDGET_META[id];
                const visible = isHomeWidgetVisible(preferences, id);
                return (
                  <WidgetGalleryTile
                    key={id}
                    widget={widget}
                    visible={visible}
                    onAdd={() => addWidget(id)}
                    onOpenHome={() => router.push('/(tabs)/home' as never)}
                  />
                );
              })}
            </View>
          </View>
        ))}
      </AppScreen>
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2200}>
        {snackbar}
      </Snackbar>
    </>
  );
}

function WidgetGalleryTile({
  widget,
  visible,
  onAdd,
  onOpenHome,
}: {
  widget: HomeWidgetMeta;
  visible: boolean;
  onAdd: () => void;
  onOpenHome: () => void;
}) {
  const theme = useTheme();
  const actionIcon = visible ? 'check' : 'plus';
  const actionColor = visible ? theme.colors.onPrimaryContainer : theme.colors.onSecondaryContainer;
  const actionBackground = visible
    ? theme.colors.primaryContainer
    : theme.colors.secondaryContainer;
  const tileIconSurface = iconSurfaceForThemeTone(theme, widget.iconTone);
  const handlePress = visible ? onOpenHome : onAdd;

  return (
    <Surface
      elevation={1}
      style={[
        styles.tile,
        {
          backgroundColor: visible ? theme.colors.elevation.level2 : theme.colors.elevation.level1,
          borderColor: visible ? theme.colors.primary : theme.colors.outlineVariant,
        },
      ]}
    >
      <TouchableRipple borderless style={styles.tileRipple} onPress={handlePress}>
        <View style={styles.tileContent}>
          <View style={[styles.tileIcon, { backgroundColor: tileIconSurface.backgroundColor }]}>
            <MaterialCommunityIcons
              name={widget.icon}
              size={21}
              color={tileIconSurface.iconColor}
            />
          </View>
          <View style={styles.tileCopy}>
            <Text variant="titleSmall" numberOfLines={1} style={styles.tileTitle}>
              {widget.title}
            </Text>
            <Text
              variant="bodySmall"
              numberOfLines={3}
              style={{ color: theme.colors.onSurfaceVariant }}
            >
              {widget.body}
            </Text>
          </View>
          <Text variant="labelSmall" style={{ color: theme.colors.onSurfaceVariant }}>
            {visible ? 'On Home' : 'Hidden'}
          </Text>
          <IconButton
            accessibilityLabel={visible ? `${widget.title} is on Home` : `Add ${widget.title}`}
            icon={actionIcon}
            mode="contained"
            size={17}
            iconColor={actionColor}
            containerColor={actionBackground}
            style={styles.cornerAction}
            onPress={handlePress}
          />
        </View>
      </TouchableRipple>
    </Surface>
  );
}

const styles = StyleSheet.create({
  summaryBand: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    padding: tokens.space.md,
  },
  summaryCopy: { flex: 1, minWidth: 0 },
  summaryTitle: { fontWeight: '800' },
  group: { gap: tokens.space.sm },
  groupTitle: { fontWeight: '800' },
  tileGrid: { gap: tokens.space.sm },
  tile: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  tileRipple: { borderRadius: tokens.radius.md },
  tileContent: {
    minHeight: 112,
    padding: tokens.space.md,
    paddingRight: 58,
    gap: tokens.space.sm,
  },
  tileIcon: {
    width: 38,
    height: 38,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  tileCopy: { gap: 2 },
  tileTitle: { fontWeight: '800' },
  cornerAction: {
    position: 'absolute',
    top: 8,
    right: 8,
  },
});
