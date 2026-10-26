# `assets/brand/` — Brand Logos & Launcher Icons

## 🎯 Role & Overview
Houses visual identity assets for 1Wallet:
- `icon.png`: Master application icon.
- `adaptive-icon.png`: Android adaptive launcher icon foreground.
- `onewallet-icon.svg`: Crisp vector SVG icon used in app bars, marketing cards, and splash components.
- `splash-icon.png` & `splash-native.png`: Static graphics used by `flutter_native_splash`.

---

## 🛡️ Critical Invariants & Architecture

1. **Resolution & Density**:
   - Master raster icons must maintain high pixel density (1024x1024) to generate sharp platform-specific assets.
2. **Branding Integrity**:
   - The trademark circular glass gradient and 1Wallet logo contours must not be modified without product owner approval.
