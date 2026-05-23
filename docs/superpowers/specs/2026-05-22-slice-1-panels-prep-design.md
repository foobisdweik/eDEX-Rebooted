# Slice 1 — Sysinfo Service Extraction + Inert Layout Seam

**Branch:** `slice-1-panels-gpui`
**Date:** 2026-05-22
**Status:** Design approved; awaiting implementation plan

## Context

The `post-web-runtime` branch is replacing the WKWebView + JS frontend
with native Rust (gpui) panels, slice by slice. The full slicing plan
lives in `~/.claude/plans/how-would-you-slice-compiled-hoare.md`; the
UI-framework decision is recorded in `NATIVE_PORT.md` (gpui, 2026-05-22).

Slice 1 was originally scoped as "replace all six telemetry panels with
gpui-rendered natives in one PR." Brainstorming refined that into three
sub-slices because gpui owns `NSApplication` by default and Tauri 2 already
does — a custom `gpui::Platform` is required to make them coexist, and
that work is too risky to bundle with the panel ports themselves:

| Sub-slice | Scope                                                                                     |
|-----------|-------------------------------------------------------------------------------------------|
| **1**     | Backend prep only: sysinfo service extraction + inert CSS seam + layout audit. **This spec.** |
| **1b**    | Insert sibling `NSView`/`CAMetalLayer` into the Tauri `NSWindow`; activate the CSS seam.  |
| **1c**    | Implement `TauriHostedPlatform: gpui::Platform`; render the six panels in gpui.           |

Slice 1's defining property is **zero user-visible change**. The app boots,
all six JS panels render and tick exactly as today. The PR is reviewable
in one sitting and is trivially revertable.

## Goal

Ship two pieces of backend prep that Slice 1b and 1c will consume:

1. A Tauri-agnostic `SysinfoService` that returns typed Rust structs, so
   native gpui code (1c) has a path to telemetry data that doesn't go
   through Tauri's `invoke()`, `AppHandle`, or JSON.
2. A documented, inactive CSS seam (`body.native-left-active`) and a
   stable DOM rect source (`#mod_column_left`) that Slice 1b will read
   for sibling `NSView` geometry and toggle when the native panel mount
   takes over.

Plus a documentation audit in `NATIVE_PORT.md` enumerating each panel's
DOM mount, CSS file, and augmented-ui polygon — the contract Slice 1c
recreates pixel-for-pixel in gpui.

## Non-goals

- Any `gpui` crate dependency. Compile-time cost shouldn't ride a refactor PR.
- Any `NSView` insertion or `tauri.conf.json` window-geometry change. (1b.)
- Any `gpui::Platform` impl or `CAMetalLayer` wiring. (1c.)
- Toggling `body.native-left-active` from anywhere. (1b.)
- Any actual rendering of panels in gpui. (1c, possibly split further.)
- Extracting `theme_service` / `settings_service` parallels for native
  consumers. `settings.rs` already has callable Rust APIs; the extraction
  is deferred until a panel actually needs it.
- Touching any of the other 10 JS classes (terminal, fs, keyboard, modal,
  audiofx, etc.). Slice 1 modifies sysinfo code, one CSS rule, one doc.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ src-tauri/src/                                                      │
│   sysinfo_service.rs   ← NEW: Tauri-agnostic. Typed structs +       │
│                          pure-Rust query fns. Owns a refresh-       │
│                          cached sysinfo::System.                    │
│   sysinfo_cmds.rs      ← shrinks to thin #[tauri::command] shims:   │
│                          call service → serde-serialize → return.   │
│                          Command names + JSON wire shape unchanged. │
│   lib.rs               ← .manage(SysinfoService::new()) so the      │
│                          service is one shared instance.            │
│                                                                     │
│ src-tauri/tests/                                                    │
│   sysinfo_contract.rs  ← NEW: fixture structs → serde → assert      │
│                          JSON shape. Locks the wire format.         │
│                                                                     │
│ src/assets/css/mod_column.css                                       │
│   + body.native-left-active #mod_column_left { ... }                │
│                          Modifier never applied in Slice 1.         │
│                                                                     │
│ src/renderer.js / src/ui.html (no change)                           │
│   #mod_column_left stays the rect source 1b will read.              │
│                                                                     │
│ NATIVE_PORT.md ← Audit appendix + conversion-log row                │
│                                                                     │
│ .github/workflows/ci.yml ← new cargo-test job                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Sysinfo service shape

