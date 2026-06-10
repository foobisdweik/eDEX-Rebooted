<!--
AGENTS.md — instructions for coding agents (Codex, Claude, etc.) working in this
repo (agents.md open format). Humans should read README.md. Agents: read this,
then Ultrareview.md and docs/plans/full-native-swift-rust-conversion-2026-05-30.md
before changing code. CLAUDE.md is the fuller companion. The closest AGENTS.md
to an edited file wins.
-->

# AGENTS.md

## Project overview

eDEX-UI **v3.0.0**, `aarch64-apple-darwin` (Apple-Silicon macOS) **only**.

- **Active native app** (`macos/eDEXNative/` SwiftPM + `crates/edex-core` + `crates/edex-ffi`) — a SwiftUI app linking the Rust core via UniFFI. **All new work lands here**, on the `post-web-runtime` branch.
- **Bundled data assets** (`assets/`) — themes, keyboard layouts, fonts, audio cues, icons, and boot/log data shared by Swift and Rust.

The legacy Tauri 2 / WKWebView frontend (`src-tauri/` + `src/`) was retired in Phase 9.7. Do not reintroduce a WebView runtime path.

## The workflow (debloated — `scripts/native-phase` is the single source of truth)

Verification is front-light, back-heavy: a fast **compile floor** before the PR; the real gate runs as **PR checks** afterward.

1. `scripts/native-phase start <phase> <slug>` — branch off latest `origin/post-web-runtime`, print first-read files.
2. Write code, TDD. Keep pure domain/display logic testable and FFI-free. **Do not add another one-feature SwiftPM target by default**; use the consolidated native taxonomy (`EdexDomainSupport`, `EdexRenderingSupport`, or the app target) and keep routing/state/view responsibilities split. New backend data → typed `Ffi…` + `EdexCore` method in `crates/edex-ffi`, then regenerate bindings (see CLAUDE.md).
3. `scripts/native-phase pr "<commit>" "<title>" "<summary>"` — the **only** ship command. It runs the compile floor (`precheck`) itself, then stages (excluding `memory.md`), commits, pushes, opens the PR against `post-web-runtime`. **Do not run the full gate by hand first** — that is CI's job.
4. Work the post-PR loop (~5 min after submit): address **gemini-code-assist**, **Cursor BugBot**, and **Native CI** status on merit — review / validate / respond / resolve (push back with technical reasoning when wrong).
5. A human merges and raises CI issues with you. No branch protection.

### Commands (don't run a remembered checklist — use these)

- `native-phase precheck` — scope-aware compile floor (the only required pre-PR check; runs inside `pr`).
- `native-phase verify [--full]` — CI-safe full gate (build + swift test + cargo test/fmt/clippy), scope-aware. **Native CI runs `verify --full`**, so local-full == CI. Optional locally.
- `native-phase smoke` — local-only `--smoke-window` (not in CI); run ad-hoc when touching FFI/bootstrap.

CI: `.github/workflows/native-ci.yml` is authoritative for the native tree.

## Conventions

- **macOS-only.** No `process.platform === "win32"` branches; cross-platform logic belongs in Rust.
- Offload FFI off the MainActor; guard every `Double → Int` cast; live graphs use `Canvas` + `TimelineView(.periodic(by: 1/30))` (bounded cadence — not `.animation`). Regenerate UniFFI bindings + `cargo fmt` after any Rust change.
- SourceKit "No such module" diagnostics in-editor are noise — the SwiftPM CLI build is the source of truth.
- Conventional-Commit messages (`feat(native): …`, `fix(native): …`). Keep `memory.md` out of commits.
- Match surrounding code's style and naming.
- Do not add new feature logic to `ContentView` or new feature ownership directly to `ShellState`. The current cleanup direction is terminal seam → action router → split stores → compositor views.

## Project knowledge (where to look)

- `Ultrareview.md` — binding anti-churn architecture addendum (taxonomy, store split, compositor pattern); still applies through Phase 9.
- `docs/plans/anti-churn-strategem-2026-06-09.md` — staged branch plan for docs, SwiftPM taxonomy, architecture cleanup, and PR.
- `docs/plans/full-native-swift-rust-conversion-2026-05-30.md` — authoritative roadmap, gates, and completion log. Historical per-panel recipes remain there for context, not as the default shape for new Swift code.
- `docs/plans/ffi-throughput-decision-2026-05-30.md` — FFI-throughput decision feeding Phase 9.
- `macos/eDEXNative/` — the native app (pure `*Support` modules + SwiftUI views).
- `assets/` — shared bundled data mirrored into user data by `edex-core`.
- `CLAUDE.md` — fuller architecture map and gotchas.

## Security

No listening socket — terminal I/O is in-process IPC. Do not reintroduce a network/WebSocket control channel (the original RCE class this fork removed).
