# Security Policy & Cryptographic Model

The 1Wallet team takes personal financial security and privacy with paramount seriousness. This policy outlines our supported versions, vulnerability reporting process, and cryptographic guarantees.

---

## 🔒 Supported Versions

We actively provide security patches for the current major release track:

| Version Track | Supported |
| :--- | :--- |
| `v2.x.x` | ✅ Yes (Active Support) |
| `v1.x.x` | ❌ No (End of Life) |

---

## 🛡️ Core Security Architecture & Guarantees

### 1. Data Isolation & Zero-Knowledge Architecture
- **Local Persistence**: User transactions, notes, receipts, and balance history are stored locally on the user's device.
- **Firebase User Isolation**: Firestore security rules (`firebase/firestore.rules`) strictly enforce that users can only read or write their own documents under `users/{uid}` matching `request.auth.uid`. Cross-user inspection or batch enumeration is blocked at the database engine level.

### 2. Encryption Standards
- **Local Backups**: Exported backup files are encrypted with `AES-256-GCM` providing authenticated data confidentiality and tamper detection.
- **Key Derivation**: Passphrase-based keys are derived using `PBKDF2` with HMAC-SHA256, a minimum of 100,000 iterations, and a cryptographically secure random 16-byte salt.
- **Key Storage**: On-device keys are safeguarded using platform secure elements:
  - **Android**: Android Keystore Provider with hardware-backed encryption.
  - **iOS**: Apple Keychain Services with `kSecAttrAccessibleAfterFirstUnlock`.

### 3. Biometric App Lock & Screen Obfuscation
- The app gate (`AppLockGate`) protects the visual layer using `local_auth` (Face ID / Fingerprint).
- When the application is sent to the background, sensitive screens and balances are masked before operating system screenshots are taken for the task switcher.

---

## 🚨 Reporting a Vulnerability

If you discover a security vulnerability within 1Wallet, please disclose it responsibly:

1. **Do Not Open a Public GitHub Issue**.
2. Email full vulnerability details, proof-of-concept steps, and affected versions to:  
   **`security@1wallet.app`** (or contact the repository maintainer privately).
3. Provide up to 48 hours for an initial response before taking any public action.
4. We acknowledge all legitimate reports and coordinate disclosure timelines following patch verification.
