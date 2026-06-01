import { useState } from 'react';
import { Pressable, StyleProp, StyleSheet, View, ViewStyle } from 'react-native';
import { Button, TextInput } from 'react-native-paper';
import { formatCompactDateLabel, isValidLocalDate, localDateTimeParts } from '../recordDateTime';
import { PremiumTextInput } from './AppKit';
import { RecordDateTimePickerOverlay } from './record/RecordDateTimePickerOverlay';

export function DateOnlyPickerField({
  label,
  value,
  placeholder = 'Select date',
  onChange,
  style,
  allowClear = false,
}: {
  label: string;
  value: string;
  placeholder?: string;
  onChange: (value: string) => void;
  style?: StyleProp<ViewStyle>;
  allowClear?: boolean;
}) {
  const [visible, setVisible] = useState(false);
  const today = localDateTimeParts(new Date()).date;
  const pickerDate = isValidLocalDate(value) ? value : today;
  const displayValue = value
    ? isValidLocalDate(value)
      ? formatCompactDateLabel(value)
      : value
    : '';

  return (
    <View style={[styles.wrapper, style]}>
      <Pressable onPress={() => setVisible(true)}>
        <View pointerEvents="none" style={styles.fieldInner}>
          <PremiumTextInput
            mode="outlined"
            label={label}
            value={displayValue}
            placeholder={placeholder}
            editable={false}
            contentStyle={styles.inputContent}
            right={<TextInput.Icon icon="calendar-outline" />}
          />
        </View>
      </Pressable>
      {allowClear && value ? (
        <Button compact mode="text" icon="close-circle-outline" onPress={() => onChange('')}>
          Clear date
        </Button>
      ) : null}
      <RecordDateTimePickerOverlay
        visible={visible}
        mode="date"
        date={pickerDate}
        time="00:00"
        onDismiss={() => setVisible(false)}
        onConfirm={(next) => {
          onChange(next.date);
          setVisible(false);
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: { minWidth: 168 },
  fieldInner: { width: '100%' },
  inputContent: { fontSize: 14, lineHeight: 20 },
});
