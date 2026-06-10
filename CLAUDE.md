# CLAUDE.md

Guidance for Claude Code (and any agent) working in this repo. **Read this, then `Ultrareview.md`, then the authoritative plan: `docs/plans/full-native-swift-rust-conversion-2026-05-30.md`.**

## Repository status

eDEX-UI **v3.0.0**, `aarch64-apple-darwin` (Apple-Silicon macOS) **only**.

The repo now holds the active native app plus shared data assets:

1. **The active native app** (`macos/eDEXNative/` SwiftPM + `crates/edex-core` + `crates/edex-ffi`) — a standalone SwiftUI app linking the Rust core via UniFFI. **All new work lands here**, on the `post-web-runtime` integration branch.
2. **Bundled data assets** (`assets/`) — themes, keyboard layouts, fonts, audio cues, icons (incl. the frozen file-icons JSON pair), and boot/log data shared by Swift and Rust.

The legacy Tauri 2 / WKWebView frontend (`src-tauri/` + `src/`) and earlier Approach-A per-panel `NSView` slots were retired in Phase 9.7; the remaining JS/Node footprint (file-icons generator/matcher, `package.json`/lockfiles/`tsconfig.json`, the `file-icons/*` submodules) was retired in Phase 11.2. **The repo contains zero JS/TS/CSS** — do not reintroduce a WebView runtime path or a Node toolchain. File icons are frozen data (`assets/icons/file-icons.json` + `assets/misc/file-icons-match.json`) consumed by `FileIconSupport` (domain) and `FileIconProvider` (app target).

