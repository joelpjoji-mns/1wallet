# Rule: Frosted Glass UI & Design Tokens

## Invariants

1. **Tokens Over Magic Numbers**:
   - Always reference spacing, padding, and corner radius constants from `AppTokens` in `lib/src/design/tokens.dart`.
   - Never hardcode arbitrary pixel paddings.

2. **Accessibility & Contrast**:
   - Glass surfaces (`liquid_glass_widgets`) must provide sufficient contrast with text colors.
   - Respect user settings for High Contrast and Reduced Motion (`MediaQuery.disableAnimationsOf(context)`).

3. **Privacy Masking**:
   - Wrap monetary balances with `PrivacyText` or check `privacyModeProvider` to ensure financial figures are masked (`••••••`) when the privacy toggle is enabled.
