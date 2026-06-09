# eDEXNative

SwiftPM native macOS app for the `post-web-runtime` migration. It links the Rust core through `crates/edex-ffi`; the legacy WKWebView/Tauri transition stack was retired in Phase 9.7.

## Current Status

The original Phase 3 shell spike proved the app can launch a native eDEX window, control AppKit window chrome, and call the Rust core through UniFFI. The app has since advanced through Phase 9.7: telemetry panels, audio, modals, settings, shortcuts, boot screen, filesystem, fuzzy finder, text editor, keyboard layout loading/rendering/input routing, and the SwiftTerm-backed PTY terminal are native.

Follow `Ultrareview.md`: the SwiftPM taxonomy groups support code into domain and rendering targets, terminal/action seams are in place, and new work should continue splitting `ShellState` ownership while keeping `ContentView` as a compositor. Shared bundled data lives under the repo-level `assets/` directory.

## Build And Run

Use the repo helper when possible:

```bash
bash scripts/native-phase smoke
```

From this directory, the manual path is:

```bash
./Scripts/build_and_run.sh
```

Or, explicitly:

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

`Package.swift` links the SwiftPM executable to the release `edex_ffi` dynamic library and adds that directory as an rpath for dev runs. Plain `swift build` assumes the Rust release dylib and generated UniFFI files already exist.

## Architecture Notes

- FFI calls go through `EdexCoreClient` and must stay off the MainActor.
- Existing support modules are grouped into `EdexDomainSupport` and `EdexRenderingSupport`; keep domain/display logic testable there instead of adding one target per feature.
- New input/routing work should target `TerminalSessionProviding` and `EdexActionHandler`, not direct view-to-store cross-calls.
- `ContentView` should place surfaces; feature rendering belongs in dedicated views.

This is still a dev SwiftPM executable rather than a signed `.app` distribution. Packaging, signing, notarization, and final asset bundling are later phases.
