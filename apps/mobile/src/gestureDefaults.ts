export const GESTURE_IGNORE_OFFSET = 100000;

export const EDGE_DRAWER_GESTURE = {
  captureWidth: 24,
  startWidth: 32,
  slop: 12,
  distance: 48,
  velocity: 0.42,
  verticalRatio: 1.2,
  failY: 24,
  negativeFail: 8,
} as const;

export const DRAWER_DISMISS_GESTURE = {
  slop: 18,
  distance: 58,
  velocity: 340,
  failY: 18,
} as const;

export const PANEL_SWIPE_GESTURE = {
  captureDistance: 18,
  triggerDistance: 52,
  verticalRatio: 1.35,
} as const;

export const ROW_DISMISS_GESTURE = {
  captureDistance: 10,
  distance: 88,
  velocity: 0.75,
  verticalRatio: 1.35,
  spring: {
    damping: 24,
    stiffness: 260,
    mass: 0.8,
  },
} as const;

export const REORDER_GESTURE = {
  activationDistance: 6,
  autoscrollThreshold: 120,
  autoscrollSpeed: 520,
  animationConfig: {
    damping: 36,
    mass: 0.25,
    overshootClamping: true,
    restDisplacementThreshold: 1,
    restSpeedThreshold: 1,
    stiffness: 420,
  },
} as const;
