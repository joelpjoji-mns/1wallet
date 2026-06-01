import { normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import type { Account, AccountType } from '@1wallet/domain/types';
import { nowIso } from '@1wallet/ledger/id';
import { createAccount } from '@1wallet/ledger/services';
import {
    normalizeAutoCapturePreferences,
    type OnboardingUseCase,
} from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { Redirect, router } from 'expo-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
    Alert,
    KeyboardAvoidingView,
    Platform,
    Pressable,
    ScrollView,
    StyleSheet,
    View,
} from 'react-native';
import { Button, Divider, HelperText, Text, TextInput, useTheme } from 'react-native-paper';
import { SafeAreaView } from 'react-native-safe-area-context';
import {
    ACCOUNT_COLOR_OPTIONS,
    ACCOUNT_ICON_OPTIONS,
    ACCOUNT_TYPE_OPTIONS,
    DEFAULT_ACCOUNT_COLOR,
    accountIconForType,
    readableTextColorForBackground,
    resolveAccountIconVisual,
} from '../src/accountOptions';
import {
    getAndroidLocationPermissionStatus,
    getAndroidNotificationPermissionStatus,
    getDeviceCameraPermissionStatus,
    getDevicePhotoLibraryPermissionStatus,
    openAndroidAppSettings,
    requestAndroidLocationPermission,
    requestAndroidNotificationPermission,
    requestDeviceCameraPermission,
    requestDevicePhotoLibraryPermission,
    type AndroidRuntimePermissionStatus,
} from '../src/androidPermissions';
import {
    getAndroidSmsPermissionState,
    requestAndroidSmsPermission,
    type AndroidSmsPermissionState,
    type AndroidSmsPermissionStatus,
} from '../src/androidSmsInbox';
import { useAuth } from '../src/auth';
import { InfoRow, PremiumTextInput, SectionCard, type AppIconName } from '../src/components/AppKit';
import { AnimatedBrandScene } from '../src/components/Brand';
import { ColorPickerIconPreview, ColorPickerOverlay } from '../src/components/ColorPickerOverlay';
import {
    OptionListOverlay,
    OptionSelectorRow,
    type OptionListItem,
} from '../src/components/OptionListOverlay';
import { buildSupportedCurrencyOptions, currencyOptionIcon } from '../src/currencyOptions';
import {
    getWalletPermissionSetupStatus,
    markWalletPermissionSetupReviewed,
} from '../src/permissionSetup';
import { normalizeHexColor } from '../src/theme';

const CURRENCY_OPTIONS = buildSupportedCurrencyOptions();

const USE_CASE_OPTIONS: {
  value: OnboardingUseCase;
  label: string;
  description: string;
  icon: AppIconName;
}[] = [
  {
    value: 'daily_spending',
    label: 'Daily spending',
    description: 'Track money moving in and out every day',
    icon: 'wallet-outline',
  },
  {
    value: 'budgeting',
    label: 'Budgeting',
    description: 'Keep categories and limits visible',
    icon: 'chart-donut',
  },
  {
    value: 'bills_subscriptions',
    label: 'Bills and subscriptions',
    description: 'Plan repeat payments before they hit',
    icon: 'calendar-clock',
  },
  {
    value: 'cards_loans',
    label: 'Cards and loans',
    description: 'Watch dues, EMI, balances, and repayments',
    icon: 'credit-card-outline',
  },
  {
    value: 'business_self_employed',
    label: 'Business/self-employed',
    description: 'Separate income, expenses, and accounts',
    icon: 'briefcase-outline',
  },
  {
    value: 'investments_net_worth',
    label: 'Investments/net worth',
    description: 'See assets and liabilities together',
    icon: 'finance',
  },
];

type OnboardingStep = 'profile' | 'mainAccount' | 'moreAccounts' | 'extraAccount' | 'permissions';
type AccountPicker = 'type' | 'currency' | 'icon' | 'color' | null;

type AccountDraft = {
  name: string;
  type: AccountType;
  icon: AppIconName;
  color: string;
  currency: string;
  opening: string;
};

function defaultAccountDraft(name: string, currency: string): AccountDraft {
  return {
    name,
    type: 'bank',
    icon: accountIconForType('bank'),
    color: DEFAULT_ACCOUNT_COLOR,
    currency,
    opening: '0',
  };
}

