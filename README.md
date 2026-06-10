<p align="center">
  <br>
  <img alt="Logo" src="media/logo.png">
  <br>
  <br><br><br>
</p>

eDEX-UI is a fullscreen terminal emulator and system monitor that looks and feels like a sci-fi computer interface.

This is a community-driven fork of the original eDEX-UI (archived October 2021). **v3.x is a full native rewrite in Swift + Rust** — a SwiftUI app (`macos/eDEXNative/`) linking a Rust core (`crates/edex-core` + `crates/edex-ffi` via UniFFI). The original Electron + Node stack, the interim Tauri 2 / WKWebView stack, and with them the entire JavaScript/TypeScript/CSS codebase are gone. The WebSocket-based terminal control channel that motivated this fork's security patches no longer exists in any form — terminal I/O is in-process, with no listening socket.

The active development branch is `post-web-runtime`; `master` is frozen at the historical v3.0.0 Tauri release.

> [!NOTE]
> Android port: [Edex-UI-android](https://github.com/theelderemo/Edex-UI-android)

# The native app

- **SwiftUI frontend, Rust backend.** No Electron, no Tauri, no WebView, no Node — at runtime or build time.
- **macOS Apple Silicon only.** Target: `aarch64-apple-darwin`. Windows and Linux are out of scope; cross-platform logic, if it returns, belongs in Rust.
- **Terminal:** [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) fed by the Rust in-process PTY (`portable-pty`), with the eDEX CRT aesthetic overlaid natively. Five tabs, cwd-follow, burn-in validated against vim/nano/top/tmux/ssh/ANSI/Unicode workloads.
- **Telemetry** via the Rust `sysinfo` crate: clock, sysinfo, hardware inspector, CPU graphs, RAM watcher, top process list — tuned for low idle CPU/GPU (see `docs/benchmarks/`).
- **Filesystem panel** with the original per-filetype SVG icon set, ported to native rendering from frozen JSON data (`assets/icons/file-icons.json` + `assets/misc/file-icons-match.json`).
- **On-screen keyboard, boot screen, modals, settings editor, fuzzy finder, text editor, audio cues** — all native Swift over typed UniFFI records.
- **Security posture.** No listening socket, no web content, no IPC bridge exposed to a renderer. The DOM-XSS→IPC escalation class is structurally gone.

# Security history

This fork originated to patch a critical RCE in the upstream Electron build: malicious websites could connect to the internal terminal control WebSocket and execute arbitrary shell commands. The v2.x patch added strict `file://` origin validation on the WebSocket. v3.0.0 (Tauri) removed the WebSocket entirely; the current native app removes the web renderer itself, so neither the socket nor the webview attack surface exists in this codebase.

Pre-built binaries from the original upstream repository still contain the WebSocket vulnerability. Use builds from this fork only.

# Build from source

## Requirements

- Apple Silicon Mac on a current macOS
- Swift 6 toolchain (the project uses [swiftly](https://github.com/swiftlang/swiftly); Xcode Command Line Tools work too)
- Rust toolchain (current stable)

## Run from source

```
git clone https://github.com/theelderemo/eDEX-UI-security-patched.git
cd eDEX-UI-security-patched
git switch post-web-runtime
bash scripts/native-phase smoke
```

`native-phase smoke` builds the Rust FFI dylib and launches the app windowed. For manual runs and packaging notes, see `macos/eDEXNative/README.md`. The frozen v3.0.0 Tauri release remains buildable from the `master` branch only.

# Project layout

```
crates/edex-core/  Rust core — PTY, sysinfo, settings, filesystem (no UI deps)
crates/edex-ffi/   UniFFI bridge; generated Swift bindings live in macos/eDEXNative/Generated/
macos/eDEXNative/  SwiftPM native macOS app (SwiftUI + SwiftTerm)
assets/            Bundled data: themes, keyboard layouts, fonts, audio, icons, boot log
scripts/           native-phase — the build/verify/ship workflow entry point
docs/              Plans, benchmarks, validation evidence
media/             Icons, logo
```

See `CLAUDE.md` for the full architecture map and per-module notes.

# Contributing

Bug reports and PRs are welcome. Target `post-web-runtime` for all app work. Target `master` only for release-branch/security fixes to the frozen Tauri stack.

# Credits

eDEX-UI was created by [GitSquared (Gabriel Saillard)](https://github.com/GitSquared). Sound effects by [IceWolf](https://soundcloud.com/iamicewolf). Original globe visualization by [Rob "Arscan" Scanlon](https://github.com/arscan).

This security-patched fork, the v3.0.0 Tauri port, and the native Swift/Rust rewrite are maintained by [theelderemo](https://github.com/theelderemo).

# License

[GPLv3.0](https://github.com/GitSquared/edex-ui/blob/master/LICENSE), same as the original project.
