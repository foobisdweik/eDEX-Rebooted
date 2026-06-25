# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

eDEX-UI **v3.0.0**, a standalone SwiftUI macOS app for **`aarch64-apple-darwin` (Apple-Silicon) only**, linking a Tauri-free Rust core through UniFFI. There is **zero JS/TS/CSS** in the tree — the legacy Tauri 2 / WKWebView frontend and the Node toolchain were fully retired. Do not reintroduce a WebView runtime, a Node toolchain, or any cross-platform / `win32` branches (cross-platform logic, if it ever returns, belongs in Rust).

Two source trees plus shared data:
- `macos/eDEXNative/` — SwiftPM app (Swift 6.4 toolchain at `~/.swiftly/bin/swift`, `.macOS(.v27)` floor).
- `crates/edex-core` (sysinfo, PTY observer, settings, fs — Tauri-free) + `crates/edex-ffi` (the UniFFI layer; committed Swift bindings in `macos/eDEXNative/Generated/`).
- `assets/` — source of truth for bundled themes, keyboard layouts, fonts, audio cues, icons (incl. frozen file-icons JSON), boot/log data. `edex-core` embeds these.

## Current goal: the HDR/EDR GPU-rendering arc

Active work follows **`docs/plans/Ultraplan.md`** — a Spike 0→D arc to (1) build a user-configurable XDR/HDR/EDR/SDR color-and-brightness platform, then (2) move the terminal aesthetic (and only measured wins beyond it) onto a GPU render path. **Spike 0 is done and merged:** the toolchain floor is raised to macOS-27 / Metal 4.1, and the precompiled-`.metallib` delivery path is established (no runtime shader compilation). Read `Ultraplan.md` for the spike definitions, the SDK symbol audit ("verify-before-use" — never invent macOS-27 EDR/Metal symbol names), and the per-spike acceptance bars.

**The one hard constraint for every new Metal surface (non-negotiable):** on-demand presentation. Draw only on content change (or the existing 10 Hz cadence), stop the timer / set `isPaused` when idle, skip commits while the window is occluded (`window.occlusionState`), and honor `SettingsSummary.reducedMotion`. **No free-running `MTKView`/`CADisplayLink` presenting every vsync.** Mirror `CpuGraphNSView` (`startPan`/`panTick`) in `Sources/Views/TelemetryPanels.swift` exactly — it is the canonical cadence template (read-only; do not modify or regress it).

## Build / test / run

`scripts/native-phase` is the single source of truth. Run the fast compile floor (`precheck`) while iterating and the full gate (`verify --full`) locally before shipping — there is no native CI to fall back on (GitHub runners lack Xcode 27), so local `verify --full` is the real gate.

- `scripts/native-phase start <phase> <slug>` — fast-forwards the base (default `master`, override `NATIVE_PHASE_BASE`), cuts `codex/native-<slug>`, prints first-read files.
- `scripts/native-phase precheck` — scope-aware **compile floor** (the only required pre-PR check; auto-run by `pr`). `swift build --build-tests` if Swift changed, `cargo check --tests` if `crates/` changed, no-op for docs.
- `scripts/native-phase verify [--full]` — the **authoritative full gate**: `cargo test`/`fmt --check`/`clippy -D warnings` + release-dylib build + `swift build --build-tests`/`swift test`. There is **no GitHub CI for the native tree** — GitHub-hosted runners lack Xcode 27, so the macOS-27/Metal-4.1 gate can only run on an Apple-Silicon macOS-27 machine. **Run `verify --full` locally before shipping; it is the only thing that gates native changes.** (GitHub still runs CodeQL via `.github/workflows/codeql-analysis.yml`.)
- `scripts/native-phase smoke` — local-only `swift run eDEXNative --smoke-window` (needs a window session; not in CI). The app loads the bundled `default.metallib`, prints FFI/window/metallib status, and self-terminates. Run after touching FFI/bootstrap/Metal.
- `scripts/native-phase pr "<commit>" "<title>" "<summary>"` — the **only** ship command: runs `precheck`, stages (excluding `memory.md`), commits, pushes, opens the PR. Do not run the full gate by hand first.

