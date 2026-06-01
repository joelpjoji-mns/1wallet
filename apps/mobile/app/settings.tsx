import type { ThemeAccentSource, ThemePreference } from '@1wallet/ledger';
import { enabledCurrencies } from '@1wallet/ledger/services';
import { useLedger } from '@1wallet/state';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import {
    Button,
    Dialog,
    Divider,
    Portal,
    Snackbar,
    Switch,
    Text,
    useTheme,
} from 'react-native-paper';
import {
    getAndroidNotificationPermissionStatus,
    openAndroidAppSettings,
    requestAndroidNotificationPermission,
    type AndroidRuntimePermissionStatus,
} from '../src/androidPermissions';
import { useAuth } from '../src/auth';
import {
    AppScreen,
    InfoRow,
    PremiumTextInput,
    QuickLink,
    SectionCard,
    type AppIconName,
} from '../src/components/AppKit';
import {
    OptionListOverlay,
    OptionSelectorRow,
    type OptionListItem,
} from '../src/components/OptionListOverlay';
import { ThemeAccentPicker } from '../src/components/ThemeAccentPicker';
import { buildEnabledCurrencyOptions, currencyOptionIcon } from '../src/currencyOptions';
import {
    buildNotificationInbox,
    normalizeNotificationPreferences,
    type AppNotificationChannel,
} from '../src/notifications';
import {
    DEFAULT_CUSTOM_ACCENT_COLOR,
    normalizeHexColor,
    normalizeThemeAccentPreference,
} from '../src/theme';
import { useWalletSignOut } from '../src/useWalletSignOut';

const LOCALE_OPTIONS: OptionListItem[] = [
  {
    value: 'en-IN',
    label: 'English (India)',
    description: 'Dates and money formatted for India',
    icon: 'translate',
  },
  {
    value: 'en-US',
    label: 'English (United States)',
    description: 'US date, number, and currency formatting',
    icon: 'translate',
  },
  {
    value: 'en-GB',
    label: 'English (United Kingdom)',
    description: 'UK date, number, and currency formatting',
    icon: 'translate',
  },
];

const THEME_OPTIONS: OptionListItem<ThemePreference>[] = [
  {
    value: 'system',
    label: 'System',
    description: 'Follow Android light or dark mode',
    icon: 'theme-light-dark',
  },
  {
    value: 'light',
    label: 'Light',
    description: 'Use the light Material You theme',
    icon: 'white-balance-sunny',
  },
  {
    value: 'dark',
    label: 'Dark',
    description: 'Use the dark Material You theme',
    icon: 'weather-night',
  },
  {
    value: 'amoled',
    label: 'AMOLED',
    description: 'Use black surfaces with Material You accents',
    icon: 'circle-opacity',
  },
];

const ACCENT_OPTIONS: OptionListItem<ThemeAccentSource>[] = [
  {
    value: 'system',
    label: 'System themed',
    description: 'Use your phone Material You accent',
    icon: 'cellphone-cog',
  },
  {
    value: 'custom',
    label: 'Custom color',
    description: 'Pick a wallet accent color',
    icon: 'palette-outline',
  },
];

const NOTIFICATION_CHANNELS: {
  channel: AppNotificationChannel;
  label: string;
  body: string;
  icon: AppIconName;
}[] = [
  {
    channel: 'reviewQueue',
    label: 'Review queue',
    body: 'Captured records waiting for approval.',
    icon: 'robot-outline',
  },
  {
    channel: 'scheduled',
    label: 'Scheduled records',
    body: 'Upcoming and overdue payments, transfers, bills, and income.',
    icon: 'calendar-clock-outline',
  },
  {
    channel: 'budgets',
    label: 'Budgets',
    body: 'Threshold and over-budget alerts.',
    icon: 'chart-timeline-variant',
  },
  {
    channel: 'goals',
    label: 'Goals',
    body: 'Goal deadline and progress warnings.',
    icon: 'bullseye-arrow',
  },
  {
    channel: 'accounts',
    label: 'Accounts and cards',
    body: 'Negative balances, card debt, and account-level warnings.',
    icon: 'wallet-outline',
  },
  {
    channel: 'imports',
    label: 'Imports',
    body: 'CSV and automation warnings or duplicates.',
    icon: 'file-alert-outline',
  },
];

