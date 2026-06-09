<!--
crates/edex-core/AGENTS.md — nearest-scope instructions for the Tauri-free Rust
core. Read the repo-root AGENTS.md and Ultrareview.md first.
-->

# AGENTS.md

## Scope

`edex-core` is the Tauri-free backend domain crate shared by the frozen Tauri adapter and the native Swift app.

## Rules

- Do not introduce `tauri` imports here.
- Do not split new Rust crates as part of the anti-churn cleanup; `Ultrareview.md` explicitly keeps the Rust side stable.
- Keep public data shapes additive and compatible with existing user-data JSON.
- PTY, filesystem, settings, sysinfo, and future terminal-emulation behavior must remain usable from both Tauri adapters and UniFFI.
- Run `cargo fmt` after Rust edits.

## Verification

From the repo root, prefer `bash scripts/native-phase verify --full` for cross-boundary changes. For crate-local iteration:

```bash
cd crates/edex-core
cargo test
cargo fmt --check
cargo clippy -- -D warnings
```
