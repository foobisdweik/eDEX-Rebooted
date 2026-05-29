# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status

eDEX-UI **v3.0.0**: a Tauri 2 + Rust native port of the historical Electron fork, targeting **`aarch64-apple-darwin` only**. The Electron + node-pty + systeminformation stack is gone — terminal I/O and system info now run through Rust over in-process Tauri IPC (no listening socket; the WebSocket RCE class that motivated the original fork no longer exists here).

v1 is "core proven": boots fullscreen, terminal echoes, managed tabs spawn independent PTYs, the left-column visual panels populate (clock/sysinfo/hardwareInspector/cpuinfo/ramwatcher/toplist), on-screen keyboard renders and swaps layouts, theme swap works, settings modal opens, audio cues fire.

**Active workstream — frontend→native conversion.** The project is incrementally replacing WKWebView JS/CSS panels with native AppKit renderers fed by Rust. The plan of record lives in `docs/` (see *Conversion docs* below); the first cut is the per-panel "slot" infrastructure plus the two trivial text panels.

**Deferred to v0.2 — not present in v1** (don't assume these modules exist): network globe (`locationGlobe`), connection list (`conninfo`), PDF viewer (`docReader`), update checker (`updateChecker`). `si_network_connections` returns an empty stub.

## Build, run, and test

```bash
# Run from source. A current STABLE Rust toolchain is required — Cargo <=1.81
# cannot parse some dependency metadata and fails before compiling.
cargo +stable tauri dev

# Release .app + .dmg → src-tauri/target/aarch64-apple-darwin/release/bundle/{macos,dmg}/
cargo +stable tauri build --target aarch64-apple-darwin
```

`tauri-cli` v2 lives at `~/.cargo/bin/cargo-tauri`. If `cargo tauri` reports "no such command," install it (this is a missing install, not a config problem):
```bash
cargo install tauri-cli --version "^2.0" --locked
```

Test coverage is **targeted, not comprehensive** — there is no broad framework. What exists:

```bash
# JS — Node's built-in test runner (run from repo root)
node --test src/bridge/bridge.test.js src/bridge/native_mount.test.js src/classes/terminalTabs.class.test.js
node --check src/renderer.js                 # syntax-check a frontend file

# Rust (run from src-tauri/)
cargo test                                   # all, incl. unit tests in-module
cargo test --test sysinfo_contract           # Rust→JS JSON wire-shape contract
cargo check
cargo fmt --check
cargo clippy -- -D warnings
```

For everything else, smoke-test by running `cargo tauri dev` and exercising the feature: terminal I/O, multi-tab spawn (Ctrl+X then 1-5), theme swap (Ctrl+Shift+S), keyboard swap, filesystem navigation, and the sysinfo/cpuinfo/ramwatcher/toplist panels.

File-icons regeneration (Node, only needed to rebuild `src/assets/icons/file-icons.json`):
```bash
npm run init-file-icons        # git submodule update --init
npm run update-file-icons      # pull submodules + run file-icons-generator.js
```

## Architecture

**The trust/IPC boundary is Tauri `invoke()` — everything crosses it in-process.** There is no socket and no sidecar. PTY output flows back to the renderer via `listen("pty://{id}/data", …)` events. The renderer never imports Node.

**`window.si` is the seam that hides Rust from the panels.** In `src/renderer.js` it's a `Proxy` that maps `window.si.networkInterfaces()` → `invoke("si_network_interfaces")` (camelCase → snake_case). Every visual class consumes that Proxy, so they don't know they're talking to Rust. When adding a sysinfo field, you change Rust *and* nothing on the JS call site changes shape.

**Backend (`src-tauri/src/`):** `main.rs` → `lib::run()`. `lib.rs` is the wiring hub: it registers the full `invoke_handler![…]` surface, `.manage()`s the shared state (`PtyManager`, `OverrideState`, `Arc<SysinfoService>`, `NativeMountState`), and `.setup()` runs `settings::ensure_userdata` + `window_chrome::configure` + `native_mount::install`.

- `pty.rs` — one `portable-pty` PTY per id, a tokio reader task per PTY emitting `pty://{id}/data`.
- `sysinfo_service.rs` / `sysinfo_cmds.rs` — **two layers, read them together.** `SysinfoService` is Tauri-agnostic: it owns the cached sysinfo handles (`System`/`Components`/`Networks`/`Disks` behind `Mutex`) and exposes typed query methods. `sysinfo_cmds.rs` is just the thin `#[tauri::command]` `si_*` wrappers over it. The split exists so the native panel renderers can query the service directly without an `invoke()` round-trip.
- `fs_cmds.rs` — `fs_*` (readdir/stat/readfile/writefile/exists/open_external).
- `settings.rs` — get/write settings, shortcuts, window state; theme/keyboard overrides; paths/displays/username/`resolve_shell`; and `ensure_userdata` (see Settings storage).
- `native_mount.rs` / `native_modal.rs` — AppKit interop (objc/cocoa/core-graphics) for the native migration. `native_mount.rs` mounts one NSView over `#mod_column_left` (the clock pilot's `setClockText`); `native_modal.rs` is an NSAlert-only notify pilot. `window_chrome.rs` — macOS window chrome.

**Frontend (`src/`):** no bundler. `ui.html` is script tags in load order; `renderer.js` is the boot IIFE and orchestrator. `classes/*.class.js` are the xterm-backed `Terminal` plus the visual panels. `bridge/*.js` (state/audio/events/sysinfo/native_mount) are the JS-side shims to Rust. The frontend payload is **fully vendored** under `src/assets/vendor/` (xterm + addon-fit/ligatures/webgl, augmented-ui, howler, smoothie — all UMD). There is **no runtime `node_modules/` and no `npm install` in the build path**; `src/package.json` only documents pinned source versions.

**Native-panel migration — Approach A (per-panel slots).** All six left-column panels instantiate into `#mod_column_left` (`renderer.js` ~339-344). The current `native_mount` seam is **column-granular**: toggling `body.native-left-active` mounts one NSView over the *whole* column and hides every panel at once — so panels cannot be converted in isolation through it. The chosen path forward (Approach A) generalizes this into a **registry of per-panel NSView "slots"**, each sized to one panel's bounding rect, hiding only that panel's DOM. A `NativeThemeState` carries theme color/fonts to the slot renderers (native views have no `:root`/CSS vars). Gates: `experimentalNativePanels` (master) + per-panel flags (`experimentalNativeClock` already exists; `experimentalNativeSysinfo` / `experimentalNativeHwInspector` planned). Convert order by effort/coupling: trivial text panels (sysinfo, hardwareInspector) → chart panels (cpuinfo via CALayer, ramwatcher dot-grid) → toplist last (needs a content-bearing native custom modal, which `native_modal` does not yet provide; note there is **no** OS-pid kill command anywhere — `pty_kill` only closes internal PTY handles).

## Conversion docs (authoritative for the migration)

- `docs/superpowers/specs/2026-05-29-native-panel-conversion-design.md` — the design spec: Approach A (per-panel slots), the verified findings that shaped it, components/data-flow, scope (Phase 0+1), deferred phases, risks. **Start here.**
- `docs/native-migration/*.spec.md` — per-panel conversion specs (data contract, DOM/CSS, lifecycle, coupling, native mapping, effort) for clock, sysinfo, hardwareInspector, cpuinfo, ramwatcher, toplist.
- `docs/superpowers/plans/2026-05-29-native-panel-slots-phase0-1.md` — the bite-sized implementation plan for Phase 0 (slot registry + theme bridge + per-panel hide) and Phase 1 (sysinfo + hardwareInspector). Execute it with subagent-driven-development or executing-plans.

## Settings storage

`~/Library/Application Support/eDEX-UI/{settings.json,shortcuts.json,lastWindowState.json,themes/,keyboards/,fonts/}`. `settings::ensure_userdata` mirrors bundled themes/keyboards/fonts/boot_log into that dir on every `setup()`: built-ins overwrite, custom files survive. `settings.json` is free-form JSON — new experimental flags need no schema change.

## Non-obvious gotchas

- **`cargo tauri dev`'s file watcher only watches `src-tauri/`.** Frontend edits under `src/` do **not** trigger a rebuild — reload the WKWebView with **Cmd+R**. Restart the dev process when you change `tauri.conf.json` or `capabilities/`.
- **Custom commands need no capability entry.** Only core-plugin permissions (window/webview/shell/process/global-shortcut) go in `src-tauri/capabilities/default.json`; a missing one fails at runtime with no friendly message. Custom `#[tauri::command]`s (the `si_*`, `fs_*`, `native_*` families) are registered purely via `generate_handler!`. (Tauri 2 renamed `allow-get-size` → `allow-inner-size`/`allow-outer-size`.)
- **The `module.exports = {…}` line at the bottom of every `src/classes/*.class.js` throws a silent `ReferenceError` in WKWebView** (no Node = no `module`). The class declarations above it already register on the global scope, so it's harmless — leftover from the Electron era. Ignore these in devtools. (`ui.html` shims `window.module = { exports: null }` before `file-icons-match.js` for the same reason.)
- **AppKit interop (`objc 0.2` / `cocoa 0.26` / `core-graphics`) deliberately reuses the stack Tauri already pulls transitively** (via tao/wry) so no extra crates enter the binary. In `native_mount.rs`/`native_panels.rs`: every `*mut Object` is stashed as `usize` (Send+Sync) and only dereferenced inside a `dispatch::Queue::main().exec_async` block; web→AppKit rects need the `content_h - (y + height)` y-flip; layers must be `retain`ed since they're handed out as raw pointers.
- **sysinfo is pinned at `0.32`; its API drifts between point releases.** If you bump it, re-check `sysinfo_service.rs`: `Components`/`Networks`/`Disks::refresh()` take no args; `Component::temperature() -> f32` (not `Option`); `System::physical_core_count(&self)` is an instance method; `NetworkData` has no `mtu()` in 0.32.
- **`generate_context!()` requires an RGBA `src-tauri/icons/icon.png`** even when only `.icns` is configured. To swap: `iconutil -c iconset media/icon.icns -o /tmp/icon.iconset && cp /tmp/icon.iconset/icon_512x512.png src-tauri/icons/icon.png`.
- **macOS-only.** `process.platform === "win32"` branches were removed; don't reintroduce them. Cross-platform support, if it returns, belongs in Rust commands, not in the WKWebView.
- **File-icons content stays content, not code:** `file-icons-generator.js`, the `file-icons/` submodules, `src/assets/icons/file-icons.json`, and `src/assets/misc/file-icons-match.js` are preserved as data; regenerate with `npm run update-file-icons`.
