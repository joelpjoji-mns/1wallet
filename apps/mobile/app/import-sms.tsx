import { formatMoney } from '@1wallet/domain/money';
import type { AccountMessageHint, CategoryKind } from '@1wallet/domain/types';
import type {
    TransactionMessageCaptureResult,
    TransactionMessageSource,
} from '@1wallet/ledger/capture/messages';
import {
    createMessageCategoryRule,
    deleteMessageCategoryRule,
    messageHintSuggestionsForAccount,
    parseTransactionMessage,
    processTransactionMessageCapture,
    updateMessageCategoryRule,
} from '@1wallet/ledger/capture/messages';
import { createCaptureCandidate, mergeAcceptedMessageAccountHints } from '@1wallet/ledger/services';
import {
    normalizeAutoCapturePreferences,
    type MessageCategoryKeywordRule,
} from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { router } from 'expo-router';
import { Fragment, useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Linking, Platform, StyleSheet, View } from 'react-native';
import { Button, Chip, Divider, Switch, Text, useTheme } from 'react-native-paper';
import { resolveAccountIconVisual } from '../src/accountOptions';
import {
    getAndroidSmsPermissionState,
    isAndroidSmsInboxAvailable,
    readAndroidSmsInbox,
    requestAndroidSmsPermission,
    type AndroidSmsPermissionState,
    type AndroidSmsPermissionStatus,
} from '../src/androidSmsInbox';
import { categoryBreadcrumb } from '../src/categoryTree';
import {
    AppScreen,
    EmptyState,
    InfoRow,
    InlineMeta,
    PremiumTextInput,
    SectionCard,
} from '../src/components/AppKit';
import { DateOnlyPickerField } from '../src/components/DateOnlyPickerField';
import {
    OptionListOverlay,
    OptionSelectorRow,
    type OptionListItem,
} from '../src/components/OptionListOverlay';
import { CategoryPickerOverlay } from '../src/components/record/RecordPickers';
import { RecordSelectorRow } from '../src/components/record/RecordSelectorRow';
import { transactionTypeLabel } from '../src/transactionTypes';

const SOURCES: TransactionMessageSource[] = ['sms', 'email', 'notification'];

type RuleEditorKind = Extract<CategoryKind, 'expense' | 'income'>;
type RulePickerMode = 'kind' | 'category' | null;

const RULE_KIND_OPTIONS: OptionListItem<RuleEditorKind>[] = [
  { value: 'expense', label: 'Expense', description: 'Spending categories', icon: 'bank-minus' },
  { value: 'income', label: 'Income', description: 'Money-in categories', icon: 'bank-plus' },
];

type SmsScanSummary = {
  scanned: number;
  recognized: number;
  posted: number;
  queued: number;
  duplicates: number;
  ignored: number;
  unrecognized: number;
  ignoredReasons: Record<string, number>;
};

