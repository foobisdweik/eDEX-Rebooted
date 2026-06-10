# GEMINI.md

> Gemini CLI project context for eDEX-UI. This file is auto-loaded as hierarchical
> instructional memory (project root). Inspect what's loaded with `/memory show`;
> after editing run `/memory refresh`. Modular docs are pulled in via `@` imports
> at the bottom — Gemini resolves them relative to this file.

## Project

eDEX-UI **v3.x**, `aarch64-apple-darwin` (Apple-Silicon macOS) **only**. One stack: the **SwiftUI + Rust native app** (`macos/eDEXNative/` + `crates/edex-core` + `crates/edex-ffi`, linked via UniFFI) plus shared bundled data in `assets/`. The legacy Tauri 2 / WKWebView frontend (`src-tauri/` + `src/`) and the JS/TS/CSS codebase were retired in Phase 9.7/11; `master` is frozen at the historical Tauri release. All work lands on `post-web-runtime`.

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

Post-PR (~5 min): address **gemini-code-assist**, **Cursor BugBot**, and **Native CI** on merit (review/validate/respond/resolve; push back with technical reasoning when wrong). A human merges. The Swift toolchain is `~/.swiftly/bin/swift`; regenerate UniFFI bindings + `cargo fmt` after any `crates/edex-ffi` change.

Past Phase 8.3 (keyboard input routing). Treat `Ultrareview.md` as binding direction through Phase 9: use the consolidated SwiftPM taxonomy, route through the terminal/action seam, continue splitting `ShellState`, and keep `ContentView` as a compositor.

## Conventions

- **macOS-only** — do not reintroduce `process.platform === "win32"` branches; cross-platform logic belongs in Rust.
- **No JS/TS/CSS, no Node toolchain.** The repo ships no JavaScript; do not add npm/bun/tsconfig back. File icons are frozen JSON data (`assets/icons/file-icons.json` + `assets/misc/file-icons-match.json`) rendered natively.
- `sysinfo` is pinned at `0.32` (API drifts) — re-check `crates/edex-core/src/sysinfo.rs` if bumped.
- Match the surrounding code's style and naming.

## Architecture

- **FFI boundary is UniFFI**: typed `Ffi…` records + `EdexCore` methods in `crates/edex-ffi`; committed Swift bindings in `macos/eDEXNative/Generated/`. `crates/edex-core` is the UI-free Rust core (sysinfo, PTY observer, settings, fs).
- Swift app: `ShellState` (`@Observable @MainActor`) is root state, `ContentView` is a compositor, feature logic lives in `EdexDomainSupport`/`EdexRenderingSupport` modules and stores (`TerminalSessionProviding`, `EdexActionHandler`, `KeyboardStore`). Terminal is SwiftTerm over the in-process PTY byte seam.
- Authoritative plan imported below; anti-churn architecture addendum is `Ultrareview.md`.

## Security

No listening socket — terminal I/O is in-process IPC. Do not reintroduce a network/WebSocket control channel (the original RCE class this fork removed).

## Imported context (migration docs)

Point Gemini at `Ultrareview.md` and `docs/plans/anti-churn-strategem-2026-06-09.md` for the anti-churn cleanup, then the authoritative plan for the roadmap + completion log. This `@`-import inlines the live plan into context:

@./docs/plans/full-native-swift-rust-conversion-2026-05-30.md

The FFI-throughput decision that feeds Phase 9 is `docs/plans/ffi-throughput-decision-2026-05-30.md`; import it with `@./docs/plans/ffi-throughput-decision-2026-05-30.md` when working the terminal path. The plan import is large; comment it out to save context window when only orientation is needed.
