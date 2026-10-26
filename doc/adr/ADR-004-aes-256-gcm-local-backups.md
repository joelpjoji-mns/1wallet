# ADR-004: AES-256-GCM & PBKDF2 for Exported Backups

## Context
Users frequently export local backup files to transfer data between devices, archive past financial years, or retain self-custody copies on cloud storage (Google Drive, iCloud, Dropbox). Plaintext JSON exports expose full financial history and account identifiers to unauthenticated inspection.

## Decision
All exported backup archives (`.1wbackup`) must be encrypted using:
- **Cipher**: `AES-256-GCM` (Galois/Counter Mode), providing authenticated encryption with associated data (AEAD) to detect tampering.
- **Key Derivation**: `PBKDF2` with HMAC-SHA256, generating a 256-bit symmetric key from user-supplied passphrases.
- **Salt & IV**: Unique 16-byte cryptographically secure random salt and 12-byte initialization vector (IV) per export bundle.
- **Iteration Count**: Minimum 100,000 iterations to protect against brute-force dictionary attacks.

## Consequences
### Positive
- Military-grade confidentiality and integrity verification for user financial data outside the application.
- Tamper detection: Any modification to ciphertext or authentication tag fails decryption before parsing.
- Interoperability across platforms: AES-GCM and PBKDF2 are standard cryptographic primitives supported natively across Flutter and Web.

### Negative / Trade-offs
- If a user loses their export passphrase, the data is mathematically unrecoverable.
