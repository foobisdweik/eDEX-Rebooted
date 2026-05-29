# Native-conversion spec — CPUINFO panel

Source of truth:
- `src/classes/cpuinfo.class.js`
- `src/assets/css/mod_cpuinfo.css`
- `src/assets/css/mod_column.css` (shared column layout)
- `src-tauri/src/sysinfo_service.rs` / `src-tauri/src/sysinfo_cmds.rs` (data)
- `src/renderer.js` (instantiation, theme load, teardown)
- `src/assets/vendor/smoothie.js` (charting library being replaced)

---

## 1. Summary

CPUINFO is a live per-core CPU monitor in the left visual column. It shows the
CPU brand string, two stacked real-time line graphs (one for the lower half of
the logical cores, one for the upper half) with a running "Avg. N%" label per
graph, plus a four-cell stat footer: current temperature, current clock speed
("SPD"), max clock speed ("MAX"), and total task/process count. The graphs
scroll continuously; everything else refreshes once per second. All data comes
from one Rust backend call (`si_panel_snapshot`); the graphs are drawn with the
vendored `smoothie` canvas library, which must be replaced natively.

---

## 2. Data contract

### Backend call (single source for the whole panel)

The panel makes exactly one kind of data call, used in three places
(constructor, initial `updateSnapshot(data)`, and the polling loop):

```js
window.si.panelSnapshot(window.settings.excludeThreadsFromToplist === true, 5, false)
```

| JS Proxy call | maps to command | maps to service method |
|---|---|---|
| `window.si.panelSnapshot(...)` | `si_panel_snapshot` | `SysinfoService::panel_snapshot(collapse_threads_by_name, top_limit, include_process_list)` |

Argument mapping (positional → command params, see `cpuinfo.class.js:18,156` and `sysinfo_cmds.rs:72-90`):

| Arg position | Value passed | Command param | Service param | Notes |
|---|---|---|---|---|
| 1 | `window.settings.excludeThreadsFromToplist === true` (default `true`, see `settings.rs:85`) | `collapseThreadsByName` (`Option<bool>`, default false) | `collapse_threads_by_name` | **Irrelevant to CPUINFO** — it only affects `top_processes`, which this panel never reads. Could pass `false` natively. |
| 2 | `5` | `topLimit` (default 5) | `top_limit` | Also irrelevant to CPUINFO; sizes `top_processes` only. |
| 3 | `false` | `includeProcessList` (default false) | `include_process_list` | Keeps `process_list` out of the payload. Good — CPUINFO doesn't need it. |

### Response fields consumed (from `PanelSnapshot`, `sysinfo_service.rs:555-566`)

The class adapts the snapshot to a legacy shape in `updateSnapshot` (lines
146-163) and reads exactly:

| Consumed JS path | Rust field (`serde camelCase`) | Type | Use |
|---|---|---|---|
| `data.cpu.manufacturer` | `cpu.manufacturer` | String | Header name (concatenated) — read once at construction |
| `data.cpu.brand` | `cpu.brand` | String | Header name — read once |
| `data.cpu.cores` | `cpu.cores` | usize | Logical core count → number of TimeSeries, the `divide` split, header `#` ranges |
| `data.cpu.speed` | `cpu.speed` | String (e.g. `"3.20"`) | "SPD" footer cell, suffixed `GHz` |
| `data.cpu.speedMax` | `cpu.speed_max` | String | "MAX" footer cell, suffixed `GHz` |
| `data.currentLoad.cpus[i].load` | `current_load.cpus[i].load` | f64 (0–100) | Per-core series sample + average |
| `data.cpuTemperature.max` | `cpu_temperature.max` | f64 | "TEMP" footer cell, suffixed `°C` |
| `data.processCount` | `process_count` | usize | "TASKS" footer cell |

Fields present in the payload but **ignored** by CPUINFO: `cpu.physicalCores`,
`current_load.avgLoad`, `current_load.currentLoad`, `cpu_temperature.main`,
`cpu_temperature.cores[]`, `top_processes[]`, `mem{}`, `process_list`.

