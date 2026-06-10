# eDEXNative

SwiftPM native macOS app for the `post-web-runtime` migration. It links the Rust core through `crates/edex-ffi`; the legacy WKWebView/Tauri transition stack was retired in Phase 9.7.

## Current Status

The original Phase 3 shell spike proved the app can launch a native eDEX window, control AppKit window chrome, and call the Rust core through UniFFI. The app has since completed the Phase 0-11 native-conversion feature scope: telemetry panels, audio, modals, settings, shortcuts, boot screen, filesystem, fuzzy finder, text editor, keyboard layout loading/rendering/input routing, SwiftTerm-backed PTY terminal, native file icons, and the media viewer are native.

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

## Package A Local App Bundle

SwiftPM does not produce a macOS `.app` archive by itself. Use the packaging helper to assemble a local bundle under `dist/eDEXNative.app`:

```bash
macos/eDEXNative/Scripts/package_app.sh
```

The helper builds the Rust FFI dylib and Swift release executable, copies bundled data into `Contents/Resources/assets`, places `libedex_ffi.dylib` in `Contents/Frameworks`, rewrites the executable linkage to `@rpath/libedex_ffi.dylib`, and ad-hoc signs the bundle by default.

For Developer ID signing, provide a real identity:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Example Team (TEAMID)" macos/eDEXNative/Scripts/package_app.sh
```

Notarization still requires external Apple credentials and should be run on the signed exported artifact. This script validates local bundle structure and signing, but it does not submit to Apple notarization.

## Architecture Notes

- FFI calls go through `EdexCoreClient` and must stay off the MainActor.
- Existing support modules are grouped into `EdexDomainSupport` and `EdexRenderingSupport`; keep domain/display logic testable there instead of adding one target per feature.
- New input/routing work should target `TerminalSessionProviding` and `EdexActionHandler`, not direct view-to-store cross-calls.
- `ContentView` should place surfaces; feature rendering belongs in dedicated views.

Distribution hardening remains a release-operations step: verify the final bundle on a clean machine, sign with Developer ID + hardened runtime, notarize, staple, and re-run Gatekeeper validation before publishing binaries.