type SettingsPicker = 'currency' | 'locale' | 'theme' | 'accent' | null;

const MANAGEMENT_LINKS = [
  {
    title: 'Sync',
    body: 'Google sign-in, cloud restore, background upload, and sync status.',
    icon: 'cloud-sync-outline',
    route: '/sync',
  },
  {
    title: 'Device permissions',
    body: 'Camera, photos, and location access with a clear reason for each prompt.',
    icon: 'shield-check-outline',
    route: '/device-permissions',
  },
  {
    title: 'Notifications',
    body: 'Review work, reminders, budgets, accounts, cards, and import alerts.',
    icon: 'bell-badge-outline',
    route: '/notifications',
  },
  {
    title: 'Currencies',
    body: 'Default currency, enabled currencies, exchange rates, and refresh status.',
    icon: 'currency-usd',
    route: '/currencies',
  },
  {
    title: 'Categories',
    body: 'Expense and income trees, hidden stats, archive controls.',
    icon: 'shape-outline',
    route: '/categories',
  },
  {
    title: 'Widgets',
    body: 'Add, restore, and review Home tiles for cashflow, trends, budgets, goals, and accounts.',
    icon: 'view-dashboard-outline',
    route: '/widgets',
  },
  {
    title: 'Import & backup',
    body: 'CSV, Wallet exports, native backups, notification captures, and duplicate checks.',
    icon: 'tray-arrow-down',
    route: '/imports',
  },
  {
    title: 'Cards',
    body: 'Statement cycle, dues, utilization, and payment flows.',
    icon: 'credit-card-outline',
    route: '/cards',
  },
  {
    title: 'Loans & EMI',
    body: 'Payoff calculator, schedules, and loan account tracking.',
    icon: 'bank-outline',
    route: '/loans',
  },
  {
    title: 'Recurring',
    body: 'Bills, subscriptions, expected income, and reminders.',
    icon: 'calendar-sync-outline',
    route: '/recurring',
  },
] as const;

