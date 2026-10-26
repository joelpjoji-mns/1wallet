# `linux/` — Linux Desktop Platform Layer

## 🎯 Role & Overview
Houses the Linux desktop embedding, CMake configuration, GTK application runner, and build scripts.

---

## 📜 Key Configuration & Files

- **`CMakeLists.txt`**:
  - Builds the native GTK executable, links Flutter engine libraries, and packages plugins.
- **`my_application.cc` / `main.cc`**:
  - GTK application lifecycle and window initialization.

---

## 🛡️ Critical Invariants & Architecture

1. **System Library Dependencies**:
   - Compiling on Linux requires GTK-3 (`libgtk-3-dev`) and build essentials (`clang`, `cmake`, `ninja`).

---

## 🔍 LLM / Developer Checklist

- [ ] Ensure any newly added Flutter desktop plugins compile cleanly under Linux CMake targets.
