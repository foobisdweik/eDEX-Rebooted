# FFI throughput decision — Phase 1.5

Date: 2026-05-30

## Scope

This spike covers the Phase-1 boundary only: the core PTY observer shape is fixed as
`on_output(id, bytes)`, `on_exit(id, status)`, and `on_metadata(id, cwd, process)`.
The existing Tauri app still receives PTY bytes through `Channel<Vec<u8>>`.

## Prototype

`crates/edex-ffi` exposes the observer as a UniFFI callback interface named
`PtyOutputSink`. A Criterion spike lives at:

```text
crates/edex-ffi/benches/uniffi_callback_throughput.rs
```

The bench measures the Rust-side observer dispatch cost using 4 KiB PTY chunks.
Local result on 2026-05-30:

```text
pty_observer_dispatch/rust_trait_4k_chunks
  time:  [81.839 ns 82.170 ns 82.541 ns]
  thrpt: [46.216 GiB/s 46.424 GiB/s 46.612 GiB/s]
```

This intentionally does **not** claim to represent Swift foreign-callback overhead;
it is the lower-bound baseline used to size the eventual Swift harness.

## Decision

Use **UniFFI for control-plane APIs** now:

- paths
- user-data setup
- settings/theme/keyboard loading
- sysinfo snapshot bootstrap
- PTY spawn/write/resize/kill/metadata commands
- low-rate PTY lifecycle metadata callbacks

Reserve a **narrow C ABI for terminal byte/grid/diff streaming only** until a
real Swift harness proves UniFFI callbacks can sustain terminal rendering loads.
The C ABI should not replace UniFFI broadly; it is only the escape hatch for the
hot path if Swift callback overhead or allocation churn is too high.

## Rationale

The target terminal renderer will eventually stream dirty-cell or byte batches at
interactive frame rates. UniFFI callback interfaces are the cleanest API for
Swift ergonomics, but they add generated binding, object-lifetime, and collection
marshalling overhead that the Rust-only lower-bound bench cannot measure.
Committing the terminal hot path to UniFFI before a Swift harness would make the
highest-risk Phase-9 work depend on an unproven callback budget.

The Phase-1 implementation therefore keeps the API surface simple and
compatible: the same observer trait backs Tauri, UniFFI, and the future C ABI.
Only the transport changes.

## Follow-up gate

Before Phase 9.2, add a throwaway Swift harness that links `edex-ffi`, implements
`PtyOutputSink`, and measures sustained callbacks for representative payloads:

- 1 KiB byte chunks at 120 Hz
- 4 KiB byte chunks at 120 Hz
- dirty-cell batches sized for 80x24 and 160x48 grids

If that stays below the frame budget with acceptable allocation pressure, keep
UniFFI for streaming. Otherwise implement the reserved C ABI for terminal
streaming only.
