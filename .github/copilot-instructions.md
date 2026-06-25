# Copilot Instructions for eDEX-Rebooted (eDEX-UI v3.0.0)

## Read this first (critical environment limitation)

This repository is a native SwiftUI macOS app + Rust core targeting **Apple Silicon macOS 27+ only**.  
A cloud agent on GitHub-hosted runners **cannot** build/validate the Swift side, because required local prerequisites are unavailable there:

- Xcode 27 / macOS-27 SDK / Metal 4.1 toolchain
- Swift 6.4 toolchain at `~/.swiftly/bin/swift`
- Homebrew `lld` linker (`ld64.lld`) used by project scripts

There is intentionally **no native CI workflow** for Swift validation.  
The authoritative local gate is:

- `scripts/native-phase verify --full` (run locally on Apple-Silicon macOS-27)

**Implication for cloud agents:**
- You can confidently run/validate **Rust-only** work.
- Treat Swift/Metal changes as **build-unverifiable in the cloud**; clearly disclose this in PRs.
- Do **not** reintroduce Node/Tauri/WKWebView/web runtime/cross-platform branches.

---

## What this repository is

eDEX-UI is a sci-fi/CRT-styled fullscreen terminal emulator for macOS.

Two-tree architecture:

- `macos/eDEXNative/` — SwiftPM native app (SwiftUI + AppKit + SwiftTerm), `// swift-tools-version: 6.4`, `.macOS(.v27)`
- `crates/edex-core` — Rust core services (`sysinfo`, `pty`, `settings`, `fs`)
- `crates/edex-ffi` — UniFFI bridge exposing `EdexCore`; committed Swift bindings in `macos/eDEXNative/Generated/`
- `assets/` — bundled themes, keyboards, fonts, audio, icons, boot/log data embedded by core

Primary languages are Swift (app) and Rust (core).  
Active stream: HDR/EDR GPU-rendering arc in `docs/plans/Ultraplan.md`.

---

## Repo map (high-signal)

Top-level:
- `CLAUDE.md`
- `Ultrareview.md`
- `crates/`
- `macos/`
- `assets/`
- `docs/`
- `scripts/`
- `.github/`

Swift app:
- `macos/eDEXNative/Package.swift` (platform/toolchain floor, targets, metallib resource/exclusions)
- `macos/eDEXNative/Sources/App/ContentView.swift`
- `macos/eDEXNative/Sources/Stores/ShellState.swift` (`@Observable @MainActor` root state)
- `macos/eDEXNative/Sources/Services/EdexCoreClient.swift` (UniFFI wrapper)
- `macos/eDEXNative/Sources/Views/TelemetryPanels.swift` (contains `CpuGraphNSView` cadence behavior)

Rust:
- `crates/edex-core/src/{sysinfo,pty,settings,fs}.rs`
- `crates/edex-ffi/src/lib.rs` (`EdexCore` UniFFI surface + `Ffi...` records)

Workflows:
- `.github/workflows/codeql-analysis.yml` (CodeQL Actions scan only; no Swift/Rust native build workflow)

---

## Build/validation: exact command policy

`scripts/native-phase` is the single source of truth.

### Commands and cloud/local availability

- `scripts/native-phase precheck`
  - Purpose: scope-aware compile floor (`cargo check --tests`, Swift build where needed)
  - **Cloud:** effectively **not runnable** for Swift paths (missing required local toolchain)
  - **Local (Apple-Silicon macOS-27):** yes

- `scripts/native-phase verify [--full]`
  - Purpose: authoritative full gate
  - Includes Rust (`cargo test`, `cargo fmt --check`, `cargo clippy -- -D warnings`) and Swift (`swift build --build-tests`, `swift test`) based on scope
  - **Cloud:** cannot replicate Swift validation
  - **Local:** yes (authoritative pre-merge check)

- `scripts/native-phase smoke`
  - Purpose: `swift run eDEXNative --smoke-window`
  - Needs window session
  - **Local-only**

- `scripts/native-phase pr ...`
  - Ship command: `precheck` → stage/commit/push/open PR
  - Use for local maintainer flow; cloud agents generally won’t execute it end-to-end

### Rust commands cloud agents can run confidently

