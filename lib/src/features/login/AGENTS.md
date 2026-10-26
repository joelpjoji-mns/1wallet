# `lib/src/features/login/` — Authentication Screen & Flow

## 🎯 Role & Overview
Provides the login and registration UI, enabling users to sign in with Google, email/password, or proceed in local-only / guest mode.

---

## 📜 Key Files

- **`login_screen.dart`**: Modern frosted login card with Google Sign-In button, email/password text fields, forgot password triggers, and a "Continue as Guest" escape hatch.

---

## 🛡️ Critical Invariants & Architecture

1. **Guest Mode Fallback**:
   - Users are never forced to create a cloud account to use 1Wallet. Guest mode must always remain prominent and fully functional.
2. **Loading & Error Feedback**:
   - Network errors, invalid credentials, or canceled Google sign-ins must present clean inline feedback without blocking the UI.

---

## 🔍 LLM / Developer Checklist

- [ ] Verify that password fields correctly mask characters and support visibility toggling.
- [ ] Ensure keyboard dismisses cleanly when tapping outside inputs.
