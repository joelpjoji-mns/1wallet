<div align="center">
  <img src="https://raw.githubusercontent.com/joelpjoji-mns/1Wallet/main/assets/icon/icon.png" width="128" height="128" alt="1Wallet Logo" style="border-radius: 20%">
  
  <h1>1Wallet</h1>
  <p><b>Your Financial World, Unified.</b></p>
  
  <p>
    <img src="https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white" alt="Flutter">
    <img src="https://img.shields.io/badge/Firebase-ffca28?style=for-the-badge&logo=firebase&logoColor=black" alt="Firebase">
    <img src="https://img.shields.io/github/actions/workflow/status/joelpjoji-mns/1wallet/android-release.yml?style=for-the-badge&label=Release" alt="Build Status">
  </p>
</div>

<br/>

## 💳 The Definitive Digital Wallet
**1Wallet** is a secure, elegant, and unified digital wallet application built for the modern financial era. It empowers users to track, manage, and consolidate their financial assets in one seamless interface.

### ✨ Key Features
* **Unified Dashboard**: View all your financial assets, transactions, and balances at a glance.
* **Secure Authentication**: Enterprise-grade security with seamless Google and Apple Sign-In support via Firebase Authentication.
* **Real-time Synchronization**: Powered by Firebase Firestore, your wallet updates instantly across all your devices.
* **Dynamic Over-The-Air Updates**: Features a highly customized Android release pipeline that supports in-app updates seamlessly via Firebase-hosted manifests.

## 🏗️ Architecture & Technology Stack
1Wallet sets the gold standard for Flutter application architecture:
* **Framework**: Flutter & Dart (Material 3)
* **State Management**: Riverpod for reactive caching and state resolution.
* **Data Modeling**: Freezed & JSON Serializable for rock-solid immutability.
* **Backend**: Firebase Auth, Cloud Firestore, Firebase Storage.
* **CI/CD Automation**: Custom Node.js scripts integrated with GitHub Actions for automated Keystore signing, Release APK generation, and dynamic JSON manifesting.

## 🛠️ Getting Started
To build and run this project locally, ensure you have Flutter installed.

1. Clone the repository:
   ```bash
   git clone https://github.com/joelpjoji-mns/1wallet.git
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Generate dependencies and models:
   ```bash
   dart run build_runner build -d
   ```
4. Run the app:
   ```bash
   flutter run
   ```

---
<div align="center">
Simplifying your financial life, one tap at a time.
</div>
