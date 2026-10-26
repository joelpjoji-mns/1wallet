# `lib/src/services/` — Platform & Notification Services

## 🎯 Role & Overview
Wraps native platform capabilities and long-running services, primarily local scheduled notifications and background job triggers.

---

## 📜 Key Files

- **`notification_service.dart`**:
  - Encapsulates initialization, channel creation (Android notification channels), icon resolution, and callback handling for `flutter_local_notifications`.
  - Supports scheduling daily bill reminders and instant transaction alerts.

---

## 🛡️ Critical Invariants & Architecture

1. **Channel Setup**:
   - Notification channels on Android must be created with appropriate importance and description so users can customize them in system settings.
2. **Payload Parsing**:
   - Tapping a notification provides an action payload (e.g. route `/review` or `/transaction/:id`). The payload must be validated safely before navigation.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/notification_capture_flow_test.dart`.
- [ ] Confirm proper initialization on both iOS and Android before calling scheduling methods.
