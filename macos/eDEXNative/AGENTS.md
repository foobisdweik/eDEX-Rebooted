<!--
macos/eDEXNative/AGENTS.md — nearest-scope instructions for the native Swift app.
Read the repo-root AGENTS.md and Ultrareview.md first. These rules override the
root file for edits under macos/eDEXNative/.
-->

# AGENTS.md

## Current Direction

The native app is past Phase 8.2. Before Phase 8.3 input routing, follow the anti-churn cleanup in `Ultrareview.md`:

- consolidate the SwiftPM/package taxonomy;
- introduce `TerminalSessionProviding`;
- introduce `EdexAction` / action handling;
- split feature ownership out of `ShellState`;
- keep `ContentView` as a compositor.

## Swift Rules

- Do not add another one-feature SwiftPM target by default.
- Do not add feature rendering directly to `ContentView`; create or use a dedicated view.
- Do not add new feature ownership directly to `ShellState`; create or use a focused store.
- Views emit actions. They should not directly coordinate unrelated subsystems.
- FFI calls go through the core bridge/client layer and must stay off the MainActor.
- Pure formatting, decoding, and display logic stays unit-testable and FFI-free.

## Verification

- Use `bash scripts/native-phase precheck` for the compile floor.
- Use `bash scripts/native-phase verify --full` when module taxonomy, generated bindings, or cross-store architecture changes.
- Use `bash scripts/native-phase smoke` when window/bootstrap behavior changes.
