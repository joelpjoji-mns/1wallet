# `lib/src/design/` — Design Tokens & Visual Styling

## 🎯 Role & Overview
This directory defines the visual design system tokens for 1Wallet, including spacing, border radii, elevation, blur levels for glassmorphism, and typography scales.

---

## 📜 Key Files

- **`tokens.dart`**:
  - `AppTokens`: Static constants for layout padding (`paddingSmall`, `paddingMedium`, `paddingLarge`), card corner radii, animation durations, glass blur sigmas, and border opacities.

---

## 🛡️ Critical Invariants & Architecture

1. **Consistent Spacing**:
   - Hardcoded magic numbers for margin, padding, and corner radius across feature screens must be avoided. Use `AppTokens` constants.
2. **Glassmorphism Performance**:
   - Frosted glass effects (`BackdropFilter`) should be balanced with device performance. Avoid deep stacking of multiple translucent blurs.

---

## 🔍 LLM / Developer Checklist

- [ ] When adjusting token values, check for layout regressions across small phone displays and tablet/desktop widths.
- [ ] Ensure high-contrast and accessibility guidelines (WCAG AA) are preserved across all custom color tokens.
