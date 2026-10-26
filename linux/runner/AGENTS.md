# `linux/runner/` — Linux Native GTK Runner Target

## 🎯 Role & Overview
Contains the GTK+ application host for running 1Wallet on Linux desktop environments.

---

## 📜 Key Files

- **`main.cc`**:
  - Main entry point initializing the GTK application and passing command-line arguments.
- **`my_application.cc`**:
  - Implements the GTK application class, window creation, window title, and Flutter engine controller setup.

---

## 🛡️ Critical Invariants & Architecture

1. **Window Size Bounds**:
   - The default window dimensions must accommodate both compact mobile-like aspect ratios and expanded desktop multi-column views.