export default function Onboarding() {
  const theme = useTheme();
  const { user } = useAuth();
  const { state, mutate } = useLedger();
  const [step, setStep] = useState<OnboardingStep>('profile');
  const [displayName, setDisplayName] = useState(
    state.preferences.profile?.displayName?.trim() || user?.displayName?.trim() || '',
  );
  const [selectedUseCases, setSelectedUseCases] = useState<OnboardingUseCase[]>(
    state.preferences.profile?.primaryUseCases?.length
      ? state.preferences.profile.primaryUseCases
      : ['daily_spending', 'budgeting'],
  );
  const [submittedProfile, setSubmittedProfile] = useState(false);
  const [mainDraft, setMainDraft] = useState(() =>
    defaultAccountDraft('Main account', state.preferences.baseCurrency),
  );
  const [extraDraft, setExtraDraft] = useState(() =>
    defaultAccountDraft('', state.preferences.baseCurrency),
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const autoCapture = normalizeAutoCapturePreferences(state.preferences.autoCapture);

  useEffect(() => {
    const nextDisplayName =
      state.preferences.profile?.displayName?.trim() || user?.displayName?.trim();
    if (!nextDisplayName) return;
    setDisplayName((current) => current.trim() || nextDisplayName);
  }, [state.preferences.profile?.displayName, user?.displayName]);

  const setupAccounts = useMemo(
    () => state.accounts.filter((account) => !account.isArchived),
    [state.accounts],
  );

  if (!user) return <Redirect href={'/login' as never} />;

  const toggleUseCase = (value: OnboardingUseCase) => {
    setSelectedUseCases((current) =>
      current.includes(value) ? current.filter((item) => item !== value) : [...current, value],
    );
  };

  const continueProfile = async () => {
    setSubmittedProfile(true);
    setError(null);
    const name = displayName.trim();
    if (!name || selectedUseCases.length === 0 || saving) return;
    setSaving(true);
    try {
      await mutate((draft) => {
        draft.userId = user.id;
        draft.preferences.profile = {
          ...(draft.preferences.profile ?? { primaryUseCases: [] }),
          displayName: name,
          primaryUseCases: selectedUseCases,
        };
      });
      setStep('mainAccount');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save your profile.');
    } finally {
      setSaving(false);
    }
  };

  const saveAccount = async (draft: AccountDraft, isMain: boolean) => {
    setError(null);
    const accountName = draft.name.trim();
    if (!accountName || saving) return false;
    setSaving(true);
    const currency = normalizeCurrencyCode(draft.currency);
    const amount = Number(draft.opening.replace(/,/g, '')) || 0;
    const isBorrowedLoan = draft.type === 'loan' || draft.type === 'overdraft';
    const principalMinor = Math.abs(toMinor(amount, currency));
    const accountColor = normalizeHexColor(draft.color) ?? DEFAULT_ACCOUNT_COLOR;

    try {
      await mutate((ledgerDraft) => {
        ledgerDraft.userId = user.id;
        if (isMain) {
          ledgerDraft.preferences.baseCurrency = currency;
          ledgerDraft.preferences.displayCurrency = currency;
          ledgerDraft.preferences.enabledCurrencies = [currency];
        }
        createAccount(ledgerDraft, {
          name: accountName,
          type: draft.type,
          currency,
          openingBalanceMinor: isBorrowedLoan ? -principalMinor : toMinor(amount, currency),
          icon: draft.icon,
          color: accountColor,
          includeInTotals: true,
          includeInBudgets: !(
            draft.type === 'loan' ||
            draft.type === 'overdraft' ||
            draft.type === 'lent'
          ),
          includeInReports: true,
          includeInNetWorth: true,
        });
      });
      setStep('moreAccounts');
      if (!isMain) setExtraDraft(defaultAccountDraft('', currency));
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save this account.');
      return false;
    } finally {
      setSaving(false);
    }
  };

  const finish = async () => {
    setError(null);
    setSaving(true);
    try {
      await mutate((draft) => {
        draft.preferences.profile = {
          ...(draft.preferences.profile ?? { primaryUseCases: selectedUseCases }),
          displayName: displayName.trim() || draft.preferences.profile?.displayName,
          primaryUseCases: selectedUseCases,
          onboardingCompletedAt: nowIso(),
        };
      });
      await getWalletPermissionSetupStatus()
        .then((status) => markWalletPermissionSetupReviewed(user.id, status))
        .catch(() => undefined);
      router.replace('/(tabs)/home');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not finish setup.');
    } finally {
      setSaving(false);
    }
  };

  const continueToPermissions = () => {
    setError(null);
    setStep('permissions');
  };

  const enableSmsAutoCapture = async () => {
    await mutate((draft) => {
      const current = normalizeAutoCapturePreferences(draft.preferences.autoCapture);
      draft.preferences.autoCapture = normalizeAutoCapturePreferences({
        ...current,
        enabled: true,
        sms: {
          ...current.sms,
          enabled: true,
          backgroundEnabled: true,
        },
      });
    });
  };

  return (
    <SafeAreaView
      style={[s.safeArea, { backgroundColor: theme.colors.background }]}
      edges={['top', 'bottom']}
    >
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={s.keyboardView}
      >
        {step === 'profile' ? (
          <ProfileStep
            displayName={displayName}
            error={error}
            saving={saving}
            selectedUseCases={selectedUseCases}
            submitted={submittedProfile}
            onChangeName={setDisplayName}
            onContinue={continueProfile}
            onToggleUseCase={toggleUseCase}
          />
        ) : null}
        {step === 'mainAccount' ? (
          <AccountStep
            title="Main account"
            subtitle="Start with the account you use most."
            draft={mainDraft}
            error={error}
            saving={saving}
            primaryLabel="Continue"
            onBack={() => setStep('profile')}
            onChange={setMainDraft}
            onSubmit={() => void saveAccount(mainDraft, true)}
          />
        ) : null}
        {step === 'moreAccounts' ? (
          <MoreAccountsStep
            accounts={setupAccounts}
            error={error}
            saving={saving}
            onAddAnother={() => setStep('extraAccount')}
            onFinish={continueToPermissions}
          />
        ) : null}
        {step === 'extraAccount' ? (
          <AccountStep
            title="Add account"
            subtitle="Create another wallet, card, cash, or loan account."
            draft={extraDraft}
            error={error}
            saving={saving}
            primaryLabel="Add account"
            onBack={() => setStep('moreAccounts')}
            onChange={setExtraDraft}
            onSubmit={() => void saveAccount(extraDraft, false)}
          />
        ) : null}
        {step === 'permissions' ? (
          <PermissionsStep
            error={error}
            saving={saving}
            smsBackgroundEnabled={autoCapture.sms.backgroundEnabled}
            onBack={() => setStep('moreAccounts')}
            onEnableSmsCapture={enableSmsAutoCapture}
            onFinish={() => void finish()}
          />
        ) : null}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

function ProfileStep({
  displayName,
  error,
  saving,
  selectedUseCases,
  submitted,
  onChangeName,
  onContinue,
  onToggleUseCase,
}: {
  displayName: string;
  error: string | null;
  saving: boolean;
  selectedUseCases: OnboardingUseCase[];
  submitted: boolean;
  onChangeName: (value: string) => void;
  onContinue: () => void;
  onToggleUseCase: (value: OnboardingUseCase) => void;
}) {
  const theme = useTheme();
  return (
    <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={s.scrollContent}>
      <View style={s.content}>
        <AnimatedBrandScene
          title="Set up 1wallet"
          message="Shape the first screen around how you handle money"
          variant="hero"
          showProgress
          style={s.firstHero}
        />
        <View style={s.copyBlock}>
          <Text variant="headlineMedium" style={s.title}>
            Your profile
          </Text>
          <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
            Pick what matters most right now.
          </Text>
        </View>
        <PremiumTextInput
          label="Name"
          value={displayName}
          onChangeText={onChangeName}
          error={submitted && !displayName.trim()}
          left={<TextInput.Icon icon="account-outline" />}
        />
        <HelperText type="error" visible={submitted && !displayName.trim()}>
          Enter your name.
        </HelperText>
        <View style={s.useCaseList}>
          {USE_CASE_OPTIONS.map((option) => {
            const selected = selectedUseCases.includes(option.value);
            return (
              <Pressable
                key={option.value}
                accessibilityRole="checkbox"
                accessibilityState={{ checked: selected }}
                style={[
                  s.selectRow,
                  {
                    backgroundColor: selected
                      ? theme.colors.primaryContainer
                      : theme.colors.elevation.level1,
                    borderColor: selected ? theme.colors.primary : theme.colors.outlineVariant,
                  },
                ]}
                onPress={() => onToggleUseCase(option.value)}
              >
                <MaterialCommunityIcons
                  name={option.icon}
                  size={24}
                  color={selected ? theme.colors.onPrimaryContainer : theme.colors.primary}
                />
                <View style={s.selectCopy}>
                  <Text variant="titleSmall" style={s.selectTitle}>
                    {option.label}
                  </Text>
                  <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                    {option.description}
                  </Text>
                </View>
                <MaterialCommunityIcons
                  name={selected ? 'check-circle' : 'circle-outline'}
                  size={22}
                  color={selected ? theme.colors.primary : theme.colors.outline}
                />
              </Pressable>
            );
          })}
        </View>
        <HelperText type="error" visible={submitted && selectedUseCases.length === 0}>
          Pick at least one focus.
        </HelperText>
        <HelperText type="error" visible={Boolean(error)}>
          {error}
        </HelperText>
        <Button
          mode="contained"
          onPress={onContinue}
          loading={saving}
          disabled={saving}
          contentStyle={s.buttonContent}
        >
          Continue
        </Button>
      </View>
    </ScrollView>
  );
}

function AccountStep({
  title,
  subtitle,
  draft,
  error,
  saving,
  primaryLabel,
  onBack,
  onChange,
  onSubmit,
}: {
  title: string;
  subtitle: string;
  draft: AccountDraft;
  error: string | null;
  saving: boolean;
  primaryLabel: string;
  onBack: () => void;
  onChange: (draft: AccountDraft) => void;
  onSubmit: () => void;
}) {
  const theme = useTheme();
  const [submitted, setSubmitted] = useState(false);
  const [picker, setPicker] = useState<AccountPicker>(null);
  const accountName = draft.name.trim();
  const typeLabel = optionLabel(ACCOUNT_TYPE_OPTIONS, draft.type);
  const typeVisual = resolveAccountIconVisual({
    type: draft.type,
    icon: accountIconForType(draft.type),
    color: draft.color,
  });
  const draftVisual = resolveAccountIconVisual(draft);

  const updateDraft = (patch: Partial<AccountDraft>) => onChange({ ...draft, ...patch });
  const submit = () => {
    setSubmitted(true);
    if (!accountName) return;
    onSubmit();
  };

  return (
    <>
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={s.scrollContent}>
        <View style={s.content}>
          <View style={s.stepHeader}>
            <Button mode="text" icon="arrow-left" onPress={onBack}>
              Back
            </Button>
            <View style={s.copyBlock}>
              <Text variant="headlineMedium" style={s.title}>
                {title}
              </Text>
              <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                {subtitle}
              </Text>
            </View>
          </View>

          <View
            style={[
              s.accountPreview,
              {
                backgroundColor: theme.colors.elevation.level1,
                borderColor: theme.colors.outlineVariant,
              },
            ]}
          >
            <View style={[s.previewIcon, { backgroundColor: draftVisual.backgroundColor }]}>
              <MaterialCommunityIcons
                name={draftVisual.icon}
                size={28}
                color={draftVisual.iconColor}
              />
            </View>
            <View style={s.previewCopy}>
              <Text variant="titleMedium" numberOfLines={1} style={s.previewTitle}>
                {accountName || title}
              </Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                {typeLabel} · {draft.currency}
              </Text>
            </View>
          </View>

          <PremiumTextInput
            label="Account name"
            value={draft.name}
            onChangeText={(value) => updateDraft({ name: value })}
            error={submitted && !accountName}
            left={<TextInput.Icon icon={accountIconForType(draft.type)} />}
          />
          <HelperText type="error" visible={submitted && !accountName}>
            Enter an account name.
          </HelperText>
          <OptionSelectorRow
            label="Account type"
            value={typeLabel}
            description="Sets the behavior for this account"
            icon={typeVisual.icon}
            iconBackgroundColor={typeVisual.backgroundColor}
            iconColor={typeVisual.iconColor}
            onPress={() => setPicker('type')}
          />
          <OptionSelectorRow
            label="Icon"
            value={optionLabel(ACCOUNT_ICON_OPTIONS, draft.icon)}
            description="Shown across Home and Accounts"
            icon={draftVisual.icon}
            iconBackgroundColor={draftVisual.backgroundColor}
            iconColor={draftVisual.iconColor}
            onPress={() => setPicker('icon')}
          />
          <OptionSelectorRow
            label="Color"
            value="Selected color"
            description="Icon accent"
            icon={draftVisual.icon}
            iconBackgroundColor={draftVisual.backgroundColor}
            iconColor={draftVisual.iconColor}
            onPress={() => setPicker('color')}
          />
          <OptionSelectorRow
            label="Currency"
            value={optionLabel(CURRENCY_OPTIONS, draft.currency)}
            description="Money unit for this account"
            icon={currencyOptionIcon(draft.currency)}
            onPress={() => setPicker('currency')}
          />
          <PremiumTextInput
            label={
              draft.type === 'loan' || draft.type === 'overdraft'
                ? 'Outstanding principal'
                : 'Opening balance'
            }
            value={draft.opening}
            onChangeText={(value) => updateDraft({ opening: value })}
            keyboardType="numeric"
            left={<TextInput.Icon icon="cash" />}
          />
          <HelperText type="error" visible={Boolean(error)}>
            {error}
          </HelperText>
          <Button
            mode="contained"
            onPress={submit}
            loading={saving}
            disabled={saving}
            contentStyle={s.buttonContent}
          >
            {primaryLabel}
          </Button>
        </View>
      </ScrollView>
      <OptionListOverlay
        visible={picker === 'type'}
        title="Account type"
        options={ACCOUNT_TYPE_OPTIONS}
        selectedValue={draft.type}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          updateDraft({
            type: option.value,
            icon:
              draft.icon === accountIconForType(draft.type)
                ? accountIconForType(option.value)
                : draft.icon,
          });
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'icon'}
        title="Account icon"
        options={ACCOUNT_ICON_OPTIONS}
        selectedValue={draft.icon}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          updateDraft({ icon: option.value });
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'currency'}
        title="Currency"
        options={CURRENCY_OPTIONS}
        selectedValue={draft.currency}
        searchPlaceholder="Search currencies"
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          updateDraft({ currency: option.value });
          setPicker(null);
        }}
      />
      <ColorPickerOverlay
        visible={picker === 'color'}
        title="Account color"
        selectedColor={draft.color}
        fallbackColor={DEFAULT_ACCOUNT_COLOR}
        swatches={ACCOUNT_COLOR_OPTIONS}
        saveLabel="Apply account color"
        accessibilityLabelPrefix="Account color"
        onDismiss={() => setPicker(null)}
        onSave={(color) => {
          updateDraft({ color });
          setPicker(null);
        }}
        renderPreview={(color) => (
          <ColorPickerIconPreview
            color={color}
            icon={draft.icon}
            title={accountName || title}
            subtitle={`${typeLabel} · ${draft.currency}`}
          />
        )}
      />
    </>
  );
}