`sysinfo_service.rs` exports one struct plus a method per current `si_*`
command. The `Mutex` wrapping is required because `sysinfo`'s refresh
methods take `&mut self`; the service must remain `Send + Sync` so Tauri's
`State` and any future native caller can share it.

```rust
pub struct SysinfoService {
    sys: Mutex<System>,
    components: Mutex<Components>,
    networks: Mutex<Networks>,
    disks: Mutex<Disks>,
}

impl SysinfoService {
    pub fn new() -> Self { ... }

    pub fn cpu(&self) -> CpuStats { ... }
    pub fn memory(&self) -> MemStats { ... }
    pub fn load(&self) -> LoadStats { ... }
    pub fn temp(&self) -> Option<TempStats> { ... }
    pub fn processes(&self) -> Vec<ProcessRow> { ... }
    pub fn network_interfaces(&self) -> Vec<NetIface> { ... }
    pub fn network_stats(&self, iface: &str) -> Option<NetStats> { ... }
    pub fn disks(&self) -> Vec<DiskInfo> { ... }
    pub fn system(&self) -> SystemInfo { ... }
    pub fn chassis(&self) -> ChassisInfo { ... }
    pub fn uptime(&self) -> u64 { ... }
    pub fn battery(&self) -> Option<BatteryInfo> { ... }
}
```

Each returned struct derives `Serialize`, `Clone`, and `Debug`. Field
names and any `#[serde(rename = "...")]` annotations are chosen so
`serde_json::to_value(&fixture)` produces the *exact* JSON shape today's
`si_*` commands return — verified by the contract tests below.

`sysinfo_cmds.rs` collapses to one-liner wrappers, retaining all 13
current command names and call signatures:

```rust
#[tauri::command]
pub fn si_cpu(svc: tauri::State<'_, SysinfoService>) -> CpuStats {
    svc.cpu()
}

#[tauri::command]
pub fn si_network_stats(
    svc: tauri::State<'_, SysinfoService>,
    iface: String,
) -> Option<NetStats> {
    svc.network_stats(&iface)
}
// ...etc for the other 11 commands
```

`lib.rs` adds `.manage(SysinfoService::new())` in `setup()`. The
`invoke_handler` list is unchanged.

### Why typed structs vs. `serde_json::Value`

Native gpui code in 1c consumes typed Rust data — `CpuStats { aggregate:
f32, ... }` directly, with no JSON in between. Going through
`serde_json::Value` would force native code to either re-parse or carry a
`Value` everywhere, both of which negate the point of skipping `invoke()`.

### Why `Mutex` (not `RwLock`)

`sysinfo`'s `refresh_*` methods require `&mut self`, and every query
involves a refresh. There are no read-only queries to optimize for, so
`Mutex` is the simpler primitive. If profiling later shows lock
contention is meaningful, the service can move to per-domain locks
(one per `sys`/`components`/`networks`/`disks`) without changing the
external API.

---

## Contract tests

`src-tauri/tests/sysinfo_contract.rs` contains one test per service
struct. Each test:

1. Builds a deterministic fixture struct (hand-written field values).
2. Calls `serde_json::to_value(&fixture)`.
3. Asserts the resulting `Value` equals a hand-written `json!({...})`
   shape with the exact field names, nesting, and key casing JS panels
   currently consume.

Example:

```rust
#[test]
fn cpu_stats_wire_shape_is_stable() {
    let fixture = CpuStats {
        usage_per_core: vec![12.5, 34.0, 56.5, 78.0],
        aggregate: 45.25,
        // ...
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = serde_json::json!({
        "usagePerCore": [12.5, 34.0, 56.5, 78.0],
        "aggregate": 45.25,
        // ...
    });
    assert_eq!(actual, expected);
}
```

The tests **do not** call any `sysinfo` API. Live values vary per machine
and would make CI flaky. The fixture is the contract; what the OS
actually returns at runtime is the service's separate concern.

Failure mode that gets caught: any rename of a serde field that would
break a JS panel (`usagePerCore` → `perCoreUsage`, dropping a field,
nesting changes, etc.) fails the test before merge.

The full panel-by-command audit (done as part of writing this spec)
identifies which fields each panel reads — those become the fields the
contract tests assert on. Fields the panels don't read are still tested
for shape but are lower priority for diff coverage.

### CI integration

`.github/workflows/ci.yml` gains a fifth job:

```yaml
rust-test:
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v4
    - uses: dtolnay/rust-toolchain@stable
      with: { targets: aarch64-apple-darwin }
    - uses: Swatinem/rust-cache@v2
    - run: cargo test --target aarch64-apple-darwin --manifest-path src-tauri/Cargo.toml
```

The existing `tauri-build` job gains a `needs: [rust-fmt, rust-clippy, rust-test, js-tests]`
gate (currently three; this adds the fourth).

---

## CSS seam

In `src/assets/css/mod_column.css` (confirmed: this file owns
`#mod_column_left`'s positioning; `extra_ratios.css` carries
viewport-ratio overrides for the same selector):

```css
/* Slice 1 native-mount seam.
   Toggled by Slice 1b once a sibling NSView/CAMetalLayer for the native
   gpui panel column is inserted into the Tauri NSWindow and sized from
   #mod_column_left's bounding rect.

   Inactive in Slice 1 — nothing toggles the body class, so JS panels
   render unchanged. Removing or renaming #mod_column_left will break
   Slice 1b's geometry source; do not touch until Slice 1c retires it. */
body.native-left-active #mod_column_left {
    visibility: hidden;
    pointer-events: none;
}
```

`visibility: hidden` preserves layout (so the rest of the page reflowing
isn't a 1b concern); `pointer-events: none` stops the hidden panels
catching clicks meant for the native overlay.

`#mod_column_left` already exists; `src/renderer.js:279` creates it. No
new DOM elements are introduced in Slice 1. If the audit reveals the
container's positioning is fragile (e.g., depends on flex sibling
geometry that the native view will disrupt), Slice 1 adds a sibling
note in `NATIVE_PORT.md`; Slice 1b owns any fix.

---

## NATIVE_PORT.md updates

### New audit appendix

Inserted between the current "Inventory" and "Priorities" sections:

```markdown
## Slice 1 layout audit

The native panel column (Slice 1b mounts; Slice 1c renders) replaces the
six JS panels currently mounted into `#mod_column_left`. The table below
is the contract Slice 1c recreates pixel-for-pixel.

| Panel              | JS class file                    | DOM root id              | CSS file                       | augmented-ui shape |
|--------------------|----------------------------------|--------------------------|--------------------------------|--------------------|
| Clock              | classes/clock.class.js           | #mod_clock               | mod_clock.css                  | <fill from CSS>    |
| Sysinfo            | classes/sysinfo.class.js         | #mod_sysinfo             | mod_sysinfo.css                | <fill from CSS>    |
| HardwareInspector  | classes/hardwareInspector.class.js | #mod_hardwareInspector | mod_hardwareInspector.css      | <fill from CSS>    |
| Cpuinfo            | classes/cpuinfo.class.js         | #mod_cpuinfo             | mod_cpuinfo.css                | <fill from CSS>    |
| RAMwatcher         | classes/ramwatcher.class.js      | #mod_ramwatcher          | mod_ramwatcher.css             | <fill from CSS>    |
| Toplist            | classes/toplist.class.js         | #mod_toplist             | mod_toplist.css, processlist.css | <fill from CSS>  |

All six mount into `#mod_column_left` (created by `src/renderer.js:279`,
class `.mod_column`).

### Rect-source contract

Slice 1b reads `getBoundingClientRect()` on `#mod_column_left` and
positions the sibling NSView/CAMetalLayer accordingly. The element MUST
NOT be renamed or removed until Slice 1c retires the JS column entirely.
A small bridge module added in Slice 1b will forward `resize` /
DPR-change events from the WKWebView to the Rust side so the native view
tracks layout reflows; designing that module is Slice 1b's problem, not
Slice 1's.

### Sysinfo commands consumed per panel

| Panel    | Calls (via `window.si.*` → `si_*` commands)                            |
|----------|------------------------------------------------------------------------|
| Clock    | _(none — local Date)_                                                  |
| Sysinfo  | si_system, si_chassis, si_uptime, si_battery                           |
| HardwareInspector | si_system, si_chassis                                         |
| Cpuinfo  | si_cpu, si_load, si_temp                                               |
| RAMwatcher | si_memory                                                            |
| Toplist  | si_processes                                                           |

