# Anti-Churn Strategem Plan

## Goal

Prepare the native app for Phase 8.3 and Phase 9 by reducing Swift-side coordination churn without changing user-facing behavior during the taxonomy pass.

## Documentation Inspection

Inspected project-facing Markdown docs:

- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `README.md`
- `SECURITY.md`
- `Ultrareview.md`
- `macos/eDEXNative/README.md`
- `.github/ISSUE_TEMPLATE/issue_template.md`
- `docs/plans/ffi-throughput-decision-2026-05-30.md`
- `docs/plans/full-native-swift-rust-conversion-2026-05-30.md`
- `docs/reviews/full-native-conversion-plan-critique-2026-05-30.md`
- `docs/superpowers/plans/2026-06-08-phase-8-2-keyboard-view.md`

Excluded dependency/vendor/agent-pack Markdown under `node_modules/`, `.claude/skills*`, `.codex/skills*`, `.cursor/skills*`, and `.gemini/skills*`; those are not project truth sources.

## Consolidation Decisions

- `Ultrareview.md` is the binding anti-churn addendum.
- The Phase 0-11 plan remains the roadmap and completion log.
- Historical per-panel target creation is retained only as history.
- Current instructions should not tell agents to add one SwiftPM target per feature by default.
- Native app guardrails now live in `macos/eDEXNative/AGENTS.md`.
- Rust crate guardrails now live in `crates/edex-core/AGENTS.md` and `crates/edex-ffi/AGENTS.md`.

## Stage 1: Documentation Consolidation

Status: complete.

Changes:

- aligned root agent instructions around `Ultrareview.md`;
- updated the human README to distinguish frozen Tauri release path from the active native app;
- refreshed `macos/eDEXNative/README.md` from Phase 3 shell-spike language to current Phase 8.2 status;
- removed stale Phase 6.1 handoff content from the main plan;
- marked older critique and Phase 8.2 implementation docs as historical;
- added nearest-scope AGENTS files.
- excluded `macos/eDEXNative/AGENTS.md` from the SwiftPM executable target so the new doc guardrail does not create unhandled-file build warnings.

Verification:

- `bash scripts/native-phase precheck`;
- run `git diff --check` before committing.

## Stage 2: SwiftPM/Package Taxonomy

Status: complete.

Completed scope:

- behavior-preserving module move only;
- consolidated completed support targets into fewer targets:
  - `EdexCoreBridge`
  - `EdexDomainSupport`
  - `EdexRenderingSupport`
  - `eDEXNative`
- updated imports, `Package.swift`, tests, and generated-binding linkage;
- kept `ShellState` split and input-routing cleanup out of the package-only step.

Verification:

```bash
cd macos/eDEXNative && ~/.swiftly/bin/swift build --build-tests
```

## Stage 3: Architecture Cleanup

Status: complete.

Completed scope:

- introduced `TerminalSessionProviding`, `StubTerminalStore`, `EdexAction`, `EdexActionHandler`, and `EdexActionRouter`;
- split keyboard ownership into `KeyboardStore`, with `ShellState` retaining compatibility wrappers for existing views;
- routed terminal input, tab switching, settings, fuzzy finder, and modal-close commands through the action boundary;
- split keyboard rendering out of `ContentView` into `EdexKeyboardPanel`;
- kept behavior equivalent except for internal routing boundaries.

Verification:

```bash
cd macos/eDEXNative && ~/.swiftly/bin/swift test
```

## Stage 4: PR

Status: ready after final full-gate verification.

Final verification:

```bash
git diff --check                         # pass
bash scripts/native-phase verify --full  # pass: Rust 17/17, Swift 224/224
bash scripts/native-phase smoke          # pass: window chrome + FFI bootstrap OK
```

After docs, taxonomy, and architecture cleanup are complete, open a PR from `anti-churning-strategem` to `post-web-runtime`.