Note: in `panel_snapshot`, `cpu.speed` and `cpu.speed_max` are currently
**identical** (both derived from `cpu.frequency()` in `cpu_stats_from_sys`,
`sysinfo_service.rs:732-745`), so SPD and MAX always render the same number on
Apple silicon today. Per-core temps exist (`cpu_temperature.cores`) but only the
`max` scalar is shown.

### Polling cadence

- Constructor fires one `panelSnapshot` immediately to build the DOM and seed
  the first frame (`updateSnapshot(data)`).
- Then `setInterval(() => this.updateSnapshot(), 1000)` — **1000 ms** — stored on
  `this.snapshotUpdater`. Each tick re-calls `panelSnapshot` (no arg cached;
  re-reads `window.settings.excludeThreadsFromToplist` every tick).
- Backend TTLs (`sysinfo_service.rs:429-432`) do **not** apply to
  `panel_snapshot` — that method always does a fresh `refresh_cpu_all` +
  `refresh_memory` + `refresh_processes` + components refresh, regardless of
  cache. So every 1 s tick is a full system refresh on a blocking worker thread.

### Settings flags read

| Flag | Where | Effect on CPUINFO |
|---|---|---|
| `window.settings.excludeThreadsFromToplist` | `cpuinfo.class.js:18,156` | Passed as arg 1; has no visible effect on this panel (only changes top-process collapsing). |

There is **no** dedicated `experimentalNativeCpuinfo` gate today — only
`experimentalNativePanels`, `experimentalNativeClock`, `experimentalNativeModal`
exist (`settings.rs:90-92`). A new gate would need to be added (see §8).

### Theme values read

| Value | Where | Use |
|---|---|---|
| `window.theme.r` / `.g` / `.b` | `cpuinfo.class.js:88` | Line stroke color `rgb(r,g,b)` for every TimeSeries |

`window.theme.{r,g,b}` are set in `renderer.js:142-145` from
`theme.colors.{r,g,b}`. The CSS also reads `--color_r/g/b` (set in the injected
`<style class="theming">`, `renderer.js:123-125`) for borders/dashes. Theme
changes do **not** live-update this panel; they trigger a full page reload (see
§6).

---

## 3. DOM structure

Built imperatively in the constructor after the first `panelSnapshot` resolves.
Container chain: `#mod_column_left` (the column `<section>`) → `#mod_cpuinfo`
(created via `innerHTML +=` in constructor, line 7) → `#mod_cpuinfo_innercontainer`
(created via `createElement` + `innerHTML`, lines 28-59).

```
#mod_column_left                         (section, shared column; from ui.html/renderer)
└─ #mod_cpuinfo                          (static wrapper, flex row)
   └─ #mod_cpuinfo_innercontainer        (flex column, width:100%)
      ├─ h1  "CPU USAGE"  <i>{cpuName}</i>     (header; cpuName = manufacturer+brand, truncated to 30 chars)
      ├─ div                              (graph block 1: cores 1..divide)
      │   ├─ h1  "# <em>1</em> - <em>{divide}</em>" <br> <i#mod_cpuinfo_usagecounter0>Avg. --%</i>
      │   └─ canvas#mod_cpuinfo_canvas_0  (height attr = 60)
      ├─ div                              (graph block 2: cores divide+1..cores)
      │   ├─ h1  "# <em>{divide+1}</em> - <em>{cores}</em>" <br> <i#mod_cpuinfo_usagecounter1>Avg. --%</i>
      │   └─ canvas#mod_cpuinfo_canvas_1  (height attr = 60)
      └─ div                              (stat footer, flex row, dashed top border)
          ├─ div  h1 "TEMP" <br> <i#mod_cpuinfo_temp>--°C</i>
          ├─ div  h1 "SPD"  <br> <i#mod_cpuinfo_speed_min>--GHz</i>
          ├─ div  h1 "MAX"  <br> <i#mod_cpuinfo_speed_max>--GHz</i>
          └─ div  h1 "TASKS"<br> <i#mod_cpuinfo_tasks>---</i>
```

Static (built once): the entire tree above. `divide = floor(cores/2)`; on an
even core count both halves are equal, on odd counts block 1 gets the smaller
half. The two `<canvas>` elements have only a `height="60"` attribute; width is
governed by CSS (`width:76%`) and smoothie's `responsive:true`.

