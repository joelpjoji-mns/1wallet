import { tokens } from '@1wallet/ui';
import type { ReactNode } from 'react';
import { useEffect, useRef } from 'react';
import { Animated, StyleSheet, View, type StyleProp, type ViewStyle } from 'react-native';
import { withColorAlpha } from '../colorAlpha';

const GLOW_RISE_MS = 520;
const GLOW_FADE_MS = 980;
const GLOW_GAP_MS = 320;

export function PulsingFieldGlow({
  active,
  children,
  color,
  dark = false,
  pulseKey,
  borderRadius = tokens.radius.lg,
  style,
}: {
  active: boolean;
  children: ReactNode;
  color: string;
  dark?: boolean;
  pulseKey: number;
  borderRadius?: number;
  style?: StyleProp<ViewStyle>;
}) {
  const opacity = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    opacity.stopAnimation();
    if (!active) {
      opacity.setValue(0);
      return;
    }
    opacity.setValue(0);
    Animated.sequence([
      Animated.timing(opacity, {
        toValue: 1,
        duration: GLOW_RISE_MS,
        useNativeDriver: true,
      }),
      Animated.timing(opacity, {
        toValue: 0,
        duration: GLOW_FADE_MS,
        useNativeDriver: true,
      }),
      Animated.delay(GLOW_GAP_MS),
      Animated.timing(opacity, {
        toValue: 0.9,
        duration: GLOW_RISE_MS,
        useNativeDriver: true,
      }),
      Animated.timing(opacity, {
        toValue: 0,
        duration: GLOW_FADE_MS,
        useNativeDriver: true,
      }),
    ]).start();
  }, [active, opacity, pulseKey]);

  return (
    <View style={[styles.container, style]}>
      {children}
      <Animated.View
        pointerEvents="none"
        style={[
          styles.glow,
          {
            backgroundColor: withColorAlpha(color, dark ? 0.14 : 0.1),
            borderColor: withColorAlpha(color, dark ? 0.62 : 0.46),
            borderRadius,
            shadowColor: color,
            opacity,
          },
        ]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'relative',
  },
  glow: {
    ...StyleSheet.absoluteFill,
    borderWidth: 1,
    elevation: 3,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.22,
    shadowRadius: 12,
  },
});
