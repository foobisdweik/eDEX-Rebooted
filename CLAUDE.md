# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status

This is eDEX-UI **v3.0.0**, a Tauri 2 + Rust native port of the historical Electron-based fork, targeting **`aarch64-apple-darwin` only**. The Electron + Node-pty + systeminformation stack is gone. Active implementation planning lives in `ULTRAPLAN.md`. Do not duplicate implementation plans or backlog lists in this guidance file.

v1 is "core proven": app boots fullscreen, terminal echoes, managed terminal tabs spawn independent PTYs, the visual panels populate (clock/sysinfo/cpuinfo/hardwareInspector/ramwatcher/toplist), keyboard renders, settings modal opens, audio cues fire.

## Architecture

```
src-tauri/                          src/
  Cargo.toml + tauri.conf.json        ui.html  (script tags, no bundler)
  capabilities/default.json           renderer.js  (boot IIFE, Tauri globals)
  src/                                classes/  (xterm shell + visual panels)
    main.rs   → lib::run()              terminal, filesystem, modal,
    lib.rs    → invoke_handler[..],     mediaPlayer, keyboard, clock,
                .manage() state,        sysinfo, hardwareInspector,
                .setup() ensures        cpuinfo, ramwatcher, toplist,
                userData dir            fuzzyFinder, audiofx,
    pty.rs    → portable-pty per id,    netstat (loaded? no — v0.2)
                tokio reader task,    assets/
                emits pty://{id}/data    css/      themes/  keyboards/
    sysinfo_cmds.rs → si_* (cpu,        fonts/    audio/   icons/
                load, temp, mem,        misc/file-icons-match.js
                processes, net,         vendor/   ← xterm/howler/smoothie/
                disks, system,                       augmented-ui (all UMD,
                chassis, uptime)                     no node_modules at runtime)
    fs_cmds.rs → fs_* (readdir,
                stat, readfile,
                writefile, exists,
                open_external)
    settings.rs → get/write_* for
                settings/shortcuts/
                window_state +
                theme/kb overrides +
                paths/displays/
                username
```

**IPC model:** every renderer↔backend call goes through Tauri `invoke()` (in-process — no socket, no sidecar). PTY data flows back via `listen("pty://{id}/data", …)` events. `window.si` in `renderer.js` is a `Proxy` that maps `window.si.networkInterfaces()` → `invoke("si_network_interfaces")` (camelCase → snake_case). All visual classes consume that Proxy, so they don't know they're talking to Rust.

**Frontend payload is fully vendored under `src/assets/vendor/`:** xterm UMD + addon-fit/ligatures/webgl, augmented-ui CSS, howler, smoothie. There's no runtime `node_modules/` and no `npm install` in the build path — `src/package.json` exists only as version-pinning documentation. The vendored UMD scripts attach globals; `ui.html` aliases the xterm globals to `window.__XTERM*__` so the project's own `class Terminal` doesn't collide.

**Settings storage:** `~/Library/Application Support/eDEX-UI/{settings.json,shortcuts.json,lastWindowState.json,themes/,keyboards/,fonts/}`. `settings.rs::ensure_userdata` mirrors bundled themes/keyboards/fonts/boot_log into that dir on every `setup()`; built-ins overwrite, custom files survive.

**File-icons content stays content, not code:** `file-icons-generator.js` (root), the `file-icons/` git submodules, `src/assets/icons/file-icons.json`, and `src/assets/misc/file-icons-match.js` are all preserved. `npm run update-file-icons` regenerates the JSON from the submodules.

## Build & dev commands

```bash
# Run from source (file watcher rebuilds on changes in src-tauri/ only;
# frontend edits in src/ are picked up by reloading the WKWebView via Cmd+R)
cargo tauri dev

# Production build → src-tauri/target/aarch64-apple-darwin/release/bundle/
#   .app and .dmg artifacts
cargo tauri build --target aarch64-apple-darwin

# File-icons regeneration (Node-side tool, uses cson-parser)
npm run init-file-icons              # git submodule update --init
npm run update-file-icons            # pull submodules + run file-icons-generator.js
```

There is **no test framework**. Smoke-test changes by running `cargo tauri dev` and exercising the affected feature — terminal I/O, theme swap (Ctrl+Shift+S), keyboard swap, multi-tab spawn (Ctrl+X then 2/3/4/5), filesystem panel navigation, the sysinfo/cpuinfo/ramwatcher/toplist panels.

## Non-obvious gotchas

- **`cargo tauri dev`'s file watcher only watches `src-tauri/`.** Frontend edits under `src/` don't trigger a rebuild — reload the WKWebView with `Cmd+R` to pick them up. Restart the dev process when you change `tauri.conf.json` or capabilities.
- **The `module.exports = {...}` line at the bottom of every `src/classes/*.class.js` throws a silent `ReferenceError` in WKWebView** (no Node = no `module`). The class declarations above it already register on the global scope, so this is harmless — leftover from the Electron era. You'll see these errors in devtools and can ignore them.
- **`generate_context!()` requires an RGBA `src-tauri/icons/icon.png`** even when only `.icns` is configured. If you swap the icon, extract a fresh RGBA PNG (`iconutil -c iconset media/icon.icns -o /tmp/icon.iconset && cp /tmp/icon.iconset/icon_512x512.png src-tauri/icons/icon.png`).
- **sysinfo crate API drifts between point releases.** Pinned at `0.32` in `Cargo.toml`. `Components/Networks/Disks::refresh()` take no args; `Component::temperature() -> f32` (not Option); `System::physical_core_count(&self)` is an instance method; `NetworkData` has no `mtu()` in 0.32. If you bump the crate, re-check `sysinfo_cmds.rs`.
- **Capabilities are allow-listed in `src-tauri/capabilities/default.json`.** New `invoke`-side APIs that touch core plugins (window, webview, shell, process, global-shortcut) need their permission added there, or Tauri 2 rejects the call at runtime with no friendly message. `core:window:allow-get-size` was renamed in Tauri 2 → use `allow-inner-size` / `allow-outer-size`.
- **macOS-only.** All `process.platform === "win32"` branches were removed. Don't reintroduce them — v0.2 may add Windows/Linux targets, and the cross-platform forks belong in Rust commands, not in the WKWebView.
- **`tauri-cli` lives at `~/.cargo/bin/cargo-tauri`** (install via `cargo install tauri-cli --version "^2.0" --locked`). If `cargo tauri` reports `no such command`, that's a missing install — not a config problem.