Single test: `swift test --filter <TestCaseOrMethod>` (in `macos/eDEXNative`); `cargo test <name>` (in the relevant crate).

**Linker note (Xcode-27-beta):** the in-toolchain `ld` rejects the Rust dylib's `__LINKEDIT` string pool at link time, so `native-phase` links Swift products with Homebrew `lld` (`brew install lld`; discovered at `/opt/homebrew/bin/ld64.lld`). `setup_swift_linker` handles this; set `EDEX_NO_LLD=1` to drop it once Apple ships a fixed `ld`.

### After any `crates/edex-ffi` signature change — regenerate bindings, then `cargo fmt`

```bash
cd crates/edex-ffi && cargo build --release && \
  cargo run --bin uniffi-bindgen -- generate --library target/release/libedex_ffi.dylib \
  --language swift --out-dir ../../macos/eDEXNative/Generated
```

### After editing any `.metal` source — recompile the bundled metallib, commit it alongside

```bash
bash macos/eDEXNative/Scripts/build-shaders.sh   # xcrun metal -std=metal4.1 -> default.metallib
```

`Sources/Shaders/default.metal` is **excluded** from the SwiftPM build; the offline-built `Sources/Shaders/default.metallib` is bundled as a package resource and loaded via `makeDefaultLibrary(bundle:)`. Never use `makeLibrary(source:)` at runtime.

## Architecture

`ShellState` (`@Observable @MainActor`, `Stores/ShellState.swift`) is the root app state; `ContentView` (`Sources/App`) composes the shell + panels; `EdexCoreClient` (`Sources/Services`) wraps the UniFFI `EdexCore`. **Keep these boundaries**: do not add feature logic to `ContentView` (it places surfaces, it does not implement them), do not add new feature ownership directly onto `ShellState`, route input/commands through the terminal seam (`TerminalSessionProviding` / `TerminalStore`) and the action router (`EdexActionHandler` emitting `EdexAction`), and route keyboard through `KeyboardStore` / `KeyboardCommandResolver`.

SwiftPM targets (consolidated taxonomy — **do not add a new per-feature target**):
- **`EdexCoreBridge`** — the generated UniFFI Swift bindings; links `-ledex_ffi` from `crates/edex-ffi/target/release`.
- **`EdexDomainSupport`** — pure domain/display logic per feature (Clock, Cpu, Ram, Sysinfo, Hardware, Toplist, Audio, Modal, Settings, Shortcuts, Boot, Filesystem, FuzzyFinder, TextEditor, MediaViewer, Keyboard, Terminal, FileIcons, Actions). Unit-tested first.
- **`EdexRenderingSupport`** — pure rendering/layout logic: `Theme/` (incl. `TerminalAestheticMetrics` — the geometry source of truth a future GPU shader must mirror), `Borders/`, `Layout/`. **New brightness/profile/tonemap logic goes here** (Spike A).
- **`eDEXNative`** (app/executable) — `App`, `Services`, `Stores`, `Support`, `Views`; depends on the support targets + SwiftTerm. The Metal host + display-probe service (Spike B) live here / as a focused service surfaced through `ShellState`.
- **`eDEXNativeTests`** — depends on the two support targets (pure logic is what gets tested).

Rust: `edex-core/src/{sysinfo,pty,settings,fs}.rs` (logic) → `edex-ffi/src/lib.rs` (typed `Ffi…` records + `EdexCore` methods). New backend data → typed `Ffi…` record + `EdexCore` method, then regenerate bindings.

## Settings

