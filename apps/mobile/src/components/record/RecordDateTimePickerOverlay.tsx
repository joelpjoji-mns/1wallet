import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
    Pressable,
    ScrollView,
    StyleSheet,
    View,
    type NativeScrollEvent,
    type NativeSyntheticEvent,
} from 'react-native';
import { Button, IconButton, Portal, Surface, Text, useTheme } from 'react-native-paper';
import { localDateTimeParts } from '../../recordDateTime';
import { useBackLayer } from '../AppBackLayer';

type DateTimeDraft = { date: string; time: string };
type Period = 'AM' | 'PM';
type PickerMode = 'date' | 'time';

const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const WHEEL_ITEM_HEIGHT = 44;
const WHEEL_VISIBLE_ITEMS = 5;
const WHEEL_VERTICAL_PADDING = WHEEL_ITEM_HEIGHT * Math.floor(WHEEL_VISIBLE_ITEMS / 2);
const WHEEL_LOOP_COPIES = 31;
const WHEEL_LOOP_CENTER_COPY = Math.floor(WHEEL_LOOP_COPIES / 2);

export function RecordDateTimePickerOverlay({
  visible,
  mode,
  date,
  time,
  onDismiss,
  onConfirm,
}: {
  visible: boolean;
  mode: PickerMode;
  date: string;
  time: string;
  onDismiss: () => void;
  onConfirm: (value: DateTimeDraft) => void;
}) {
  const theme = useTheme();
  const [selectedDate, setSelectedDate] = useState(date);
  const [visibleMonth, setVisibleMonth] = useState(() => startOfMonth(parseDate(date)));
  const [hour, setHour] = useState(() => parseTime12(time).hour);
  const [minute, setMinute] = useState(() => parseTime12(time).minute);
  const [period, setPeriod] = useState<Period>(() => parseTime12(time).period);

  useBackLayer(visible, onDismiss);

  useEffect(() => {
    if (!visible) return;
    const nextDate = parseDate(date);
    const nextTime = parseTime12(time);
    setSelectedDate(localDateTimeParts(nextDate).date);
    setVisibleMonth(startOfMonth(nextDate));
    setHour(nextTime.hour);
    setMinute(nextTime.minute);
    setPeriod(nextTime.period);
  }, [date, time, visible]);

  const weeks = useMemo(() => calendarWeeks(visibleMonth), [visibleMonth]);
  const monthTitle = visibleMonth.toLocaleDateString(undefined, {
    month: 'long',
    year: 'numeric',
  });
  const selectedDateValue = parseDate(selectedDate);
  const selectedSummary = selectedDateValue.toLocaleDateString(undefined, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  });
  const displayTime = `${hour}:${pad2(minute)} ${period}`;

  if (!visible) return null;

  const chooseCurrent = () => {
    const today = new Date();
    setSelectedDate(localDateTimeParts(today).date);
    setVisibleMonth(startOfMonth(today));
    if (mode === 'time') {
      const nextTime = parseTime12(localDateTimeParts(today).time);
      setHour(nextTime.hour);
      setMinute(nextTime.minute);
      setPeriod(nextTime.period);
    }
  };

  const confirm = () => {
    onConfirm({ date: selectedDate, time: to24HourTime(hour, minute, period) });
    onDismiss();
  };

  return (
    <Portal>
      <View style={styles.backdrop}>
        <Surface
          style={[
            styles.dialog,
            {
              backgroundColor: theme.colors.elevation.level2,
              borderColor: theme.colors.outlineVariant,
            },
          ]}
          elevation={5}
        >
          <View style={styles.header}>
            <IconButton icon="close" onPress={onDismiss} />
            <View style={styles.headerCopy}>
              <Text variant="titleLarge" style={styles.title}>
                {mode === 'date' ? 'Choose date' : 'Choose time'}
              </Text>
              <Text
                variant="bodyMedium"
                numberOfLines={2}
                style={{ color: theme.colors.onSurfaceVariant }}
              >
                {selectedSummary} at {displayTime}
              </Text>
            </View>
          </View>

          <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
            <SummaryPanel selectedDateValue={selectedDateValue} displayTime={displayTime} />

            {mode === 'date' ? (
              <>
                <View style={styles.monthHeader}>
                  <IconButton
                    icon="chevron-left"
                    mode="contained-tonal"
                    onPress={() => setVisibleMonth(addMonths(visibleMonth, -1))}
                  />
                  <Text variant="titleMedium" style={styles.monthTitle}>
                    {monthTitle}
                  </Text>
                  <IconButton
                    icon="chevron-right"
                    mode="contained-tonal"
                    onPress={() => setVisibleMonth(addMonths(visibleMonth, 1))}
                  />
                </View>

                <CalendarGrid
                  weeks={weeks}
                  selectedDate={selectedDate}
                  visibleMonth={visibleMonth}
                  onSelectDate={setSelectedDate}
                />
              </>
            ) : (
              <TimePanel
                hour={hour}
                minute={minute}
                period={period}
                displayTime={displayTime}
                onChangeHour={setHour}
                onChangeMinute={setMinute}
                onChangePeriod={setPeriod}
              />
            )}

            <View style={styles.actions}>
              <Button
                mode="contained-tonal"
                icon={mode === 'date' ? 'calendar-today' : 'clock-outline'}
                onPress={chooseCurrent}
              >
                {mode === 'date' ? 'Today' : 'Now'}
              </Button>
              <Button mode="outlined" onPress={onDismiss}>
                Cancel
              </Button>
              <Button mode="contained" icon="check" onPress={confirm}>
                Apply
              </Button>
            </View>
          </ScrollView>
        </Surface>
      </View>
    </Portal>
  );
}