function MoreAccountsStep({
  accounts,
  error,
  saving,
  onAddAnother,
  onFinish,
}: {
  accounts: Account[];
  error: string | null;
  saving: boolean;
  onAddAnother: () => void;
  onFinish: () => void;
}) {
  const theme = useTheme();
  return (
    <ScrollView contentContainerStyle={s.scrollContent}>
      <View style={s.content}>
        <View style={s.copyBlock}>
          <Text variant="headlineMedium" style={s.title}>
            Accounts
          </Text>
          <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
            Keep going now or finish setup.
          </Text>
        </View>
        <View style={s.accountList}>
          {accounts.map((account) => {
            const color = normalizeHexColor(account.color) ?? DEFAULT_ACCOUNT_COLOR;
            const icon = (account.icon ?? accountIconForType(account.type)) as AppIconName;
            return (
              <View
                key={account.id}
                style={[
                  s.accountRow,
                  {
                    backgroundColor: theme.colors.elevation.level1,
                    borderColor: theme.colors.outlineVariant,
                  },
                ]}
              >
                <View style={[s.accountRowIcon, { backgroundColor: color }]}>
                  <MaterialCommunityIcons
                    name={icon}
                    size={22}
                    color={readableTextColorForBackground(color)}
                  />
                </View>
                <View style={s.previewCopy}>
                  <Text variant="titleSmall" style={s.selectTitle}>
                    {account.name}
                  </Text>
                  <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                    {optionLabel(ACCOUNT_TYPE_OPTIONS, account.type)} · {account.currency}
                  </Text>
                </View>
              </View>
            );
          })}
        </View>
        <HelperText type="error" visible={Boolean(error)}>
          {error}
        </HelperText>
        <Button
          mode="contained"
          onPress={onFinish}
          loading={saving}
          disabled={saving || accounts.length === 0}
          contentStyle={s.buttonContent}
        >
          Continue
        </Button>
        <Button
          mode="outlined"
          icon="plus"
          onPress={onAddAnother}
          disabled={saving}
          contentStyle={s.buttonContent}
        >
          Add another account
        </Button>
      </View>
    </ScrollView>
  );
}