export default function SmsImport() {
  const theme = useTheme();
  const { state, mutate, selectors } = useLedger();
  const autoCapture = normalizeAutoCapturePreferences(state.preferences.autoCapture);
  const storedTriggerKeywords = autoCapture.sms.triggerKeywords.join(', ');
  const storedIgnoredSenders = autoCapture.sms.ignoredSenderIds.join(', ');
  const storedScanLimit = String(autoCapture.sms.scanLimit);
  const storedAutoPostConfidence = String(autoCapture.autoPostConfidence);
  const [source, setSource] = useState<TransactionMessageSource>('sms');
  const [sender, setSender] = useState('');
  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [selectedAccountId, setSelectedAccountId] = useState<string | undefined>();
  const [selectedHintIds, setSelectedHintIds] = useState<string[]>([]);
  const [smsScanSummary, setSmsScanSummary] = useState<SmsScanSummary | undefined>();
  const [isScanningSms, setIsScanningSms] = useState(false);
  const [scanFromDate, setScanFromDate] = useState(() => localDateString(new Date()));
  const [scanToDate, setScanToDate] = useState(() => localDateString(new Date()));
  const [triggerKeywordsDraft, setTriggerKeywordsDraft] = useState(storedTriggerKeywords);
  const [ignoredSendersDraft, setIgnoredSendersDraft] = useState(storedIgnoredSenders);
  const [scanLimitDraft, setScanLimitDraft] = useState(storedScanLimit);
  const [autoPostConfidenceDraft, setAutoPostConfidenceDraft] = useState(storedAutoPostConfidence);
  const [smsPermissionState, setSmsPermissionState] = useState<AndroidSmsPermissionState>();
  const [ruleEditorId, setRuleEditorId] = useState<string | undefined>();
  const [ruleName, setRuleName] = useState('');
  const [ruleKeywords, setRuleKeywords] = useState('');
  const [ruleKind, setRuleKind] = useState<RuleEditorKind>('expense');
  const [ruleCategoryId, setRuleCategoryId] = useState<string | undefined>();
  const [rulePickerMode, setRulePickerMode] = useState<RulePickerMode>(null);
  const smsInboxAvailable = isAndroidSmsInboxAvailable();
  const messageCategoryRules = state.preferences.messageCategoryRules ?? [];
  const pendingReviewCount = selectors.queryCaptureCandidates(state, { status: 'pending' }).length;

  const refreshSmsPermissionState = useCallback(async () => {
    const next = await getAndroidSmsPermissionState();
    setSmsPermissionState(next);
    return next;
  }, []);

  useEffect(() => {
    void refreshSmsPermissionState();
  }, [refreshSmsPermissionState, smsInboxAvailable]);

  useEffect(() => {
    setTriggerKeywordsDraft(storedTriggerKeywords);
  }, [storedTriggerKeywords]);

  useEffect(() => {
    setIgnoredSendersDraft(storedIgnoredSenders);
  }, [storedIgnoredSenders]);

  useEffect(() => {
    setScanLimitDraft(storedScanLimit);
  }, [storedScanLimit]);

  useEffect(() => {
    setAutoPostConfidenceDraft(storedAutoPostConfidence);
  }, [storedAutoPostConfidence]);

  const result = useMemo(() => {
    if (!body.trim()) return undefined;
    return parseTransactionMessage(state, {
      source,
      sender: sender.trim() || undefined,
      subject: subject.trim() || undefined,
      body,
      receivedAt: new Date().toISOString(),
    });
  }, [body, sender, source, state, subject]);

  const matchedAccount = result?.match.accountId
    ? state.accounts.find((account) => account.id === result.match.accountId)
    : undefined;
  const matchedCategory = result?.categoryMatch.categoryId
    ? state.categories.find((category) => category.id === result.categoryMatch.categoryId)
    : undefined;
  const selectedAccount = selectedAccountId
    ? state.accounts.find((account) => account.id === selectedAccountId)
    : matchedAccount;
  const selectedAccountVisual = selectedAccount
    ? resolveAccountIconVisual(selectedAccount)
    : undefined;
  const selectedRuleCategory = ruleCategoryId
    ? state.categories.find((category) => category.id === ruleCategoryId)
    : undefined;
  const hintSuggestions = useMemo(
    () =>
      result && selectedAccount
        ? messageHintSuggestionsForAccount(
            selectedAccount,
            {
              source,
              sender: sender.trim() || undefined,
              subject: subject.trim() || undefined,
              body,
            },
            result,
          )
        : [],
    [body, result, selectedAccount, sender, source, subject],
  );
  useEffect(() => {
    setSelectedAccountId(result?.match.accountId);
  }, [body, result?.match.accountId, sender, source, subject]);

  useEffect(() => {
    setSelectedHintIds(
      hintSuggestions.filter((hint) => !hint.existing).map((hint) => hint.id ?? hintId(hint)),
    );
  }, [hintSuggestions]);

  useEffect(() => {
    if (selectedRuleCategory && selectedRuleCategory.kind !== ruleKind) {
      setRuleCategoryId(undefined);
    }
  }, [ruleKind, selectedRuleCategory]);

  const resetRuleEditor = () => {
    setRuleEditorId(undefined);
    setRuleName('');
    setRuleKeywords('');
    setRuleKind('expense');
    setRuleCategoryId(undefined);
    setRulePickerMode(null);
  };

  const editRule = (rule: MessageCategoryKeywordRule) => {
    const category = state.categories.find((item) => item.id === rule.categoryId);
    setRuleEditorId(rule.id);
    setRuleName(rule.name);
    setRuleKeywords(rule.keywords.join(', '));
    setRuleKind(category?.kind === 'income' ? 'income' : 'expense');
    setRuleCategoryId(rule.categoryId);
  };

  const saveRule = async () => {
    const keywords = splitKeywordList(ruleKeywords);
    if (!ruleCategoryId) {
      Alert.alert('Choose a category', 'Pick the category these SMS keywords should use.');
      return;
    }
    if (keywords.length === 0) {
      Alert.alert('Add keywords', 'Enter at least one keyword or merchant name.');
      return;
    }

    await mutate((draft) => {
      if (ruleEditorId) {
        updateMessageCategoryRule(draft, ruleEditorId, {
          name: ruleName,
          keywords,
          categoryId: ruleCategoryId,
        });
      } else {
        createMessageCategoryRule(draft, {
          name: ruleName,
          keywords,
          categoryId: ruleCategoryId,
        });
      }
    });
    resetRuleEditor();
  };

  const toggleRule = async (rule: MessageCategoryKeywordRule) => {
    await mutate((draft) => {
      updateMessageCategoryRule(draft, rule.id, { enabled: !rule.enabled });
    });
  };

  const removeRule = async (rule: MessageCategoryKeywordRule) => {
    await mutate((draft) => {
      deleteMessageCategoryRule(draft, rule.id);
    });
    if (ruleEditorId === rule.id) resetRuleEditor();
  };

  const updateAutoCapture = async (patch: {
    enabled?: boolean;
    autoPost?: boolean;
    smsEnabled?: boolean;
    smsBackgroundEnabled?: boolean;
  }) => {
    const enablingSmsCapture = patch.smsEnabled === true || patch.smsBackgroundEnabled === true;
    if (enablingSmsCapture && Platform.OS === 'android') {
      const permission = await requestAndroidSmsPermission();
      await refreshSmsPermissionState();
      if (permission !== 'granted') {
        showSmsPermissionAlert(permission);
        return;
      }
    }
    await mutate((draft) => {
      const current = normalizeAutoCapturePreferences(draft.preferences.autoCapture);
      draft.preferences.autoCapture = normalizeAutoCapturePreferences({
        ...current,
        enabled: patch.enabled ?? (enablingSmsCapture ? true : current.enabled),
        autoPost: patch.autoPost ?? current.autoPost,
        sms: {
          ...current.sms,
          enabled: patch.smsEnabled ?? (enablingSmsCapture ? true : current.sms.enabled),
          backgroundEnabled:
            patch.smsBackgroundEnabled ??
            (patch.smsEnabled === true ? true : current.sms.backgroundEnabled),
        },
      });
    });
  };

  const requestSmsPermissions = async () => {
    const permission = await requestAndroidSmsPermission();
    await refreshSmsPermissionState();
    if (permission === 'granted') {
      await enableSmsAutoCapture();
      Alert.alert('SMS permission granted', 'Auto Capture can now scan payment alerts locally.');
      return;
    }
    showSmsPermissionAlert(permission);
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

  const saveAutoCaptureSettings = async () => {
    const scanLimit = Number(scanLimitDraft);
    const autoPostConfidence = Number(autoPostConfidenceDraft);
    await mutate((draft) => {
      const current = normalizeAutoCapturePreferences(draft.preferences.autoCapture);
      draft.preferences.autoCapture = normalizeAutoCapturePreferences({
        ...current,
        autoPostConfidence: Number.isFinite(autoPostConfidence)
          ? autoPostConfidence
          : current.autoPostConfidence,
        sms: {
          ...current.sms,
          scanLimit: Number.isFinite(scanLimit) ? scanLimit : current.sms.scanLimit,
          triggerKeywords: splitKeywordList(triggerKeywordsDraft),
          ignoredSenderIds: splitKeywordList(ignoredSendersDraft),
        },
      });
    });
    Alert.alert('Auto Capture saved', 'SMS trigger and posting settings are updated.');
  };

  const queueCapture = async () => {
    if (!result?.candidateInput) return;
    const acceptedHints = hintSuggestions.filter((hint) =>
      selectedHintIds.includes(hint.id ?? hintId(hint)),
    );
    const candidateInput = {
      ...result.candidateInput,
      suggestedAccountId: selectedAccountId ?? result.candidateInput.suggestedAccountId,
      rawPayload: {
        ...result.candidateInput.rawPayload,
        selectedAccountId: selectedAccountId ?? result.candidateInput.suggestedAccountId,
        acceptedMessageHints: acceptedHints,
      },
      warnings:
        selectedAccountId && result.candidateInput.warnings
          ? result.candidateInput.warnings.filter(
              (warning) =>
                warning !== 'ambiguous account match' &&
                warning !== 'account needs matching detail',
            )
          : result.candidateInput.warnings,
    };
    await mutate((draft) => {
      if (selectedAccountId && acceptedHints.length > 0) {
        mergeAcceptedMessageAccountHints(draft, selectedAccountId, acceptedHints);
      }
      createCaptureCandidate(draft, candidateInput);
    });
    Alert.alert('Queued for review', 'The parsed message is waiting in Review.', [
      { text: 'Stay', style: 'cancel' },
      { text: 'Review', onPress: () => router.push('/review') },
    ]);
  };

  const scanSmsInbox = async () => {
    const dateRange = smsScanDateRange(scanFromDate, scanToDate);
    if (!dateRange) {
      Alert.alert('Check date range', 'Enter valid From and To dates in YYYY-MM-DD format.');
      return;
    }
    if (dateRange.minDate > dateRange.maxDate) {
      Alert.alert('Check date range', 'The From date must be before the To date.');
      return;
    }
    if (!smsInboxAvailable) {
      Alert.alert(
        'SMS reader unavailable',
        Platform.OS === 'android'
          ? 'Rebuild the Android development app after installing the SMS reader.'
          : 'SMS inbox scanning is available on Android only.',
      );
      return;
    }

    setIsScanningSms(true);
    try {
      const permission = await requestAndroidSmsPermission();
      await refreshSmsPermissionState();
      if (permission !== 'granted') {
        setSmsScanSummary({
          scanned: 0,
          recognized: 0,
          posted: 0,
          queued: 0,
          duplicates: 0,
          ignored: 0,
          unrecognized: 0,
          ignoredReasons: {},
        });
        showSmsPermissionAlert(permission);
        return;
      }

      const messages = await readAndroidSmsInbox({
        maxCount: autoCapture.sms.scanLimit,
        minDate: dateRange.minDate,
        maxDate: dateRange.maxDate,
      });
      const summary: SmsScanSummary = {
        scanned: messages.length,
        recognized: 0,
        posted: 0,
        queued: 0,
        duplicates: 0,
        ignored: 0,
        unrecognized: 0,
        ignoredReasons: {},
      };
      await mutate((draft) => {
        const preferences = normalizeAutoCapturePreferences(draft.preferences.autoCapture);
        for (const message of messages) {
          const result = processTransactionMessageCapture(
            draft,
            {
              source: 'sms',
              sender: message.sender,
              body: message.body,
              receivedAt: message.receivedAt,
            },
            {
              triggerKeywords: preferences.sms.triggerKeywords,
              ignoredSenderIds: preferences.sms.ignoredSenderIds,
              autoPost: preferences.autoPost,
              autoPostConfidence: preferences.autoPostConfidence,
              smsInboxId: message.id,
            },
          );
          if (result.parseResult?.candidateInput) summary.recognized += 1;
          if (result.outcome === 'posted') summary.posted += 1;
          else if (result.outcome === 'queued') summary.queued += 1;
          else if (result.outcome === 'duplicate') summary.duplicates += 1;
          else if (result.outcome === 'ignored') summary.ignored += 1;
          else if (result.outcome === 'unrecognized') summary.unrecognized += 1;
          const reason = smsCaptureReason(result);
          if (reason) summary.ignoredReasons[reason] = (summary.ignoredReasons[reason] ?? 0) + 1;
        }
        draft.preferences.autoCapture = normalizeAutoCapturePreferences({
          ...preferences,
          sms: {
            ...preferences.sms,
            lastRun: { ...summary, ranAt: new Date().toISOString() },
          },
        });
      });
      setSmsScanSummary(summary);
      Alert.alert(
        'SMS scan complete',
        `${dateRange.label}: ${summary.posted} posted, ${summary.queued} queued, ${summary.duplicates} duplicates, ${summary.ignored} ignored, ${summary.unrecognized} unrecognized.`,
        [
          { text: 'Stay', style: 'cancel' },
          { text: 'Review', onPress: () => router.push('/review') },
        ],
      );
    } catch (error) {
      Alert.alert('Could not scan SMS inbox', (error as Error).message);
    } finally {
      setIsScanningSms(false);
    }
  };

  const toggleHint = (id: string) => {
    setSelectedHintIds((current) =>
      current.includes(id) ? current.filter((item) => item !== id) : [...current, id],
    );
  };

  const applySmsScanPreset = (preset: 'today' | 'yesterday' | 'last7') => {
    const today = startOfLocalDay(new Date());
    if (preset === 'today') {
      const value = localDateString(today);
      setScanFromDate(value);
      setScanToDate(value);
      return;
    }
    if (preset === 'yesterday') {
      const value = localDateString(addLocalDays(today, -1));
      setScanFromDate(value);
      setScanToDate(value);
      return;
    }
    setScanFromDate(localDateString(addLocalDays(today, -6)));
    setScanToDate(localDateString(today));
  };

  return (
    <AppScreen
      title="Auto Capture"
      subtitle="Read-only transaction alert capture for SMS now, with room for email later."
      actions={[{ icon: 'robot-outline', label: 'Review', onPress: () => router.push('/review') }]}
    >
      <SectionCard
        title="Capture settings"
        subtitle="Only messages matching trigger keywords are parsed; non-matches are discarded."
      >
        <View style={s.switchRow}>
          <View style={s.fill}>
            <Text variant="titleSmall">Auto Capture</Text>
            <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
              Enables local parsing for transaction alerts.
            </Text>
          </View>
          <Switch
            value={autoCapture.enabled}
            onValueChange={(enabled) => void updateAutoCapture({ enabled })}
          />
        </View>
        <Divider />
        <View style={s.switchRow}>
          <View style={s.fill}>
            <Text variant="titleSmall">SMS capture</Text>
            <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
              Uses read access only; 1wallet is not the default SMS app.
            </Text>
          </View>
          <Switch
            value={autoCapture.sms.enabled}
            onValueChange={(smsEnabled) => void updateAutoCapture({ smsEnabled })}
          />
        </View>
        <Divider />
        <View style={s.switchRow}>
          <View style={s.fill}>
            <Text variant="titleSmall">Background monitoring</Text>
            <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
              Handles new transaction-looking SMS without opening an inbox view.
            </Text>
          </View>
          <Switch
            value={autoCapture.sms.backgroundEnabled}
            onValueChange={(smsBackgroundEnabled) =>
              void updateAutoCapture({ smsBackgroundEnabled })
            }
          />
        </View>
        <Divider />
        <View style={s.switchRow}>
          <View style={s.fill}>
            <Text variant="titleSmall">Auto-post high confidence</Text>
            <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
              Safe categorized matches post directly; everything else waits in Review.
            </Text>
          </View>
          <Switch
            value={autoCapture.autoPost}
            onValueChange={(autoPost) => void updateAutoCapture({ autoPost })}
          />
        </View>
        <View style={s.inlineInputs}>
          <PremiumTextInput
            label="Auto-post confidence"
            value={autoPostConfidenceDraft}
            onChangeText={setAutoPostConfidenceDraft}
            keyboardType="number-pad"
            style={s.smallInput}
          />
          <PremiumTextInput
            label="Scan limit"
            value={scanLimitDraft}
            onChangeText={setScanLimitDraft}
            keyboardType="number-pad"
            style={s.smallInput}
          />
        </View>
        <PremiumTextInput
          label="Trigger keywords"
          value={triggerKeywordsDraft}
          onChangeText={setTriggerKeywordsDraft}
          placeholder="credited, debited, ₹, GBP, $"
          multiline
        />
        <PremiumTextInput
          label="Ignored SMS senders"
          value={ignoredSendersDraft}
          onChangeText={setIgnoredSendersDraft}
          placeholder="VM-PROMO, AD-SALE"
          autoCapitalize="characters"
        />
        <Button mode="contained" icon="content-save-outline" onPress={saveAutoCaptureSettings}>
          Save settings
        </Button>
      </SectionCard>

      <SectionCard title="Parser tester" subtitle="Paste one alert to preview extraction rules.">
        <View style={s.chips}>
          {SOURCES.map((item) => (
            <Chip key={item} selected={source === item} onPress={() => setSource(item)}>
              {item.toUpperCase()}
            </Chip>
          ))}
        </View>
      </SectionCard>

      <SectionCard title="SMS reader" subtitle="Android inbox access and latest scan result.">
        <InfoRow
          icon="cellphone-message"
          label="Reader"
          value={
            Platform.OS !== 'android'
              ? 'Android only'
              : smsInboxAvailable
                ? 'Ready'
                : 'Needs rebuild'
          }
          tone={smsInboxAvailable ? 'positive' : 'warning'}
        />
        <Divider />
        <InfoRow
          icon="shield-check-outline"
          label="SMS permission"
          value={smsPermissionLabel(smsPermissionState)}
          tone={smsPermissionTone(smsPermissionState)}
        />
        {smsScanSummary ? (
          <>
            <Divider />
            <InfoRow
              icon="message-processing-outline"
              label="Last scan"
              value={scanSummaryLabel(smsScanSummary)}
              tone={smsScanSummary.posted || smsScanSummary.queued ? 'positive' : 'default'}
            />
            <Divider />
            <InfoRow
              icon="filter-outline"
              label="Recognized"
              value={`${smsScanSummary.recognized} of ${smsScanSummary.scanned} · ${smsScanSummary.duplicates} duplicates`}
            />
            {smsScanReasonEntries(smsScanSummary).map(([reason, count]) => (
              <Fragment key={reason}>
                <Divider />
                <InfoRow
                  icon="alert-circle-outline"
                  label={reason}
                  value={String(count)}
                  tone="warning"
                />
              </Fragment>
            ))}
          </>
        ) : autoCapture.sms.lastRun ? (
          <>
            <Divider />
            <InfoRow
              icon="message-processing-outline"
              label="Last run"
              value={scanSummaryLabel(autoCapture.sms.lastRun)}
              tone={
                autoCapture.sms.lastRun.posted || autoCapture.sms.lastRun.queued
                  ? 'positive'
                  : 'default'
              }
            />
            {smsScanReasonEntries(autoCapture.sms.lastRun).map(([reason, count]) => (
              <Fragment key={reason}>
                <Divider />
                <InfoRow
                  icon="alert-circle-outline"
                  label={reason}
                  value={String(count)}
                  tone="warning"
                />
              </Fragment>
            ))}
          </>
        ) : null}
      </SectionCard>

      <SectionCard
        title="Scan SMS inbox"
        subtitle="Choose the date range before reading messages from Android."
      >
        <View style={s.scanPresetRow}>
          <Button
            compact
            mode="outlined"
            icon="calendar-today"
            onPress={() => applySmsScanPreset('today')}
          >
            Today
          </Button>
          <Button
            compact
            mode="outlined"
            icon="calendar-arrow-left"
            onPress={() => applySmsScanPreset('yesterday')}
          >
            Yesterday
          </Button>
          <Button
            compact
            mode="outlined"
            icon="calendar-week"
            onPress={() => applySmsScanPreset('last7')}
          >
            Last 7 days
          </Button>
        </View>
        <View style={s.inlineInputs}>
          <DateOnlyPickerField
            label="From date"
            value={scanFromDate}
            onChange={setScanFromDate}
            allowClear
            style={s.smallInput}
          />
          <DateOnlyPickerField
            label="To date"
            value={scanToDate}
            onChange={setScanToDate}
            allowClear
            style={s.smallInput}
          />
        </View>
        <InfoRow
          icon="calendar-range-outline"
          label="Range"
          value={smsScanRangeLabel(scanFromDate, scanToDate)}
        />
        <Divider />
        <InfoRow
          icon="format-list-numbered"
          label="Limit"
          value={`${autoCapture.sms.scanLimit} newest messages in range`}
        />
        <View style={s.sampleRow}>
          <Button
            mode="contained"
            icon="message-processing-outline"
            loading={isScanningSms}
            disabled={!smsInboxAvailable || isScanningSms}
            onPress={() => void scanSmsInbox()}
          >
            Scan range
          </Button>
          <Button mode="outlined" icon="robot-outline" onPress={() => router.push('/review')}>
            {pendingReviewCount > 0 ? `Review (${pendingReviewCount})` : 'Review'}
          </Button>
          {Platform.OS === 'android' && smsPermissionState?.overall !== 'granted' ? (
            <Button
              mode="outlined"
              icon="shield-key-outline"
              onPress={() => void requestSmsPermissions()}
            >
              Allow SMS
            </Button>
          ) : null}
        </View>
      </SectionCard>

      <SectionCard
        title="Keyword categories"
        subtitle="Custom rules run before the built-in bank, card, merchant, and bill keywords."
      >
        {messageCategoryRules.length === 0 ? (
          <EmptyState
            icon="text-search"
            title="No custom rules"
            body="Add merchant or bill keywords that should always map to a category."
          />
        ) : (
          <View style={s.ruleList}>
            {messageCategoryRules.map((rule) => (
              <View key={rule.id} style={s.ruleCard}>
                <View style={s.ruleHeader}>
                  <View style={s.fill}>
                    <Text variant="titleSmall" numberOfLines={1} style={s.ruleTitle}>
                      {rule.name}
                    </Text>
                    <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                      {ruleCategoryLabel(state, rule)}
                    </Text>
                  </View>
                  <Text
                    variant="labelMedium"
                    numberOfLines={1}
                    style={{ color: theme.colors.onSurfaceVariant }}
                  >
                    {rule.enabled ? 'Enabled' : 'Paused'}
                  </Text>
                </View>
                <InlineMeta
                  numberOfLines={2}
                  items={[
                    ...rule.keywords.slice(0, 6),
                    rule.keywords.length > 6 ? `+${rule.keywords.length - 6}` : null,
                  ]}
                />
                <View style={s.sampleRow}>
                  <Button
                    compact
                    mode="contained-tonal"
                    icon="pencil-outline"
                    onPress={() => editRule(rule)}
                  >
                    Edit
                  </Button>
                  <Button compact mode="outlined" onPress={() => void toggleRule(rule)}>
                    {rule.enabled ? 'Pause' : 'Enable'}
                  </Button>
                  <Button
                    compact
                    mode="outlined"
                    textColor={theme.colors.error}
                    onPress={() => void removeRule(rule)}
                  >
                    Delete
                  </Button>
                </View>
              </View>
            ))}
          </View>
        )}

        {ruleEditorId || ruleName || ruleKeywords || ruleCategoryId ? (
          <View style={s.ruleEditor}>
            <PremiumTextInput label="Rule name" value={ruleName} onChangeText={setRuleName} />
            <PremiumTextInput
              label="Keywords"
              value={ruleKeywords}
              onChangeText={setRuleKeywords}
              placeholder="school fees, gym, apple icloud"
              multiline
            />
            <OptionSelectorRow
              label="Kind"
              value={ruleKindLabel(ruleKind)}
              description="Choose which category list to use"
              icon={ruleKind === 'income' ? 'bank-plus' : 'bank-minus'}
              onPress={() => setRulePickerMode('kind')}
            />
            <RecordSelectorRow
              icon="shape-outline"
              label="Category"
              value={
                selectedRuleCategory
                  ? (categoryBreadcrumb(state.categories, selectedRuleCategory.id) ??
                    selectedRuleCategory.name)
                  : 'Choose category'
              }
              supporting={selectedRuleCategory ? 'Custom SMS rule target' : 'Required'}
              onPress={() => setRulePickerMode('category')}
            />
            <View style={s.sampleRow}>
              <Button mode="text" onPress={resetRuleEditor}>
                Cancel
              </Button>
              <Button mode="contained" icon="content-save-outline" onPress={() => void saveRule()}>
                Save rule
              </Button>
            </View>
          </View>
        ) : (
          <Button mode="contained-tonal" icon="plus" onPress={() => setRuleName('New rule')}>
            Add custom rule
          </Button>
        )}
      </SectionCard>

      <SectionCard title="Message">
        <PremiumTextInput
          label={source === 'email' ? 'From' : 'Sender'}
          value={sender}
          onChangeText={setSender}
          autoCapitalize="none"
        />
        {source === 'email' ? (
          <PremiumTextInput label="Subject" value={subject} onChangeText={setSubject} />
        ) : null}
        <PremiumTextInput
          label="Message body"
          value={body}
          onChangeText={setBody}
          multiline
          numberOfLines={8}
          style={s.bodyInput}
        />
      </SectionCard>

      <SectionCard title="Parse preview">
        {!result ? (
          <EmptyState
            icon="message-text-outline"
            title="No message loaded"
            body="Paste a transaction alert to preview extraction."
          />
        ) : (
          <View style={s.preview}>
            <InfoRow
              icon="cash"
              label="Amount"
              value={
                result.amountMinor !== undefined && result.currency
                  ? formatMoney(
                      { amountMinor: result.amountMinor, currency: result.currency },
                      state.preferences.locale,
                    )
                  : 'Needs review'
              }
              tone={result.amountMinor !== undefined ? 'positive' : 'warning'}
            />
            <Divider />
            <InfoRow
              icon="swap-horizontal"
              label="Type"
              value={
                result.suggestedType ? transactionTypeLabel(result.suggestedType) : 'Needs review'
              }
            />
            <Divider />
            <InfoRow
              icon={selectedAccountVisual?.icon ?? 'bank-outline'}
              iconBackgroundColor={selectedAccountVisual?.backgroundColor}
              iconColor={selectedAccountVisual?.iconColor}
              label="Account"
              value={
                selectedAccount?.name ?? (result.match.ambiguous ? 'Ambiguous' : 'Needs detail')
              }
              tone={selectedAccount ? 'positive' : 'warning'}
            />
            <Divider />
            <InfoRow
              icon="store-outline"
              label="Merchant"
              value={result.merchant ?? 'Needs review'}
            />
            <Divider />
            <InfoRow
              icon="shape-outline"
              label="Category"
              value={
                matchedCategory
                  ? (categoryBreadcrumb(state.categories, matchedCategory.id) ??
                    matchedCategory.name)
                  : result.categoryMatch.ambiguous
                    ? 'Ambiguous'
                    : 'Needs review'
              }
              tone={matchedCategory ? 'positive' : 'warning'}
            />
            <Divider />
            <InfoRow
              icon="calendar-outline"
              label="Date"
              value={
                result.occurredAt ? new Date(result.occurredAt).toLocaleString() : 'Needs review'
              }
            />
            <Divider />
            <InfoRow
              icon="percent-outline"
              label="Confidence"
              value={`${Math.round(result.confidence)}%`}
            />
            {result.fragments.length > 0 ? (
              <InlineMeta
                numberOfLines={3}
                items={result.fragments.map(
                  (fragment) => `${fragment.label ?? fragment.kind}: ${fragment.value}`,
                )}
              />
            ) : null}
            {result.warnings.length > 0 ? (
              <View style={[s.warningBox, { backgroundColor: theme.colors.secondaryContainer }]}>
                {result.warnings.map((warning) => (
                  <Text
                    key={warning}
                    variant="labelMedium"
                    style={{ color: theme.colors.onSecondaryContainer }}
                  >
                    {warning}
                  </Text>
                ))}
              </View>
            ) : null}
            {hintSuggestions.length > 0 ? (
              <View style={s.hintPanel}>
                <Text variant="titleSmall">Suggested account hints</Text>
                <View style={s.chips}>
                  {hintSuggestions.map((hint) => {
                    const id = hint.id ?? hintId(hint);
                    const selected = selectedHintIds.includes(id);
                    return (
                      <Chip
                        key={id}
                        compact
                        selected={selected}
                        disabled={hint.existing}
                        onPress={() => toggleHint(id)}
                      >
                        {hint.label ?? hint.kind}: {hint.value}
                        {hint.existing ? ' saved' : ''}
                      </Chip>
                    );
                  })}
                </View>
              </View>
            ) : null}
            <Button
              mode="contained"
              icon="inbox-arrow-down-outline"
              disabled={!result.candidateInput}
              onPress={queueCapture}
            >
              Queue to review
            </Button>
          </View>
        )}
      </SectionCard>

      {result?.match.candidates.length ? (
        <SectionCard title="Account candidates">
          {result.match.candidates.map((candidate, index) => (
            <View key={candidate.accountId}>
              <Button
                mode={candidate.accountId === selectedAccount?.id ? 'contained-tonal' : 'outlined'}
                icon="target-account"
                onPress={() => setSelectedAccountId(candidate.accountId)}
              >
                Use {candidate.accountName}
              </Button>
              <InfoRow
                icon="target-account"
                label={candidate.accountName}
                value={`${candidate.score}`}
                tone={candidate.accountId === result.match.accountId ? 'positive' : 'default'}
              />
              <InlineMeta items={candidate.matchedBy} />
              {index < result.match.candidates.length - 1 ? <Divider /> : null}
            </View>
          ))}
        </SectionCard>
      ) : null}
      <OptionListOverlay
        visible={rulePickerMode === 'kind'}
        title="Choose rule kind"
        options={RULE_KIND_OPTIONS}
        selectedValue={ruleKind}
        searchable={false}
        onDismiss={() => setRulePickerMode(null)}
        onSelect={(option) => {
          setRuleKind(option.value);
          setRulePickerMode(null);
        }}
      />
      <CategoryPickerOverlay
        visible={rulePickerMode === 'category'}
        kind={ruleKind}
        categories={state.categories}
        selectedId={ruleCategoryId}
        onDismiss={() => setRulePickerMode(null)}
        onClear={() => {
          setRuleCategoryId(undefined);
          setRulePickerMode(null);
        }}
        onSelect={(category) => {
          setRuleCategoryId(category.id);
          setRulePickerMode(null);
        }}
      />
    </AppScreen>
  );
}

function hintId(hint: AccountMessageHint): string {
  return `${hint.target}:${hint.kind}:${hint.value}`;
}

function showSmsPermissionAlert(status: AndroidSmsPermissionStatus) {
  if (status === 'blocked') {
    Alert.alert(
      'SMS permission blocked',
      'Android is no longer showing the SMS prompt for 1wallet. Open app settings and allow SMS to enable Auto Capture.',
      [
        { text: 'Not now', style: 'cancel' },
        { text: 'Open settings', onPress: () => void Linking.openSettings() },
      ],
    );
    return;
  }
  Alert.alert('SMS permission needed', 'Allow SMS access before enabling SMS capture.');
}

function smsPermissionLabel(state?: AndroidSmsPermissionState): string {
  if (!state) return 'Checking';
  if (state.overall === 'unavailable') return 'Android only';
  if (state.overall === 'granted') return 'Granted';
  if (state.overall === 'partial') return 'Partly granted';
  return 'Not granted';
}

function smsPermissionTone(
  state?: AndroidSmsPermissionState,
): 'default' | 'positive' | 'warning' | 'danger' {
  if (!state) return 'default';
  if (state.overall === 'granted') return 'positive';
  if (state.overall === 'partial') return 'warning';
  return 'warning';
}

function scanSummaryLabel(summary: {
  posted: number;
  queued: number;
  ignored: number;
  unrecognized?: number;
}) {
  return `${summary.posted} posted, ${summary.queued} queued, ${summary.ignored} ignored, ${summary.unrecognized ?? 0} unrecognized`;
}

function smsScanReasonEntries(summary: { ignoredReasons?: Record<string, number> }) {
  return Object.entries(summary.ignoredReasons ?? {})
    .filter((entry): entry is [string, number] => entry[1] > 0)
    .sort((left, right) => right[1] - left[1]);
}

function smsScanDateRange(fromDate: string, toDate: string) {
  const from = parseLocalDate(fromDate);
  const to = parseLocalDate(toDate);
  if (!from || !to) return undefined;
  const max = new Date(to);
  max.setHours(23, 59, 59, 999);
  return {
    minDate: from.getTime(),
    maxDate: max.getTime(),
    label: fromDate === toDate ? fromDate : `${fromDate} to ${toDate}`,
  };
}

function smsScanRangeLabel(fromDate: string, toDate: string): string {
  const range = smsScanDateRange(fromDate, toDate);
  if (!range) return 'Invalid date range';
  return range.label;
}

function localDateString(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function parseLocalDate(value: string): Date | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (!match) return undefined;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(year, month - 1, day);
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
    return undefined;
  }
  date.setHours(0, 0, 0, 0);
  return date;
}

