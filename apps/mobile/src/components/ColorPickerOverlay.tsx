import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import {
    PanResponder,
    ScrollView,
    StyleSheet,
    View,
    type GestureResponderEvent,
    type LayoutChangeEvent,
} from 'react-native';
import {
    Appbar,
    Button,
    Portal,
    Surface,
    Text,
    TouchableRipple,
    useTheme,
} from 'react-native-paper';
import { SafeAreaView } from 'react-native-safe-area-context';
import { APP_ICONS, iconTextColorForBackground, type AppIconName } from '../iconSystem';
import { DEFAULT_CUSTOM_ACCENT_COLOR, normalizeHexColor } from '../theme';
import { useBackLayer } from './AppBackLayer';

const SPECTRUM_COLUMNS = 28;
const SPECTRUM_ROWS = 12;
const TONE_STEPS = 18;
const MIN_TONE_VALUE = 0.12;

type HsvColor = {
  hue: number;
  saturation: number;
  value: number;
};

export function ColorPickerOverlay({
  visible,
  title,
  selectedColor,
  fallbackColor = DEFAULT_CUSTOM_ACCENT_COLOR,
  swatches,
  saveLabel = 'Apply color',
  clearLabel = 'Use default color',
  allowClear = false,
  accessibilityLabelPrefix = 'Color',
  onDismiss,
  onSave,
  onClear,
  renderPreview,
}: {
  visible: boolean;
  title: string;
  selectedColor?: string;
  fallbackColor?: string;
  swatches: readonly string[];
  saveLabel?: string;
  clearLabel?: string;
  allowClear?: boolean;
  accessibilityLabelPrefix?: string;
  onDismiss: () => void;
  onSave: (color: string) => void;
  onClear?: () => void;
  renderPreview?: (color: string) => ReactNode;
}) {
  const theme = useTheme();
  const initialColor = normalizeHexColor(selectedColor) ?? normalizeHexColor(fallbackColor);
  const [draftColor, setDraftColor] = useState(initialColor ?? DEFAULT_CUSTOM_ACCENT_COLOR);

  useBackLayer(visible, onDismiss);

  useEffect(() => {
    if (visible) setDraftColor(initialColor ?? DEFAULT_CUSTOM_ACCENT_COLOR);
  }, [initialColor, visible]);

  const normalizedColor = normalizeHexColor(draftColor);
  const previewColor = normalizedColor ?? initialColor ?? DEFAULT_CUSTOM_ACCENT_COLOR;

  if (!visible) return null;

  return (
    <Portal>
      <Surface
        style={[styles.fullScreenOverlay, { backgroundColor: theme.colors.background }]}
        elevation={0}
      >
        <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
          <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
            <Appbar.BackAction onPress={onDismiss} />
            <Appbar.Content title={title} titleStyle={styles.appbarTitle} />
            <Appbar.Action
              icon={APP_ICONS.action.check}
              disabled={!normalizedColor}
              onPress={() => {
                if (normalizedColor) onSave(normalizedColor);
              }}
            />
          </Appbar.Header>
          <ScrollView
            contentContainerStyle={styles.content}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            {renderPreview ? (
              renderPreview(previewColor)
            ) : (
              <DefaultColorPreview color={previewColor} />
            )}

            <SpectrumColorPicker
              color={previewColor}
              accessibilityLabelPrefix={accessibilityLabelPrefix}
              onChange={setDraftColor}
            />

            <View style={styles.swatchSection}>
              <View style={styles.sectionHeader}>
                <Text variant="titleSmall" style={{ color: theme.colors.onSurface }}>
                  Saved colors
                </Text>
                <Text variant="labelMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                  {previewColor.toUpperCase()}
                </Text>
              </View>
              <View style={styles.swatchGrid}>
                {swatches.map((color) => {
                  const normalizedSwatch = normalizeHexColor(color) ?? color;
                  const selected = normalizedSwatch === normalizedColor;
                  return (
                    <TouchableRipple
                      key={color}
                      accessibilityRole="button"
                      accessibilityLabel={`${accessibilityLabelPrefix} ${normalizedSwatch}`}
                      borderless
                      style={[
                        styles.swatchButton,
                        {
                          borderColor: selected
                            ? iconTextColorForBackground(normalizedSwatch)
                            : theme.colors.outlineVariant,
                          backgroundColor: normalizedSwatch,
                        },
                      ]}
                      onPress={() => setDraftColor(normalizedSwatch)}
                    >
                      <View style={styles.swatchInner}>
                        {selected ? (
                          <MaterialCommunityIcons
                            name={APP_ICONS.action.check}
                            size={20}
                            color={iconTextColorForBackground(normalizedSwatch)}
                          />
                        ) : null}
                      </View>
                    </TouchableRipple>
                  );
                })}
              </View>
            </View>

            <View style={styles.actionRow}>
              {allowClear && onClear ? (
                <Button mode="outlined" icon="palette-swatch-outline" onPress={onClear}>
                  {clearLabel}
                </Button>
              ) : null}
              <Button
                mode="contained"
                icon="palette-outline"
                disabled={!normalizedColor}
                onPress={() => {
                  if (normalizedColor) onSave(normalizedColor);
                }}
              >
                {saveLabel}
              </Button>
            </View>
          </ScrollView>
        </SafeAreaView>
      </Surface>
    </Portal>
  );
}