Dynamic (updated each tick by id lookup):
- `#mod_cpuinfo_usagecounter0` / `_usagecounter1` → `Avg. {N}%`
- `#mod_cpuinfo_temp` → `{N}°C`
- `#mod_cpuinfo_speed_min` → `{N}GHz`
- `#mod_cpuinfo_speed_max` → `{N}GHz`
- `#mod_cpuinfo_tasks` → `{N}`
- both `<canvas>` → repainted continuously by smoothie's own rAF loop (not by the
  1 s interval; the interval only `append`s new samples)

The id-based DOM writes are wrapped in `try/catch` that fails silently — guard
against the element being mid-refresh during a theme swap (lines 128-142).

---

## 4. Visual spec

From `mod_cpuinfo.css` (+ shared `mod_column.css`). Units are mostly `vh`
(viewport-height-relative), so everything scales with window height. `0.092vh`
is the project's "1px-ish" hairline.

Layout / container (`#mod_cpuinfo`):
- `display:flex`; `padding: 0.645vh 0`; `letter-spacing: 0.092vh`.
- `font-family: var(--font_main_light)`.
- Top border: `0.092vh solid rgba(--color_r,--color_g,--color_b, 0.3)`.
- `::before` / `::after` pseudo-elements draw short (`0.833vh`) left/right
  vertical hairline ticks at the top corners (the augmented-corner look), same
  30%-alpha theme color. **No `augmented-ui` attribute is used on this panel** —
  the bracket effect is pure CSS pseudo-elements.

Inner container (`#mod_cpuinfo_innercontainer`): `flex-column`, centered,
`space-between`, `width:100%`.

Header `h1:first-child`: `font-size:1.48vh`, near-full width, negative bottom
margin to pull the graph block up; the `<i>` (CPU name) is `1.20vh`,
`opacity:0.5`, right-aligned, normal font-style, nudged up `1.9vh`.

Generic `h1` in panel: `font-size:1.3vh`, `line-height:1.5vh`, no margin.
`em` (the numbers in `# 1 - 4`): `font-family: var(--font_main)` (the heavier
face vs. the light header font), normal style.
`i` (the value readouts): `font-size:1.3vh`, `opacity:0.5`, normal style,
`margin-top:0.5vh`.

Graph rows (`#mod_cpuinfo > div > div`): `flex-row`, centered, `space-between`,
`margin: 0.278vh 0`.

Stat footer (`> div > div:last-child`): `width:95%`, `border-top: 0.092vh dashed`
30%-alpha theme color, `padding-top:0.838vh`; each of its four children is
`width:20%`, `text-align:center`.

Canvas styling (`#mod_cpuinfo canvas`):
- `width:76%`, `height:4.167vh` (CSS box; note the `height="60"` HTML attr is the
  smoothie backing-store/logical height, separate from the CSS display height).
- `border-top` and `border-bottom`: `0.092vh dashed` 30%-alpha theme color.
- `margin: 0.46vh 0`.

Theme custom properties used: `--color_r`, `--color_g`, `--color_b` (all borders
and dashes, always at `0.3` alpha), `--font_main`, `--font_main_light`.

Animations/transitions: none on the panel itself. The column wrapper
(`mod_column.css`) provides the entrance: `section.mod_column` fades in via
`opacity` transition when `.activated` is added, and each direct child `div`
runs a one-shot `fadeIn` keyframe (`animation-play-state` flipped to `running`
by the boot tick loop in `renderer.js:352-361`). The CPUINFO graph line itself
has no CSS animation — its motion is smoothie's canvas redraw.

---

## 5. Charting analysis

### How smoothie is wired today

Two `SmoothieChart` instances (`this.charts[0]`, `this.charts[1]`), one per
canvas. Chart options (identical for both, `cpuinfo.class.js:62-78`):

```js
{
  limitFPS: 30,                 // cap redraw at 30 fps
  responsive: true,            // size canvas to its CSS box
  millisPerPixel: 50,          // horizontal scroll speed (≈ pan rate)
  grid: { fillStyle:'transparent', strokeStyle:'transparent',
          verticalSections:0, borderVisible:false },   // invisible grid/bg
  labels: { disabled: true },  // no axis labels
  yRangeFunction: () => ({ min:0, max:100 })           // fixed 0–100% y-axis
}
```

