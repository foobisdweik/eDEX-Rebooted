# Phase 9 terminal strategy — SwiftTerm-first

Date: 2026-06-08
Status: **Decided.** Supersedes the emulation approach in slices 9.1–9.2 of
`full-native-swift-rust-conversion-2026-05-30.md` for the *current* project scope.

## Decision

Ship Phase 9 by integrating **SwiftTerm** (Miguel de Icaza's mature MIT Swift
terminal: VT/xterm emulation + AppKit rendering + selection/mouse/clipboard) as
the terminal surface, fed by the **existing** in-process PTY byte stream
(`PtyOutputSink`). The goal of this project's Phase 9 is narrowed to:

> Integrate SwiftTerm → working native terminal (echo, 5 tabs, CWD tracking,
> vim/tmux/ssh burn-in) → **delete the WKWebView frontend.**

## What is explicitly OUT of scope (separate future project)

The plan's original thesis — terminal **emulation in Rust** (grid + scrollback +
ANSI parsing in `crates/edex-core/src/terminal/*`, slice 9.1) with a bespoke
Swift cell renderer (9.2) — is **carved out as a separate, later initiative**
("Phase 9-prime"). It is NOT required to ship v1.

## Why this is safe / reversible

The FFI byte seam does **not** change. PTY bytes already stream Rust→Swift via
the `PtyOutputSink` callback interface (`spawn_pty`/`write_pty`/`resize_pty`/
`kill_pty`/`pty_metadata` are already generated and shipping). A future Rust
emulator slots in *behind* that same boundary: it would consume the same bytes
and expose a grid/dirty-cell view; only the Swift-side *consumer* of bytes
changes (SwiftTerm → custom renderer). Nothing built now is thrown away.

## Trade-offs accepted

- Rust core stays **byte-transport only** for the terminal; the FFI-throughput
  C-ABI escape hatch (`ffi-throughput-decision-2026-05-30.md`) stays unused for
  now — that decision's 9.2 gate is moot under SwiftTerm.
- External Swift dependency (SwiftTerm) — its rendering model, its bugs,
  effectively single-maintainer. Accepted for shipping speed.
- The eDEX **aesthetic** (glow, scanlines, custom cursor) is layered *over*
  SwiftTerm via an overlay (CALayer/Metal) and SwiftTerm's theming hooks, rather
  than owned end-to-end. Tracked as a later polish slice.

## Integration notes (binding for implementers)

- Use SwiftTerm's **feed-driven `TerminalView`** (macOS) — NOT
  `LocalProcessTerminalView`, which would spawn its *own* PTY. We own the PTY in
  Rust. Push bytes via `terminal.feed(byteArray:)`; route user input out via the
  `TerminalViewDelegate.send(source:data:)` callback into `write_pty`.
- SwiftTerm enters via a **SwiftPM dependency** on the `eDEXNative` app target —
  this is an external package dep, not a new per-feature target, so it does not
  violate the anti-churn "no new one-feature target" rule.
- **Test-target boundary:** `eDEXNativeTests` only links `EdexDomainSupport` /
  `EdexRenderingSupport`, NOT `EdexCoreBridge`. So TDD-able logic (spawn-option
  mapping, byte/lifecycle buffering, tab model) lives as **pure domain types in
  `EdexDomainSupport`**; thin FFI/SwiftTerm adapters live in the app target and
  are covered by `native-phase smoke`.
- MainActor rule still applies: `PtyOutputSink` callbacks arrive off-main; hop to
  `@MainActor` before touching `@Observable` state or the view.

## Revised slice plan (this project)

- **9.1** — PTY client façade + pure domain spawn-request + byte/lifecycle buffer
  (TDD in `EdexDomainSupport`; FFI adapter in `Services`). No UI, no SwiftTerm.
- **9.2** — Add SwiftTerm dep; `TerminalStore: TerminalSessionProviding` for a
  single tab: spawn from settings, feed bytes → `TerminalView`, input →
  `write_pty`; replace `StubTerminalStore` in `ShellState`.
- **9.3** — Mount `TerminalView` in `ContentView` (replace placeholder); wire
  `resize_pty` from measured cols/rows.
- **9.4** — Five-tab model: per-tab PTY id, switch/close, complete COPY/PASTE +
  NEXT/PREVIOUS_TAB shortcuts and physical shell shortcuts.
- **9.5** — CWD/process metadata (poll `pty_metadata` or `on_metadata`); update
  `activeCwd`, sync filesystem panel `fsPath` to active tab.
- **9.6** — eDEX aesthetic overlay over SwiftTerm; stdout audio cue.
- **9.7** — Burn-in (shell, vim, nano, top/htop, tmux, ssh, ANSI, Unicode,
  resize, scrollback) → **delete WKWebView frontend.**
