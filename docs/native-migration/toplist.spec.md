# Native-conversion spec — TOPLIST panel

Source of truth (read these, don't re-derive):
- `src/classes/toplist.class.js`
- `src/assets/css/mod_toplist.css` (the always-visible mini list)
- `src/assets/css/mod_processlist.css` (the expanded modal table — applies only inside the modal)
- `src/assets/css/mod_column.css` (shared column layout)
- `src-tauri/src/sysinfo_service.rs` + `src-tauri/src/sysinfo_cmds.rs` (data: `panel_snapshot` / `si_panel_snapshot`)
- `src/renderer.js` line ~344 (instantiation)
- `src/classes/modal.class.js` (Modal contract this panel depends on)
- `src-tauri/src/native_modal.rs` + `native_modal_notify` (native modal pilot)
- `src-tauri/src/native_mount.rs` + `src/bridge/native_mount.js` (mount seam)

---

## 1. Summary

`Toplist` is the bottom panel of the left column (`#mod_column_left`). It renders a compact, always-on "TOP PROCESSES" table — the 5 hottest processes by CPU+memory score, one row each showing `PID | NAME | CPU% | MEM%` — refreshed every 2 s. The whole panel element is clickable: clicking anywhere on it opens a **large modal** (`new Modal`, type `custom`) titled "Active Processes" that lists *all* processes in a wider, **column-sortable** table (PID / Name / User / CPU / Memory / State / Started / Runtime), refreshed every 1 s while open. This is the **only left-column panel that is interactive** (click → modal) and the only one that touches `window.term` / `window.currentTerm` / `window.keyboard`. **Important correctness note: in this v3 codebase the modal is read-only — there is NO process-kill button, no kill control, and no kill IPC anywhere in `toplist.class.js`.** The brief's "process-kill flow" describes intent/history, not current behavior; this spec documents exactly what exists and flags the kill flow as a *to-be-built* native prerequisite.

---

## 2. Data contract

### Backend data calls

Both call sites use the **same** command, `si_panel_snapshot`, with different args. The `window.si` Proxy maps `window.si.panelSnapshot(...)` → `invoke("si_panel_snapshot", {...})`. **The Proxy passes positional JS args; the Tauri command signature accepts them as named keys `collapse_threads_by_name`, `top_limit`, `include_process_list`.** (Verify the Proxy in `src/bridge/sysinfo.js` actually maps positional → named for this command — the snapshot call uses three positional args, unlike the no-arg `si_*` calls. If the Proxy does not special-case it, this is a latent bug the native port sidesteps entirely by calling `SysinfoService::panel_snapshot` directly.)

| Call site | JS call | Args (positional) | → command params | Cadence | Response fields consumed |
|---|---|---|---|---|---|
| Mini list (`updateList`) | `window.si.panelSnapshot(collapse, 5, false)` | `collapse_threads_by_name = settings.excludeThreadsFromToplist === true`; `top_limit = 5`; `include_process_list = false` | `si_panel_snapshot` → `SysinfoService::panel_snapshot(collapse, 5, false)` | `setInterval` **2000 ms** (+ one call at construct) | Reads only `data.topProcesses[]`, each row's `pid`, `name`, `cpu`, `mem`. (Other PanelSnapshot fields — `cpu`, `currentLoad`, `cpuTemperature`, `processCount`, `mem` — are ignored here; sysinfo/cpuinfo/ramwatcher consume those.) |
| Modal list (`updateProcessList`) | `window.si.panelSnapshot(collapse, 5, true)` | same `collapse`; `top_limit = 5`; `include_process_list = true` | `si_panel_snapshot(collapse, 5, true)` | `setInterval` **1000 ms** while modal open | Reads only `snapshot.processList` (`.list[]`). Per row consumes: `pid`, `name`, `user`, `cpu`, `mem`, `state`, `started` (ISO string). Computes `runtime` client-side = `now − Date.parse(started)`. **Does NOT use `topProcesses` here**, even though `top_limit:5` is still requested (wasted work the native port can drop). |

### Exact response field shapes (from `sysinfo_service.rs`, `#[serde(rename_all = "camelCase")]`)

- `PanelSnapshot.topProcesses` = `Vec<ProcessTopRow>` → `{ pid: u32, name: String, cpu: f64, mem: f64 }`. `cpu` is raw `cpu_usage()` percent; `mem` is `memory * 100 / total_memory` (already a percent of total RAM).
- `PanelSnapshot.processList` = `Option<ProcessList>` (omitted from JSON when `include_process_list == false`, via `skip_serializing_if`). `ProcessList = { all, running, blocked, sleeping, list: Vec<ProcessRow> }`. JS reads only `.list`.
- `ProcessRow` = `{ pid: u32, name, cpu: f64, mem: f64, started: String (ISO "YYYY-MM-DDThh:mm:ssZ"), state: String (Debug-formatted sysinfo status, e.g. "Run"/"Sleep"), user: String (numeric uid string from `user_id()`, often empty), command: String }`. JS ignores `command`.

### Backend semantics worth porting verbatim

- **Sorting / truncation of `topProcesses` happens in Rust** (`panel_snapshot`): score = `cpu*100 + mem`, descending, then `truncate(top_limit.max(1))`. The mini list trusts Rust's order as-is.
- **`collapse_threads_by_name`** (driven by `settings.excludeThreadsFromToplist`): when true, Rust groups rows sharing a `name` — sums cpu+mem, keeps the lowest pid (`collapse_top_rows_by_name` / `collapse_process_rows_by_name`). Applies to BOTH `topProcesses` and `processList`.
- **No TTL cache on this path.** Unlike `si_processes`/`si_mem`, `panel_snapshot` always does a fresh `refresh_cpu_all + refresh_memory + refresh_processes_specifics(All, true, everything()) + components.refresh()`. It is the heaviest sysinfo command; the 1 s modal poll re-runs the full refresh each tick.

### `window.settings.*` flags read
- `window.settings.excludeThreadsFromToplist` — boolean; read fresh on **every** `updateList` and `updateProcessList` tick (so toggling it takes effect on the next poll without re-instantiation).
- Native gating flags (`experimentalNativePanels` / `experimentalNativeModal`) are owned by `renderer.js` / `modal.class.js`, not by `Toplist` directly.

### `window.theme.*` values read
- **None** read in JS. All theming is via CSS custom properties (see §4). `window.theme.{r,g,b}` exist but this panel reaches color only through `var(--color_r/g/b)` in CSS.

---

## 3. DOM structure

### Always-visible mini panel (built in constructor into `#mod_column_left`)

```
div#mod_toplist                                  (static; this.onclick = processList)
 ├─ h1  "TOP PROCESSES"  <i>PID | NAME | CPU | MEM</i>   (static header + sub-label)
 ├─ br
 └─ table#mod_toplist_table                       (static container)
      └─ tr × up-to-5                             (DYNAMIC — fully rebuilt each 2 s tick)
           ├─ td  {pid}
           ├─ td  <strong>{name}</strong>
           ├─ td  {round(cpu,1)}%
           └─ td  {round(mem,1)}%
```
- `updateList()` clears via `document.querySelectorAll("#mod_toplist_table > tr").forEach(el => el.remove())` then re-appends — **no diffing, full teardown/rebuild every tick.** (Note the selector is global `#...`, not scoped to `this`, but ids are unique so it's fine in practice.)

### Expanded modal table (built by `processList()` via `new Modal`, type `custom`)

The Modal wraps this HTML (CSS in `mod_processlist.css`):
```
table#processContainer                           (scroll container, max-height 60vh)
 ├─ thead > tr
 │    └─ td.{pid|name|user|cpu|mem|state|started|runtime}.header  ("PID"…"Runtime")
 │         (each .header is click-to-sort; click handler appends ▲/▼ to its text)
 └─ tbody#processList
      └─ tr × N (all processes)                  (DYNAMIC — fully rebuilt each 1 s tick)
           └─ td.pid / td.name / td.user / td.cpu / td.mem / td.state / td.started / td.runtime
```
- Modal chrome (the outer `#modal_<uuid>`, `<h1>` title, Close button, `augmented-ui` frame, draggable header) is supplied by `Modal` — see §5.

---

## 4. Visual spec

### Mini panel (`mod_toplist.css`)
- `div#mod_toplist`: `border-top: 0.092vh solid rgba(var(--color_r),var(--color_g),var(--color_b),0.3)`; `font-family: var(--font_main_light)`; `letter-spacing: 0.092vh`; `padding: 0.645vh 0`; `display: flex; flex-wrap: wrap`. **All sizing is `vh`/`vw`-relative** (resolution-independent eDEX convention).
- Decorative tick marks via `::before` (left border stub, offset up/left) and `::after` (right border stub, pushed `right:-15.4vw; top:-12.7vh`) — small cyan corner accents drawn with `var(--color_*)` at 0.3 alpha. These are pure decoration.
- `:hover { cursor: pointer }` on the whole panel (signals clickability).
- `h1`: `font-size: 1.48vh`, negative `margin-bottom: -1vh` (pulls the table up under the header). The `<i>` sub-label: `font-size: 1.20vh`, `opacity: 0.5`, right-aligned, positioned `bottom: 1.6vh` (sits on the header's right side).
- `table#mod_toplist_table`: width 99%, `td` font-size `1.50vh`. Column constraints: **col 2 (name)** `min/max-width 7vw` + `overflow:hidden; text-overflow:ellipsis; white-space:nowrap` (truncates long names); **cols 3–4 (cpu/mem)** `text-align:right`, `min/max-width 2.4vw`.

### Modal table (`mod_processlist.css`)
- `table#processContainer`: `display:block; max-height:60vh; overflow:auto` (vertically scrollable).
- `td.header`: `font-weight:bold`, background `rgba(var(--color_r),var(--color_g),var(--color_b),0.6)` (accent fill), `color: var(--color_light_black)` (dark text on accent), centered, `:hover{cursor:pointer}` (sortable affordance).
- Fixed per-column widths in `vw`: pid 5, name 12, user 7, cpu 3 (centered), mem 3 (centered), state 6 (centered), started 11, runtime 5.

### Theme custom properties consumed (all from the injected `:root` block in `renderer.js`, fed by the active theme JSON)
| CSS var | Theme JSON source | Use |
|---|---|---|
| `--color_r/g/b` | `colors.r/g/b` (ints) | border/tick accents, header fill |
| `--color_light_black` | `colors.light_black` | header text color (dark) |
| `--font_main_light` | `cssvars.font_main_light` | panel font |

### Borders / augmented-ui / animation
- **`augmented-ui` is NOT used by the toplist tables themselves.** It appears only on the *Modal frame* (`Modal` adds `augmented-ui="tr-clip bl-clip exe"` for `custom` type — see §5), so the clipped-corner look is a Modal concern, not a toplist concern.
- No CSS `@keyframes`/transitions defined for toplist directly. The only animation is the shared column fade-in from `mod_column.css` (`section.mod_column` opacity transition + `> div` `fadeIn` keyframe, play-state toggled by the boot `tickHandle` in `renderer.js`). The Modal contributes its own `blink` close animation and audio cues.

---

## 5. Interaction & coupling surface (CRITICAL)

This is the most coupled left-column panel. Trigger and globals:

**Trigger:** `this._element.onclick = this.processList` — any click on the mini panel runs `processList()`. (Note: assigned as a bare reference, so inside `processList` `this` is the clicked element, not the `Toplist` instance — which is why everything in `processList` is self-contained locals/closures and never touches instance state.)

**`processList()` sequence (exact):**
1. `window.keyboard.detach()` — detaches the on-screen keyboard's key event listeners before the modal mounts.
2. `new Modal({ type: "custom", title: "Active Processes", html: <#processContainer table> }, onclose)` — the `onclose` callback sets a closure flag `removed = true`. (It does **not** itself `clearInterval`; the interval self-clears on its next tick via `if (removed) clearInterval(updateInterval)`. There is a commented-out `//clearInterval(updateInterval)` — a latent ~1 s leak window where one more poll fires after close. Native port should clear synchronously on close.)
3. Wire sort: iterate `document.getElementsByClassName("header")`, add a click listener per header that strips any existing ▲/▼ from all headers, calls `setSortKey(title)` (3-state cycle: none → desc → asc → none), and re-appends the arrow glyph. Sorting is done **client-side** in `updateProcessList` via a big `switch(sortKey)` over PID/Name/User/CPU/Memory/State/Started/Runtime; default sort = `(b.cpu-a.cpu)*100 + b.mem-a.mem` (mirrors Rust's top-score).
4. `updateProcessList()` once immediately.
5. `window.keyboard.attach()` — re-attaches the on-screen keyboard.
6. `window.term[window.currentTerm].term.focus()` — **refocuses the active xterm terminal** so the keyboard's key events route back to the shell after the modal opened. `window.term` is the array/map of `Terminal` wrappers, `window.currentTerm` the active tab index; `.term` is the underlying xterm.js instance, `.focus()` is xterm's API.
7. `var updateInterval = setInterval(updateProcessList, 1000)` — the 1 s modal refresh.

**`updateProcessList()`** has its own local `currentlyUpdating` re-entrancy guard, fetches `panelSnapshot(collapse,5,true)`, bails if `!data || !data.list`, computes `runtime` per row, sorts client-side, then (if `!removed`) clears `#processList > tr` and rebuilds all rows; if `removed` it `clearInterval(updateInterval)` and stops.

### The process-kill flow — current state
- **There is none in this codebase.** No kill button, no `confirm`-style nested Modal, no `pty_kill`/SIGTERM/SIGKILL invocation, nothing reaching the PTY or shell from the process list. The modal is a sortable viewer only. (Historical eDEX forks added a per-row "kill" affordance that popped a confirm Modal and shelled out; that code is absent here.)
- **Closest existing kill primitive:** `pty.rs::pty_kill(id)` — but it kills an *internal PTY handle by eDEX PTY id*, not an arbitrary OS process by PID. It cannot serve a generic "kill this process from the list" feature. A new Rust command (e.g. `proc_kill(pid, signal)`) would be required (see §7/§8).

### Every `window.*` global touched by this panel
| Global | Where | Purpose |
|---|---|---|
| `window.si.panelSnapshot` | both update loops | the only data source |
| `window.settings.excludeThreadsFromToplist` | both update loops | collapse-by-name flag |
| `window.keyboard.detach()` / `.attach()` | `processList` open | quiesce on-screen keyboard around modal mount |
| `window.term[window.currentTerm].term.focus()` | `processList` open | restore terminal focus after modal |
| `window.currentTerm` | indexes into `window.term` | active tab |
| `new Modal(...)` (`window` global class) | `processList` | the expanded list container; **hard dependency on the Modal path** |
| `window.modals[...]` | indirectly via Modal | Modal's registry/close machinery |
| `window.audioManager.*` | indirectly via Modal | open/close/denied cues |
| `document.*` (getElementById, querySelectorAll, getElementsByClassName, createElement) | everywhere | DOM build/teardown |

### Modal contract depended upon
`Modal` with `type:"custom"` renders an in-DOM, draggable, `augmented-ui`-framed popup containing `options.html`, appends a "Close" button whose `onclick` calls `window.modals[id].close()`, and on close runs the `onclose` callback (here: set `removed=true`). The **native modal pilot (`native_modal_notify` / `native_modal.rs`) does NOT cover this case** — that path is explicitly gated to `this.type !== "custom"` (info/warning/error NSAlerts only). So today the process-list modal is *always* the legacy DOM modal even when `experimentalNativeModal` is on. A native toplist needs a **custom/content-bearing native modal** that does not yet exist.

---

## 6. Lifecycle

- **Constructor `(parentId)`**: throws on missing arg; `getElementById(parentId)` (always `"mod_column_left"`, per `renderer.js:344`); builds `#mod_toplist` with the header + empty `#mod_toplist_table`; sets `this._element.onclick = this.processList`; appends to parent; sets `this.currentlyUpdating = false`; calls `updateList()` once; starts `this.listUpdater = setInterval(updateList, 2000)`.
- **Instantiation order**: created last of the six left-column panels (after clock, sysinfo, hardwareInspector, cpuinfo, ramwatcher), so it sits at the bottom. The boot `tickHandle` then sets each panel's `animation-play-state: running` in sequence to stagger the fade-in.
- **Mini update loop**: 2000 ms, re-entrancy-guarded by `this.currentlyUpdating`; `.catch(()=>{})` swallows errors silently; `.finally` always clears the guard. Empty/missing data → `data.topProcesses || []` → renders nothing, no error.
- **Modal update loop**: 1000 ms, separate closure-local `currentlyUpdating` and `removed` flags; bails on `!data || !data.list`; `.catch` clears its guard; self-clears the interval on close.
- **Teardown**: **none.** There is no `destroy()`/`unload()`. `this.listUpdater` (2 s) is never cleared — it lives for the app's lifetime (acceptable since panels persist until reload). The modal interval is the only one cleaned up, and only lazily (next tick after `removed`).
- **Error/empty handling**: both loops fail silent; no UI error state, no "no data" placeholder.

---

## 7. Native mapping proposal

### View structure (AppKit-first; SwiftUI optional)
- **Mini panel** → a small fixed-height native view: a header label ("TOP PROCESSES" + the dim "PID | NAME | CPU | MEM" sub-label) over a 5-row list. A non-scrolling `NSStackView` of 5 row views, or a tiny `NSTableView` with 4 columns (PID, Name [truncating], CPU%, MEM% [right-aligned]). The whole view is a single click target (NSClickGestureRecognizer) that opens the expanded modal. Mirror CSS: accent top-border, dim sub-label, name truncation, right-aligned numeric columns; pull `--color_*` / `--color_light_black` / `--font_main_light` from the theme so it tracks theme swaps.
- **Expanded list** → an `NSPanel`/sheet (or SwiftUI `Window`/sheet) containing a sortable, scrolling **`NSTableView`** (8 columns: PID/Name/User/CPU/Memory/State/Started/Runtime). Use the table's built-in `sortDescriptors` for click-to-sort header behavior (replaces the manual ▲/▼ glyph + closure-state machine). Compute `Runtime` from `started` like the JS does, or add a `runtime_ms` field to `ProcessRow` in Rust so the view doesn't parse ISO strings.

### Data-flow choice
- **Call `SysinfoService` directly — no `invoke()`, no `window.si` Proxy.** The native renderer holds the `Arc<SysinfoService>` (the same `State` the commands use) and calls `panel_snapshot(collapse, 5, false)` for the mini list and `panel_snapshot(collapse, 5, true)` (or a leaner `processes()`-style query) for the modal. This eliminates the positional-vs-named arg ambiguity flagged in §2 and the per-tick IPC. Read `excludeThreadsFromToplist` from settings each tick (Rust settings store) to preserve live-toggle behavior.
- **Mount path**: extend the existing `native_mount.rs` NSView (the `#mod_column_left` sibling that already carries the clock pilot) to host the toplist mini view, gated behind `experimentalNativePanels`. The expanded list is a **separate window/panel**, not part of the mounted column view.

### Kill flow mapped natively (NEW work — does not exist today)
1. Native table row selection → a "Kill" action (context menu / button).
2. → native confirm modal. **This requires a content/confirm native modal** beyond today's `native_modal_notify` (which is OK-only NSAlert, non-custom). Either extend the NSAlert path to support a 2-button confirm returning the choice, or build a small custom native confirm.
3. On confirm → a **new Rust command** `proc_kill(pid: u32, signal: i32)` (e.g. via `libc::kill` / sysinfo's `Process::kill_with`), allow-listed in capabilities. Note: `pty_kill` is unsuitable (kills internal PTY handles by eDEX id, not OS PIDs). Killing non-owned PIDs will fail without privilege — surface the error in the UI.
4. No terminal/PTY routing is needed for kill (the legacy `term.focus()` step is only about restoring keyboard focus after the *DOM* modal; a native window won't steal xterm focus the same way, so that coupling largely disappears).

### Dependency on the native Modal path
Hard. The defining feature (click → big process list) needs a **custom/content-bearing native modal or window**, which the current pilot explicitly excludes (`type !== "custom"`). A confirm-capable native modal is an additional prerequisite for the *new* kill feature.

### Top 3 conversion risks
1. **No native custom-modal exists.** The whole expand-to-list interaction (and any future kill confirm) blocks on building a content/confirm native modal — the current `native_modal_notify` pilot can't render a table or return a choice.
2. **Kill is net-new, privileged, and easy to get wrong.** `proc_kill(pid,signal)` doesn't exist; it touches arbitrary OS processes, needs a capability + signal semantics + permission-failure handling. Reusing `pty_kill` would be incorrect.
3. **Cost of the 1 s full-snapshot poll, plus terminal-focus / keyboard quiescing.** `panel_snapshot(...,true)` does a full uncached process+cpu+mem+components refresh every second while the modal is open; native should consider a lighter query and reproduce the `keyboard.detach/attach` + terminal-focus dance (or prove it's unnecessary) so the on-screen keyboard and shell focus don't break when the native modal is up.

---

## 8. Sequencing note — convert LAST of the six

This panel must convert **after** clock, sysinfo, hardwareInspector, cpuinfo, and ramwatcher because:
- It is the **only** left-column panel with an interactive popup; the other five are read-only displays that map cleanly onto the existing `native_mount` column view. Toplist needs UI infrastructure they don't.
- It has a **hard dependency on a native custom modal** (content-bearing, and — for kill — confirm-capable) that does **not** exist yet. Today's pilot (`native_modal_notify`) only does OK-only NSAlerts for non-custom types.
- It couples to `window.term` / `window.currentTerm` / `window.keyboard` — the terminal and on-screen-keyboard subsystems. A native toplist modal must coexist with those (focus, key routing) or replace that coordination natively; that's only sensible once the terminal/keyboard story is settled.

### Native prerequisites (explicit)
1. A **content-bearing native modal/window** (table-hosting) — beyond the OK-only NSAlert pilot.
2. A **confirm-capable native modal** (2-button, returns choice) — for the kill feature.
3. A **new `proc_kill(pid, signal)` Rust command** + capability entry. **Checked: no general process-kill command exists** — `pty.rs::pty_kill(id)` only kills internal PTY handles by eDEX id, not OS PIDs, so it cannot be reused.
4. Native access to `SysinfoService::panel_snapshot` (already available via the shared `Arc` state) and to the `excludeThreadsFromToplist` setting each tick.

---

## 9. Effort estimate

**L (Large).** The mini list alone is S–M (a 5-row themed table over a direct `panel_snapshot` call). What pushes it to L is everything the interaction needs that doesn't exist yet: a content-bearing native modal/window with a sortable table, a confirm-capable native modal, a brand-new privileged `proc_kill` Rust command + capability, and reproducing the keyboard-detach / terminal-refocus coordination. It is the most coupled left-column panel and depends on infrastructure none of the other five require.
