# `lib/src/features/settings/` — Settings, Backups & Preferences

## 🎯 Role & Overview
Manages application configuration, user preferences, security lock toggles, local backup creation/restoration, account deletion, and system permission setup.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `settings_screen.dart` | Main settings dashboard with preference sections (Appearance, Currency, Security, Backup, About). In offline mode it shows the `OfflineModeCard`, swaps "Sign out" for "Sync with Google", and hides account deletion (there is no account). |
| `settings_components.dart` | Reusable setting tiles, section headers, switches, and preference pickers. `SettingsProfileSection(offline:)` renders the device-only profile. |
| `offline_mode_section.dart` | `OfflineModeCard` (offline status, "Back up & sync with Google", encrypted export/import shortcuts). `showOfflineUpgradeSheet` drives `OfflineModeController`: Google sign-in → keep local / use Google / merge choice with confirmations → migration. |
| `data_backup_screen.dart` | Exporting encrypted wallet backup files, importing legacy JSON/zip backups, and cloud restore options. Offline restores report "restored on this device" and never attempt a cloud write. |
| `account_deletion_controller.dart` | Multi-step safety controller for wiping local state and deleting user accounts from Firebase Firestore. |
| `device_permissions_screen.dart` | Auditing granted/denied device permissions (SMS, Notifications, Camera). |
| `permissions_setup_screen.dart` & `permission_setup_controller.dart` | Interactive onboarding permissions wizard explaining why permissions are needed. Completion is keyed by `AuthState.ownerId` (`'local-user'` offline). `copyCompletion` carries it over on an offline → Google upgrade. |

---

## 🛡️ Critical Invariants & Architecture

1. **Backup Downgrade Protection**:
   - When restoring a backup file, the schema version must be checked against `kLedgerSchemaVersion`. Restoring backups from newer versions than the installed app must be rejected with an upgrade warning.
2. **Account Deletion Finality**:
   - Account deletion must purge both local persistent stores (`SharedPreferences`, files) and remote Firestore documents, logging the user out.
3. **Offline Mode Never Signs Out**:
   - Signing out clears the device wallet, which is an offline user's only copy. Offline mode offers the Google upgrade and encrypted export/import instead.
4. **Canonical settings UI**:
   - Preference groups are `AppGroupedSection` + `AppGroupedTile` / `AppGroupedTile.toggle` (danger zone: `destructive: true`); never raw `GlassGroupedSection`/`GlassListTile` (they drop the app font) or bare `GlassSwitch` rows.
   - Confirmations use `showAppConfirmDialog` (destructive when data is removed or overwritten); feedback uses `showAppSnackBar`; sheets use `showAppSheet`. The offline-upgrade sheet uses the standard panel, not the login-only `BrandFrostedPanel`.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/backup_restore_and_downgrade_guard_test.dart` and `test/account_delete_flow_test.dart`.
- [ ] Ensure `settings_month_start_day_validation_test.dart` passes when changing monthly budget start dates (1-28).
- [ ] Offline surfaces: run `test/offline_mode_screens_test.dart` and `test/offline_upgrade_migration_test.dart`.
