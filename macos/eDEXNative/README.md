# eDEXNative Phase 3 Shell

This is the Phase 3.1/3.2 Swift shell spike for the full native Swift+Rust migration.
It is intentionally parallel to the Tauri app and does not touch the WKWebView frontend or native panel slot files.

## What it proves

- SwiftUI/AppKit can launch the first native eDEX window.
- The app links `crates/edex-ffi/target/release/libedex_ffi.dylib`.
- Generated UniFFI Swift bindings can call:
  - `EdexCore.ensureUserdata()`
  - `EdexCore.paths()`
  - `EdexCore.loadSettingsJson()`
  - `EdexCore.loadThemeJson(name:)`
- The window chrome mirrors `src-tauri/src/window_chrome.rs`:
  - transparent titlebar
  - normal windowed traffic lights
  - fullscreen-capable window
  - `keepGeometry`-controlled 16:10 content aspect ratio
  - F11 fullscreen toggle

## Build/run

From this directory:

```bash
./Scripts/build_and_run.sh
```

Or manually:

```bash
cd ../../crates/edex-ffi
cargo build --release
cargo run --bin uniffi-bindgen -- generate \
  --library target/release/libedex_ffi.dylib \
  --language swift \
  --out-dir ../../macos/eDEXNative/Generated

cd ../../macos/eDEXNative
swift run eDEXNative
```

`Package.swift` links the SwiftPM executable to the release `edex_ffi` dynamic library and adds that directory as an rpath for dev runs. On a clean checkout, run `./Scripts/build_and_run.sh` first; plain `swift build` assumes the Rust release dylib and generated UniFFI files already exist. This is not a notarized packaging setup yet.

## 3.1 shell-viability assessment

Viable for continuing the Option-3 migration. The shell starts cleanly as a regular macOS app process, keeps AppKit-level control of the `NSWindow`, and calls the existing Rust core through UniFFI without Tauri. That is enough signal to use this shell as the future home for native panels and to skip additional interim CPU/RAM/toplist investment in `native_panels.rs` unless the Swift panel work slips badly.

Main caveat: this is still a dev SwiftPM executable rather than a signed `.app` distribution. Packaging, signing, notarization, asset bundling, and a production terminal renderer are later phases.
