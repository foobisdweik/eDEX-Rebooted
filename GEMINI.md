# GEMINI.md

> Gemini CLI project context for eDEX-UI. This file is auto-loaded as hierarchical
> instructional memory (project root). Inspect what's loaded with `/memory show`;
> after editing run `/memory refresh`. Modular docs are pulled in via `@` imports
> at the bottom — Gemini resolves them relative to this file.

## Project

eDEX-UI **v3.0.0** — a Tauri 2 + Rust native port of the historical Electron fork. **Target: `aarch64-apple-darwin` (Apple-Silicon macOS) only.** No Electron, no Node runtime, no `node_modules/` shipped. Terminal I/O and system info flow through Rust over in-process Tauri IPC (no listening socket). The frontend is a WKWebView payload of plain-JS classes + CSS, with no bundler.

## Commands

```bash
# Run from source (needs a CURRENT stable Rust toolchain; Cargo <=1.81 fails).
cargo +stable tauri dev

# Release .app + .dmg
cargo +stable tauri build --target aarch64-apple-darwin

# Tests (no broad framework — run what's relevant)
node --check <edited-frontend-file>.js
node --test src/bridge/bridge.test.js src/bridge/native_mount.test.js src/classes/terminalTabs.class.test.js
cd src-tauri && cargo test && cargo test --test sysinfo_contract && cargo fmt --check && cargo clippy -- -D warnings
```

`tauri-cli` v2 is at `~/.cargo/bin/cargo-tauri` (`cargo install tauri-cli --version "^2.0" --locked`). The dev watcher only watches `src-tauri/`; reload the WKWebView with **Cmd+R** for `src/` edits.

## Conventions

- **macOS-only** — do not reintroduce `process.platform === "win32"` branches; cross-platform logic belongs in Rust commands.
- Frontend libs are **vendored** under `src/assets/vendor/` (UMD); never `npm install` the frontend — `src/package.json` only records pinned versions.
- The trailing `module.exports = {…}` in each `src/classes/*.class.js` throws a harmless WKWebView `ReferenceError` — leave it.
- New core-plugin APIs (window/webview/shell/process/global-shortcut) need a permission in `src-tauri/capabilities/default.json`; **custom `#[tauri::command]`s do not**.
- `sysinfo` is pinned at `0.32` (API drifts) — re-check `sysinfo_service.rs` if bumped.
- Match the surrounding code's style and naming.

## Architecture

- **IPC boundary is Tauri `invoke()`** (in-process). `window.si` in `renderer.js` is a `Proxy` mapping camelCase → snake_case `si_*` commands; visual classes consume it unaware they're talking to Rust.
- Backend (`src-tauri/src/`): `lib.rs` wires everything (`invoke_handler!` + `.manage()` + `.setup()`); `sysinfo_service.rs` (cached typed queries) + `sysinfo_cmds.rs` (thin `si_*` wrappers) are two layers; `pty.rs` (portable-pty); `native_mount.rs` / `native_panels.rs` are AppKit interop — opaque pointers stashed as `usize`, dereferenced only inside `dispatch::Queue::main`, web→AppKit rects y-flipped.
- **Active workstream: native-panel conversion (Approach A — per-panel NSView slots),** default-off behind `experimentalNative*` flags. Full design + plan imported below.

## Security

No listening socket — terminal I/O is in-process IPC. Do not reintroduce a network/WebSocket control channel (the original RCE class this fork removed).

## Workflow

Substantial / multi-file changes go on an isolated branch + PR after full validation, not direct to `master`. Conventional-Commit messages (`feat(native): …`).

## Imported context (migration docs)

Point Gemini at **both** the design (orientation) and the plan (execution). These `@`-imports inline the live docs into context:

@./docs/superpowers/specs/2026-05-29-native-panel-conversion-design.md
@./docs/superpowers/plans/2026-05-29-native-panel-slots-phase0-1.md

Per-panel research lives in `docs/native-migration/*.spec.md` — import an individual file with `@./docs/native-migration/<panel>.spec.md` when working that panel. The plan import is large; comment it out to save context window when only orientation is needed.
