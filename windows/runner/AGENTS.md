# `windows/runner/` — Windows Desktop Runner Target

## 🎯 Role & Overview
Houses the native Win32 application host, message loop, DPI scaling handler, and Windows executable resource scripts.

---

## 📜 Key Files

- **`main.cpp`**:
  - Win32 entrypoint (`wWinMain`), initializes COM, parses command-line parameters, and starts the message loop.
- **`flutter_window.cpp`**:
  - Manages the Win32 window, high-DPI scaling, and Flutter view embedding.
- **`Runner.rc` & `resource.h`**:
  - Executable icons, version metadata, and application manifest resources.

---

## 🛡️ Critical Invariants & Architecture

1. **High-DPI Awareness**:
   - `flutter_window.cpp` ensures per-monitor DPI scaling is active so text and vector glass elements remain sharp when dragged between monitors.
