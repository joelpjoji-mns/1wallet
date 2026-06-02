import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useEffect, useMemo, useRef } from 'react';
import { Animated, Easing, StyleSheet, View, type ViewStyle } from 'react-native';
import { Button, Text, useTheme } from 'react-native-paper';
import { withColorAlpha } from '../colorAlpha';
import { APP_ICONS, type AppIconName } from '../iconSystem';
import { LAUNCH_PALETTE as launchPalette } from '../launchTheme';

type LaunchStage = 'session' | 'wallet' | 'sync';
type AnimatedBrandSceneVariant = 'compact' | 'hero';
type LaunchPaletteBase = { [Key in keyof typeof launchPalette]: string };
type ResolvedLaunchPalette = LaunchPaletteBase & {
  bandPrimary: string;
  bandTertiary: string;
  bandGold: string;
  cardFill: string;
  completedRail: string;
  focusBorder: string;
  focusFill: string;
  haloFill: string;
  markBackground: string;
  markBorder: string;
  markGlint: string;
  progressTrack: string;
  stageBorder: string;
};

const LAUNCH_STAGES: {
  id: LaunchStage;
  label: string;
  icon: AppIconName;
}[] = [
  { id: 'session', label: 'Session', icon: APP_ICONS.status.session },
  { id: 'wallet', label: 'Wallet', icon: APP_ICONS.status.wallet },
  { id: 'sync', label: 'Ready', icon: APP_ICONS.status.ready },
];

const LAUNCH_STAGE_INDEX: Record<LaunchStage, number> = {
  session: 0,
  wallet: 1,
  sync: 2,
};

const launchLedgerLines = Array.from({ length: 12 }, (_, index) => index);

export function BrandMark({ size = 72, style }: { size?: number; style?: ViewStyle }) {
  const theme = useTheme();
  const radius = Math.max(16, Math.round(size * 0.28));
  const iconSize = Math.round(size * 0.48);
  const badgeSize = Math.round(size * 0.34);

  return (
    <View
      accessibilityRole="image"
      accessibilityLabel="1wallet"
      style={[
        brandStyles.mark,
        {
          width: size,
          height: size,
          borderRadius: radius,
          backgroundColor: theme.colors.primaryContainer,
        },
        style,
      ]}
    >
      <View
        style={[
          brandStyles.markAccent,
          {
            width: Math.round(size * 0.72),
            height: Math.round(size * 0.52),
            borderRadius: Math.round(size * 0.16),
            borderColor: theme.colors.primary,
            backgroundColor: theme.colors.surface,
          },
        ]}
      />
      <MaterialCommunityIcons
        name={APP_ICONS.brand.wallet}
        size={iconSize}
        color={theme.colors.primary}
      />
      <View
        style={[
          brandStyles.numberBadge,
          {
            width: badgeSize,
            height: badgeSize,
            borderRadius: Math.round(badgeSize / 2),
            backgroundColor: theme.colors.tertiary,
          },
        ]}
      >
        <Text
          variant="labelLarge"
          style={[brandStyles.numberText, { color: theme.colors.onTertiary }]}
        >
          1
        </Text>
      </View>
    </View>
  );
}

