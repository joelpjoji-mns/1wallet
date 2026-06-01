import type {
    FutureRuleOccurrence,
    PostFutureRuleOccurrenceOverrides,
} from '@1wallet/ledger/rules/futureGeneration';
import type { FutureGenerationRule, LedgerState } from '@1wallet/ledger/store/types';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { Button, Portal, Surface, Text, useTheme } from 'react-native-paper';
import { useBackLayer } from '../components/AppBackLayer';
import { RecordDateTimeFields } from '../components/record/RecordDateTimeFields';
import {
    dateTimeToIso,
    isValidLocalDate,
    isValidLocalTime,
    localDateTimePartsFromIso,
} from '../recordDateTime';
import { dueLabel } from './display';

type PostponeDraft = {
  date: string;
  time: string;
};

export function OccurrencePostponeDialog({
  visible,
  rule,
  occurrence,
  state,
  title = 'Postpone occurrence',
  confirmLabel = 'Postpone',
  onDismiss,
  onPostpone,
}: {
  visible: boolean;
  rule?: FutureGenerationRule | null;
  occurrence?: FutureRuleOccurrence;
  state: LedgerState;
  title?: string;
  confirmLabel?: string;
  onDismiss: () => void;
  onPostpone: (overrides: PostFutureRuleOccurrenceOverrides) => Promise<void> | void;
}) {
  const theme = useTheme();
  const [draft, setDraft] = useState<PostponeDraft>(() => emptyDraft(occurrence));
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useBackLayer(visible, onDismiss);

  useEffect(() => {
    if (!visible) return;
    setDraft(emptyDraft(occurrence));
    setError(null);
    setBusy(false);
  }, [occurrence, visible]);

  if (!visible || !rule || !occurrence) return null;

  const update = (patch: Partial<PostponeDraft>) =>
    setDraft((current) => ({ ...current, ...patch }));

  const postpone = async () => {
    if (!isValidLocalDate(draft.date)) {
      setError('Enter a valid date');
      return;
    }
    if (!isValidLocalTime(draft.time)) {
      setError('Enter a valid time');
      return;
    }

    setBusy(true);
    setError(null);
    try {
      await onPostpone({
        occurredAt: dateTimeToIso(draft.date, draft.time, new Date(occurrence.occurredAt)),
      });
    } catch (caught) {
      setError((caught as Error).message);
      setBusy(false);
    }
  };

  return (
    <Portal>
      <Pressable style={styles.backdrop} onPress={onDismiss} />
      <Surface
        style={[
          styles.sheet,
          {
            backgroundColor: theme.colors.background,
            borderColor: theme.colors.outlineVariant,
          },
        ]}
        elevation={4}
      >
        <ScrollView
          contentContainerStyle={styles.content}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          <View style={styles.headerRow}>
            <View style={[styles.headerIcon, { backgroundColor: theme.colors.primaryContainer }]}>
              <MaterialCommunityIcons
                name="calendar-arrow-right"
                size={22}
                color={theme.colors.primary}
              />
            </View>
            <View style={styles.fill}>
              <Text variant="titleMedium" numberOfLines={1} style={styles.title}>
                {title}
              </Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                {rule.name} · {dueLabel(occurrence.occurredAt, state.preferences.locale)}
              </Text>
            </View>
          </View>

          <RecordDateTimeFields
            date={draft.date}
            time={draft.time}
            layout="stacked"
            onChangeDate={(date) => update({ date })}
            onChangeTime={(time) => update({ time })}
          />

          {error ? (
            <Text variant="bodySmall" style={{ color: theme.colors.error }}>
              {error}
            </Text>
          ) : null}

          <View style={styles.actionRow}>
            <Button mode="text" onPress={onDismiss} disabled={busy}>
              Cancel
            </Button>
            <Button
              mode="contained"
              icon="calendar-arrow-right"
              loading={busy}
              disabled={busy}
              onPress={() => void postpone()}
            >
              {confirmLabel}
            </Button>
          </View>
        </ScrollView>
      </Surface>
    </Portal>
  );
}

function emptyDraft(occurrence?: FutureRuleOccurrence): PostponeDraft {
  const dateTime = occurrence
    ? localDateTimePartsFromIso(occurrence.occurredAt)
    : localDateTimePartsFromIso(new Date().toISOString());
  return { date: dateTime.date, time: dateTime.time };
}

const styles = StyleSheet.create({
  backdrop: {
    ...StyleSheet.absoluteFill,
    backgroundColor: 'rgba(0,0,0,0.42)',
  },
  sheet: {
    position: 'absolute',
    left: tokens.space.md,
    right: tokens.space.md,
    bottom: tokens.space.lg,
    maxHeight: '88%',
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  content: {
    gap: tokens.space.md,
    padding: tokens.space.md,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
  },
  headerIcon: {
    width: 42,
    height: 42,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  fill: { flex: 1, minWidth: 0 },
  title: { fontWeight: '800' },
  actionRow: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    flexWrap: 'wrap',
    gap: tokens.space.sm,
  },
});
