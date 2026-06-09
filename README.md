<p align="center">
  <br>
  <img alt="Logo" src="media/logo.png">
  <br>
  <br><br><br>
</p>

eDEX-UI is a fullscreen terminal emulator and system monitor that looks and feels like a sci-fi computer interface.

This is a community-driven fork of the original eDEX-UI (archived October 2021). **v3.0.0 is a native rewrite on Tauri 2 + Rust**, replacing the original Electron + Node stack. The WebSocket-based terminal control channel that motivated this fork's security patches has been removed entirely — terminal I/O now flows through Tauri's in-process IPC, with no listening socket.

The active development branch is now `post-web-runtime`: a SwiftUI + Rust native app under `macos/eDEXNative/` is replacing the WKWebView frontend while reusing `crates/edex-core` and `crates/edex-ffi`. The Tauri/WKWebView stack remains the historical v3.0.0 release path until the Phase 11 deletion gate is green.

> [!NOTE]
> Android port: [Edex-UI-android](https://github.com/theelderemo/Edex-UI-android)

# What's new in v3.0.0

- **Tauri 2 + Rust backend.** No Electron, no Node runtime at runtime, no `node_modules/` shipped.
- **macOS Apple Silicon only.** Target: `aarch64-apple-darwin`. Windows and Linux are out of scope for this release; they may return in a later version.
- **Native PTY** via the Rust `portable-pty` crate (replacing `node-pty`).
- **Native system info** via the Rust `sysinfo` crate (replacing the `systeminformation` npm package).
- **Vendored frontend payload.** xterm + addons (fit/ligatures/webgl), augmented-ui, howler, and smoothie are checked into `src/assets/vendor/` as UMD bundles — no install step for the frontend.
- **WKWebView renderer** instead of a bundled Chromium. Smaller, faster cold start, lower memory.
- **Security posture.** No localhost WebSocket. Tauri capabilities allow-list every backend command the frontend can invoke (`src-tauri/capabilities/default.json`).

# What works in v1 (this release)

Boots fullscreen, terminal echoes, terminal tabs spawn independent PTYs (Ctrl+X then 1-5, Ctrl+Tab, Ctrl+Shift+Tab), filesystem panel follows the active tab, sysinfo/cpuinfo/ramwatcher/toplist panels populate, hardware inspector renders, on-screen keyboard renders and swaps layouts, theme swap (Ctrl+Shift+S), settings modal opens, audio cues fire.

# Known issues / v0.2 backlog

- Network globe (`locationGlobe`), connection list (`conninfo`), PDF viewer (`docReader`), and GitHub update checker (`updateChecker`) are **not present** in v1 — they will return in v0.2 reimplemented against Rust commands.
- `si_network_connections` returns an empty list (placeholder for v0.2).
- `.app` is not yet code-signed or notarized.

# Security history

This fork originated to patch a critical RCE in the upstream Electron build: malicious websites could connect to the internal terminal control WebSocket and execute arbitrary shell commands. The v2.x patch added strict `file://` origin validation on the WebSocket. **v3.0.0 removes the WebSocket entirely** — terminal I/O is now in-process Tauri IPC, so the class of vulnerability no longer exists in this codebase.

Pre-built binaries from the original upstream repository still contain the WebSocket vulnerability. Use builds from this fork only.

# Build from source

## Requirements

- macOS 11+ on Apple Silicon (`aarch64-apple-darwin`)
- Rust toolchain (stable)
- `tauri-cli` v2:
  ```
  cargo install tauri-cli --version "^2.0" --locked
  ```
- Xcode Command Line Tools (`xcode-select --install`)
- Node.js is **only** required if you want to regenerate `src/assets/icons/file-icons.json` from the file-icons submodules. The app itself does not need Node to build or run.

> [!IMPORTANT]
> Use a current stable Rust toolchain. Older Cargo builds, including 1.81, cannot parse some current dependency metadata and fail before compiling the app.

## Run from source

Released Tauri/WKWebView stack:

```
git clone https://github.com/theelderemo/eDEX-UI-security-patched.git
cd eDEX-UI-security-patched
cargo +stable tauri dev
```

Active native app:

```
git switch post-web-runtime
bash scripts/native-phase smoke
```

For manual native-app runs, see `macos/eDEXNative/README.md`.

## Produce a release `.app` / `.dmg`

```
cargo +stable tauri build --target aarch64-apple-darwin
```

Verified v3.0.0 artifacts land in:

- `src-tauri/target/aarch64-apple-darwin/release/bundle/macos/eDEX-UI.app`
- `src-tauri/target/aarch64-apple-darwin/release/bundle/dmg/eDEX-UI_3.0.0_aarch64.dmg`

## (Optional) regenerate file-icons

```
npm run init-file-icons
npm run update-file-icons
```

# Project layout

```
src-tauri/         Rust backend — Tauri commands, PTY, sysinfo, filesystem, settings
src/               WKWebView frontend — ui.html + classes/*.class.js + vendored assets
crates/edex-core/  Tauri-free Rust core shared by Tauri adapters and the native app
crates/edex-ffi/   UniFFI bridge and generated Swift bindings source
macos/eDEXNative/  SwiftPM native macOS app replacing the WKWebView frontend
media/             Icons, logo
file-icons/        File-icons source (git submodules; content, not code)
```

See `CLAUDE.md` for the full architecture map and per-module notes.

# Contributing

Bug reports and PRs are welcome. Target `post-web-runtime` for native migration work. Target `master` only for release-branch/security fixes to the frozen Tauri stack. If you're working on a v0.2-backlog module, open an issue first so we can sync on the design.

# Credits

eDEX-UI was created by [GitSquared (Gabriel Saillard)](https://github.com/GitSquared). Sound effects by [IceWolf](https://soundcloud.com/iamicewolf). Original globe visualization by [Rob "Arscan" Scanlon](https://github.com/arscan).

This security-patched fork and the v3.0.0 Tauri port are maintained by [theelderemo](https://github.com/theelderemo).

# License

[GPLv3.0](https://github.com/GitSquared/edex-ui/blob/master/LICENSE), same as the original project.
