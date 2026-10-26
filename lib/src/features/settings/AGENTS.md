# `lib/src/features/settings/` — Settings, Backups & Preferences

## 🎯 Role & Overview
Manages application configuration, user preferences, security lock toggles, local backup creation/restoration, account deletion, and system permission setup.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `settings_screen.dart` | Main settings dashboard with preference sections (Appearance, Currency, Security, Backup, About). |
| `settings_components.dart` | Reusable setting tiles, section headers, switches, and preference pickers. |
| `data_backup_screen.dart` | Exporting encrypted wallet backup files, importing legacy JSON/zip backups, and cloud restore options. |
| `account_deletion_controller.dart` | Multi-step safety controller for wiping local state and deleting user accounts from Firebase Firestore. |
| `device_permissions_screen.dart` | Auditing granted/denied device permissions (SMS, Notifications, Camera). |
| `permissions_setup_screen.dart` & `permission_setup_controller.dart` | Interactive onboarding permissions wizard explaining why permissions are needed. |

---

## 🛡️ Critical Invariants & Architecture

1. **Backup Downgrade Protection**:
   - When restoring a backup file, the schema version must be checked against `kLedgerSchemaVersion`. Restoring backups from newer versions than the installed app must be rejected with an upgrade warning.
2. **Account Deletion Finality**:
   - Account deletion must purge both local persistent stores (`SharedPreferences`, files) and remote Firestore documents, logging the user out.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/backup_restore_and_downgrade_guard_test.dart` and `test/account_delete_flow_test.dart`.
- [ ] Ensure `settings_month_start_day_validation_test.dart` passes when changing monthly budget start dates (1-28).
