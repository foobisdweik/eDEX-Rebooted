<!--
Ultrareview.md — anti-churn architecture addendum for coding agents working in
this repo. Agents: read AGENTS.md/CLAUDE.md first, then this file, then
docs/plans/full-native-swift-rust-conversion-2026-05-30.md. The closest
AGENTS.md to an edited file wins.
-->

# Ultrareview.md

## Status

This document is now the binding anti-churn addendum for the native Swift/Rust migration. The Phase 0-11 plan remains the roadmap and completion log; this file tells agents how to keep reducing coordination points before Phase 8.3 and Phase 9.

The approved sequence is:

1. Inspect and consolidate documentation.
2. Consolidate only the SwiftPM/package taxonomy.
3. Immediately follow with architectural cleanup: terminal seam, action router, `ShellState` split, and `ContentView` compositor split.
4. Resume Phase 8.3 input routing after the cleanup.

Do not use this branch to implement Phase 8.3 behavior or Phase 9 terminal rendering.

## Premises

- Apple Silicon only.
- macOS Tahoe minimum.
- No Intel, Windows, Linux, or iOS support.
- Single application, not a reusable framework.
- Rust core and UniFFI bridge already exist and are validated.

For this project shape, the native app should trade tiny per-feature modules for fewer, clearer coordination points.

## 1. Consolidate SwiftPM Targets

This is worthwhile as a dedicated mechanical pass, not as a behavior change.

Current shape:

```text
ClockSupport
SysinfoSupport
HardwareSupport
KeyboardSupport
KeyboardViewSupport
CpuinfoSupport
RamwatcherSupport
ToplistSupport
FilesystemSupport
FuzzyFinderSupport
TextEditorSupport
AudioSupport
ModalSupport
...
```

Every new subsystem used to touch `Package.swift` in multiple places. The consolidation pass groups support code into:

```text
EdexCoreBridge
EdexDomainSupport
EdexRenderingSupport
eDEXNative
```

Target layout:

```text
Sources/
├── EdexCoreBridge/
├── EdexDomainSupport/
│   ├── Clock/
│   ├── Sysinfo/
│   ├── Hardware/
│   ├── Cpu/
│   ├── Ram/
│   ├── Toplist/
│   ├── Filesystem/
│   ├── Keyboard/
│   ├── Settings/
│   ├── Audio/
│   └── Modal/
├── EdexRenderingSupport/
│   ├── Borders/
│   ├── Layout/
│   ├── Theme/
│   └── Terminal/
└── eDEXNative/
```

Keep future package work behavior-preserving. Move files, fix imports, update tests, and run the native gate before changing routing behavior.

## 2. Split `ShellState`

`ShellState` currently owns telemetry, filesystem, fuzzy finder, text editor, settings, shortcuts, keyboard, boot sequence, audio coordination, modal coordination, and FFI access. That was acceptable while porting panels; it is too much surface area for input routing and terminal work.

The cleanup should move toward:

```swift
@Observable
final class ShellState {
    let app: AppStore
    let telemetry: TelemetryStore
    let filesystem: FilesystemStore
    let settings: SettingsStore
    let keyboard: KeyboardStore
    let modal: ModalStore
    let terminal: TerminalStore
}
```

Phase 8.3 and Phase 9 should mostly touch terminal/input stores, not a giant root state object.

## 3. Create The Terminal Seam

The anti-churn branch introduced this before Phase 8.3:

```swift
protocol TerminalSessionProviding {
    var activeCwd: String { get }
    var activeTab: Int { get }

    func sendInput(_ text: String)
    func switchTab(_ index: Int)
}
```

Back it with a native stub today, then replace the implementation during Phase 9. Filesystem, fuzzy finder, shortcuts, keyboard, and future terminal rendering should all target the same API.

## 4. Introduce An Action Router

Do not let this shape grow:

```text
Keyboard -> ShellState -> Modal -> Audio -> Terminal -> Shortcuts
```

Views should emit actions:

```swift
enum EdexAction {
    case keyboardInput(String)
    case openSettings
    case openFuzzyFinder
    case switchTerminal(Int)
    case closeModal
}

protocol EdexActionHandler {
    func handle(_ action: EdexAction)
}
```

Stores consume actions. Views do not directly coordinate unrelated subsystems.

## 5. Make `ContentView` A Compositor

`ContentView` should place surfaces. It should not implement surfaces.

Long-term shape:

```text
EdexTelemetryColumn
EdexTerminalShell
EdexFilesystemPanel
EdexKeyboardPanel
EdexStatusRibbon
EdexModalLayer
EdexBootOverlay
```

Do not add new feature rendering directly to `ContentView`. If a view body becomes feature logic, split it into a dedicated view.

## 6. Keep Rust Stable

The Rust side is already in good shape:

- `edex-core`
- `edex-ffi`
- PTY observer abstraction
- UniFFI bridge
- Tauri adapters

Avoid more Rust crate decomposition unless a concrete problem appears. Extra crates would likely increase Cargo complexity, FFI complexity, build times, and cross-crate refactor cost without improving this single-platform app.

## 7. Tooling And Guardrails

Useful follow-ups after the current branch:

- Add `scripts/native-phase scaffold <phase> <slug>` only if repeated feature setup remains error-prone after SwiftPM consolidation.
- Keep nested `AGENTS.md` files in native/Rust subtrees so local instructions travel with the code.
- Keep `memory.md` uncommitted; it is a local handoff scratch file.

## Non-Goals

- Do not change legacy Tauri behavior except to keep the transition build working.
- Do not add Phase 8.3 routing behavior during the package-only consolidation pass.
- Do not start Phase 9 terminal rendering in the anti-churn branch.
- Do not split Rust crates as part of this cleanup.
