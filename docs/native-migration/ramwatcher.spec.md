# Native Migration Spec — RAMWATCHER panel

Source of truth (read-only references):
- `src/classes/ramwatcher.class.js`
- `src/assets/css/mod_ramwatcher.css`
- `src/assets/css/mod_column.css` (shared column layout)
- `src-tauri/src/sysinfo_service.rs` (`panel_snapshot`, `mem`, `MemStats`, `mem_stats_from_system`)
- `src-tauri/src/sysinfo_cmds.rs` (`si_panel_snapshot`, `si_mem`)
- `src/renderer.js` (instantiation L343; theme/CSS-var injection L110-146)
- `src/bridge/native_mount.js` + `src-tauri/src/native_mount.rs` (mount seam)

---

## 1. Summary

RAMWATCHER is the memory-monitor panel in the left column (`#mod_column_left`). It
shows a label header (`MEMORY` plus an inline "USING x OUT OF y GiB" readout), a
**440-cell dot-matrix grid** (40 columns × 11 rows) that visualizes the fraction of
RAM that is *active*, *available-but-cached*, and *free* using three opacity tiers,
and a **SWAP row** with a thin `<progress>` bar plus a "x.x GiB" text. It is a
sampled-snapshot panel updated every 1.5 s. **It does NOT use smoothie** — there is
no real-time line chart; the only animation is a CSS width transition on the swap bar.

---

## 2. Data contract

### Call

| What | Value |
|---|---|
| JS call | `window.si.panelSnapshot(false, 5, false)` |
| Maps to (Proxy camelCase→snake_case) | `invoke("si_panel_snapshot", {...})` |
| Tauri command | `si_panel_snapshot(collapse_threads_by_name, top_limit, include_process_list)` (`sysinfo_cmds.rs:73`) |
| Service method | `SysinfoService::panel_snapshot(false, 5, false)` (`sysinfo_service.rs:97`) |
| Arguments passed | `collapse_threads_by_name = false`, `top_limit = 5`, `include_process_list = false` |
| Polling cadence | `setInterval(..., 1500)` ms; first call fires immediately in the constructor (`updateInfo()` before the interval is set) |
| Re-entrancy guard | `this.currentlyUpdating` boolean — skips a tick if the previous async resolve hasn't returned |

> NOTE: RAMWATCHER only consumes the `mem` field of the snapshot. The `top_limit=5`
> argument forces `panel_snapshot` to also sort/truncate the process list (work that
> RAMWATCHER throws away). It does **not** call the lighter `si_mem` command. A native
> renderer should call `SysinfoService::mem()` directly (`sysinfo_service.rs:196`) —
> same `MemStats`, far cheaper, and TTL-cached. See Risk 3.

### Response fields consumed

The panel reads `snapshot.mem` only. `MemStats` is serialized camelCase
(`sysinfo_service.rs:570`), fields (all `u64`, **bytes**):