`new TimeSeries()` is created once per logical core (`this.series[i]`, total =
`cpu.cores`). Each series is added to chart 0 if `i < divide`, else chart 1
(lines 81-96), each with per-series options:

```js
{ lineWidth: 1.7, strokeStyle: `rgb(${theme.r},${theme.g},${theme.b})` }
```

So **every core line is the same theme color** — the two graphs are dense bundles
of N/2 overlapping single-color traces (no per-core color differentiation), with
bezier interpolation (smoothie's default `interpolation:'bezier'`).

Rendering starts with `chart.streamTo(canvas, 500)` for each chart (line 99):
`500` is the `delayMillis` (render lag/smoothing buffer). `streamTo` calls
`start()`, which kicks smoothie's own internal `requestAnimationFrame` render
loop — this is independent of the panel's 1 s data interval.

Data feed: every 1 s tick, `updateSnapshot` iterates `data.cpus` and calls
`this.series[i].append(Date.now(), e.load)` (line 117). It also computes the two
half-averages and writes the `Avg. N%` labels. So: **samples arrive at 1 Hz, but
the chart redraws at up to 30 fps**, smoothly interpolating/scrolling between the
1 Hz points — that's the whole reason smoothie is used here.

Chart instance count: **2 charts, `cpu.cores` TimeSeries** (e.g. on an
8-performance/efficiency-core M-series reporting 8–10 logical CPUs, that's 2
charts and 8–10 traces split 4-and-4 / 5-and-5).

### Native charting replacement plan

The native panel must reproduce: two scrolling 0–100% line plots, each
overlaying ~N/2 thin single-color bezier traces, fed at 1 Hz, animated/scrolled
at ~30 fps, theme-colored, with transparent background and dashed top/bottom
borders. Recommendation, in priority order:

1. **Recommended: `CAShapeLayer` / Core Animation on a `CALayer`-backed NSView.**
   This matches the existing `native_mount.rs` substrate (it already builds
   `CALayer`/`CATextLayer` sublayers and a 1px border layer). Maintain a rolling
   ring buffer of the last `width/millisPerPixel`-worth of samples per core; on
   each frame build a `CGPath` per trace and assign to a `CAShapeLayer.path`.
   Use an implicit/explicit `CABasicAnimation` on a translate transform to do the
   horizontal scroll between 1 Hz samples (Core Animation interpolates on the
   render server, off the main thread — gives the same "smooth between samples"
   feel smoothie fakes with rAF). Pros: lowest integration risk (same Cocoa
   layer model already in the repo), no SwiftUI dependency, transparent bg and
   dashed borders are trivial CALayer properties (`lineDashPattern`). Cons: more
   manual path math; bezier smoothing requires building a smoothed path yourself
   (Catmull-Rom → cubic, or just `addCurveToPoint` between points).

2. **Alternative: SwiftUI `Charts` (`LineMark` in a `Chart`).** Drive it from an
   `@Observable`/`TimelineView` updating samples; `Chart` handles the path and
   `chartYScale(domain: 0...100)` pins the axis; hide axes/grid with
   `.chartXAxis(.hidden)` / `.chartYAxis(.hidden)`. Pros: declarative, least
   code, easy theming via `.foregroundStyle`. Cons: introduces SwiftUI hosting
   into a currently Cocoa/`CALayer` native seam; many overlapping `LineMark`s
   (one per core) is not Charts' sweet spot and the implicit-animation story for
   continuous scroll is weaker than CA; macOS 13+ floor (fine for this target).
   Smooth interpolation between 1 Hz samples would need `.animation` on the data
   or `Charts`' `interpolationMethod(.catmullRom)`.

3. **Overkill: Metal / `CAMetalLayer`.** `native_mount.rs` notes a future
   CAMetalLayer path. A custom Metal line renderer would give the best
   performance and exact bezier control, but for two small 0–100% sparkline
   strips updated at 1 Hz it is far more engineering than warranted. Reserve only
   if the whole column moves to a single Metal-backed gpui surface.

Tradeoff summary: **go with option 1 (CAShapeLayer)** to stay consistent with the
existing native mount and avoid a SwiftUI dependency for a non-interactive
graph. Reproduce smoothie's behavior as: fixed y-domain 0–100, ~30 fps redraw
cap, ~50 ms-per-pixel scroll, 1.7pt stroke in theme color, bezier-smoothed path,
no grid/labels, ~500 ms render-lag buffer.

---

## 6. Lifecycle

- **Constructor arg:** `parentId` (string), required — throws `"Missing
  parameters"` if falsy. Instantiated as `new Cpuinfo("mod_column_left")` in
  `renderer.js:342`, after clock/sysinfo/hardwareInspector and before
  ramwatcher/toplist.
- **Init:** constructor appends `#mod_cpuinfo`, then awaits the first
  `panelSnapshot`. **All DOM, charts, and the interval are created inside that
  promise's `.then`** — so nothing renders until the first backend response
  resolves. If the first call rejects, `.catch(() => {})` swallows it and the
  panel stays empty (no DOM beyond the empty `#mod_cpuinfo`, no interval, no
  retry).
- **Update loop:** `this.snapshotUpdater = setInterval(updateSnapshot, 1000)`.
  Each tick calls `panelSnapshot` again, adapts the shape, appends per-core
  samples, recomputes averages, updates the four footer cells. Smoothie's own rAF
  loop (started by `streamTo`) drives the visible animation independently.
- **Teardown:** **There is no `destroy`/`stop` method and `snapshotUpdater` is
  never cleared by the class.** The only teardown path is a full page reload:
  theme change (`renderer.js:422-424` `window.location.reload()`), keyboard swap,
  or the "Reload UI" action. Reload tears down the whole WKWebView document,
  which stops smoothie's rAF loop and the interval together. **For the native
  port this is the key risk to fix:** a native renderer must explicitly stop both
  the 1 Hz polling and the redraw/animation timer on teardown (the original code
  leaks neither only because the page is destroyed). The smoothie streamData/rAF
  must be stopped (`SmoothieChart.stop()` equivalent) and the poll cancelled.
- **Error/empty handling:** constructor returns early if `!data || !data.cpu ||
  !data.currentLoad`. `updateSnapshot` returns early if `!data` or `!data.cpus`
  (the `#216` mem-leak guard, line 114). All footer DOM writes are in silent
  `try/catch`. Averages divide by `stats.length` (could be `NaN`/`0%` if a half
  is empty, but `divide ≥ 1` for any real CPU).

---

## 7. Coupling & interactions

Globals / external dependencies:
- `window.si` — the renderer Proxy → `invoke("si_panel_snapshot")`. Only data
  source.
- `window.settings.excludeThreadsFromToplist` — read each tick (no effect on
  output; see §2).
- `window.theme.{r,g,b}` — read once at construction for line color.
- `window.SmoothieChart` / `window.TimeSeries` — vendored globals from
  `assets/vendor/smoothie.js` (the thing being replaced).
- `document.getElementById(parentId)` and the per-element id writes — DOM only.

User interactions: **none.** The panel is read-only/non-interactive; no click,
hover, drag, or input handlers. (Smoothie's tooltip feature is off — `tooltip`
not enabled.) Nothing is written back to settings or the backend.

Cross-panel deps: shares the `si_panel_snapshot` backend call and the
`excludeThreadsFromToplist` setting with **`toplist.class.js`** (and
`ramwatcher`/`sysinfo` consume overlapping snapshot fields). All sibling panels
poll `panelSnapshot` independently on their own intervals — there is no shared
poller. Converting CPUINFO alone is safe (no shared JS state with siblings) but
note the **redundant full-system refresh**: each panel triggering its own 1 s
`panel_snapshot` means several full `refresh_all`-class passes per second. A
native renderer querying `SysinfoService` directly is the chance to share one
refresh across native panels.

Layout coupling: lives inside `#mod_column_left`, which is the exact container
the native-mount seam (`native_mount.rs` + `bridge/native_mount.js`) hides
(`body.native-left-active`) and overlays with an NSView. So CPUINFO's native
view would be a sublayer/subview of that same mounted NSView, sized from
`#mod_column_left`'s rect.

---

## 8. Native mapping proposal

### View structure (AppKit + CALayer, matching the existing seam)

Within the already-mounted `native_mount` NSView for `#mod_column_left`, add a
`CpuinfoLayer` group (or a dedicated subview) stacked in the column at CPUINFO's
slot:
- `CATextLayer` — header "CPU USAGE" + right-aligned dimmed CPU name.
- Two graph groups, each:
  - `CATextLayer` — "# a - b" range title + `Avg. N%` readout.
  - `CALayer` plot area with dashed top/bottom borders (`borderWidth` +
    `lineDashPattern` on sublayer borders, or two thin dashed `CAShapeLayer`s).
  - N/2 `CAShapeLayer` traces (or one merged path) for the cores, 1.7pt stroke,
    theme color, bezier-smoothed, fixed 0–100 y-domain, scrolling transform.
- Footer: four `CATextLayer` cells (TEMP / SPD / MAX / TASKS) on a dashed-top
  row.

(If the team prefers SwiftUI: an `NSHostingView` wrapping a `VStack` of a header
`Text`, two `Chart`s with hidden axes + `chartYScale(0...100)`, and a 4-column
footer `Grid`. See §5 option 2 tradeoffs.)

### Data flow choice

**Recommend direct `SysinfoService` query, not the `nativeMount` JS bridge.**
Rationale: the data already lives in Rust; a native renderer can hold an
`Arc<SysinfoService>` (already `.manage()`d) and call `panel_snapshot(false, 1,
false)` (or better, a leaner future `cpu_panel()` returning only cpu +
current_load + cpu_temperature + process_count) on a Rust-side 1 s timer, then
push frames to the layer. This drops the per-tick `invoke()` round-trip and the
JS Proxy entirely. The `nativeMount.setClockText`-style string bridge that the
clock pilot uses is the wrong model here — CPUINFO needs structured arrays and
high-frequency redraws, not a text push. Use the bridge only for
activation/visibility/geometry (which `native_mount.js` already owns), and let
the panel's data + drawing live fully in Rust/Core Animation.

A new gate flag (e.g. `experimentalNativeCpuinfo`, mirroring
`experimentalNativeClock` in `settings.rs:90-92` and the
`cpuinfo.class.js`/`clock.class.js` guard pattern) should toggle whether the JS
`Cpuinfo` builds its DOM or no-ops in favor of the native layer.

### Top 3 conversion risks

1. **Smoothie's "smooth scroll between 1 Hz samples" is the panel's signature
   look.** Naively redrawing a static polyline at 1 Hz looks janky vs. the
   original's interpolated 30 fps scroll. Must reproduce the
   millisPerPixel-driven horizontal pan + bezier smoothing + ~500 ms render-lag
   buffer with CABasicAnimation or a Metal/CA redraw loop.
2. **No teardown today.** The JS class leaks `snapshotUpdater` and the smoothie
   rAF loop, surviving only because theme/keyboard changes reload the page. The
   native version must explicitly cancel its data timer and redraw loop on
   deactivate/reload, and must coexist cleanly with the page-reload teardown the
   rest of the app still uses.
3. **Theme color is captured once at construction and only updated via full
   reload.** A native renderer sharing the long-lived `native_mount` view must
   decide how it picks up theme changes — either also rebuild on reload, or wire
   a theme-change signal to recolor the `CAShapeLayer` strokes
   (`#mod_column_left` may not be torn down the same way the WKWebView document
   is). Also note `cpu.speed`/`cpu.speedMax` are identical today (SPD == MAX) and
   only `cpuTemperature.max` (a scalar) is shown though per-core temps exist —
   preserve these exact behaviors unless a fix is intended.

---

## 9. Effort estimate

**M (medium).** The data side is trivial (one existing backend method, ~8 scalar
fields). The bulk of the work is faithfully replacing smoothie: two scrolling,
bezier-smoothed, multi-trace 0–100% line graphs with theme color, transparent
bg, dashed borders, 1 Hz data into ~30 fps animated scroll — plus adding a clean
teardown path the JS original never had. Not L because there's no interactivity,
no new IPC protocol, and the NSView mount substrate already exists; not S because
the charting reimplementation (path smoothing + scroll animation) is real work
and easy to get visually wrong.