`~/Library/Application Support/eDEX-UI/{settings.json,shortcuts.json,lastWindowState.json,themes/,keyboards/,fonts/}`. `settings::ensure_userdata` mirrors bundled assets there (built-ins overwrite, custom files survive). `settings.json` is **free-form JSON — new experimental/brightness/CRT flags need no schema change**; `default_settings()` in `crates/edex-core/src/settings.rs` is the canonical default list. Where the UI needs typed access, extend the Swift `SettingsFile` (`EdexCoreClient.swift`) and `SettingsSummary` (`ShellState.swift`) — `reducedMotion` is the precedent.

## Non-obvious gotchas

- **Offload FFI/`NSScreen` reads off the MainActor.** `ShellState` is `@MainActor`; every `refresh…()` does `await Task.detached(priority: .background){ client.… }.value` then assigns. AppKit reads (e.g. `backingScaleFactor`, the EDR triad) capture on MainActor → detach → assign on MainActor.
- **Guard every `Double → Int` cast** against non-finite/out-of-range — see `RamwatcherSupport.safeInt`. Tonemap/brightness math (Spike A) must do the same.
- **Live CPU graph is do-not-regress:** a `CAShapeLayer` path rebuilt once per sample + a 10 Hz timer-stepped `transform.translation.x` (`CpuGraphScrollGeometry` + `CpuGraphNSView`), skipped while occluded. Do **not** reintroduce a `TimelineView` redraw loop, animate a SwiftUI `.offset` over a clipped `Canvas`, or use a continuous render-server `CABasicAnimation` (each was measured pinning the main thread or WindowServer — the last at ~46% steady WindowServer CPU, fixed in PR #50).
- **Telemetry refresh discipline:** `cpu_snapshot` is CPU-only and must not rebuild the process table; `SysinfoService::toplist_snapshot` is the single (TTL-deduped) process-table producer. CPU temperature reads at most once per `TEMP_SNAPSHOT_TTL` (the SMC read is ~110 ms, empty on Apple Silicon). Keep `SysinfoService::new()` lazy — no `refresh_all()` at construction.
- **macOS-27 dyld + the Rust dylib:** dyld refuses to `dlopen` a Mach-O whose `LC_SYMTAB` string-pool offset is not 8-byte aligned. `crates/edex-ffi/Cargo.toml` sets `[profile.release] strip = "none"` to land it on the boundary, and `native-phase`'s `build_ffi_dylib` asserts `stroff % 8 == 0` and fails loudly if it ever drifts. Do not remove either.
- **Smoke build hitting a missing `metal` compiler / stale toolchain mount** is a stale SwiftPM build plan after a Metal-toolchain update (a SwiftTerm `.metal` compiles at build time). Fix: `swift package clean` in `macos/eDEXNative`.
- **`sysinfo` is pinned at `0.32`** (API drifts) — re-check `crates/edex-core/src/sysinfo.rs` if bumped; `mem_stats_from_system` keeps `available >= free` by clamping against stored `free_strict`.
- **No listening socket** — terminal/render I/O is in-process. Do not reintroduce a network/WebSocket control channel (the RCE class this fork removed).
- **SourceKit "No such module 'X'" in-editor diagnostics are noise** — the SwiftPM CLI build is the source of truth.

## Workflow norms

- Branch off `master` (the consolidated default/trunk; `main` was renamed to it). One spike = one `native-phase` branch/PR.
- Before a `pr`, run `scripts/native-phase verify --full` locally — it is the authoritative gate (no native CI exists; see above). After a `pr`, work the review loop (~5 min): address gemini-code-assist and Cursor BugBot on merit — validate and push back with technical reasoning when a suggestion is wrong. A human merges; there is no branch protection.
- `Ultrareview.md` (anti-churn architecture addendum: target taxonomy, store split, compositor pattern) still applies. The retired Phase 0–11 conversion plan and the deleted `docs/plans/{QoL-improvements,anti-churn-strategem-2026-06-09}.md` are canonical deletions — consult git history, do not restore them.