From `crates/edex-ffi` / `crates/edex-core` as appropriate:
- `cargo build`
- `cargo test <name>` (or full `cargo test`)
- `cargo fmt --check`
- `cargo clippy -- -D warnings`

Always run `cargo fmt` after Rust edits.

### Required invariant: `strip = "none"` in `crates/edex-ffi/Cargo.toml`

Do **not** remove `[profile.release] strip = "none"` in `crates/edex-ffi/Cargo.toml`.  
Project scripts enforce Mach-O `LC_SYMTAB.stroff % 8 == 0` alignment; this is required for macOS-27 dyld compatibility of `libedex_ffi.dylib`.

---

## Mandatory regeneration/build rules

Use **always** semantics:

1) **After any `crates/edex-ffi` signature change, always regenerate Swift bindings and then format:**
```bash
cd crates/edex-ffi && cargo build --release && \
  cargo run --bin uniffi-bindgen -- generate --library target/release/libedex_ffi.dylib \
  --language swift --out-dir ../../macos/eDEXNative/Generated
cargo fmt
```

2) **After any `.metal` source edit, always rebuild and commit the bundled metallib:**
```bash
bash macos/eDEXNative/Scripts/build-shaders.sh
```

`default.metal` is excluded from SwiftPM compile; app uses bundled offline-built `default.metallib` via `makeDefaultLibrary(bundle:)`.  
Never switch to runtime `makeLibrary(source:)`.

---

## Linker/toolchain gotchas (important)

- `scripts/native-phase` uses Homebrew `ld64.lld` when available (`brew install lld`) because Xcode-27 toolchain linker can reject the Rust dylib `__LINKEDIT` string pool.
- `EDEX_NO_LLD=1` disables this workaround.
- In cloud environments lacking this toolchain, Swift link/build is expected to fail; do not treat this as signal of bad code quality.
- If Swift build reports missing `metal` compiler or stale toolchain-mount behavior after toolchain changes, mitigate with:
  - `swift package clean` in `macos/eDEXNative`

---

## Architecture guidance for edits

- Root app state: `ShellState` (`@Observable @MainActor`)
- UI composition: `ContentView` composes shell/panels
- Core client: `EdexCoreClient` wraps UniFFI `EdexCore`
- Input/command seams:
  - terminal seam via `TerminalSessionProviding` / `TerminalStore`
  - action routing via `EdexActionHandler` + `EdexAction`
  - keyboard routing via `KeyboardStore` / `KeyboardCommandResolver`

SwiftPM targets (do not add per-feature targets):
- `EdexCoreBridge`
- `EdexDomainSupport`
- `EdexRenderingSupport`
- `eDEXNative`
- `eDEXNativeTests`

Rust flow:
- `edex-core` logic → `edex-ffi` UniFFI API (`EdexCore` surface)

---

## Non-obvious behavioral constraints (do-not-regress)

- Offload FFI / expensive reads from MainActor pattern (`Task.detached { ... }` then assign on main actor).
- Guard `Double -> Int` casts (`RamwatcherSupport.safeInt` pattern).
- Preserve live CPU graph behavior (`CpuGraphNSView`) and on-demand/occlusion-gated cadence patterns.
- `sysinfo` pinned to `0.32`.
- No listening socket / network control channel.
- SourceKit “No such module …” editor diagnostics may be noise; SwiftPM CLI build is source of truth.
- Default/trunk branch is `master`.

---

## Practical PR behavior for cloud agents

When submitting cloud-authored PRs:

1) Run and report all Rust checks you can run.
2) If touching Swift/Metal, explicitly state:
   - Swift/native gate could not be executed in cloud due to missing Xcode-27/Swift-6.4/macOS-27/Metal-4.1 + `ld64.lld`.
   - Maintainer must run `scripts/native-phase verify --full` locally.
3) Do not add CI assumptions that GitHub-hosted runners can validate native Swift app builds here.
4) Prefer minimal, surgical edits; preserve target layout and existing seams.

---

## Trust policy for future agents

Treat this file as the default operating playbook for this repository.  
Only perform additional broad search/exploration when:
- the requested task touches areas not covered here, or
- an instruction here is demonstrably stale/incorrect in the current tree.