export function BrandedLoadingState({
  title = '1wallet',
  message = 'Getting your wallet ready',
  stage = 'wallet',
}: {
  title?: string;
  message?: string;
  stage?: LaunchStage;
}) {
  const entrance = useRef(new Animated.Value(0)).current;
  const breathe = useRef(new Animated.Value(0)).current;
  const sweep = useRef(new Animated.Value(0)).current;
  const drift = useRef(new Animated.Value(0)).current;
  const activeStageIndex = LAUNCH_STAGE_INDEX[stage];
  const palette = useResolvedLaunchPalette();

  useEffect(() => {
    const intro = Animated.timing(entrance, {
      toValue: 1,
      duration: 260,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: true,
    });
    const breathing = Animated.loop(
      Animated.sequence([
        Animated.timing(breathe, {
          toValue: 1,
          duration: 900,
          easing: Easing.out(Easing.cubic),
          useNativeDriver: true,
        }),
        Animated.timing(breathe, {
          toValue: 0,
          duration: 900,
          easing: Easing.in(Easing.cubic),
          useNativeDriver: true,
        }),
      ]),
    );
    const progressSweep = Animated.loop(
      Animated.timing(sweep, {
        toValue: 1,
        duration: 720,
        easing: Easing.inOut(Easing.cubic),
        useNativeDriver: true,
      }),
    );
    const backdropDrift = Animated.loop(
      Animated.sequence([
        Animated.timing(drift, {
          toValue: 1,
          duration: 2400,
          easing: Easing.inOut(Easing.cubic),
          useNativeDriver: true,
        }),
        Animated.timing(drift, {
          toValue: 0,
          duration: 2400,
          easing: Easing.inOut(Easing.cubic),
          useNativeDriver: true,
        }),
      ]),
    );
    intro.start();
    breathing.start();
    progressSweep.start();
    backdropDrift.start();
    return () => {
      intro.stop();
      breathing.stop();
      progressSweep.stop();
      backdropDrift.stop();
    };
  }, [breathe, drift, entrance, sweep]);

  const copyOpacity = entrance.interpolate({ inputRange: [0, 1], outputRange: [0.72, 1] });
  const copyTranslateY = entrance.interpolate({ inputRange: [0, 1], outputRange: [14, 0] });
  const haloOpacity = breathe.interpolate({ inputRange: [0, 1], outputRange: [0.18, 0.36] });
  const haloScale = breathe.interpolate({ inputRange: [0, 1], outputRange: [0.94, 1.08] });
  const sweepTranslate = sweep.interpolate({ inputRange: [0, 1], outputRange: [-150, 150] });
  const sweepScale = sweep.interpolate({ inputRange: [0, 0.5, 1], outputRange: [0.36, 0.9, 0.36] });

  return (
    <View style={[brandStyles.launchScreen, { backgroundColor: palette.background }]}>
      <LaunchBackdrop entrance={entrance} breathe={breathe} drift={drift} palette={palette} />

      <View style={brandStyles.launchStack}>
        <Animated.View
          pointerEvents="none"
          style={[
            brandStyles.launchHalo,
            {
              backgroundColor: palette.haloFill,
              borderColor: palette.primary,
              opacity: haloOpacity,
              transform: [{ scale: haloScale }],
            },
          ]}
        />
        <LaunchBrandMark entrance={entrance} breathe={breathe} sweep={sweep} palette={palette} />
      </View>

      <Animated.View
        style={[
          brandStyles.copy,
          { opacity: copyOpacity, transform: [{ translateY: copyTranslateY }] },
        ]}
      >
        <Text variant="headlineSmall" style={[brandStyles.launchTitle, { color: palette.text }]}>
          {title}
        </Text>
        <Text variant="bodyMedium" style={[brandStyles.centerText, { color: palette.mutedText }]}>
          {message}
        </Text>
      </Animated.View>

      <Animated.View style={[brandStyles.stageRail, { opacity: copyOpacity }]}>
        {LAUNCH_STAGES.map((item, index) => {
          const active = index === activeStageIndex;
          const completed = index < activeStageIndex;
          return (
            <View
              key={item.id}
              style={[
                brandStyles.stagePill,
                {
                  backgroundColor: active
                    ? palette.railActive
                    : completed
                      ? palette.completedRail
                      : palette.rail,
                  borderColor: active
                    ? palette.primary
                    : completed
                      ? palette.tertiary
                      : palette.stageBorder,
                },
              ]}
            >
              <MaterialCommunityIcons
                name={completed ? APP_ICONS.status.ready : item.icon}
                size={14}
                color={active ? palette.primary : completed ? palette.tertiary : palette.mutedText}
              />
              <Text
                variant="labelSmall"
                numberOfLines={1}
                style={{
                  color: active ? palette.text : completed ? palette.tertiary : palette.mutedText,
                }}
              >
                {item.label}
              </Text>
            </View>
          );
        })}
      </Animated.View>

      <View style={[brandStyles.progressTrack, { backgroundColor: palette.progressTrack }]}>
        <Animated.View
          style={[
            brandStyles.progressFill,
            {
              backgroundColor: palette.primary,
              transform: [{ translateX: sweepTranslate }, { scaleX: sweepScale }],
            },
          ]}
        />
      </View>
    </View>
  );
}

