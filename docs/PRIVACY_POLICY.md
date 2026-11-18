# Privacy Policy for 1Wallet

**Last Updated: November 18, 2026**

Welcome to **1Wallet** ("we", "our", or "us"). Your privacy is our highest priority. 1Wallet is designed from the ground up as an offline-first, privacy-focused personal finance and expense tracking application.

This Privacy Policy explains how information is handled when you use 1Wallet on Android and companion platforms.

---

## 1. Core Principles

- **Your data belongs to you:** We do not sell, rent, monetize, or broker your personal or financial data to any third party.
- **Offline by default:** 1Wallet functions completely offline. You can track accounts, budgets, and transactions without ever creating an account or connecting to the internet.
- **On-device intelligence:** Receipt scanning and transaction parsing occur locally on your device without sending sensitive documents or SMS messages to external AI servers.
- **No advertising:** 1Wallet contains no advertisements or third-party advertising SDKs.

---

## 2. Information We Access and How It Is Used

### A. Financial Ledger Data
- **What:** Transaction amounts, dates, merchant names, categories, account balances, and currency choices that you enter or import.
- **Purpose:** To calculate your account balances, net worth, and spending visualizations.
- **Storage:** Stored locally in your device's secured application sandbox. If you explicitly link a Google account, your ledger is synchronized to an encrypted Firebase Cloud Firestore database associated solely with your user identifier.

### B. Device Permissions
1Wallet requests specific permissions only when you explicitly enable features that require them:

* **Camera (`android.permission.CAMERA`):**
  * **Use:** Used solely for scanning paper receipts using on-device optical character recognition (OCR) via Google ML Kit.
  * **Privacy:** Images captured by the camera are processed directly on your device. We do not transmit or store receipt photos on external servers.
* **SMS Messages (`android.permission.READ_SMS`, `android.permission.RECEIVE_SMS`):**
  * **Use:** An optional automated expense ingestion feature. If enabled, 1Wallet reads incoming bank transaction alerts to parse amounts, dates, and merchant names.
  * **Privacy:** SMS messages are processed purely on-device. Personal conversations and non-financial SMS messages are ignored and never collected, transmitted, or logged.
* **Notification Listener (`BIND_NOTIFICATION_LISTENER_SERVICE`):**
  * **Use:** An optional feature enabling 1Wallet to detect transaction push alerts from payment or banking apps you specify.
  * **Privacy:** Notification content is parsed on-device to record ledger entries and is never uploaded.
* **Biometrics (`USE_BIOMETRIC`, `USE_FINGERPRINT`):**
  * **Use:** Allows you to lock 1Wallet with your fingerprint, face unlock, or PIN.
  * **Privacy:** Authentication is handled by Android’s native BiometricPrompt API. 1Wallet never has access to your biometric samples or credentials.
* **Storage / Photos (`READ_MEDIA_IMAGES`):**
  * **Use:** Allows you to attach receipt images or import PDF / CSV bank statements from your device.

---

## 3. Cloud Synchronization & Third-Party Services

If you choose to use cloud sync, 1Wallet connects with:
- **Google Sign-In / Firebase Authentication:** Authenticates your account securely without exposing your passwords.
- **Google Cloud Firestore:** Stores your encrypted ledger data for multi-device sync and cloud backup.

All data transmitted between your device and Google Cloud services is encrypted in transit using standard Transport Layer Security (TLS 1.3) and encrypted at rest on Google Cloud infrastructure.

---

## 4. Data Retention and Deletion

- **Local Data:** You can delete all local data at any time by navigating to **Settings > Clear Data** or by uninstalling the application.
- **Cloud Data:** If you have enabled cloud sync, you can delete your cloud account and all associated cloud ledger records directly inside **Settings > Account > Delete Account & Data**. Once deleted, all cloud records are permanently purged.

---

## 5. Security Practices

We implement industry-standard security safeguards to protect your personal information:
- Passcode and biometric app lock gates.
- Optional AES-256 encrypted local backups.
- Secure token storage using Android Keystore / EncryptedSharedPreferences.

---

## 6. Children's Privacy

1Wallet is not directed at children under the age of 13. We do not knowingly collect personal information from children.

---

## 7. Changes to This Privacy Policy

We may update this Privacy Policy periodically. Any updates will be reflected with a revised "Last Updated" date at the top of this document and published in the application.

---

## 8. Contact Us

If you have questions, feedback, or data privacy requests regarding 1Wallet, please contact:

**Developer:** Joel P Joji  
**Email:** privacy@onewallet.app *(or your preferred contact email)*  
**Repository:** https://github.com/joelpjoji/1wallet