Done & merged on `post-web-runtime`: Phase 5 telemetry panels (clock, sysinfo, hardware, cpu, ram, toplist), Phase 6 (audio, modal manager, settings editor, shortcuts, boot screen), Phase 7 (filesystem, fuzzy finder, text editor), Phase 8.1 (keyboard layout loader), 8.2 (keyboard view), anti-churn cleanup (SwiftPM taxonomy, terminal/action seams, `KeyboardStore`, `EdexKeyboardPanel`), 8.3 (on-screen keyboard input routing), Phase 9 SwiftTerm integration through 9.6, Phase 9.7 (terminal burn-in + WKWebView/Tauri retirement, PR #42), and the telemetry perf pass (PR #43). The plan's original "emulate in Rust" approach (slices 9.1–9.2) is carved out as a separate future project; nothing is thrown away because the `PtyOutputSink` FFI seam is unchanged. Remaining roadmap: Phase 10 (media viewer + PDF). The per-phase completion log lives in the authoritative plan.

## The per-phase workflow (debloated — follow it exactly)

Verification is **front-light, back-heavy**: a fast compile check before the PR, with the real gate running *as PR checks* afterward. `scripts/native-phase` is the single source of truth.

1. **`scripts/native-phase start <phase> <slug>`** — fast-forwards `post-web-runtime`, cuts `codex/native-<slug>`, prints first-read files.
2. **Write code, TDD.** Pure domain/display logic still gets tests first, but **do not create another one-feature SwiftPM target by default**. The old per-panel target recipe is now migration history; new cross-cutting work should use the consolidated taxonomy (`EdexDomainSupport`, `EdexRenderingSupport`, or the app target). New backend data → typed `Ffi…` record + `EdexCore` method in `crates/edex-ffi`, then regenerate bindings (below).
3. **`scripts/native-phase pr "<commit>" "<title>" "<summary>"`** — this is the *only* command you run to ship. It runs the **compile floor** (`precheck`) itself, then stages (excluding `memory.md`), commits, pushes, and opens the PR against `post-web-runtime`. Do **not** run the full local gate by hand first — that's CI's job now.
4. **Work the post-PR loop (~5 min after submit):** address **gemini-code-assist**, **Cursor BugBot**, and the **Native CI** status on merit — review / validate / respond / resolve (push back with technical reasoning when a suggestion is wrong; don't perform agreement).
5. **A human merges** and raises any CI issue with you. There is no branch protection.

### The verification commands

- **`native-phase precheck`** — scope-aware **compile floor**, the only required pre-PR check. `swift build --build-tests` if `macos/eDEXNative/` changed; `cargo check --tests` if `crates/` changed; no-op for docs-only. Seconds. (Runs automatically inside `pr`.)
- **`native-phase verify [--full]`** — the **CI-safe full gate**: `cargo test` / `cargo fmt --check` / `cargo clippy -- -D warnings` + release-dylib build + `swift build --build-tests` / `swift test`. Scope-aware locally; `--full` (or `NATIVE_PHASE_FULL=1`) forces everything. **Native CI runs `bash scripts/native-phase verify --full`**, so the local full gate and CI cannot drift. Run this locally only when you want extra confidence — it is not required before a PR.
- **`native-phase smoke`** — the local-only `swift run eDEXNative --smoke-window`. Not in CI (needs a window session). Run ad-hoc when you touch FFI/bootstrap.

### CI

- `.github/workflows/native-ci.yml` is authoritative for the native tree (runs `verify --full` on PRs to `post-web-runtime`/`master`).

### Regenerate UniFFI bindings (after any `crates/edex-ffi` signature change)

```bash
cd crates/edex-ffi && cargo build --release && \
  cargo run --bin uniffi-bindgen -- generate --library target/release/libedex_ffi.dylib \
  --language swift --out-dir ../../macos/eDEXNative/Generated
```

## Architecture

**Native app (`macos/eDEXNative/`, SwiftPM).** `ShellState` (`@Observable @MainActor`) is still the root app state, `ContentView` composes the shell + panels, and `EdexCoreClient` wraps the UniFFI `EdexCore`. Internal boundaries are in place: `TerminalSessionProviding` + `StubTerminalStore` (Phase 9 replaces the stub), `EdexActionHandler`, `KeyboardStore`, grouped `EdexDomainSupport` / `EdexRenderingSupport` targets, `EdexKeyboardPanel`, and Phase 8.3 input routing (`KeyboardCommandResolver`, diacritics, detached-field routing). Do not add feature logic to `ContentView`, do not add new feature ownership directly to `ShellState`, and route input/commands through the terminal seam + action router. The Swift toolchain is at `~/.swiftly/bin/swift` (Swift 6.x).

**Rust core.** `crates/edex-core` is Tauri-free (sysinfo, PTY observer, settings, fs). `crates/edex-ffi` is the UniFFI layer (typed `Ffi…` records + `EdexCore` methods); committed Swift bindings live in `macos/eDEXNative/Generated/`. The native app links `-ledex_ffi` from `crates/edex-ffi/target/release`. `edex-core` embeds shared bundled data from `assets/`.

## Conversion docs (authoritative)

- `Ultrareview.md` — binding anti-churn architecture addendum (taxonomy, store split, compositor pattern); still applies through Phase 9.
- `docs/plans/anti-churn-strategem-2026-06-09.md` — staged branch plan for docs, SwiftPM taxonomy, architecture cleanup, and PR.
- `docs/plans/full-native-swift-rust-conversion-2026-05-30.md` — Phase 0–11 roadmap, gates, and completion log. Historical per-panel recipes remain there for context, not as the default architecture for new Swift work.
- `docs/plans/ffi-throughput-decision-2026-05-30.md` — FFI-throughput decision feeding Phase 9.
- `assets/` is the source of truth for bundled themes, keyboard layouts, fonts, audio, icons, and boot/log data.

## Settings storage

`~/Library/Application Support/eDEX-UI/{settings.json,shortcuts.json,lastWindowState.json,themes/,keyboards/,fonts/}`. `settings::ensure_userdata` mirrors bundled assets there on setup (built-ins overwrite, custom files survive). `settings.json` is free-form JSON — new experimental flags need no schema change.

## Non-obvious gotchas

- **Offload FFI off the MainActor.** `ShellState` is `@MainActor`; every `refresh…()` does `await Task.detached(priority: .background){ client.… }.value` then assigns.
- **Guard every `Double → Int` cast** against non-finite/out-of-range (the reviewer and reality crash on it) — see `RamwatcherSupport.safeInt`.
- **Live graphs:** SwiftUI `Canvas` + `TimelineView(.periodic(by: 1/30))` — a bounded 30 Hz scroll cadence (was `.animation`, which redrew at the display rate up to 120 Hz; see the telemetry-perf pass). Guard `Canvas` size finite+positive.
- **Telemetry refresh discipline:** the CPU panel poll (`cpu_snapshot`) is CPU-only and must not rebuild the process table; `SysinfoService::toplist_snapshot` is the single process-table producer (TTL-deduped). CPU temperature is read at most once per `TEMP_SNAPSHOT_TTL` (the `Components`/SMC read is ~110 ms and empty on Apple Silicon). Keep `SysinfoService::new()` lazy — no `refresh_all()` at construction.
- **Regenerate bindings** after any `crates/edex-ffi` signature change (command above); run `cargo fmt` after editing Rust.
- **SourceKit "No such module 'X'" diagnostics in-editor are noise** — the SwiftPM CLI build is the source of truth.
- **macOS-only.** Don't reintroduce `process.platform === "win32"` branches; cross-platform logic, if it returns, belongs in Rust.
- **`sysinfo` is pinned at `0.32`** (API drifts) — re-check `crates/edex-core/src/sysinfo.rs` if bumped. Note `mem_stats_from_system` keeps the `available >= free` invariant by clamping against the stored `free_strict`.
- **No listening socket** — terminal I/O is in-process. Do not reintroduce a network/WebSocket control channel (the original RCE class this fork removed).
- **Anti-churn guardrails:** terminal-facing code should target `TerminalSessionProviding`; views should emit `EdexAction` rather than directly coordinating subsystems; `ContentView` should place surfaces, not implement them.