export function AnimatedBrandScene({
  title = '1wallet',
  message = 'Your money, ready when you are',
  variant = 'compact',
  showProgress = false,
  style,
}: {
  title?: string;
  message?: string;
  variant?: AnimatedBrandSceneVariant;
  showProgress?: boolean;
  style?: ViewStyle;
}) {
  const entrance = useRef(new Animated.Value(0)).current;
  const breathe = useRef(new Animated.Value(0)).current;
  const sweep = useRef(new Animated.Value(0)).current;
  const drift = useRef(new Animated.Value(0)).current;
  const palette = useResolvedLaunchPalette();

  useEffect(() => {
    const intro = Animated.timing(entrance, {
      toValue: 1,
      duration: 260,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: true,
    });
    const breathing = Animated.loop(
      Animated.sequence([
        Animated.timing(breathe, {
          toValue: 1,
          duration: 900,
          easing: Easing.out(Easing.cubic),
          useNativeDriver: true,
        }),
        Animated.timing(breathe, {
          toValue: 0,
          duration: 900,
          easing: Easing.in(Easing.cubic),
          useNativeDriver: true,
        }),
      ]),
    );
    const progressSweep = Animated.loop(
      Animated.timing(sweep, {
        toValue: 1,
        duration: 720,
        easing: Easing.inOut(Easing.cubic),
        useNativeDriver: true,
      }),
    );
    const backdropDrift = Animated.loop(
      Animated.sequence([
        Animated.timing(drift, {
          toValue: 1,
          duration: 2400,
          easing: Easing.inOut(Easing.cubic),
          useNativeDriver: true,
        }),
        Animated.timing(drift, {
          toValue: 0,
          duration: 2400,
          easing: Easing.inOut(Easing.cubic),
          useNativeDriver: true,
        }),
      ]),
    );
    intro.start();
    breathing.start();
    progressSweep.start();
    backdropDrift.start();
    return () => {
      intro.stop();
      breathing.stop();
      progressSweep.stop();
      backdropDrift.stop();
    };
  }, [breathe, drift, entrance, sweep]);

  const copyOpacity = entrance.interpolate({ inputRange: [0, 1], outputRange: [0.72, 1] });
  const copyTranslateY = entrance.interpolate({ inputRange: [0, 1], outputRange: [14, 0] });
  const haloOpacity = breathe.interpolate({ inputRange: [0, 1], outputRange: [0.16, 0.34] });
  const haloScale = breathe.interpolate({ inputRange: [0, 1], outputRange: [0.94, 1.08] });
  const sweepTranslate = sweep.interpolate({ inputRange: [0, 1], outputRange: [-150, 150] });
  const sweepScale = sweep.interpolate({ inputRange: [0, 0.5, 1], outputRange: [0.36, 0.9, 0.36] });

  return (
    <View
      style={[
        brandStyles.animatedScene,
        variant === 'hero' ? brandStyles.animatedSceneHero : brandStyles.animatedSceneCompact,
        { backgroundColor: palette.background },
        style,
      ]}
    >
      <LaunchBackdrop entrance={entrance} breathe={breathe} drift={drift} palette={palette} />
      <View style={brandStyles.animatedSceneInner}>
        <View style={brandStyles.launchStack}>
          <Animated.View
            pointerEvents="none"
            style={[
              brandStyles.launchHalo,
              {
                borderColor: palette.primary,
                backgroundColor: palette.haloFill,
                opacity: haloOpacity,
                transform: [{ scale: haloScale }],
              },
            ]}
          />
          <LaunchBrandMark entrance={entrance} breathe={breathe} sweep={sweep} palette={palette} />
        </View>
        <Animated.View
          style={[
            brandStyles.animatedSceneCopy,
            { opacity: copyOpacity, transform: [{ translateY: copyTranslateY }] },
          ]}
        >
          <Text
            variant={variant === 'hero' ? 'headlineMedium' : 'headlineSmall'}
            style={[brandStyles.launchTitle, { color: palette.text }]}
          >
            {title}
          </Text>
          <Text variant="bodyMedium" style={[brandStyles.centerText, { color: palette.mutedText }]}>
            {message}
          </Text>
        </Animated.View>
        {showProgress ? (
          <View style={[brandStyles.progressTrack, { backgroundColor: palette.progressTrack }]}>
            <Animated.View
              style={[
                brandStyles.progressFill,
                {
                  backgroundColor: palette.primary,
                  transform: [{ translateX: sweepTranslate }, { scaleX: sweepScale }],
                },
              ]}
            />
          </View>
        ) : null}
      </View>
    </View>
  );
}