function SpectrumColorPicker({
  color,
  accessibilityLabelPrefix,
  onChange,
}: {
  color: string;
  accessibilityLabelPrefix: string;
  onChange: (color: string) => void;
}) {
  const theme = useTheme();
  const hsvColor = useMemo(() => hexToHsv(color), [color]);
  const [spectrumSize, setSpectrumSize] = useState({ width: 1, height: 1 });
  const [toneWidth, setToneWidth] = useState(1);
  const spectrumCells = useMemo(() => buildSpectrumCells(), []);
  const toneStops = useMemo(
    () => buildToneStops(hsvColor.hue, hsvColor.saturation),
    [hsvColor.hue, hsvColor.saturation],
  );
  const selectorColor = iconTextColorForBackground(color);

  const selectSpectrumPoint = useCallback(
    (x: number, y: number) => {
      const xRatio = clamp(x / spectrumSize.width, 0, 1);
      const yRatio = clamp(y / spectrumSize.height, 0, 1);
      onChange(
        hsvToHex({
          hue: xRatio * 360,
          saturation: yRatio,
          value: hsvColor.value,
        }),
      );
    },
    [hsvColor.value, onChange, spectrumSize.height, spectrumSize.width],
  );

  const selectTonePoint = useCallback(
    (x: number) => {
      const xRatio = clamp(x / toneWidth, 0, 1);
      onChange(
        hsvToHex({
          hue: hsvColor.hue,
          saturation: hsvColor.saturation,
          value: MIN_TONE_VALUE + xRatio * (1 - MIN_TONE_VALUE),
        }),
      );
    },
    [hsvColor.hue, hsvColor.saturation, onChange, toneWidth],
  );

  const selectSpectrumFromEvent = useCallback(
    (event: GestureResponderEvent) => {
      selectSpectrumPoint(event.nativeEvent.locationX, event.nativeEvent.locationY);
    },
    [selectSpectrumPoint],
  );

  const selectToneFromEvent = useCallback(
    (event: GestureResponderEvent) => {
      selectTonePoint(event.nativeEvent.locationX);
    },
    [selectTonePoint],
  );

  const spectrumResponder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponder: () => true,
        onPanResponderGrant: selectSpectrumFromEvent,
        onPanResponderMove: selectSpectrumFromEvent,
      }),
    [selectSpectrumFromEvent],
  );

  const toneResponder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponder: () => true,
        onPanResponderGrant: selectToneFromEvent,
        onPanResponderMove: selectToneFromEvent,
      }),
    [selectToneFromEvent],
  );

  const handleSpectrumLayout = useCallback((event: LayoutChangeEvent) => {
    const { width, height } = event.nativeEvent.layout;
    setSpectrumSize({ width: Math.max(width, 1), height: Math.max(height, 1) });
  }, []);

  const handleToneLayout = useCallback((event: LayoutChangeEvent) => {
    setToneWidth(Math.max(event.nativeEvent.layout.width, 1));
  }, []);

  const selectorLeft = clamp(hsvColor.hue / 360, 0, 1) * spectrumSize.width;
  const selectorTop = clamp(hsvColor.saturation, 0, 1) * spectrumSize.height;
  const toneLeft =
    clamp((hsvColor.value - MIN_TONE_VALUE) / (1 - MIN_TONE_VALUE), 0, 1) * toneWidth;

  return (
    <View
      style={[
        styles.pickerPanel,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
    >
      <View style={styles.sectionHeader}>
        <Text variant="titleSmall" style={{ color: theme.colors.onSurface }}>
          Spectrum
        </Text>
        <View style={[styles.selectedColorPill, { borderColor: theme.colors.outlineVariant }]}>
          <View style={[styles.selectedColorDot, { backgroundColor: color }]} />
          <Text variant="labelMedium" style={{ color: theme.colors.onSurfaceVariant }}>
            {color.toUpperCase()}
          </Text>
        </View>
      </View>

      <View
        accessibilityRole="adjustable"
        accessibilityLabel={`${accessibilityLabelPrefix} spectrum`}
        onLayout={handleSpectrumLayout}
        style={[styles.spectrumFrame, { borderColor: theme.colors.outlineVariant }]}
        {...spectrumResponder.panHandlers}
      >
        <View pointerEvents="none" style={styles.spectrumGrid}>
          {spectrumCells.map((cell) => (
            <View
              key={cell.key}
              style={[
                styles.spectrumCell,
                {
                  width: `${100 / SPECTRUM_COLUMNS}%`,
                  height: `${100 / SPECTRUM_ROWS}%`,
                  backgroundColor: cell.color,
                },
              ]}
            />
          ))}
        </View>
        <View
          pointerEvents="none"
          style={[
            styles.spectrumSelector,
            {
              backgroundColor: color,
              borderColor: selectorColor,
              left: selectorLeft,
              top: selectorTop,
            },
          ]}
        >
          <View style={[styles.spectrumSelectorCore, { backgroundColor: selectorColor }]} />
        </View>
      </View>

      <View style={styles.toneHeader}>
        <Text variant="titleSmall" style={{ color: theme.colors.onSurface }}>
          Tone
        </Text>
      </View>
      <View
        accessibilityRole="adjustable"
        accessibilityLabel={`${accessibilityLabelPrefix} tone`}
        onLayout={handleToneLayout}
        style={[styles.toneRail, { borderColor: theme.colors.outlineVariant }]}
        {...toneResponder.panHandlers}
      >
        {toneStops.map((tone) => (
          <View key={tone.key} style={[styles.toneStop, { backgroundColor: tone.color }]} />
        ))}
        <View
          pointerEvents="none"
          style={[
            styles.toneSelector,
            {
              backgroundColor: color,
              borderColor: selectorColor,
              left: toneLeft,
            },
          ]}
        />
      </View>
    </View>
  );
}

function DefaultColorPreview({ color }: { color: string }) {
  return (
    <View style={[styles.defaultPreview, { backgroundColor: color }]}>
      <MaterialCommunityIcons
        name="palette-outline"
        size={24}
        color={iconTextColorForBackground(color)}
      />
    </View>
  );
}

export function ColorPickerIconPreview({
  color,
  icon,
  title,
  subtitle,
}: {
  color: string;
  icon: AppIconName;
  title: string;
  subtitle?: string;
}) {
  const theme = useTheme();
  const iconColor = iconTextColorForBackground(color);
  return (
    <View
      style={[
        styles.iconPreviewPanel,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
    >
      <View style={[styles.iconPreviewAvatar, { backgroundColor: color }]}>
        <MaterialCommunityIcons name={icon} size={28} color={iconColor} />
      </View>
      <View style={styles.iconPreviewCopy}>
        <Text variant="titleMedium" numberOfLines={1} style={{ color: theme.colors.onSurface }}>
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
    </View>
  );
}

const styles = StyleSheet.create({
  fullScreenOverlay: {
    ...StyleSheet.absoluteFill,
    zIndex: 30,
  },
  safeArea: { flex: 1 },
  appbarTitle: { fontWeight: '700' },
  content: { gap: tokens.space.lg, padding: tokens.space.lg, paddingTop: 0, paddingBottom: 32 },
  pickerPanel: {
    gap: tokens.space.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.lg,
    padding: tokens.space.md,
  },
  sectionHeader: {
    minHeight: 32,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.md,
  },
  selectedColorPill: {
    minHeight: 30,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.pill,
    paddingHorizontal: tokens.space.sm,
  },
  selectedColorDot: {
    width: 16,
    height: 16,
    borderRadius: tokens.radius.pill,
  },
  spectrumFrame: {
    height: 184,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.md,
    overflow: 'hidden',
  },
  spectrumGrid: {
    flex: 1,
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  spectrumCell: {},
  spectrumSelector: {
    position: 'absolute',
    width: 30,
    height: 30,
    marginLeft: -15,
    marginTop: -15,
    borderRadius: tokens.radius.pill,
    borderWidth: 3,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000000',
    shadowOpacity: 0.28,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 4 },
    elevation: 6,
  },
  spectrumSelectorCore: {
    width: 8,
    height: 8,
    borderRadius: tokens.radius.pill,
  },
  toneHeader: { marginTop: tokens.space.xs },
  toneRail: {
    height: 34,
    flexDirection: 'row',
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.pill,
    overflow: 'hidden',
  },
  toneStop: { flex: 1 },
  toneSelector: {
    position: 'absolute',
    top: 3,
    width: 28,
    height: 28,
    marginLeft: -14,
    borderRadius: tokens.radius.pill,
    borderWidth: 3,
    shadowColor: '#000000',
    shadowOpacity: 0.24,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 3 },
    elevation: 5,
  },
  swatchSection: { gap: tokens.space.sm },
  swatchGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: tokens.space.md,
  },
  swatchButton: {
    width: 56,
    height: 56,
    borderRadius: tokens.radius.pill,
    borderWidth: 3,
    overflow: 'hidden',
  },
  swatchInner: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
  },
  actionRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'flex-end',
    gap: tokens.space.sm,
  },
  defaultPreview: {
    height: 72,
    borderRadius: tokens.radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
  },
  iconPreviewPanel: {
    minHeight: 82,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.lg,
    padding: tokens.space.md,
  },
  iconPreviewAvatar: {
    width: 54,
    height: 54,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  iconPreviewCopy: { flex: 1, minWidth: 0 },
});