function startOfLocalDay(date: Date): Date {
  const next = new Date(date);
  next.setHours(0, 0, 0, 0);
  return next;
}

function addLocalDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

function smsCaptureReason(result: TransactionMessageCaptureResult): string | undefined {
  if (result.outcome === 'ignored') return ignoredReasonLabel(result.trigger.ignoredReason);
  if (result.outcome === 'unrecognized') return result.parseResult?.warnings[0] ?? 'Unrecognized';
  if (result.outcome === 'duplicate') return 'Duplicate';
  if (result.error) return 'Auto-post failed';
  return undefined;
}

function ignoredReasonLabel(reason: TransactionMessageCaptureResult['trigger']['ignoredReason']) {
  switch (reason) {
    case 'security':
      return 'Security or OTP';
    case 'balance_only':
      return 'Balance only';
    case 'ignored_sender':
      return 'Ignored sender';
    case 'no_trigger_keyword':
      return 'No trigger keyword';
    default:
      return 'Ignored';
  }
}

function splitKeywordList(value: string): string[] {
  return value
    .split(/[\n,]/g)
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function ruleCategoryLabel(
  state: ReturnType<typeof useLedger>['state'],
  rule: MessageCategoryKeywordRule,
): string {
  return categoryBreadcrumb(state.categories, rule.categoryId) ?? 'Missing category';
}

function ruleKindLabel(kind: RuleEditorKind): string {
  return kind === 'income' ? 'Income' : 'Expense';
}

const s = StyleSheet.create({
  fill: { flex: 1, minWidth: 0 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  sampleRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  switchRow: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.md },
  inlineInputs: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  smallInput: { flex: 1, minWidth: 168 },
  scanPresetRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  bodyInput: { minHeight: 180 },
  preview: { gap: tokens.space.sm },
  hintPanel: { gap: tokens.space.sm, paddingTop: tokens.space.xs },
  ruleList: { gap: tokens.space.sm },
  ruleCard: { gap: tokens.space.sm, paddingVertical: tokens.space.xs },
  ruleHeader: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.sm },
  ruleTitle: { fontWeight: '800' },
  ruleEditor: { gap: tokens.space.sm, paddingTop: tokens.space.sm },
  warningBox: { borderRadius: tokens.radius.md, padding: tokens.space.md, gap: 4 },
});