function LaunchBackdrop({
  entrance,
  breathe,
  drift,
  palette,
}: {
  entrance: Animated.Value;
  breathe: Animated.Value;
  drift: Animated.Value;
  palette: ResolvedLaunchPalette;
}) {
  const bandTranslate = drift.interpolate({ inputRange: [0, 1], outputRange: [-18, 18] });
  const lineTranslate = drift.interpolate({ inputRange: [0, 1], outputRange: [0, -22] });
  const panelOpacity = entrance.interpolate({ inputRange: [0, 1], outputRange: [0, 1] });
  const focusScale = breathe.interpolate({ inputRange: [0, 1], outputRange: [0.96, 1.04] });

  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      <View style={[brandStyles.launchBackdropBase, { backgroundColor: palette.backgroundDeep }]} />
      <Animated.View
        style={[
          brandStyles.launchBand,
          brandStyles.launchBandPrimary,
          {
            backgroundColor: palette.bandPrimary,
            transform: [{ translateX: bandTranslate }, { rotate: '-14deg' }],
          },
        ]}
      />
      <Animated.View
        style={[
          brandStyles.launchBand,
          brandStyles.launchBandTertiary,
          {
            backgroundColor: palette.bandTertiary,
            transform: [{ translateX: Animated.multiply(bandTranslate, -1) }, { rotate: '-13deg' }],
          },
        ]}
      />
      <Animated.View
        style={[
          brandStyles.launchBand,
          brandStyles.launchBandGold,
          {
            backgroundColor: palette.bandGold,
            opacity: panelOpacity,
            transform: [{ translateX: bandTranslate }, { rotate: '-14deg' }],
          },
        ]}
      />
      <Animated.View
        style={[brandStyles.launchLedgerLines, { transform: [{ translateY: lineTranslate }] }]}
      >
        {launchLedgerLines.map((index) => (
          <View
            key={index}
            style={[
              brandStyles.launchLedgerLine,
              {
                backgroundColor: palette.line,
                opacity: 0.35 + (index % 3) * 0.12,
                width: `${62 + (index % 4) * 9}%`,
                marginLeft: `${(index % 5) * 4}%`,
              },
            ]}
          />
        ))}
      </Animated.View>
      <Animated.View
        style={[
          brandStyles.launchFocusPlate,
          {
            backgroundColor: palette.focusFill,
            borderColor: palette.focusBorder,
            opacity: panelOpacity,
            transform: [{ scale: focusScale }],
          },
        ]}
      />
    </View>
  );
}