function PermissionsStep({
  error,
  saving,
  smsBackgroundEnabled,
  onBack,
  onEnableSmsCapture,
  onFinish,
}: {
  error: string | null;
  saving: boolean;
  smsBackgroundEnabled: boolean;
  onBack: () => void;
  onEnableSmsCapture: () => Promise<void>;
  onFinish: () => void;
}) {
  const theme = useTheme();
  const [smsPermission, setSmsPermission] = useState<AndroidSmsPermissionState | undefined>();
  const [notificationStatus, setNotificationStatus] = useState<
    AndroidRuntimePermissionStatus | undefined
  >();
  const [cameraStatus, setCameraStatus] = useState<AndroidRuntimePermissionStatus | undefined>();
  const [photoLibraryStatus, setPhotoLibraryStatus] = useState<
    AndroidRuntimePermissionStatus | undefined
  >();
  const [locationStatus, setLocationStatus] = useState<
    AndroidRuntimePermissionStatus | undefined
  >();
  const [permissionBusy, setPermissionBusy] = useState<
    'sms' | 'notifications' | 'camera' | 'photos' | 'location' | null
  >(null);

  const refreshPermissions = useCallback(async () => {
    const [
      nextSmsPermission,
      nextNotificationStatus,
      nextCameraStatus,
      nextPhotoLibraryStatus,
      nextLocationStatus,
    ] = await Promise.all([
      getAndroidSmsPermissionState(),
      getAndroidNotificationPermissionStatus(),
      getDeviceCameraPermissionStatus(),
      getDevicePhotoLibraryPermissionStatus(),
      getAndroidLocationPermissionStatus(),
    ]);
    setSmsPermission(nextSmsPermission);
    setNotificationStatus(nextNotificationStatus);
    setCameraStatus(nextCameraStatus);
    setPhotoLibraryStatus(nextPhotoLibraryStatus);
    setLocationStatus(nextLocationStatus);
    return {
      smsPermission: nextSmsPermission,
      notificationStatus: nextNotificationStatus,
      cameraStatus: nextCameraStatus,
      photoLibraryStatus: nextPhotoLibraryStatus,
      locationStatus: nextLocationStatus,
    };
  }, []);

  useEffect(() => {
    void refreshPermissions().catch(() => undefined);
  }, [refreshPermissions]);

  const smsReady = smsPermission?.overall === 'granted';
  const notificationReady =
    notificationStatus === 'granted' || notificationStatus === 'unavailable';
  const cameraReady = permissionReady(cameraStatus);
  const photoLibraryReady = permissionReady(photoLibraryStatus);
  const locationReady = permissionReady(locationStatus);
  const smsButtonLabel = smsReady
    ? smsBackgroundEnabled
      ? 'SMS ready'
      : 'Turn on capture'
    : 'Allow SMS';

  const requestSmsAccess = async () => {
    if (smsReady) {
      await onEnableSmsCapture();
      return;
    }
    setPermissionBusy('sms');
    try {
      const status = await requestAndroidSmsPermission();
      const next = await refreshPermissions();
      if (status === 'granted' || next.smsPermission.overall === 'granted') {
        await onEnableSmsCapture();
        return;
      }
      showOnboardingSmsPermissionAlert(status);
    } catch (err) {
      Alert.alert('SMS permission failed', err instanceof Error ? err.message : String(err));
    } finally {
      setPermissionBusy(null);
    }
  };

  const requestNotifications = async () => {
    setPermissionBusy('notifications');
    try {
      const status = await requestAndroidNotificationPermission();
      await refreshPermissions();
      if (status !== 'granted' && status !== 'unavailable') {
        showOnboardingNotificationPermissionAlert(status);
      }
    } catch (err) {
      Alert.alert(
        'Notification permission failed',
        err instanceof Error ? err.message : String(err),
      );
    } finally {
      setPermissionBusy(null);
    }
  };

  const requestCamera = async () => {
    setPermissionBusy('camera');
    try {
      const status = await requestDeviceCameraPermission();
      await refreshPermissions();
      if (status !== 'granted' && status !== 'unavailable') {
        showOnboardingRuntimePermissionAlert('Camera', status);
      }
    } catch (err) {
      Alert.alert('Camera permission failed', err instanceof Error ? err.message : String(err));
    } finally {
      setPermissionBusy(null);
    }
  };

  const requestPhotos = async () => {
    setPermissionBusy('photos');
    try {
      const status = await requestDevicePhotoLibraryPermission();
      await refreshPermissions();
      if (status !== 'granted' && status !== 'unavailable') {
        showOnboardingRuntimePermissionAlert('Photos', status);
      }
    } catch (err) {
      Alert.alert('Photos permission failed', err instanceof Error ? err.message : String(err));
    } finally {
      setPermissionBusy(null);
    }
  };

  const requestLocation = async () => {
    setPermissionBusy('location');
    try {
      const status = await requestAndroidLocationPermission();
      await refreshPermissions();
      if (status !== 'granted' && status !== 'unavailable') {
        showOnboardingRuntimePermissionAlert('Location', status);
      }
    } catch (err) {
      Alert.alert('Location permission failed', err instanceof Error ? err.message : String(err));
    } finally {
      setPermissionBusy(null);
    }
  };

  return (
    <ScrollView contentContainerStyle={s.scrollContent}>
      <View style={s.content}>
        <View style={s.stepHeader}>
          <Button mode="text" icon="arrow-left" onPress={onBack}>
            Back
          </Button>
          <View style={s.copyBlock}>
            <Text variant="headlineMedium" style={s.title}>
              Permissions
            </Text>
            <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
              Set up capture and alerts.
            </Text>
          </View>
        </View>

        <SectionCard title="Auto Capture" subtitle="SMS stays local and queued items go to Review.">
          <InfoRow
            icon="message-processing-outline"
            label="SMS access"
            value={smsPermissionLabel(smsPermission)}
            tone={smsPermissionTone(smsPermission)}
          />
          <Button
            mode={smsReady && smsBackgroundEnabled ? 'outlined' : 'contained'}
            icon={smsReady ? 'check-circle-outline' : 'message-processing-outline'}
            onPress={() => void requestSmsAccess()}
            loading={permissionBusy === 'sms'}
            disabled={permissionBusy !== null || (smsReady && smsBackgroundEnabled)}
            contentStyle={s.buttonContent}
          >
            {smsButtonLabel}
          </Button>
          <Divider />
          <InfoRow
            icon="bell-badge-outline"
            label="Notifications"
            value={runtimePermissionLabel(notificationStatus)}
            tone={runtimePermissionTone(notificationStatus)}
          />
          <Button
            mode={notificationReady ? 'outlined' : 'contained'}
            icon={notificationReady ? 'check-circle-outline' : 'bell-outline'}
            onPress={() => void requestNotifications()}
            loading={permissionBusy === 'notifications'}
            disabled={permissionBusy !== null || notificationReady}
            contentStyle={s.buttonContent}
          >
            {notificationReady ? 'Notifications ready' : 'Allow notifications'}
          </Button>
          <Divider />
          <InfoRow
            icon="battery-heart-outline"
            label="Battery behavior"
            value={smsBackgroundEnabled ? 'Background on' : 'Needs SMS'}
            tone={smsBackgroundEnabled ? 'positive' : 'warning'}
          />
          <Button
            mode="outlined"
            icon="cog-outline"
            onPress={() => void openAndroidAppSettings()}
            contentStyle={s.buttonContent}
          >
            Open app settings
          </Button>
        </SectionCard>

        <SectionCard
          title="Receipts and context"
          subtitle="These permissions power receipt capture and transaction details."
        >
          <InfoRow
            icon="camera-outline"
            label="Camera"
            value={runtimePermissionLabel(cameraStatus)}
            tone={runtimePermissionTone(cameraStatus)}
          />
          <Text
            variant="bodySmall"
            style={[s.permissionReason, { color: theme.colors.onSurfaceVariant }]}
          >
            Why: scan receipt and bill photos for OCR and attachments.
          </Text>
          <Button
            mode={cameraReady ? 'outlined' : 'contained'}
            icon={cameraReady ? 'check-circle-outline' : 'camera-outline'}
            onPress={() => void requestCamera()}
            loading={permissionBusy === 'camera'}
            disabled={permissionBusy !== null || cameraReady}
            contentStyle={s.buttonContent}
          >
            {cameraReady ? 'Camera ready' : 'Allow camera'}
          </Button>
          <Divider />
          <InfoRow
            icon="image-outline"
            label="Photos"
            value={runtimePermissionLabel(photoLibraryStatus)}
            tone={runtimePermissionTone(photoLibraryStatus)}
          />
          <Text
            variant="bodySmall"
            style={[s.permissionReason, { color: theme.colors.onSurfaceVariant }]}
          >
            Why: choose existing receipt and bill images from your photo library.
          </Text>
          <Button
            mode={photoLibraryReady ? 'outlined' : 'contained'}
            icon={photoLibraryReady ? 'check-circle-outline' : 'image-outline'}
            onPress={() => void requestPhotos()}
            loading={permissionBusy === 'photos'}
            disabled={permissionBusy !== null || photoLibraryReady}
            contentStyle={s.buttonContent}
          >
            {photoLibraryReady ? 'Photos ready' : 'Allow photos'}
          </Button>
          <Divider />
          <InfoRow
            icon="map-marker-outline"
            label="Location"
            value={runtimePermissionLabel(locationStatus)}
            tone={runtimePermissionTone(locationStatus)}
          />
          <Text
            variant="bodySmall"
            style={[s.permissionReason, { color: theme.colors.onSurfaceVariant }]}
          >
            Why: tag where a transaction or receipt happened when you choose to save place details.
          </Text>
          <Button
            mode={locationReady ? 'outlined' : 'contained'}
            icon={locationReady ? 'check-circle-outline' : 'map-marker-outline'}
            onPress={() => void requestLocation()}
            loading={permissionBusy === 'location'}
            disabled={permissionBusy !== null || locationReady}
            contentStyle={s.buttonContent}
          >
            {locationReady ? 'Location ready' : 'Allow location'}
          </Button>
        </SectionCard>

        <HelperText type="error" visible={Boolean(error)}>
          {error}
        </HelperText>
        <Button
          mode="contained"
          onPress={onFinish}
          loading={saving}
          disabled={saving}
          contentStyle={s.buttonContent}
        >
          Finish setup
        </Button>
      </View>
    </ScrollView>
  );
}

