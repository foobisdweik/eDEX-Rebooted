# Resume Notes

Project: `eDEX-UI-security-patched`
Branch: `anti-churning-strategem`
Base: `post-web-runtime`
Status date: 2026-06-09

## Current State

`post-web-runtime` is the rolling native-conversion integration branch. `master` remains frozen at PR #12. The native app is complete through Phase 8.2; Phase 8.3 input routing is intentionally paused for anti-churn cleanup.

This branch performs and now contains:

1. Documentation consolidation.
2. SwiftPM/package taxonomy consolidation.
3. Architecture cleanup before Phase 8.3:
   - terminal seam,
   - action router,
   - `ShellState` split,
   - `ContentView` compositor split.
4. PR against `post-web-runtime`.

## Completed In This Branch

- Reframed `Ultrareview.md` as the binding anti-churn architecture addendum.
- Added `docs/plans/anti-churn-strategem-2026-06-09.md`.
- Updated root agent docs (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`) so future agents stop adding one SwiftPM target per feature by default.
- Updated `README.md` and `macos/eDEXNative/README.md` to distinguish the frozen Tauri release path from the active native app.
- Added scoped guardrails:
  - `macos/eDEXNative/AGENTS.md`
  - `crates/edex-core/AGENTS.md`
  - `crates/edex-ffi/AGENTS.md`
- Updated `macos/eDEXNative/Package.swift` to exclude `AGENTS.md` from the executable target so SwiftPM does not emit an unhandled-file warning.
- Removed stale handoff text from the main conversion plan and marked historical docs as historical.

Docs-stage verification:

```bash
git diff --check
bash scripts/native-phase precheck
```

## Completed Taxonomy Work

Stage 2 is complete as a behavior-preserving module consolidation.

Current target shape:

- `EdexCoreBridge`
- `EdexDomainSupport`
- `EdexRenderingSupport`
- `eDEXNative`

Existing support modules were moved into grouped source folders under `Sources/EdexDomainSupport/` and `Sources/EdexRenderingSupport/`. Imports, tests, and `Package.swift` now use the grouped targets instead of one SwiftPM target per feature.

## Completed Architecture Work

Stage 3 is complete as an internal boundary cleanup ahead of Phase 8.3.

- Added `TerminalSessionProviding`, `StubTerminalStore`, `EdexAction`, `EdexActionHandler`, and `EdexActionRouter` in `EdexDomainSupport/Actions`.
- Added `KeyboardStore` as the first focused store split from `ShellState`.
- Made `ShellState` conform to `EdexActionHandler` and route terminal input, tab switching, settings, fuzzy finder, and modal close actions through the action boundary.
- Split native keyboard rendering into `EdexKeyboardPanel`, leaving `ContentView` as more of a compositor.
- Added `NativeActionRoutingTests`.
- Addressed Gemini review feedback after PR creation:
  - replaced new `Task.sleep(nanoseconds:)` usage with `Task.sleep(for:)`;
  - marked `EdexKeyboardPanel` callbacks `@MainActor`.

## Final Verification

Completed before PR:

```bash
git diff --check                         # pass
bash scripts/native-phase verify --full  # pass: Rust 17/17, Swift 224/224
bash scripts/native-phase smoke          # pass: window chrome + FFI bootstrap OK
```

PR #35 is open against `post-web-runtime`. `memory.md` remains local/uncommitted.

Keep this `memory.md` local/uncommitted unless explicitly told otherwise.