function LaunchBrandMark({
  entrance,
  breathe,
  sweep,
  palette,
}: {
  entrance: Animated.Value;
  breathe: Animated.Value;
  sweep: Animated.Value;
  palette: ResolvedLaunchPalette;
}) {
  const markScale = entrance.interpolate({
    inputRange: [0, 0.62, 1],
    outputRange: [0.82, 1.05, 1],
  });
  const markOpacity = entrance.interpolate({ inputRange: [0, 1], outputRange: [0.82, 1] });
  const markTranslateY = entrance.interpolate({ inputRange: [0, 1], outputRange: [18, 0] });
  const cardTranslateX = entrance.interpolate({ inputRange: [0, 1], outputRange: [-30, 0] });
  const cardRotate = entrance.interpolate({ inputRange: [0, 1], outputRange: ['-18deg', '-8deg'] });
  const badgeScale = entrance.interpolate({
    inputRange: [0, 0.55, 0.78, 1],
    outputRange: [0, 0, 1.16, 1],
  });
  const iconFloat = breathe.interpolate({ inputRange: [0, 1], outputRange: [1.5, -1.5] });
  const glintTranslate = sweep.interpolate({ inputRange: [0, 1], outputRange: [-112, 112] });

  return (
    <Animated.View
      accessibilityRole="image"
      accessibilityLabel="1wallet opening"
      style={[
        brandStyles.launchMark,
        {
          backgroundColor: palette.markBackground,
          borderColor: palette.markBorder,
          opacity: markOpacity,
          transform: [{ translateY: markTranslateY }, { scale: markScale }],
        },
      ]}
    >
      <Animated.View
        pointerEvents="none"
        style={[
          brandStyles.launchMarkGlint,
          {
            backgroundColor: palette.markGlint,
            transform: [{ translateX: glintTranslate }, { rotate: '-22deg' }],
          },
        ]}
      />
      <Animated.View
        style={[
          brandStyles.launchCard,
          {
            borderColor: palette.primary,
            backgroundColor: palette.cardFill,
            transform: [{ translateX: cardTranslateX }, { rotate: cardRotate }],
          },
        ]}
      />
      <Animated.View style={{ transform: [{ translateY: iconFloat }] }}>
        <MaterialCommunityIcons name={APP_ICONS.brand.wallet} size={42} color={palette.primary} />
      </Animated.View>
      <Animated.View
        style={[
          brandStyles.launchBadge,
          {
            backgroundColor: palette.tertiary,
            transform: [{ scale: badgeScale }],
          },
        ]}
      >
        <Text
          variant="labelLarge"
          style={[brandStyles.numberText, { color: palette.tertiaryText }]}
        >
          1
        </Text>
      </Animated.View>
    </Animated.View>
  );
}