function buildSpectrumCells() {
  const cells: { key: string; color: string }[] = [];
  for (let row = 0; row < SPECTRUM_ROWS; row += 1) {
    const saturation = row / (SPECTRUM_ROWS - 1);
    for (let column = 0; column < SPECTRUM_COLUMNS; column += 1) {
      const hue = (column / (SPECTRUM_COLUMNS - 1)) * 360;
      cells.push({
        key: `${row}:${column}`,
        color: hsvToHex({ hue, saturation, value: 1 }),
      });
    }
  }
  return cells;
}

function buildToneStops(hue: number, saturation: number) {
  return Array.from({ length: TONE_STEPS }, (_unused, index) => {
    const ratio = index / (TONE_STEPS - 1);
    return {
      key: String(index),
      color: hsvToHex({ hue, saturation, value: MIN_TONE_VALUE + ratio * (1 - MIN_TONE_VALUE) }),
    };
  });
}

function hexToHsv(color: string): HsvColor {
  const normalized = normalizeHexColor(color) ?? DEFAULT_CUSTOM_ACCENT_COLOR;
  const value = normalized.slice(1);
  const red = parseInt(value.slice(0, 2), 16) / 255;
  const green = parseInt(value.slice(2, 4), 16) / 255;
  const blue = parseInt(value.slice(4, 6), 16) / 255;
  const max = Math.max(red, green, blue);
  const min = Math.min(red, green, blue);
  const delta = max - min;
  const saturation = max === 0 ? 0 : delta / max;
  let hue = 0;

  if (delta !== 0) {
    if (max === red) hue = ((green - blue) / delta) % 6;
    else if (max === green) hue = (blue - red) / delta + 2;
    else hue = (red - green) / delta + 4;
    hue *= 60;
    if (hue < 0) hue += 360;
  }

  return { hue, saturation, value: max };
}