function smsPermissionLabel(state?: AndroidSmsPermissionState) {
  if (!state) return 'Checking';
  if (state.overall === 'granted') return 'Granted';
  if (state.overall === 'partial') return 'Partial';
  if (state.overall === 'unavailable') return 'Unavailable';
  return 'Needed';
}

function smsPermissionTone(
  state?: AndroidSmsPermissionState,
): 'default' | 'positive' | 'warning' | 'danger' {
  if (!state) return 'default';
  if (state.overall === 'granted') return 'positive';
  if (state.overall === 'unavailable') return 'default';
  return 'warning';
}

function runtimePermissionLabel(status?: AndroidRuntimePermissionStatus) {
  if (!status) return 'Checking';
  if (status === 'granted') return 'Granted';
  if (status === 'blocked') return 'Blocked';
  if (status === 'unavailable') return 'Not needed';
  return 'Needed';
}

function runtimePermissionTone(
  status?: AndroidRuntimePermissionStatus,
): 'default' | 'positive' | 'warning' | 'danger' {
  if (!status || status === 'unavailable') return 'default';
  if (status === 'granted') return 'positive';
  if (status === 'blocked') return 'danger';
  return 'warning';
}

function permissionReady(status?: AndroidRuntimePermissionStatus) {
  return status === 'granted' || status === 'unavailable';
}

