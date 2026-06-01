import type { Transaction } from '@1wallet/domain/types';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useEffect, useMemo, useRef, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Text, TextInput, TouchableRipple, useTheme } from 'react-native-paper';
import { PremiumTextInput, premiumSurfaceBorder } from '../AppKit';

type NoteSuggestionSource = Pick<
  Transaction,
  'id' | 'notes' | 'occurredAt' | 'createdAt' | 'updatedAt'
>;

type NoteAutocompleteInputProps = {
  value: string;
  onChangeText: (value: string) => void;
  sources: readonly NoteSuggestionSource[];
  excludeTransactionId?: string;
  label?: string;
  numberOfLines?: number;
  maxSuggestions?: number;
};

type NoteSuggestionCandidate = {
  note: string;
  normalized: string;
  position: number;
  wordRank: number;
  timestamp: number;
};

export function NoteAutocompleteInput({
  value,
  onChangeText,
  sources,
  excludeTransactionId,
  label = 'Notes',
  numberOfLines = 3,
  maxSuggestions = 5,
}: NoteAutocompleteInputProps) {
  const theme = useTheme();
  const [focused, setFocused] = useState(false);
  const blurTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const suggestions = useMemo(
    () =>
      noteSuggestionsFromTransactions(sources, value, {
        excludeTransactionId,
        limit: maxSuggestions,
      }),
    [excludeTransactionId, maxSuggestions, sources, value],
  );
  const showSuggestions = focused && suggestions.length > 0;

  const clearBlurTimer = () => {
    if (!blurTimerRef.current) return;
    clearTimeout(blurTimerRef.current);
    blurTimerRef.current = null;
  };

  useEffect(
    () => () => {
      if (blurTimerRef.current) clearTimeout(blurTimerRef.current);
    },
    [],
  );

  const selectSuggestion = (suggestion: string) => {
    clearBlurTimer();
    onChangeText(suggestion);
    setFocused(false);
  };

  return (
    <View style={styles.container}>
      <PremiumTextInput
        label={label}
        value={value}
        onChangeText={onChangeText}
        onFocus={() => {
          clearBlurTimer();
          setFocused(true);
        }}
        onBlur={() => {
          clearBlurTimer();
          blurTimerRef.current = setTimeout(() => setFocused(false), 140);
        }}
        multiline
        numberOfLines={numberOfLines}
        left={<TextInput.Icon icon="note-text-outline" />}
      />
      {showSuggestions ? (
        <View
          style={[
            styles.suggestionList,
            {
              backgroundColor: theme.colors.elevation.level2,
              borderColor: premiumSurfaceBorder(theme),
            },
          ]}
        >
          {suggestions.map((suggestion, index) => (
            <TouchableRipple
              key={suggestion}
              accessibilityRole="button"
              accessibilityLabel={`Use note ${suggestion}`}
              onPress={() => selectSuggestion(suggestion)}
            >
              <View
                style={[
                  styles.suggestionRow,
                  index > 0 && {
                    borderTopColor: theme.colors.outlineVariant,
                    borderTopWidth: StyleSheet.hairlineWidth,
                  },
                ]}
              >
                <View
                  style={[
                    styles.suggestionIcon,
                    { backgroundColor: theme.colors.secondaryContainer },
                  ]}
                >
                  <MaterialCommunityIcons
                    name="history"
                    size={16}
                    color={theme.colors.onSecondaryContainer}
                  />
                </View>
                <Text variant="bodyMedium" numberOfLines={2} style={styles.suggestionText}>
                  {suggestion}
                </Text>
              </View>
            </TouchableRipple>
          ))}
        </View>
      ) : null}
    </View>
  );
}

export function noteSuggestionsFromTransactions(
  sources: readonly NoteSuggestionSource[],
  value: string,
  options: { excludeTransactionId?: string; limit?: number } = {},
): string[] {
  const query = normalizeNoteForSearch(value);
  if (!query) return [];

  const candidatesByNote = new Map<string, NoteSuggestionCandidate>();
  for (const source of sources) {
    if (source.id === options.excludeTransactionId) continue;
    const note = source.notes?.trim();
    if (!note) continue;

    const normalized = normalizeNoteForSearch(note);
    if (!normalized || normalized === query) continue;

    const position = normalized.indexOf(query);
    if (position < 0) continue;

    const wordRank = normalized.startsWith(query) ? 0 : normalized.includes(` ${query}`) ? 1 : 2;
    const candidate: NoteSuggestionCandidate = {
      note,
      normalized,
      position,
      wordRank,
      timestamp: noteTimestamp(source),
    };
    const previous = candidatesByNote.get(normalized);
    if (!previous || candidate.timestamp > previous.timestamp) {
      candidatesByNote.set(normalized, candidate);
    }
  }

  return Array.from(candidatesByNote.values())
    .sort(
      (left, right) =>
        left.wordRank - right.wordRank ||
        left.position - right.position ||
        right.timestamp - left.timestamp ||
        left.note.length - right.note.length ||
        left.normalized.localeCompare(right.normalized),
    )
    .slice(0, options.limit ?? 5)
    .map((candidate) => candidate.note);
}

function normalizeNoteForSearch(value: string): string {
  return value.trim().replace(/\s+/g, ' ').toLowerCase();
}

function noteTimestamp(source: NoteSuggestionSource): number {
  const times = [source.occurredAt, source.updatedAt, source.createdAt]
    .map((value) => Date.parse(value))
    .filter((value) => !Number.isNaN(value));
  return times.length > 0 ? Math.max(...times) : 0;
}

const styles = StyleSheet.create({
  container: { gap: tokens.space.xs },
  suggestionList: {
    borderRadius: tokens.radius.lg,
    borderWidth: 1,
    overflow: 'hidden',
  },
  suggestionRow: {
    minHeight: 48,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
    paddingHorizontal: tokens.space.md,
    paddingVertical: tokens.space.sm,
  },
  suggestionIcon: {
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  suggestionText: { flex: 1 },
});
