# Critique — Full Native Swift+Rust Conversion Plan (2026-05-30)

> **Status:** Historical review. The core ordering issues were resolved during execution: PTY observer shape landed in Phase 1, the FFI throughput decision is recorded in `docs/plans/ffi-throughput-decision-2026-05-30.md`, the Phase-2 interim-slot decision resolved to skip after the Swift shell proved viable, and Phase 8.2 is now complete. The remaining live concern is Swift-side coordination churn before Phase 8.3, now tracked by `Ultrareview.md`.

**Scope:** plan-of-record `docs/plans/full-native-swift-rust-conversion-2026-05-30.md` vs. source export `prompt-exports/oracle-plan-2026-05-30-020037-…md`. The export holds **two** oracle responses with *different* phase orderings; the plan adopted the first (core-before-slots). Five targeted concerns only.

---

## 1. Top 3 under-specified seams (implementer must guess)

1. **PTY → core callback abstraction (Item 1.3).** "Output flows through a core callback/observer" never fixes the trait shape, *and* never says how the existing Tauri `Channel<Vec<u8>>` path (`pty.rs:131-146`) is re-expressed so the thin Tauri adapter (1.2) still works after extraction. Does the adapter re-wrap the core callback back into a `Channel`? Unspecified — yet 1.3 blocks both 9.1 (terminal core) and the Swift `PtyOutputSink`. This is the single highest-leverage missing decision.
2. **FFI terminal-streaming throughput (dropped from the export).** The plan locks UniFFI (1.4) but never decides how high-frequency dirty-cell/grid updates cross FFI — per-cell? per-frame? snapshot? The export explicitly flagged this (export L1750: *"validate UniFFI callback overhead early… if too slow, add a narrow C ABI only for terminal byte/diff streaming"*). That escape-hatch is gone. 9.1/9.2 just say "emits dirty-cell updates over FFI." On the critical path; see §5.
3. **"Screenshot tolerance" is undefined.** ~10 done-when clauses (0.2, 2.1, …) hinge on fidelity "within tolerance," but no tool, threshold, or harness is named. The Open Questions section even admits the *bar itself* (tolerance vs. pixel-exact) is unresolved — so the acceptance criterion for most of the work is circular.

*(All three are genuine missing decisions, not "didn't paste code." The plan's references to SysinfoService / native_panels.rs / the `window.si` Proxy are appropriately terse.)*

## 2. Specificity balance

- **Over-specifies (implementation agent should own):** prescribing concrete Swift type breakdowns in done-when — `AppModel`/`ThemeManager`/`LineChartLayer`/`AugmentedLayer`/`PanelChromeView`, and the `TerminalMetalView` vs `TerminalLayerView` renderer choice (9.2). For a *plan*, naming the class graph pre-commits decisions that belong to the build. `alacritty_terminal` is handled correctly (held as an Open Question).
- **Load-bearing framing lost vs. export:** (a) the **C-ABI fallback** for terminal streaming (§1.2 above); (b) the export's Version-B **0.3 "validation gates"** — CI/documented commands for Rust tests, Swift tests, screenshot-diff, startup timing, terminal+panel smoke — was compressed into the plan's 0.3 *static* `native-migration-checklist.md`. The plan kept the map and dropped the **continuous-validation mechanism**, which is what actually enforces fidelity during a months-long migration.

## 3. Contradictions / missing dependencies in the phase order

- **Phase-2 "cap investment" checkpoint is mis-placed (the flagged one).** 2.2 says build CPU/RAM/toplist slots "only if the Swift shell isn't usable yet" — but shell usability isn't knowable until Phase 3 (3.1-3.3), arguably Phase 4. Phase 2 is ordered *before* Phase 3, so the checkpoint asks a question whose inputs don't exist yet. The **decision point must move after a Phase-3 shell spike**, or Phase 2 should be reordered after it.
- **Terminal critical-path vs. downstream deps.** 7.1 depends on "terminal CWD events," 7.2 on "terminal input," 8.3 on "terminal model" — all Phase-9 surfaces, yet Phases 7-8 precede Phase 9. The prose "start 9.1 early in parallel" covers the *core* but **not** the tabs/CWD-event interface those items actually consume (scheduled at 9.3). A minimal terminal-tabs/CWD FFI stub is an unscheduled prerequisite.
- **Toplist 5.6 `Deps: native modal (6.2)`** — a backward dependency from Phase 5 into Phase 6. 5.6 cannot complete inside Phase 5. (The export's Version B avoided this by ordering modals *before* panels.)

## 4. Over-planning risk (cut/simplify for a plan)

- **Phase 11 (decommission) is over-itemized** — 11.1-11.5 are mechanical; collapse to two (freeze; delete+retire).
- **Three near-duplicate closure lists:** the "Deletion gate," "Open Questions," and "Sequencing & risks" restate the dependency closure of Phases 5-10. Keep the Deletion gate; have the others reference it.
- **Prescriptive Swift type names** (per §2) are plan-level over-reach. Keep "Key files" pointing at the *JS/CSS being replaced*; drop the invented Swift filenames.

## 5. Questions whose answers change implementation ORDER

1. **Can UniFFI carry terminal streaming, or is a narrow C ABI needed?** If the latter, that seam must land **before 9.2 and likely before committing the full FFI surface in 1.4** — this is a Phase-1 spike, not a Phase-9 discovery. Reorders 1.4 ↔ 9.
2. **Must a terminal tabs/CWD interface exist before Phase 7?** If filesystem/fuzzyFinder/input-router genuinely need live CWD + routing, a 9.3-style stub moves *ahead* of Phase 7; otherwise 7-8 stall waiting on Phase 9.
3. **Fidelity bar: tolerance vs. pixel-exact?** Pixel-exact forces Phase 4 (layout/primitives) to be fully "done" and to precede every panel; tolerance lets Phase 4 and Phase 5 panels proceed in parallel. Directly sets how serialized Phases 4→5 are.
4. **Phase-2 cap decision (build 3 interim slots or skip)?** Determines whether Phase 2 carries 0 or three L–XL items — but per §3 the decision can't be taken at Phase 2's current position.

---

**Bottom line:** strategy and high-level sequencing are sound. Before execution, resolve three things that move work earlier: the PTY-callback/Channel re-adapter shape (1.3), an FFI-throughput spike with a C-ABI fallback (pull from Phase 9 into Phase 1), and a concrete fidelity-validation gate (restore from the export's 0.3). Then relocate the Phase-2 checkpoint after the Phase-3 shell spike and schedule a terminal CWD/tabs stub ahead of Phase 7.
