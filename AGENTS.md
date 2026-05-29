<!--
AGENTS.md — instructions for coding agents working in this repo (agents.md open
format; plain Markdown, no required fields). Humans should read README.md.
Agents: read this file, then the "Project knowledge" links before changing code.
The closest AGENTS.md to an edited file wins if nested ones are added later.
-->

# AGENTS.md

## Project overview

eDEX-UI **v3.0.0** — a Tauri 2 + Rust native port of the historical Electron fork. **Target: `aarch64-apple-darwin` (Apple-Silicon macOS) only.** No Electron, no Node runtime, no `node_modules/` shipped. Terminal I/O and system info run through Rust over in-process Tauri IPC; there is no listening socket. The frontend is a WKWebView payload of plain-JS classes + CSS (no bundler).

## Setup & build

- Toolchain: a **current stable** Rust toolchain (Cargo ≤1.81 fails to parse dependency metadata). `tauri-cli` v2 lives at `~/.cargo/bin/cargo-tauri`; install with `cargo install tauri-cli --version "^2.0" --locked`.
- Run from source: `cargo +stable tauri dev`
- Release build: `cargo +stable tauri build --target aarch64-apple-darwin` → `src-tauri/target/aarch64-apple-darwin/release/bundle/{macos,dmg}/`
- The dev watcher only watches `src-tauri/`; reload the WKWebView with **Cmd+R** to pick up `src/` edits. Restart on `tauri.conf.json` / `capabilities/` changes.

## Testing instructions (run before claiming work is done)

There is no broad test framework — coverage is targeted. Run the relevant checks:

```bash
# JS (repo root)
node --check <edited-frontend-file>.js
node --test src/bridge/bridge.test.js src/bridge/native_mount.test.js src/classes/terminalTabs.class.test.js

# Rust (from src-tauri/)
cargo test
cargo test --test sysinfo_contract        # Rust→JS JSON wire-shape contract
cargo fmt --check
cargo clippy -- -D warnings
```

Anything not covered by a test is smoke-tested by running `cargo tauri dev` and exercising the feature (terminal I/O, multi-tab spawn `Ctrl+X` then 1-5, theme swap `Ctrl+Shift+S`, the sysinfo/cpuinfo/ramwatcher/toplist panels).

## Code style & conventions

- **macOS-only.** Do not reintroduce `process.platform === "win32"` branches; cross-platform logic, if it returns, belongs in Rust commands.
- Frontend libraries are **vendored** under `src/assets/vendor/` (UMD). Do not run `npm install` for the frontend; `src/package.json` is version-pinning documentation only.
- The `module.exports = {…}` line at the bottom of every `src/classes/*.class.js` throws a harmless `ReferenceError` in WKWebView (no Node). Leave it — the class already registered on the global scope.
- **Capabilities:** new APIs touching core plugins (window/webview/shell/process/global-shortcut) need a permission in `src-tauri/capabilities/default.json`, or Tauri rejects them at runtime. Custom `#[tauri::command]`s (the `si_*`, `fs_*`, `native_*` families) need **no** capability entry.
- `sysinfo` is pinned at `0.32`; its API drifts — re-check `sysinfo_service.rs` if you bump it.
- Match the style, naming, and comment density of surrounding code.

## Architecture pointers

- **IPC boundary is Tauri `invoke()`** (in-process). `window.si` in `renderer.js` is a `Proxy` mapping camelCase → snake_case `si_*` commands, so visual classes don't know they talk to Rust.
- Backend (`src-tauri/src/`): `lib.rs` is the wiring hub (`invoke_handler!` + `.manage()` state + `.setup()`); `sysinfo_service.rs` (cached typed queries) and `sysinfo_cmds.rs` (thin `si_*` wrappers) are **two layers — read together**; `pty.rs` (portable-pty); `native_mount.rs` / `native_panels.rs` (AppKit interop — every `*mut Object` is stashed as `usize` and only touched inside `dispatch::Queue::main`; web→AppKit rects need a y-flip).
- **Active workstream: native-panel conversion (Approach A — per-panel NSView slots).** See Project knowledge below.

## Project knowledge (where to look)

- `docs/superpowers/specs/2026-05-29-native-panel-conversion-design.md` — **design spec, read first** (Approach A, the column-granular blocker, scope, risks).
- `docs/superpowers/plans/2026-05-29-native-panel-slots-phase0-1.md` — task-by-task implementation plan to **execute**.
- `docs/native-migration/*.spec.md` — per-panel research (clock, sysinfo, hardwareInspector, cpuinfo, ramwatcher, toplist).
- `CLAUDE.md` — fuller architecture map and gotchas.

## Commit & PR conventions

- Substantial / multi-file changes go on an **isolated branch + PR after full validation**, not direct to `master`.
- Use Conventional-Commit-style messages (`feat(native): …`, `fix(pty): …`).

## Security

- The app has **no listening socket** — terminal I/O is in-process IPC. Do not reintroduce a network/WebSocket control channel (that was the original RCE class this fork removed).
