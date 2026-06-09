<!--
crates/edex-ffi/AGENTS.md — nearest-scope instructions for the UniFFI bridge.
Read the repo-root AGENTS.md, Ultrareview.md, and docs/plans/ffi-throughput-decision-2026-05-30.md first.
-->

# AGENTS.md

## Scope

`edex-ffi` is the UniFFI bridge between the native Swift app and `edex-core`.

## Rules

- Expose typed `Ffi...` records and methods on `EdexCore`; avoid JSON strings for new native APIs.
- Regenerate committed Swift bindings after any UDL/signature change.
- Use UniFFI for control-plane APIs. Keep the reserved narrow C ABI only for terminal byte/grid/diff streaming if the Phase 9 Swift harness proves UniFFI is too slow.
- Run `cargo fmt` after Rust edits.
- Keep Swift UI state mutations on the Swift MainActor; Rust callbacks may arrive off-main-thread.

## Binding Regeneration

```bash
cd crates/edex-ffi
cargo build --release
cargo run --bin uniffi-bindgen -- generate \
  --library target/release/libedex_ffi.dylib \
  --language swift \
  --out-dir ../../macos/eDEXNative/Generated
```

## Verification

```bash
cd crates/edex-ffi
cargo test
cargo fmt --check
cargo clippy -- -D warnings
```
