# 1wallet

The 1wallet mobile app built with Flutter. Features Google/Firebase sign-in,
branded launch/login screens, first-run onboarding, and Material 3 theming.

## Local auth config

Copy `.env.example` to `.env` and fill the Firebase + Google OAuth values before
testing real Google sign-in:

- `FIREBASE_API_KEY`
- `FIREBASE_AUTH_DOMAIN`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_STORAGE_BUCKET`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_APP_ID`
- `GOOGLE_WEB_CLIENT_ID`
- `GOOGLE_ANDROID_CLIENT_ID`
- `GOOGLE_IOS_CLIENT_ID`

`.env` is intentionally ignored by git. Android is configured with package ID
`com.joelpjoji.one.wallet`, so the Firebase project must include that package and
its debug/release SHA fingerprints for Google sign-in to work.

The config loader accepts direct names such as `FIREBASE_API_KEY`.

## QA email/password restore

Google remains the primary production sign-in. A debug-only email/password panel
can be shown for Firebase restore testing with:

- `ONEWALLET_ENABLE_EMAIL_PASSWORD_AUTH=true`
- `ONEWALLET_QA_EMAIL=<your Firebase QA email>`
- `ONEWALLET_QA_PASSWORD=<local generated password>`

Keep the QA password only in ignored local files such as `.env`.

On sign-in, the app checks Firestore for the authenticated user's latest
wallet snapshot at `users/{uid}/wallets/default`, downloads ordered snapshot
chunks, validates the `OneWalletArchiveV1` checksum, converts the
ledger into local models, persists it locally, and then routes to Home. If no
cloud snapshot exists, onboarding still creates the first local wallet.

The current cloud implementation is restore/read-only. Automatic upload
is intentionally not enabled yet.

## Validation

Use the local Flutter SDK path on Windows:

```powershell
C:\Users\Joel\development\flutter\bin\flutter.bat analyze --no-pub
C:\Users\Joel\development\flutter\bin\flutter.bat test --no-pub
C:\Users\Joel\development\flutter\bin\flutter.bat build apk --debug --no-pub
```

If `flutter pub get` reports that plugin symlink support is required, enable
Windows Developer Mode and run it again.