function showOnboardingRuntimePermissionAlert(
  label: 'Camera' | 'Photos' | 'Location',
  status: AndroidRuntimePermissionStatus,
) {
  const blocked = status === 'blocked';
  Alert.alert(
    blocked ? `${label} permission is blocked` : `${label} permission not granted`,
    blocked
      ? `Open Android settings and allow ${label.toLowerCase()} permission for 1wallet.`
      : `You can continue now and allow ${label.toLowerCase()} permission later from Android settings.`,
    blocked
      ? [
          { text: 'Not now', style: 'cancel' },
          { text: 'Open settings', onPress: () => void openAndroidAppSettings() },
        ]
      : [{ text: 'OK' }],
  );
}

function showOnboardingSmsPermissionAlert(status: AndroidSmsPermissionStatus) {
  const blocked = status === 'blocked';
  Alert.alert(
    blocked ? 'SMS permission is blocked' : 'SMS permission not granted',
    blocked
      ? 'Open Android settings and allow SMS permissions for 1wallet.'
      : 'You can continue now and allow SMS capture later from Auto Capture.',
    blocked
      ? [
          { text: 'Not now', style: 'cancel' },
          { text: 'Open settings', onPress: () => void openAndroidAppSettings() },
        ]
      : [{ text: 'OK' }],
  );
}

