import { tokens } from '@1wallet/ui';
import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { Button, TextInput } from 'react-native-paper';
import {
    formatCompactDateLabel,
    formatLocalTime12,
    localDateTimeParts,
    shiftLocalDate,
} from '../../recordDateTime';
import { PremiumTextInput } from '../AppKit';
import { RecordDateTimePickerOverlay } from './RecordDateTimePickerOverlay';

type PickerMode = 'date' | 'time' | null;

export function RecordDateTimeFields({
  date,
  time,
  layout = 'row',
  onChangeDate,
  onChangeTime,
}: {
  date: string;
  time: string;
  layout?: 'row' | 'stacked';
  onChangeDate: (value: string) => void;
  onChangeTime: (value: string) => void;
}) {
  const [pickerMode, setPickerMode] = useState<PickerMode>(null);
  const stacked = layout === 'stacked';

  const setNow = () => {
    const now = localDateTimeParts(new Date());
    onChangeDate(now.date);
    onChangeTime(now.time);
  };

  return (
    <View style={styles.wrapper}>
      <View style={styles.quickRow}>
        <Button compact mode="contained-tonal" icon="calendar-today" onPress={setNow}>
          Now
        </Button>
        <Button
          compact
          mode="outlined"
          icon="chevron-left"
          onPress={() => onChangeDate(shiftLocalDate(date, -1))}
        >
          Day
        </Button>
        <Button
          compact
          mode="outlined"
          icon="chevron-right"
          onPress={() => onChangeDate(shiftLocalDate(date, 1))}
        >
          Day
        </Button>
      </View>
      <View style={[styles.fieldsRow, stacked && styles.fieldsColumn]}>
        <Pressable
          style={stacked ? styles.fullField : styles.dateField}
          onPress={() => setPickerMode('date')}
        >
          <View pointerEvents="none" style={styles.fieldInner}>
            <PremiumTextInput
              label="Date"
              value={formatCompactDateLabel(date)}
              placeholder="Select date"
              editable={false}
              contentStyle={styles.dateInputContent}
              right={<TextInput.Icon icon="calendar-outline" />}
            />
          </View>
        </Pressable>
        <Pressable
          style={stacked ? styles.fullField : styles.timeField}
          onPress={() => setPickerMode('time')}
        >
          <View pointerEvents="none" style={styles.fieldInner}>
            <PremiumTextInput
              label="Time"
              value={formatLocalTime12(time)}
              placeholder="Select time"
              editable={false}
              contentStyle={styles.dateInputContent}
              right={<TextInput.Icon icon="clock-outline" />}
            />
          </View>
        </Pressable>
      </View>
      <RecordDateTimePickerOverlay
        visible={pickerMode !== null}
        mode={pickerMode ?? 'date'}
        date={date}
        time={time}
        onDismiss={() => setPickerMode(null)}
        onConfirm={(value) => {
          onChangeDate(value.date);
          onChangeTime(value.time);
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: { gap: tokens.space.sm },
  quickRow: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.xs },
  fieldsRow: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.xs, width: '100%' },
  fieldsColumn: { flexDirection: 'column' },
  dateField: { flex: 1.35, minWidth: 168 },
  timeField: { flex: 1, minWidth: 124 },
  fullField: { width: '100%', minWidth: 0 },
  fieldInner: { width: '100%' },
  dateInputContent: { fontSize: 14, lineHeight: 20 },
});