function useResolvedLaunchPalette(): ResolvedLaunchPalette {
  const theme = useTheme();
  return useMemo(() => {
    const isDark = theme.dark;
    const isAmoled = isDark && isTrueBlackColor(theme.colors.background);
    const background = isAmoled ? '#000000' : isDark ? '#101214' : '#FFFFFF';
    const backgroundDeep = isAmoled ? '#000000' : isDark ? '#07090C' : '#F7F9FC';
    const surface = isAmoled ? '#050505' : isDark ? '#171A1F' : '#FFFFFF';
    const surfaceRaised = isAmoled ? '#0B0B0B' : isDark ? '#20242A' : '#F9FBFE';
    const neutralBandAlpha = isAmoled ? 0.026 : isDark ? 0.052 : 0.038;
    const neutralPlateAlpha = isAmoled ? 0.038 : isDark ? 0.07 : 0.05;
    const accentAlpha = isAmoled ? 0.11 : isDark ? 0.15 : 0.11;

    return {
      background,
      backgroundDeep,
      primary: theme.colors.primary,
      primaryDeep: theme.colors.primaryContainer,
      tertiary: theme.colors.tertiary,
      tertiaryDeep: theme.colors.tertiaryContainer,
      tertiaryText: theme.colors.onTertiary,
      gold: theme.colors.secondary,
      text: theme.colors.onBackground,
      mutedText: theme.colors.onSurfaceVariant,
      rail: withColorAlpha(theme.colors.onSurface, isDark ? 0.11 : 0.07),
      railActive: withColorAlpha(theme.colors.primary, accentAlpha),
      line: withColorAlpha(theme.colors.onSurface, isAmoled ? 0.08 : isDark ? 0.12 : 0.08),
      lineStrong: withColorAlpha(theme.colors.onSurface, isAmoled ? 0.12 : isDark ? 0.16 : 0.12),
      bandPrimary: withColorAlpha(theme.colors.onSurface, neutralBandAlpha),
      bandTertiary: withColorAlpha(theme.colors.onSurface, neutralBandAlpha),
      bandGold: withColorAlpha(theme.colors.onSurface, neutralBandAlpha * 0.72),
      cardFill: surface,
      completedRail: withColorAlpha(theme.colors.onSurface, isDark ? 0.14 : 0.09),
      focusBorder: withColorAlpha(theme.colors.outline, isAmoled ? 0.2 : isDark ? 0.26 : 0.2),
      focusFill: withColorAlpha(theme.colors.onSurface, neutralPlateAlpha),
      haloFill: withColorAlpha(theme.colors.primary, isAmoled ? 0.045 : isDark ? 0.064 : 0.052),
      markBackground: withColorAlpha(surfaceRaised, 0.98),
      markBorder: withColorAlpha(theme.colors.outline, isDark ? 0.32 : 0.28),
      markGlint: withColorAlpha(theme.colors.onSurface, isDark ? 0.11 : 0.08),
      progressTrack: withColorAlpha(theme.colors.onSurface, isDark ? 0.12 : 0.08),
      stageBorder: withColorAlpha(theme.colors.outline, isDark ? 0.22 : 0.22),
    };
  }, [theme]);
}

function isTrueBlackColor(color: string) {
  return color.trim().toLowerCase() === '#000' || color.trim().toLowerCase() === '#000000';
}

export function RecoveryState({
  title,
  body,
  actionLabel,
  onAction,
  secondaryActionLabel,
  onSecondaryAction,
}: {
  title: string;
  body: string;
  actionLabel: string;
  onAction: () => void;
  secondaryActionLabel?: string;
  onSecondaryAction?: () => void;
}) {
  const theme = useTheme();

  return (
    <View style={[brandStyles.screen, { backgroundColor: theme.colors.background }]}>
      <BrandMark size={76} />
      <View style={brandStyles.copy}>
        <Text variant="headlineSmall" style={brandStyles.title}>
          {title}
        </Text>
        <Text
          variant="bodyMedium"
          style={[brandStyles.centerText, { color: theme.colors.onSurfaceVariant }]}
        >
          {body}
        </Text>
      </View>
      <View style={brandStyles.actions}>
        <Button mode="contained" onPress={onAction}>
          {actionLabel}
        </Button>
        {secondaryActionLabel && onSecondaryAction ? (
          <Button mode="text" onPress={onSecondaryAction}>
            {secondaryActionLabel}
          </Button>
        ) : null}
      </View>
    </View>
  );
}