function showOnboardingNotificationPermissionAlert(status: AndroidRuntimePermissionStatus) {
  const blocked = status === 'blocked';
  Alert.alert(
    blocked ? 'Notifications are blocked' : 'Notifications not granted',
    blocked
      ? 'Open Android settings and allow notifications for 1wallet.'
      : 'You can continue now and allow notifications later from Android settings.',
    blocked
      ? [
          { text: 'Not now', style: 'cancel' },
          { text: 'Open settings', onPress: () => void openAndroidAppSettings() },
        ]
      : [{ text: 'OK' }],
  );
}

function optionLabel<TValue extends string>(
  options: readonly OptionListItem<TValue>[],
  value: TValue,
) {
  return options.find((option) => option.value === value)?.label ?? value;
}

const s = StyleSheet.create({
  safeArea: { flex: 1 },
  keyboardView: { flex: 1 },
  scrollContent: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: tokens.space.lg,
  },
  content: {
    width: '100%',
    maxWidth: 520,
    alignSelf: 'center',
    gap: tokens.space.md,
  },
  firstHero: { marginHorizontal: -tokens.space.lg },
  copyBlock: { gap: tokens.space.xs },
  title: { fontWeight: '800' },
  useCaseList: { gap: tokens.space.sm },
  selectRow: {
    minHeight: 78,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.md,
    padding: tokens.space.md,
  },
  selectCopy: { flex: 1, gap: 3 },
  selectTitle: { fontWeight: '700' },
  permissionReason: { marginTop: -tokens.space.xs },
  buttonContent: { minHeight: 48 },
  stepHeader: { gap: tokens.space.xs },
  accountPreview: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.md,
    padding: tokens.space.md,
  },
  previewIcon: {
    width: 56,
    height: 56,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  previewCopy: { flex: 1, gap: 3 },
  previewTitle: { fontWeight: '800' },
  accountList: { gap: tokens.space.sm },
  accountRow: {
    minHeight: 72,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.md,
    padding: tokens.space.md,
  },
  accountRowIcon: {
    width: 44,
    height: 44,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