function hsvToHex({ hue, saturation, value }: HsvColor): string {
  const normalizedHue = ((hue % 360) + 360) % 360;
  const chroma = value * saturation;
  const hueSegment = normalizedHue / 60;
  const secondComponent = chroma * (1 - Math.abs((hueSegment % 2) - 1));
  const match = value - chroma;
  let red = 0;
  let green = 0;
  let blue = 0;

  if (hueSegment >= 0 && hueSegment < 1) [red, green, blue] = [chroma, secondComponent, 0];
  else if (hueSegment < 2) [red, green, blue] = [secondComponent, chroma, 0];
  else if (hueSegment < 3) [red, green, blue] = [0, chroma, secondComponent];
  else if (hueSegment < 4) [red, green, blue] = [0, secondComponent, chroma];
  else if (hueSegment < 5) [red, green, blue] = [secondComponent, 0, chroma];
  else [red, green, blue] = [chroma, 0, secondComponent];

  return rgbToHex(red + match, green + match, blue + match);
}

function rgbToHex(red: number, green: number, blue: number): string {
  return `#${[red, green, blue]
    .map((component) =>
      Math.round(clamp(component, 0, 1) * 255)
        .toString(16)
        .padStart(2, '0'),
    )
    .join('')}`.toUpperCase();
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}