function SummaryPanel({
  selectedDateValue,
  displayTime,
}: {
  selectedDateValue: Date;
  displayTime: string;
}) {
  const theme = useTheme();
  return (
    <View style={[styles.summaryPanel, { backgroundColor: theme.colors.primaryContainer }]}>
      <View style={styles.summaryCopy}>
        <Text variant="labelLarge" style={{ color: theme.colors.onPrimaryContainer }}>
          {selectedDateValue.toLocaleDateString(undefined, { weekday: 'long' }).toUpperCase()}
        </Text>
        <Text
          variant="headlineSmall"
          numberOfLines={1}
          adjustsFontSizeToFit
          minimumFontScale={0.78}
          style={[styles.summaryDate, { color: theme.colors.primary }]}
        >
          {selectedDateValue.toLocaleDateString(undefined, { month: 'long', day: 'numeric' })}
        </Text>
      </View>
      <View style={[styles.summaryTimePill, { backgroundColor: theme.colors.surfaceVariant }]}>
        <MaterialCommunityIcons
          name="clock-outline"
          size={20}
          color={theme.colors.onSurfaceVariant}
        />
        <Text
          variant="titleMedium"
          numberOfLines={1}
          adjustsFontSizeToFit
          minimumFontScale={0.8}
          style={{ color: theme.colors.onSurfaceVariant }}
        >
          {displayTime}
        </Text>
      </View>
    </View>
  );
}

function CalendarGrid({
  weeks,
  selectedDate,
  visibleMonth,
  onSelectDate,
}: {
  weeks: Date[][];
  selectedDate: string;
  visibleMonth: Date;
  onSelectDate: (value: string) => void;
}) {
  const theme = useTheme();
  const todayDate = localDateTimeParts(new Date()).date;
  return (
    <View style={styles.calendarGrid}>
      <View style={styles.weekRow}>
        {WEEKDAYS.map((day) => (
          <Text
            key={day}
            variant="labelMedium"
            style={[styles.weekday, { color: theme.colors.onSurfaceVariant }]}
          >
            {day}
          </Text>
        ))}
      </View>
      {weeks.map((week) => (
        <View key={week.map((day) => day.toISOString()).join('-')} style={styles.weekRow}>
          {week.map((day) => {
            const local = localDateTimeParts(day).date;
            const selected = local === selectedDate;
            const outside = day.getMonth() !== visibleMonth.getMonth();
            const today = local === todayDate;
            return (
              <Pressable
                key={local}
                style={[
                  styles.dayCell,
                  selected && { backgroundColor: theme.colors.primary },
                  !selected && today && { borderColor: theme.colors.primary, borderWidth: 1 },
                ]}
                onPress={() => onSelectDate(local)}
              >
                <View style={styles.dayInner}>
                  <Text
                    variant="titleSmall"
                    numberOfLines={1}
                    adjustsFontSizeToFit
                    minimumFontScale={0.8}
                    style={{
                      color: selected
                        ? theme.colors.onPrimary
                        : outside
                          ? theme.colors.onSurfaceDisabled
                          : theme.colors.onSurface,
                      fontWeight: selected ? '800' : '600',
                    }}
                  >
                    {day.getDate()}
                  </Text>
                </View>
              </Pressable>
            );
          })}
        </View>
      ))}
    </View>
  );
}

