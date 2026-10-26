# `web/splash/` — Web Native Splash Assets

## 🎯 Role & Overview
Houses static CSS, lightweight HTML, and image assets displayed while the Flutter WebAssembly / JavaScript runtime initializes in the user's browser.

---

## 🛡️ Critical Invariants & Architecture

1. **Zero Runtime Dependency**:
   - The splash styling defined in `splash.js` or `style.css` must execute instantly upon HTML parsing before Flutter scripts are loaded.
2. **Smooth Fadeout**:
   - The splash container is smoothly faded out once the Flutter engine dispatches the first rendered frame.