`SysinfoService` in Slice 1 must expose typed accessors for all of these
(plus the remaining commands JS uses elsewhere: `si_network_interfaces`,
`si_network_stats`, `si_disks`).
```

The actual augmented-ui shape values are filled in by inspecting each
`mod_*.css` file during implementation — the audit is itself a
deliverable of Slice 1, not a prerequisite.

### Conversion log row

Appended to the Conversion Log table:

```markdown
| 2026-05-?? | Slice 1 backend prep | n/a → SysinfoService + CSS seam | <commit> | No user-visible change. Slice 1b/1c land panel mount + gpui render. |
```

### Open question status

No Open Architectural Questions are resolved by Slice 1. The decision to
hide gpui inside Tauri's `NSApplication` (via `TauriHostedPlatform`) was
recorded in chat but isn't merged code yet; it's a Slice 1c concern and
gets its own Decisions entry then.

---

## Verification

1. **CI green** — `rust-fmt`, `rust-clippy -D warnings`, `rust-test`
   (new), `js-tests`, `tauri-build --no-bundle` all pass.
2. **Local build** — `cargo +stable tauri build --target aarch64-apple-darwin` succeeds.
3. **Local boot** — `cargo tauri dev` boots fullscreen; all six panels
   render and tick exactly as before; theme swap (Ctrl+Shift+S) still
   re-styles them; tab spawn (Ctrl+X then 2/3/4/5) unaffected.
4. **DevTools spot-check** — the new CSS rule is present (`body.native-left-active #mod_column_left`);
   `body` element has no `native-left-active` class; `#mod_column_left`
   is visible and pointer-active.
5. **Diff scope** — `git diff --name-only origin/post-web-runtime...HEAD`
   matches exactly:
   - `src-tauri/src/sysinfo_service.rs` (new)
   - `src-tauri/src/sysinfo_cmds.rs` (shrunk)
   - `src-tauri/src/lib.rs` (mod declaration + `.manage`)
   - `src-tauri/tests/sysinfo_contract.rs` (new)
   - `src/assets/css/mod_column.css`
   - `NATIVE_PORT.md`
   - `.github/workflows/ci.yml`
   - `docs/superpowers/specs/2026-05-22-slice-1-panels-prep-design.md` (this file)

No other files modified. No JS class touched. No `src/bridge/*` change.
No `src/ui.html` change. `src-tauri/Cargo.toml` unchanged — `serde` and
`serde_json` are already direct deps (lines 26-27).

---

## Risks and mitigations

| Risk                                                                 | Mitigation                                                                                                                |
|----------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------|
| Serde rename gets a field's case wrong; JS panel silently breaks.    | Contract tests assert exact JSON shape per command; CI catches before merge.                                              |
| `sysinfo` 0.32 API differences cause incorrect refresh semantics in service. | Service mirrors the existing `sysinfo_cmds.rs` refresh patterns exactly; clippy + manual `cargo tauri dev` smoke-test catch divergence. |
| `Mutex` contention slows panels under load.                          | Defer until profiled. Each panel polls at 500ms-2s; contention is not plausible in v1.                                    |
| Audit table values rot (renames, deletions in later slices).         | Slice 1c is the consumer; if it diverges from the audit, the divergence is the change being reviewed. Audit is a 2026-05-22 snapshot, not a permanent contract. |
| `extra_ratios.css` overrides `#mod_column_left` at certain viewport ratios; the seam rule could be defeated by specificity. | Place the seam rule in `mod_column.css` using `body.native-left-active #mod_column_left` (specificity 0,1,1) — beats the unprefixed selectors in `extra_ratios.css`. |

---

## What this enables

After Slice 1 merges:

- **Slice 1b** can insert a sibling `NSView` and toggle `body.native-left-active`
  with zero changes outside `src-tauri/` and one CSS class application.
- **Slice 1c** can implement `TauriHostedPlatform: gpui::Platform`, mount
  gpui into the NSView, and pull data directly from `SysinfoService`
  with no `invoke()` round-trip, no `AppHandle` plumbing, and no JSON.
- **The JS panels remain a working fallback** at every commit until 1c
  lands. If 1c misses a panel feature, the failure mode is "native panel
  missing a field" rather than "broken app."

---

## Reference

- Slicing plan: `~/.claude/plans/how-would-you-slice-compiled-hoare.md`
- Native port plan + decisions: `NATIVE_PORT.md`
- gpui decision: `NATIVE_PORT.md` Decisions, 2026-05-22
- Existing sysinfo commands: `src-tauri/src/sysinfo_cmds.rs`
- Existing left-column DOM creation: `src/renderer.js:279`
- CI workflow: `.github/workflows/ci.yml`
- Project guidance: `CLAUDE.md`