function TimePanel({
  hour,
  minute,
  period,
  displayTime,
  onChangeHour,
  onChangeMinute,
  onChangePeriod,
}: {
  hour: number;
  minute: number;
  period: Period;
  displayTime: string;
  onChangeHour: (value: number) => void;
  onChangeMinute: (value: number) => void;
  onChangePeriod: (value: Period) => void;
}) {
  const theme = useTheme();
  return (
    <View
      style={[
        styles.timePanel,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
    >
      <View style={styles.timeHeader}>
        <MaterialCommunityIcons name="clock-outline" size={22} color={theme.colors.primary} />
        <View style={styles.timeHeaderCopy}>
          <Text variant="titleMedium" style={styles.timeTitle}>
            Time
          </Text>
        </View>
        <Text variant="titleLarge" style={styles.timeValue}>
          {displayTime}
        </Text>
      </View>

      <View style={styles.wheelLabelRow}>
        <Text
          variant="labelLarge"
          style={[styles.wheelLabel, { color: theme.colors.onSurfaceVariant }]}
        >
          Hour
        </Text>
        <Text variant="labelLarge" style={styles.wheelColonLabel}>
          {' '}
        </Text>
        <Text
          variant="labelLarge"
          style={[styles.wheelLabel, { color: theme.colors.onSurfaceVariant }]}
        >
          Minute
        </Text>
        <Text
          variant="labelLarge"
          style={[styles.wheelLabel, { color: theme.colors.onSurfaceVariant }]}
        >
          AM/PM
        </Text>
      </View>

      <View style={styles.wheelPicker}>
        <View
          pointerEvents="none"
          style={[styles.wheelSelectionBand, { backgroundColor: theme.colors.primaryContainer }]}
        />
        <TimeWheelColumn values={HOUR_VALUES} selectedValue={hour} onChange={onChangeHour} loop />
        <Text
          variant="displaySmall"
          style={[styles.wheelSeparator, { color: theme.colors.primary }]}
        >
          :
        </Text>
        <TimeWheelColumn
          values={MINUTE_VALUES}
          selectedValue={minute}
          onChange={onChangeMinute}
          loop
        />
        <TimeWheelColumn values={PERIOD_VALUES} selectedValue={period} onChange={onChangePeriod} />
      </View>
    </View>
  );
}

function TimeWheelColumn<TValue extends string | number>({
  values,
  selectedValue,
  onChange,
  loop = false,
}: {
  values: { value: TValue; label: string }[];
  selectedValue: TValue;
  onChange: (value: TValue) => void;
  loop?: boolean;
}) {
  const theme = useTheme();
  const scrollRef = useRef<ScrollView>(null);
  const suppressNextSyncRef = useRef(false);
  const valueCount = values.length;
  const wheelValues = useMemo(
    () =>
      loop
        ? Array.from(
            { length: valueCount * WHEEL_LOOP_COPIES },
            (_, index) => values[positiveModulo(index, valueCount)]!,
          )
        : values,
    [loop, valueCount, values],
  );
  const selectedBaseIndex = Math.max(
    0,
    values.findIndex((item) => item.value === selectedValue),
  );

  const scrollToIndex = useCallback((index: number, animated: boolean) => {
    scrollRef.current?.scrollTo({ y: index * WHEEL_ITEM_HEIGHT, animated });
  }, []);

  const centeredLoopIndex = useCallback(
    (baseIndex: number) => (loop ? baseIndex + valueCount * WHEEL_LOOP_CENTER_COPY : baseIndex),
    [loop, valueCount],
  );

  useEffect(() => {
    if (suppressNextSyncRef.current) {
      suppressNextSyncRef.current = false;
      return;
    }
    const frame = requestAnimationFrame(() => {
      scrollToIndex(centeredLoopIndex(selectedBaseIndex), false);
    });
    return () => cancelAnimationFrame(frame);
  }, [centeredLoopIndex, scrollToIndex, selectedBaseIndex]);

  const selectIndex = (index: number, animated = true) => {
    const nextWheelIndex = loop
      ? positiveModulo(index, wheelValues.length)
      : clamp(index, 0, valueCount - 1);
    const nextBaseIndex = loop ? positiveModulo(nextWheelIndex, valueCount) : nextWheelIndex;
    const nextValue = values[nextBaseIndex]?.value;
    if (nextValue === undefined) return;
    suppressNextSyncRef.current = true;
    onChange(nextValue);
    scrollToIndex(centeredLoopIndex(nextBaseIndex), animated);
  };

  const handleMomentumScrollEnd = (event: NativeSyntheticEvent<NativeScrollEvent>) => {
    selectIndex(Math.round(event.nativeEvent.contentOffset.y / WHEEL_ITEM_HEIGHT), false);
  };

  const handleScrollEndDrag = (event: NativeSyntheticEvent<NativeScrollEvent>) => {
    const velocity = event.nativeEvent.velocity?.y ?? 0;
    if (Math.abs(velocity) > 0.05) return;
    requestAnimationFrame(() => {
      selectIndex(Math.round(event.nativeEvent.contentOffset.y / WHEEL_ITEM_HEIGHT), true);
    });
  };

  return (
    <View style={styles.wheelColumn}>
      <ScrollView
        ref={scrollRef}
        nestedScrollEnabled
        showsVerticalScrollIndicator={false}
        snapToInterval={WHEEL_ITEM_HEIGHT}
        snapToAlignment="start"
        decelerationRate="normal"
        disableIntervalMomentum={false}
        overScrollMode="never"
        contentContainerStyle={styles.wheelContent}
        onMomentumScrollEnd={handleMomentumScrollEnd}
        onScrollEndDrag={handleScrollEndDrag}
      >
        {wheelValues.map((item, index) => {
          const selected = item.value === selectedValue;
          return (
            <Pressable
              key={`${String(item.value)}-${index}`}
              style={styles.wheelItem}
              onPress={() => selectIndex(index)}
            >
              <Text
                variant="headlineSmall"
                style={[
                  styles.wheelItemText,
                  {
                    color: selected ? theme.colors.primary : theme.colors.onSurfaceVariant,
                    opacity: selected ? 1 : 0.54,
                  },
                ]}
              >
                {item.label}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

function calendarDays(month: Date): Date[] {
  const first = startOfMonth(month);
  const cursor = new Date(first);
  const offset = (first.getDay() + 6) % 7;
  cursor.setDate(first.getDate() - offset);
  return Array.from({ length: 42 }, (_, index) => {
    const day = new Date(cursor);
    day.setDate(cursor.getDate() + index);
    return day;
  });
}

function calendarWeeks(month: Date): Date[][] {
  const days = calendarDays(month);
  return Array.from({ length: 6 }, (_, index) => days.slice(index * 7, index * 7 + 7));
}

function parseDate(value: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (!match) return new Date();
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(year, month - 1, day);
  if (
    parsed.getFullYear() !== year ||
    parsed.getMonth() !== month - 1 ||
    parsed.getDate() !== day
  ) {
    return new Date();
  }
  return parsed;
}

function parseTime12(value: string): { hour: number; minute: number; period: Period } {
  const match = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  const now = new Date();
  const hour24 = match ? clamp(Number(match[1]), 0, 23) : now.getHours();
  const minute = match ? clamp(Number(match[2]), 0, 59) : now.getMinutes();
  const period: Period = hour24 >= 12 ? 'PM' : 'AM';
  const hour = hour24 % 12 || 12;
  return { hour, minute, period };
}

function to24HourTime(hour: number, minute: number, period: Period): string {
  const normalizedHour = period === 'AM' ? (hour === 12 ? 0 : hour) : hour === 12 ? 12 : hour + 12;
  return `${pad2(normalizedHour)}:${pad2(minute)}`;
}

function startOfMonth(value: Date): Date {
  return new Date(value.getFullYear(), value.getMonth(), 1);
}

function addMonths(value: Date, amount: number): Date {
  return new Date(value.getFullYear(), value.getMonth() + amount, 1);
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function positiveModulo(value: number, divisor: number): number {
  if (divisor <= 0) return 0;
  return ((value % divisor) + divisor) % divisor;
}

function pad2(value: number): string {
  return String(value).padStart(2, '0');
}

const HOUR_VALUES = Array.from({ length: 12 }, (_, index) => {
  const hour = index + 1;
  return { value: hour, label: String(hour) };
});
const MINUTE_VALUES = Array.from({ length: 60 }, (_, minute) => ({
  value: minute,
  label: pad2(minute),
}));
const PERIOD_VALUES: { value: Period; label: string }[] = [
  { value: 'AM', label: 'AM' },
  { value: 'PM', label: 'PM' },
];

const styles = StyleSheet.create({
  backdrop: {
    ...StyleSheet.absoluteFill,
    zIndex: 20,
    backgroundColor: 'rgba(0,0,0,0.54)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: tokens.space.lg,
  },
  dialog: {
    width: '100%',
    maxWidth: 520,
    maxHeight: '86%',
    borderRadius: tokens.radius.lg,
    borderWidth: 1,
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.xs,
    paddingHorizontal: tokens.space.sm,
    paddingTop: tokens.space.sm,
  },
  headerCopy: { flex: 1, minWidth: 0 },
  title: { fontWeight: '800' },
  content: { padding: tokens.space.lg, gap: tokens.space.md },
  summaryPanel: {
    borderRadius: tokens.radius.lg,
    padding: tokens.space.md,
    gap: tokens.space.sm,
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  summaryCopy: { flex: 1, minWidth: 0 },
  summaryDate: { fontWeight: '800' },
  summaryTimePill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.xs,
    borderRadius: tokens.radius.pill,
    paddingHorizontal: tokens.space.md,
    paddingVertical: tokens.space.sm,
    flexShrink: 1,
    minWidth: 112,
  },
  monthHeader: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.sm },
  monthTitle: { flex: 1, fontWeight: '800', textAlign: 'center' },
  calendarGrid: { gap: tokens.space.xs },
  weekRow: { flexDirection: 'row', gap: tokens.space.xs },
  weekday: { flex: 1, textAlign: 'center', fontWeight: '800' },
  dayCell: {
    flex: 1,
    aspectRatio: 1,
    minHeight: 38,
    borderRadius: tokens.radius.md,
    overflow: 'hidden',
    borderColor: 'transparent',
  },
  dayInner: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  timePanel: {
    borderWidth: 1,
    borderRadius: tokens.radius.lg,
    padding: tokens.space.md,
    gap: tokens.space.sm,
  },
  timeHeader: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.sm },
  timeHeaderCopy: { flex: 1, minWidth: 0 },
  timeTitle: { fontWeight: '800' },
  timeValue: { fontWeight: '800' },
  wheelLabelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.xs,
    paddingHorizontal: tokens.space.xs,
  },
  wheelLabel: { flex: 1, textAlign: 'center', fontWeight: '800' },
  wheelColonLabel: { width: 18 },
  wheelPicker: {
    height: WHEEL_ITEM_HEIGHT * WHEEL_VISIBLE_ITEMS,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.xs,
    borderRadius: tokens.radius.lg,
    overflow: 'hidden',
  },
  wheelSelectionBand: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: WHEEL_VERTICAL_PADDING,
    height: WHEEL_ITEM_HEIGHT,
    borderRadius: tokens.radius.md,
  },
  wheelColumn: { flex: 1, minWidth: 0, height: '100%' },
  wheelContent: { paddingVertical: WHEEL_VERTICAL_PADDING },
  wheelItem: {
    height: WHEEL_ITEM_HEIGHT,
    alignItems: 'center',
    justifyContent: 'center',
  },
  wheelItemText: { fontWeight: '800', textAlign: 'center' },
  wheelSeparator: { width: 18, textAlign: 'center', fontWeight: '800' },
  actions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'flex-end',
    gap: tokens.space.sm,
  },
});