| Field | Used by RAMWATCHER | Meaning (per `mem_stats_from_system`, L791) |
|---|---|---|
| `total` | yes | `sys.total_memory()` |
| `free` | yes | **strict**: `total - used` (NOT sysinfo's raw free) |
| `used` | yes (validation only) | `sys.used_memory()` |
| `active` | yes | aliased to `used` on macOS (`active = used`) |
| `available` | yes | `available_memory().max(free)` |
| `swaptotal` | yes | `sys.total_swap()` |
| `swapused` | yes | `sys.used_swap()` |
| `swapfree` | no | — |
| `buffers`,`cached`,`slab`,`buffcache` | no | hard-zero on macOS |

### Derived computations (reproduce exactly in native)

```
// validation; throws (caught → no-op) if violated
assert(free + used == total)              // L43

active440    = round(440 * active / total)                 // L46
available440 = round(440 * (available - free) / total)     // L47
// dots: [0..active440) = "active", [active440 .. active440+available440) = "available",
//       remainder = "free"

GiB divisor  = 1073742000  bytes          // L67 (note: NOT 2^30 = 1073741824)
totalGiB     = round(total/divisor * 10)/10
usedGiB      = round(active/divisor * 10)/10
header text  = `USING ${usedGiB} OUT OF ${totalGiB} GiB`

usedSwapPct  = round(100 * swapused / swaptotal)  // → progress.value, fallback 0
usedSwapGiB  = round(swapused/divisor * 10)/10    // → "x.x GiB"
```

> Because `free = total - used` (strict) and `available = available_memory().max(free)`,
> `available - free >= 0` always holds, so `available440` is non-negative. On a machine
> where `available_memory()` ≈ `free`, `available440` collapses to ~0 and the grid shows
> essentially active-vs-free only. Reproduce the arithmetic verbatim; do not "improve" it.

### `window.settings.*` flags read by this panel

**None.** RAMWATCHER reads no settings flags. (Activation gates live in
`renderer.js`/native_mount: `experimentalNativePanels`, `experimentalNativeClock`,
`experimentalNativeModal` — RAMWATCHER has no dedicated gate yet.)

### `window.theme.*` values read by this panel

**None directly.** RAMWATCHER never touches `window.theme`. All color/font come from
CSS custom properties (`var(--color_r/g/b)`, `var(--font_main_light)`) injected once
into `<head>` by `renderer.js` (L118-131) from the theme JSON:
- `--color_r/g/b` ← `theme.colors.{r,g,b}` (the accent RGB triple)
- `--font_main_light` ← `theme.cssvars.font_main_light`

A native renderer must obtain the same accent RGB + light font, either by reading the
resolved CSS vars via the bridge or (preferred) by loading the active theme from Rust
(`get_theme`) directly.

---

## 3. DOM structure

Built once in the constructor (`ramwatcher.class.js:7-26`); the container is
`#mod_column_left` (passed as `parentId`). An outer `<div id="mod_ramwatcher">` is
appended to the column; its `innerHTML` is:

```
#mod_ramwatcher                              (outer; ::before/::after = decorative tick borders)
└─ #mod_ramwatcher_inner
   ├─ h1  "MEMORY"
   │    └─ i#mod_ramwatcher_info             ← dynamic "USING x OUT OF y GiB"
   ├─ #mod_ramwatcher_pointmap               ← 40×11 CSS grid
   │    └─ div.mod_ramwatcher_point  × 440   ← each cycles class free|available|active
   └─ #mod_ramwatcher_swapcontainer          (3-col grid 15%/65%/20%)
        ├─ h1  "SWAP"
        ├─ progress#mod_ramwatcher_swapbar  max=100 value=0   ← dynamic value
        └─ h3#mod_ramwatcher_swaptext  "0.0 GiB"              ← dynamic text
```

Static: header labels, the 440 point `<div>`s, the swap scaffold.
Dynamic per tick: each point's class (`free`/`available`/`active`), `#mod_ramwatcher_info`
text, swap `value`, swap text.

> **Shuffle detail (visual identity):** after building, the 440 points are collected
> into `this.points` and **Fisher-Yates shuffled** (`shuffleArray`, L83-88). Class
> assignment then walks the shuffled order, so active/available cells are scattered
> randomly across the grid rather than filling left-to-right. The shuffle happens once
> at construction; the same scrambled mapping persists for the panel's lifetime. A
> native port must replicate a one-time random permutation to match the look.

---

## 4. Visual spec (from `mod_ramwatcher.css` + `mod_column.css`)

All sizes are `vh`-relative (viewport-height responsive). Color is the theme accent
`rgb(var(--color_r),--color_g,--color_b))`; opacity encodes state.

**Container `#mod_ramwatcher`**
- `border-top: 0.092vh solid rgba(accent, 0.3)`; `font-family: var(--font_main_light)`;
  `letter-spacing: 0.092vh`; `font-size: 1.111vh`; `display: flex`; `padding-top: 0.645vh`.
- `::before` / `::after`: small left/right tick borders (0.092vh, 0.3 alpha, height 0.833vh)
  rising above the top border — decorative HUD frame corners.

**Header `h1` "MEMORY"** — `font-size: 1.48vh`, full width, `margin-bottom: -1.5vh`
(pulls the grid up under it). Inline `i#..._info`: `font-size: 1.20vh`, `opacity: 0.5`,
right-aligned, offset `bottom: 1.6vh` so it sits on the header's right edge.

**Point grid `#mod_ramwatcher_pointmap`**
- `display: grid`; `grid-template-columns: repeat(40, 1fr)`; `grid-template-rows: repeat(11, 1fr)`;
  `grid-auto-flow: column`; `grid-gap: 0.23vh`; padding-top/left `0.5vh`; `margin-bottom: 0.8vh`.
- **column-major flow** — points fill down each column then across (matters for grid mapping).

**Point `div.mod_ramwatcher_point`** — `width: 0.2vh`; `height: 0.25vh`;
`background: rgb(accent)`. State = opacity only:
- `.free` → `opacity: 0.1`
- `.available` → `opacity: 0.3`
- `.active` → `opacity: 1`

(No transition on the points; class flips are instantaneous.)

**Swap row `#mod_ramwatcher_swapcontainer`** — `grid-template-columns: 15% 65% 20%`.
- `h1` "SWAP": `font-size: 1.3vh`, `line-height: 1.5vh`, vertically centered.
- `progress#..._swapbar`: webkit-appearance none; `border-right: .1vh solid rgba(accent,0.8)`;
  track `::-webkit-progress-bar` = `rgba(accent,0.4)`, `height: .25vh`;
  value `::-webkit-progress-value` = `rgb(accent)`, `height: .4vh`,
  **`transition: width .5s cubic-bezier(0.4,0,1,1)`** (the panel's only animation).
- `h3#..._swaptext`: `font-size: 1.3vh`, `opacity: 0.5`, right-aligned, `white-space: nowrap`.

**Column context (`mod_column.css`)** — `.mod_column` is `width: 17%`, absolutely
positioned, flex-column, `justify-content: space-between`, `opacity:0 → 1` when
`.activated` (0.5s fade). Children fade in via a paused `fadeIn` animation that
`renderer.js` un-pauses one panel at a time. `body.native-left-active #mod_column_left`
is set `visibility:hidden; pointer-events:none` — this is the seam a native mount uses
to hide the JS column once the NSView is in place.

**No `augmented-ui`** on this panel (the HUD frame is the manual `::before/::after`
tick borders + `border-top`).

---

## 5. Charting analysis

**RAMWATCHER does not use smoothie.** No `window.SmoothieChart`, no `window.TimeSeries`,
no `<canvas>`. The "visualization" is:
1. a **static dot-matrix** (440 div opacity tiers) recomputed each 1.5s tick, and
2. a **single horizontal progress bar** (swap) with a CSS width transition.

There is no time-series history kept — each tick is an instantaneous snapshot.

**Native replacement recommendation:** No charting library needed.
- Dot grid → a single **`CALayer` with 440 sublayers** (or one layer drawn via
  `draw(in:)` / a `CAShapeLayer` of 440 rects), updating only `opacity` per cell per
  tick. For 440 tiny cells, a custom `NSView` doing one `CGContext` fill pass per tick
  is simplest and cheapest; SwiftUI `Canvas` is equally viable and avoids 440 view
  nodes. Avoid SwiftUI Charts (it's for series/marks, wrong tool here).
- Swap bar → `NSProgressIndicator` (custom-drawn) or a two-rect SwiftUI shape with a
  `.animation(.timingCurve(0.4,0,1,1, duration: 0.5), value: pct)` to mirror the CSS
  transition.
- Header readouts → plain `Text` / `CATextLayer` (the existing clock pilot already uses
  a `CATextLayer`, so the pattern is proven in `native_mount.rs`).

---

## 6. Lifecycle

| Phase | Behavior |
|---|---|
| Constructor arg | `parentId` (string DOM id, always `"mod_column_left"`); throws `"Missing parameters"` if falsy |
| Init | builds DOM, appends to parent, collects + **shuffles** the 440 points, sets `currentlyUpdating=false`, calls `updateInfo()` once immediately, then `setInterval(updateInfo, 1500)` stored on `this.infoUpdater` |
| Update loop | `updateInfo()` — guard on `currentlyUpdating`; `panelSnapshot` → recompute tiers → diff-and-set point classes (only writes class if it changed) → set header/swap text → `value` |
| Validation | throws if `free + used !== total` (caught silently → tick is skipped, guard reset) |
| Error / empty | `.catch(() => { this.currentlyUpdating = false; })` — any rejection (IPC error, bad data, missing DOM) just resets the guard; **no UI error state, stale values remain on screen** |
| Teardown | **NONE.** No `destroy()`; `this.infoUpdater` is never cleared. The panel lives for the app's lifetime. (A native port must add explicit teardown / cancel its polling task.) |

---

## 7. Coupling & interactions

- **Globals read:** `window.si` (Proxy → IPC). Indirect: CSS vars `--color_*`,
  `--font_main_light` (theme-injected), and the `.mod_column.activated` / `fadeIn`
  orchestration driven by `renderer.js`.
- **Other classes referenced:** none. RAMWATCHER is self-contained; it does not read or
  call any sibling panel.
- **User interactions:** **none.** No clicks, hovers, drags, or keyboard. Pure display.
- **Writes back:** **nothing** — read-only consumer of system state. No settings, no
  files, no events emitted.
- **Cross-panel deps:** shares `#mod_column_left` with `clock`, `sysinfo`,
  `hardwareInspector`, `cpuinfo`, `toplist` (all appended to the same column in order at
  `renderer.js:339-344`). RAMWATCHER is **4th** in that stack. Because the native mount
  seam hides the *entire* `#mod_column_left` (`body.native-left-active`), porting one
  panel in isolation requires either (a) migrating the whole column at once, or (b) a
  per-panel mount strategy that the current seam does not yet support. **Flag:** this is
  the dominant migration constraint — RAMWATCHER cannot go native independently without
  the other left-column panels also being native (or a finer-grained seam).

---

## 8. Native mapping proposal

**View structure (SwiftUI, embeddable via `NSHostingView` into the mounted NSView):**
```
RAMWatcherView (VStack, leading)
├─ HStack { Text("MEMORY")  Spacer()  Text(headerReadout).opacity(0.5) }
├─ MemoryDotGrid                       // Canvas or custom NSView; 40×11, column-major,
│                                      // fixed one-time permutation, 3 opacity tiers
└─ HStack(15/65/20) {
     Text("SWAP")
     SwapBar(pct:)                     // 2-rect shape, .timingCurve(0.4,0,1,1,0.5)
     Text(swapReadout).opacity(0.5)
   }
```
Color = theme accent `Color(r,g,b)`; font = the light theme font; opacities
0.1/0.3/1.0 for free/available/active mirror the CSS exactly.

**Data-flow choice: direct `SysinfoService` query, NOT the bridge.**
- RAMWATCHER writes nothing back and reads only `MemStats`. The cleanest native path is
  a Swift-side timer (`Timer`/`DispatchSourceTimer`, 1.5 s) that asks Rust for
  `MemStats` and renders. Prefer `SysinfoService::mem()` over `panel_snapshot` (drop the
  wasted process-list sort). This avoids `invoke()`/`listen()` entirely.
- The existing `native_mount` seam currently only ships rect geometry + a single
  `set_clock_text` string. To feed `MemStats` to a native RAMWATCHER you'd add either
  (a) a new `native_mount_set_*` push command, or (b) let the native view own its own
  poll loop calling into `SysinfoService` (it's already `Arc`-managed state). Option (b)
  is more idiomatic and decouples cadence from the WKWebView.

**Top 3 conversion risks**
1. **Whole-column coupling (highest).** The mount seam hides all of `#mod_column_left`;
   RAMWATCHER is one of six stacked panels and can't be ported alone without a
   finer-grained seam or a same-time port of the column. Plan the column, not the panel.
2. **Theme parity.** Accent RGB + `font_main_light` currently flow only as injected CSS
   vars (from `theme.colors`/`theme.cssvars`). Native must source the same theme (via
   `get_theme` / a shared theme model) and react to live theme swaps (Ctrl+Shift+S),
   which today just rewrite the `<head>` style — the native layer won't see that unless
   wired to a theme-change signal.
3. **Visual-fidelity details.** The one-time Fisher-Yates point shuffle, column-major
   grid flow, the exact GiB divisor (`1073742000`, not `2^30`), and the
   `cubic-bezier(0.4,0,1,1)` 0.5s swap-bar easing all contribute to the "feel"; getting
   the dot scatter or rounding wrong makes it visibly diverge from the JS panel.

---

## 9. Effort estimate

**S–M (lean S).** The data contract is trivial (one `MemStats` struct, simple
arithmetic, no charting library, no history buffer, no user input, no write-backs), so
the panel itself is small. The bump to "M" comes entirely from shared infrastructure —
the all-or-nothing column mount seam and live theme propagation — which is cross-cutting
work not specific to RAMWATCHER. The isolated render+poll logic is a clean Small.
