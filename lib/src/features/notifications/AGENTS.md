# `lib/src/features/notifications/` — Notifications Engine

## 🎯 Role & Overview
Handles scheduling and delivering local push notifications for bill reminders, daily summary alerts, budget threshold breaches, and capture review requests.

---

## 📜 Key Files

- **`notification_engine.dart`**: Core scheduling engine leveraging `flutter_local_notifications` and `timezone` to queue recurring or one-time alerts.

---

## 🛡️ Critical Invariants & Architecture

1. **Permission Check**:
   - Notifications must not attempt to trigger without checking and requesting `POST_NOTIFICATIONS` runtime permission on Android 13+ and iOS.
2. **Timezone Awareness**:
   - All scheduled alerts must use zoned date-times (`TZDateTime`) with user local timezone to prevent alerts from firing at incorrect hours.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/notification_capture_flow_test.dart`.
- [ ] Ensure that cancelling a recurring transaction also cancels its associated scheduled local notification ID.
