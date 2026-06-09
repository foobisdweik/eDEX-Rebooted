# GEMINI.md

> Gemini CLI project context for eDEX-UI. This file is auto-loaded as hierarchical
> instructional memory (project root). Inspect what's loaded with `/memory show`;
> after editing run `/memory refresh`. Modular docs are pulled in via `@` imports
> at the bottom — Gemini resolves them relative to this file.

## Project

eDEX-UI **v3.0.0**, `aarch64-apple-darwin` (Apple-Silicon macOS) **only**. Two stacks: the **legacy Tauri 2 + Rust / WKWebView app** (`src-tauri/` + `src/`, frozen at master/PR #12) and the **active SwiftUI + Rust native app** (`macos/eDEXNative/` + `crates/edex-core` + `crates/edex-ffi`) that replaces it along the Phase 0-11 plan. All new work lands in the native app on `post-web-runtime`.

## Workflow & commands (debloated — `scripts/native-phase` is the source of truth)

Verification is front-light, back-heavy: a fast compile floor before the PR; the real gate runs as PR checks afterward.

```bash
# 1. Branch off latest origin/post-web-runtime + print first-read files.
scripts/native-phase start <phase> <slug>

# 2. Write code (TDD): keep pure domain/display logic tested and FFI-free.
#    Do not add another one-feature SwiftPM target by default; follow Ultrareview.md.

# 3. The ONLY ship command — runs the compile floor itself, then commits/pushes/opens the PR.
scripts/native-phase pr "feat(native): ..." "feat(native): ..." "<summary>"
```

- `native-phase precheck` — scope-aware compile floor (only required pre-PR check; runs inside `pr`).
- `native-phase verify [--full]` — CI-safe full gate; **Native CI runs `verify --full`**, so local-full == CI. Optional locally — don't run the full gate by hand before a PR.
- `native-phase smoke` — local-only `--smoke-window` (not in CI).

Post-PR (~5 min): address **gemini-code-assist** review + **Native CI** (review/validate/respond/resolve). **Ignore Cursor BugBot.** A human merges. The Swift toolchain is `~/.swiftly/bin/swift`; regenerate UniFFI bindings + `cargo fmt` after any `crates/edex-ffi` change.

Past Phase 8.3 (keyboard input routing). Treat `Ultrareview.md` as binding direction through Phase 9: use the consolidated SwiftPM taxonomy, route through the terminal/action seam, continue splitting `ShellState`, and keep `ContentView` as a compositor.

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
- **Active workstream: the full SwiftUI + Rust native app under `macos/eDEXNative/`** (SwiftPM, linking `crates/edex-core` via the `crates/edex-ffi` UniFFI layer), replacing the WKWebView frontend. The earlier Approach-A per-panel `NSView` slots are a frozen/superseded interim bridge. Authoritative plan imported below; anti-churn architecture addendum is `Ultrareview.md`.

## Security

No listening socket — terminal I/O is in-process IPC. Do not reintroduce a network/WebSocket control channel (the original RCE class this fork removed).

## Imported context (migration docs)

Point Gemini at `Ultrareview.md` and `docs/plans/anti-churn-strategem-2026-06-09.md` for the anti-churn cleanup, then the authoritative plan for the roadmap + completion log. This `@`-import inlines the live plan into context:

@./docs/plans/full-native-swift-rust-conversion-2026-05-30.md

The FFI-throughput decision that feeds Phase 9 is `docs/plans/ffi-throughput-decision-2026-05-30.md`; import it with `@./docs/plans/ffi-throughput-decision-2026-05-30.md` when working the terminal path. The plan import is large; comment it out to save context window when only orientation is needed.