export default function Settings() {
  const theme = useTheme();
  const { state, mutate, reset, setBaseCurrency: setLedgerBaseCurrency } = useLedger();
  const { authProvider, user } = useAuth();
  const { signOutWallet, signingOut } = useWalletSignOut();
  const [startDay, setStartDay] = useState(String(state.preferences.startDayOfMonth));
  const [picker, setPicker] = useState<SettingsPicker>(null);
  const [accentPickerVisible, setAccentPickerVisible] = useState(false);
  const [resetVisible, setResetVisible] = useState(false);
  const [snackbar, setSnackbar] = useState<string | null>(null);
  const [pushPermissionStatus, setPushPermissionStatus] =
    useState<AndroidRuntimePermissionStatus>('unavailable');
  const notificationSettings = normalizeNotificationPreferences(state.preferences.notifications);
  const notifications = buildNotificationInbox(state);
  const unreadNotifications = notifications.filter((notification) => !notification.read).length;
  const accentPreference = normalizeThemeAccentPreference(state.preferences.themeAccent);
  const savedCustomAccent = normalizeHexColor(state.preferences.themeAccent?.customColor);
  const currencyOptions = useMemo(
    () => buildEnabledCurrencyOptions(enabledCurrencies(state), [state.preferences.baseCurrency]),
    [state],
  );

  const saveMessage = (message: string) => setSnackbar(message);

  useEffect(() => {
    let mounted = true;
    void getAndroidNotificationPermissionStatus().then((status) => {
      if (mounted) setPushPermissionStatus(status);
    });
    return () => {
      mounted = false;
    };
  }, []);

  const setBaseCurrency = async (currency: string) => {
    await setLedgerBaseCurrency(currency);
    saveMessage('Base currency updated');
  };

  const setLocale = async (locale: string) => {
    await mutate((draft) => {
      draft.preferences.locale = locale;
    });
    saveMessage('Locale updated');
  };

  const setThemePreference = async (value: ThemePreference) => {
    await mutate((draft) => {
      draft.preferences.theme = value;
    });
    saveMessage('Theme preference saved');
  };

  const setSystemAccent = async () => {
    await mutate((draft) => {
      draft.preferences.themeAccent = {
        source: 'system',
        customColor: normalizeHexColor(draft.preferences.themeAccent?.customColor),
      };
    });
    saveMessage('System accent enabled');
  };

  const setCustomAccent = async (color: string) => {
    const normalized = normalizeHexColor(color) ?? DEFAULT_CUSTOM_ACCENT_COLOR;
    await mutate((draft) => {
      draft.preferences.themeAccent = { source: 'custom', customColor: normalized };
    });
    setAccentPickerVisible(false);
    saveMessage('Custom accent saved');
  };

  const saveStartDay = async () => {
    const day = Number(startDay);
    if (!Number.isInteger(day) || day < 1 || day > 28) {
      saveMessage('Start day must be between 1 and 28');
      return;
    }

    await mutate((draft) => {
      draft.preferences.startDayOfMonth = day;
    });
    saveMessage('Month start day updated');
  };

  const setNotificationsEnabled = async (enabled: boolean) => {
    await mutate((draft) => {
      draft.preferences.notifications = {
        ...normalizeNotificationPreferences(draft.preferences.notifications),
        enabled,
      };
    });
    saveMessage(enabled ? 'Notifications enabled' : 'Notifications paused');
  };

  const setPushNotificationsEnabled = async (enabled: boolean) => {
    if (enabled) {
      const status = await requestAndroidNotificationPermission();
      setPushPermissionStatus(status);
      if (status !== 'granted') {
        saveMessage(
          status === 'blocked'
            ? 'Enable notification permission in Android settings'
            : 'Notification permission not granted',
        );
        return;
      }
    }

    await mutate((draft) => {
      draft.preferences.notifications = {
        ...normalizeNotificationPreferences(draft.preferences.notifications),
        pushEnabled: enabled,
      };
    });
    saveMessage(enabled ? 'Android notifications enabled' : 'Android notifications paused');
  };

  const setQuietHoursEnabled = async (enabled: boolean) => {
    await mutate((draft) => {
      const current = normalizeNotificationPreferences(draft.preferences.notifications);
      draft.preferences.notifications = {
        ...current,
        quietHours: { ...current.quietHours, enabled },
      };
    });
    saveMessage(enabled ? 'Quiet hours enabled' : 'Quiet hours disabled');
  };

  const setNotificationChannelEnabled = async (
    channel: AppNotificationChannel,
    enabled: boolean,
  ) => {
    await mutate((draft) => {
      const current = normalizeNotificationPreferences(draft.preferences.notifications);
      draft.preferences.notifications = {
        ...current,
        channels: { ...current.channels, [channel]: enabled },
      };
    });
    saveMessage(enabled ? 'Notification channel enabled' : 'Notification channel paused');
  };

  const resetLedger = async () => {
    setResetVisible(false);
    await reset();
    saveMessage('Local ledger reset');
    router.replace('/' as never);
  };

  const logout = async () => {
    try {
      await signOutWallet();
      router.replace('/login' as never);
    } catch (err) {
      saveMessage(settingsErrorMessage(err, 'Could not back up and sign out.'));
    }
  };

  const pendingCaptures = state.captureCandidates.filter(
    (candidate) => candidate.status === 'pending',
  );

  return (
    <>
      <AppScreen
        title="Settings"
        back={false}
        drawer
        subtitle="Control your ledger, automation, privacy, and mobile workflow."
        actions={[
          { icon: 'robot-outline', label: 'Review queue', onPress: () => router.push('/review') },
        ]}
      >
        <SectionCard title="Profile" subtitle="Current auth mode and account actions.">
          <InfoRow
            icon="account-circle-outline"
            label="Signed in as"
            value={user?.email ?? 'Local user'}
          />
          <InfoRow
            icon="cloud-check-outline"
            label="Sync mode"
            value={authModeLabel(authProvider)}
          />
          <Button
            mode="contained-tonal"
            icon="logout-variant"
            onPress={() => void logout()}
            loading={signingOut}
            disabled={signingOut}
          >
            {signingOut ? 'Backing up wallet' : 'Sign out'}
          </Button>
        </SectionCard>

        <SectionCard title="Preferences" subtitle="Used by reports, forms, and dashboard widgets.">
          <OptionSelectorRow
            label="Base currency"
            value={optionLabel(currencyOptions, state.preferences.baseCurrency)}
            description="Default money unit for totals and reports"
            icon={currencyOptionIcon(state.preferences.baseCurrency)}
            onPress={() => setPicker('currency')}
          />

          <OptionSelectorRow
            label="Locale"
            value={optionLabel(LOCALE_OPTIONS, state.preferences.locale)}
            description="Number, date, and money formatting"
            icon="translate"
            onPress={() => setPicker('locale')}
          />

          <View style={styles.inlineForm}>
            <PremiumTextInput
              label="Month starts on day"
              value={startDay}
              onChangeText={setStartDay}
              keyboardType="number-pad"
              style={styles.dayInput}
            />
            <Button mode="contained-tonal" onPress={() => void saveStartDay()}>
              Save
            </Button>
          </View>

          <OptionSelectorRow
            label="Theme"
            value={optionLabel(THEME_OPTIONS, state.preferences.theme)}
            description="Material You color mode"
            icon="theme-light-dark"
            onPress={() => setPicker('theme')}
          />

          <OptionSelectorRow
            label="Accent"
            value={accentValueLabel(accentPreference.source)}
            description="Drawer, filters, buttons, and navigation color"
            icon="palette-outline"
            onPress={() => setPicker('accent')}
          />
        </SectionCard>

        <SectionCard title="Feature hub" subtitle="The overkill surfaces for the finance engine.">
          {MANAGEMENT_LINKS.map((link, index) => (
            <View key={link.route}>
              <QuickLink
                icon={link.icon}
                title={link.title}
                body={link.body}
                onPress={() => router.push(link.route as never)}
              />
              {index < MANAGEMENT_LINKS.length - 1 && <Divider />}
            </View>
          ))}
        </SectionCard>

        <SectionCard
          title="Capture & automation"
          subtitle="Manual review stays in control before automation posts anything."
        >
          <InfoRow
            icon="inbox-arrow-down-outline"
            label="Pending review"
            value={String(pendingCaptures.length)}
          />
          <InfoRow
            icon="bell-outline"
            label="Notifications"
            value={notificationSettings.enabled ? `${unreadNotifications} unread` : 'Paused'}
            tone={unreadNotifications ? 'warning' : 'positive'}
          />
          <InfoRow
            icon="message-text-outline"
            label="Auto Capture"
            value="SMS ready"
            tone="positive"
          />
          <InfoRow icon="file-table-outline" label="CSV imports" value="Ready" tone="positive" />
          <Button
            mode="contained-tonal"
            icon="robot-outline"
            onPress={() => router.push('/review')}
          >
            Open review queue
          </Button>
          <Button
            mode="contained-tonal"
            icon="bell-badge-outline"
            onPress={() => router.push('/notifications' as never)}
          >
            Open notifications
          </Button>
          <Button
            mode="contained-tonal"
            icon="message-processing-outline"
            onPress={() => router.push('/auto-capture' as never)}
          >
            Open Auto Capture
          </Button>
        </SectionCard>

        <SectionCard
          title="Notifications"
          subtitle="Local-first finance alerts generated from the ledger."
        >
          <View style={styles.switchRow}>
            <View style={styles.switchCopy}>
              <Text variant="titleSmall">Notification inbox</Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                {notifications.length} active signals across review, reminders, budgets, accounts,
                and imports.
              </Text>
            </View>
            <Switch
              value={notificationSettings.enabled}
              onValueChange={(value) => void setNotificationsEnabled(value)}
            />
          </View>
          <Divider />
          <View style={styles.switchRow}>
            <View style={styles.switchCopy}>
              <Text variant="titleSmall">Android notifications</Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                {notificationPermissionLabel(pushPermissionStatus)}
              </Text>
            </View>
            <Switch
              value={notificationSettings.pushEnabled && pushPermissionStatus === 'granted'}
              disabled={!notificationSettings.enabled}
              onValueChange={(value) => void setPushNotificationsEnabled(value)}
            />
          </View>
          {pushPermissionStatus === 'blocked' ? (
            <Button
              mode="contained-tonal"
              icon="cellphone-cog"
              onPress={() => void openAndroidAppSettings()}
            >
              Open Android settings
            </Button>
          ) : null}
          <Divider />
          <View style={styles.switchRow}>
            <View style={styles.switchCopy}>
              <Text variant="titleSmall">Quiet hours</Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                {notificationSettings.quietHours.start} to {notificationSettings.quietHours.end}
              </Text>
            </View>
            <Switch
              value={notificationSettings.quietHours.enabled}
              disabled={!notificationSettings.enabled}
              onValueChange={(value) => void setQuietHoursEnabled(value)}
            />
          </View>
          <InfoRow icon="bell-badge-outline" label="Unread" value={String(unreadNotifications)} />
          <Divider />
          {NOTIFICATION_CHANNELS.map((item, index) => (
            <View key={item.channel}>
              <View style={styles.switchRow}>
                <View style={styles.channelCopy}>
                  <MaterialCommunityIcons name={item.icon} size={20} color={theme.colors.primary} />
                  <View style={styles.switchCopy}>
                    <Text variant="titleSmall">{item.label}</Text>
                    <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                      {item.body}
                    </Text>
                  </View>
                </View>
                <Switch
                  value={notificationSettings.channels[item.channel]}
                  disabled={!notificationSettings.enabled}
                  onValueChange={(value) => void setNotificationChannelEnabled(item.channel, value)}
                />
              </View>
              {index < NOTIFICATION_CHANNELS.length - 1 ? <Divider /> : null}
            </View>
          ))}
          <Button
            mode="contained-tonal"
            icon="bell-outline"
            onPress={() => router.push('/notifications' as never)}
          >
            Open notification inbox
          </Button>
        </SectionCard>

        <SectionCard
          title="Security & privacy"
          subtitle="Local-first until cloud sync is configured."
        >
          <View style={styles.switchRow}>
            <View style={styles.switchCopy}>
              <Text variant="titleSmall">Privacy mode</Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                Hide amounts in widgets and screenshots once native widgets are added.
              </Text>
            </View>
            <Switch value={false} disabled />
          </View>
          <View style={styles.switchRow}>
            <View style={styles.switchCopy}>
              <Text variant="titleSmall">Biometric lock</Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                Requires a native security slice after the app shell is stable.
              </Text>
            </View>
            <Switch value={false} disabled />
          </View>
        </SectionCard>

        <SectionCard title="Data" subtitle="Useful while developing the local ledger.">
          <InfoRow icon="database-outline" label="Accounts" value={String(state.accounts.length)} />
          <InfoRow
            icon="swap-horizontal"
            label="Transactions"
            value={String(state.transactions.length)}
          />
          <InfoRow
            icon="shape-outline"
            label="Categories"
            value={String(state.categories.length)}
          />
          <Button
            mode="contained"
            icon="database-import-outline"
            onPress={() => router.push('/imports' as never)}
          >
            Open import & backup
          </Button>
          <Button
            mode="contained-tonal"
            icon="file-table-outline"
            onPress={() => router.push('/import-wallet-csv' as never)}
          >
            Wallet CSV reset/import
          </Button>
          <Button
            mode="contained-tonal"
            icon="delete-alert-outline"
            onPress={() => setResetVisible(true)}
          >
            Reset local ledger
          </Button>
        </SectionCard>
      </AppScreen>

      <OptionListOverlay
        visible={picker === 'currency'}
        title="Base currency"
        options={currencyOptions}
        selectedValue={state.preferences.baseCurrency}
        searchPlaceholder="Search currencies"
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setPicker(null);
          void setBaseCurrency(option.value);
        }}
      />

      <OptionListOverlay
        visible={picker === 'locale'}
        title="Locale"
        options={LOCALE_OPTIONS}
        selectedValue={state.preferences.locale}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setPicker(null);
          void setLocale(option.value);
        }}
      />

      <OptionListOverlay
        visible={picker === 'theme'}
        title="Theme"
        options={THEME_OPTIONS}
        selectedValue={state.preferences.theme}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setPicker(null);
          void setThemePreference(option.value);
        }}
      />

      <OptionListOverlay
        visible={picker === 'accent'}
        title="Accent"
        options={ACCENT_OPTIONS}
        selectedValue={accentPreference.source}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setPicker(null);
          if (option.value === 'system') {
            void setSystemAccent();
            return;
          }
          setAccentPickerVisible(true);
        }}
      />

      <ThemeAccentPicker
        visible={accentPickerVisible}
        initialColor={
          savedCustomAccent ?? accentPreference.customColor ?? DEFAULT_CUSTOM_ACCENT_COLOR
        }
        onDismiss={() => setAccentPickerVisible(false)}
        onSave={(color) => void setCustomAccent(color)}
      />

      <Portal>
        <Dialog visible={resetVisible} onDismiss={() => setResetVisible(false)}>
          <Dialog.Title>Reset local ledger?</Dialog.Title>
          <Dialog.Content>
            <Text variant="bodyMedium">
              This clears local accounts, transactions, budgets, goals, and capture candidates on
              this device.
            </Text>
          </Dialog.Content>
          <Dialog.Actions>
            <Button onPress={() => setResetVisible(false)}>Cancel</Button>
            <Button textColor={theme.colors.error} onPress={() => void resetLedger()}>
              Reset
            </Button>
          </Dialog.Actions>
        </Dialog>
      </Portal>
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2200}>
        {snackbar}
      </Snackbar>
    </>
  );
}

function optionLabel(options: readonly OptionListItem[], value: string) {
  return options.find((option) => option.value === value)?.label ?? value;
}

function accentValueLabel(source: ThemeAccentSource): string {
  return source === 'custom' ? 'Custom color' : 'System themed';
}

function authModeLabel(provider: ReturnType<typeof useAuth>['authProvider']): string {
  if (provider === 'firebase') return 'Firebase';
  if (provider === 'supabase') return 'Supabase';
  return 'Local dev';
}

function notificationPermissionLabel(status: AndroidRuntimePermissionStatus): string {
  if (status === 'granted') return 'Native alerts can appear in Android notifications.';
  if (status === 'blocked') return 'Android permission is blocked for this app.';
  if (status === 'denied') return 'Android permission is needed for native alerts.';
  return 'Native alerts are available on Android devices.';
}

function settingsErrorMessage(err: unknown, fallback: string): string {
  return err instanceof Error && err.message ? err.message : fallback;
}

const styles = StyleSheet.create({
  inlineForm: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  dayInput: { flex: 1 },
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 16,
  },
  switchCopy: { flex: 1, gap: 2 },
  channelCopy: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12 },
});