const brandStyles = StyleSheet.create({
  launchScreen: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: tokens.space.xl,
    gap: tokens.space.lg,
    overflow: 'hidden',
    backgroundColor: launchPalette.background,
  },
  launchBackdropBase: {
    ...StyleSheet.absoluteFill,
    backgroundColor: launchPalette.backgroundDeep,
  },
  launchBand: {
    position: 'absolute',
    left: -150,
    width: 720,
    borderRadius: 26,
  },
  launchBandPrimary: {
    top: 96,
    height: 232,
    backgroundColor: 'rgba(49, 93, 168, 0.46)',
  },
  launchBandTertiary: {
    bottom: 72,
    height: 260,
    backgroundColor: 'rgba(13, 84, 55, 0.48)',
  },
  launchBandGold: {
    top: 244,
    left: 156,
    width: 410,
    height: 96,
    backgroundColor: 'rgba(223, 200, 148, 0.18)',
  },
  launchLedgerLines: {
    position: 'absolute',
    top: 150,
    left: 34,
    right: 34,
    gap: 28,
  },
  launchLedgerLine: {
    height: 1,
    borderRadius: 1,
    backgroundColor: launchPalette.line,
  },
  launchFocusPlate: {
    position: 'absolute',
    top: '35%',
    alignSelf: 'center',
    width: 274,
    height: 274,
    borderRadius: 137,
    borderWidth: 2,
    borderColor: 'rgba(169, 199, 255, 0.28)',
    backgroundColor: 'rgba(155, 221, 181, 0.08)',
  },
  animatedScene: {
    alignSelf: 'stretch',
    justifyContent: 'center',
    overflow: 'hidden',
    backgroundColor: launchPalette.background,
  },
  animatedSceneCompact: {
    minHeight: 260,
    borderRadius: 28,
  },
  animatedSceneHero: {
    minHeight: 360,
  },
  animatedSceneInner: {
    alignItems: 'center',
    justifyContent: 'center',
    gap: tokens.space.sm,
    padding: tokens.space.lg,
  },
  animatedSceneCopy: { alignItems: 'center', gap: tokens.space.xs, maxWidth: 300 },
  screen: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: tokens.space.xl,
    gap: tokens.space.lg,
    overflow: 'hidden',
  },
  launchStack: {
    width: 184,
    height: 164,
    alignItems: 'center',
    justifyContent: 'center',
  },
  launchHalo: {
    position: 'absolute',
    width: 158,
    height: 122,
    borderRadius: 42,
    borderWidth: 2,
    backgroundColor: 'rgba(169, 199, 255, 0.08)',
  },
  launchMark: {
    width: 108,
    height: 108,
    borderRadius: 34,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(215, 227, 255, 0.32)',
  },
  launchMarkGlint: {
    position: 'absolute',
    width: 44,
    height: 160,
    backgroundColor: 'rgba(244, 247, 251, 0.11)',
  },
  launchCard: {
    position: 'absolute',
    width: 74,
    height: 52,
    borderRadius: 16,
    borderWidth: 2,
  },
  launchBadge: {
    position: 'absolute',
    right: 10,
    bottom: 10,
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
  },
  mark: {
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
  },
  markAccent: {
    position: 'absolute',
    borderWidth: 2,
    transform: [{ rotate: '-8deg' }],
  },
  numberBadge: {
    position: 'absolute',
    right: 8,
    bottom: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  numberText: { fontWeight: '800' },
  copy: { alignItems: 'center', gap: tokens.space.xs, maxWidth: 280 },
  title: { fontWeight: '800', textAlign: 'center' },
  launchTitle: { fontWeight: '800', textAlign: 'center', color: launchPalette.text },
  centerText: { textAlign: 'center' },
  stageRail: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    gap: tokens.space.xs,
    maxWidth: 320,
  },
  stagePill: {
    minHeight: 30,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    paddingHorizontal: tokens.space.sm,
    borderRadius: tokens.radius.pill,
    borderWidth: StyleSheet.hairlineWidth,
  },
  progressTrack: {
    width: 156,
    height: 5,
    borderRadius: 4,
    overflow: 'hidden',
  },
  progressFill: {
    flex: 1,
    borderRadius: 4,
  },
  actions: { alignSelf: 'stretch', gap: tokens.space.sm, maxWidth: 320 },
});
