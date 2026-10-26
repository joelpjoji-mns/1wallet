# `windows/` — Windows Desktop Platform Layer

## 🎯 Role & Overview
Houses the native Windows desktop runner, Win32 application entry point, CMake build system, and Windows resources (icons, version metadata).

---

## 📜 Key Configuration & Files

- **`CMakeLists.txt`**:
  - Directs MSVC or Clang to compile the Win32 executable, embed resource scripts, and link Flutter engine DLLs.
- **`runner/main.cpp` & `flutter_window.cpp`**:
  - Win32 message loop, window creation, sizing, and DPI awareness settings.
- **`runner/Runner.rc`**:
  - Windows executable resources, file version, product name, and icon definitions.

---

## 🛡️ Critical Invariants & Architecture

1. **DPI Awareness**:
   - `flutter_window.cpp` coordinates high-DPI scaling across multi-monitor setups.

---

## 🔍 LLM / Developer Checklist

- [ ] Confirm that `flutter build windows` produces a clean bundle with all required dynamic libraries (`flutter_windows.dll`, plugin DLLs).
