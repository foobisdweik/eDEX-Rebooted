# Native-conversion spec — SYSINFO panel

Source of truth (read these, don't re-derive):
- `src/classes/sysinfo.class.js`
- `src/assets/css/mod_sysinfo.css`
- `src/assets/css/mod_column.css` (shared column layout)
- `src/bridge/sysinfo.js` (the `window.si` Proxy)
- `src-tauri/src/sysinfo_service.rs` + `src-tauri/src/sysinfo_cmds.rs` (data)
- `src/renderer.js` line ~340 (instantiation)
- `src-tauri/src/native_mount.rs` + `src/bridge/native_mount.js` (mount seam)

---

## 1. Summary

`Sysinfo` is a small four-cell status strip rendered into the left column (`#mod_column_left`). The cells display, left to right: the current **date** (year + `MON DD`), the system **uptime** (`Nd HH:MM`), the OS **type** (hard-coded `"macOS"`), and the **power** state (battery percentage, or `CHARGE` / `WIRED` / `ON`). The date is driven entirely by the browser clock; uptime and battery are polled from the Rust backend. It is a read-only display with no user interaction.

---

## 2. Data contract

### Backend data calls

| JS call | Proxy maps to command | Service method | Args | Cadence | Response fields consumed |
|---|---|---|---|---|---|
| `window.si.uptime()` | `si_uptime` | `SysinfoService::uptime()` | none | `setInterval` 60000 ms (+ one call at construct) | returns a bare `u64` (seconds). JS does its own day/hour/minute math. |
| `window.si.battery()` | `si_battery` | `SysinfoService::battery()` | none | `setInterval` 3000 ms (+ one call at construct) | `hasBattery` (bool), `isCharging` (bool), `acConnected` (bool), `percent` (i64). **Only these 4 fields are read.** All other `BatteryInfo` fields (cycleCount, capacities, voltage, model, etc.) are ignored by this panel. |

Notes:
- `window.si.uptime` is mapped by the Proxy's camelCase→snake_case rule (`bridge/sysinfo.js`, the generic `"si_" + prop.replace(...)` path); no special payload handling, called with `{}`.
- `si_uptime` and `si_system` are **synchronous** Tauri commands (`#[tauri::command] pub fn`), not async/blocking. `si_battery` is async and dispatched onto a blocking worker thread (`blocking(...)` in `sysinfo_cmds.rs`); each `battery::Manager::new()` call rebuilds the battery handle every poll.
- The OS `TYPE` cell is NOT a data call — it is a const string `"macOS"` baked into the constructor (the historical `require("os")` path is gone per ULTRAPLAN). A native port should likewise hard-code it or derive once from `System::os_version()` via `SysinfoService::system()` (`si_system`).

### Browser-local data (no backend)
- **Date cell**: `new Date()` — `getFullYear()`, `getMonth()` (mapped to a 3-letter month via a switch), `getDate()`. Refreshed via a self-rescheduling `setTimeout` that fires at the next local midnight (`timeToNewDay` computed from current hours/minutes), not a fixed interval.

### `window.settings.*` flags read
- **None directly.** `Sysinfo` reads no settings. (For native gating, the relevant external flags are `window.settings.experimentalNativePanels`, `experimentalNativeClock`, `experimentalNativeModal` — owned by `renderer.js` / `native_mount.js`, not this class.)

### `window.theme.*` values read
- **None in JS.** Theming is purely via CSS custom properties resolved at render time: `--color_r/_g/_b` and `--font_main_light`. These are injected once into `<style class="theming">` by `renderer.js::_loadTheme` from `theme.colors.{r,g,b}` and `theme.cssvars.font_main_light`.

---

## 3. DOM structure

Built by appending to `this.parent.innerHTML` (so it is a sibling of the other panels inside `#mod_column_left`):

```
#mod_sysinfo                       (flex row, static container)
 ├─ div                            (cell 1 — DATE, dynamic)
 │   ├─ h1   "1970"   → year       (textContent replaced by updateDate)
 │   └─ h2   "JAN 1"  → "MON DD"   (textContent replaced by updateDate)
 ├─ div                            (cell 2 — UPTIME)
 │   ├─ h1   "UPTIME"              (static label)
 │   └─ h2   "0:0:0"  → uptime     (innerHTML replaced; embeds <span style="opacity:0.5"> for the d / : separators)
 ├─ div                            (cell 3 — TYPE)
 │   ├─ h1   "TYPE"                (static label)
 │   └─ h2   "macOS"              (static, set once at construct)
 └─ div                            (cell 4 — POWER)
     ├─ h1   "POWER"              (static label)
     └─ h2   "00%"   → power      (textContent replaced by updateBattery)
```

- **Static:** the `#mod_sysinfo` container, all `h1` labels, the TYPE value, and the `::before`/`::after` pseudo-element border ticks.
- **Dynamic:** the year `h1`, the date `h2`, the uptime `h2` (note: **`innerHTML`** with embedded opacity spans), the power `h2`.
- **Selector coupling (fragile):** all updates target cells by structural position — `#mod_sysinfo > div:first-child`, `:nth-child(2)`, `:last-child`. There are no ids/classes on the cells. Reordering cells breaks updates.

---

## 4. Visual spec

From `mod_sysinfo.css` (all sizes are viewport-height relative — `vh`):

- **Container `#mod_sysinfo`:** `display:flex; flex-direction:row; align-items:center; justify-content:space-between`. `height: 5.556vh`. `font-size: 1.111vh`. `font-family: var(--font_main_light)`. `letter-spacing: 0.092vh`.
- **Top border:** `border-top: 0.092vh solid rgba(var(--color_r), var(--color_g), var(--color_b), 0.3)` — themed accent color at 30% opacity.
- **Corner ticks:** `::before` (left) and `::after` (right) pseudo-elements draw short vertical 1px-ish lines (`0.833vh` tall, `0.092vh` wide) in the same `rgba(--color_r/_g/_b, 0.3)`, offset `top:-2.87vh` to sit above the strip. Decorative bracket accents.
- **Cells `#mod_sysinfo div`:** `height:100%; box-sizing:border-box; padding:0.925vh 0.46vh; display:flex; flex-direction:column; align-items:flex-start; justify-content:space-around`.
- **Labels `h1`:** `margin:0; opacity:0.5` (dimmed).
- **Values `h2`:** `margin:0` (full opacity). Uptime separators (`d`, `:`) are individually dimmed to 0.5 via inline span styles.
- **No `augmented-ui`** on this panel. **No CSS animations/transitions** declared in `mod_sysinfo.css` itself.
- **Inherited from `mod_column.css`:** the panel rides the column's fade-in. The column starts `opacity:0` with `transition: opacity .5s` and is revealed by adding `.activated`; each direct child `div` also runs a one-shot `@keyframes fadeIn` (0→1, `.5s`) that is `animation-play-state: paused` until `renderer.js`'s staggered tick sets it `running`. `#mod_column_left` is right-aligned (`align-items:flex-end`).

### Theme custom properties to honor in native
- `--color_r`, `--color_g`, `--color_b` → the accent RGB (border + ticks at 0.3 alpha; text presumably inherits the column's accent via global rules).
- `--font_main_light` → the light-weight UI font for the strip text.
- Source values live on `window.theme.colors.{r,g,b}` and `window.theme.cssvars.font_main_light` (injected by `renderer.js`).

---

## 5. Lifecycle

- **Constructor** `new Sysinfo(parentId)` — takes a container **element id string** (called as `new Sysinfo("mod_column_left")`); throws `"Missing parameters"` if falsy. Resolves `document.getElementById(parentId)`, appends the DOM via `innerHTML +=`, then immediately:
  - `updateDate()` (synchronous, schedules its own midnight `setTimeout`).
  - `updateUptime()` (async, first paint) + `this.uptimeUpdater = setInterval(updateUptime, 60000)`.
  - `updateBattery()` (first paint) + `this.batteryUpdater = setInterval(updateBattery, 3000)`.
- **Three independent timers run concurrently:**
  1. uptime — `setInterval` 60 s.
  2. battery — `setInterval` 3 s.
  3. date — self-rescheduling `setTimeout` to next midnight.
- **Teardown:** **none.** No `destroy()`/`stop()` method; the interval handles (`uptimeUpdater`, `batteryUpdater`) and the date `setTimeout` are stored but never cleared. The class assumes a single instance for the app lifetime (consistent with `window.mods.sysinfo`). The midnight `setTimeout` is not even stored, so it cannot be cancelled.
- **Error / empty handling:**
  - Uptime: no try/catch — a rejected `si_uptime` would surface to the global `window.onerror` graphical error modal.
  - Battery: `.then()` only, no `.catch()` — a rejected promise is unhandled.
  - `BatteryInfo::absent()` (no battery present) returns `hasBattery:false`, which the JS renders as `"ON"`. `ac_connected` defaults to `true` in the absent case (irrelevant since `hasBattery` short-circuits).

---

## 6. Coupling & interactions

- **Globals consumed:** `window.si.uptime`, `window.si.battery` (the Proxy in `bridge/sysinfo.js`), `document` (id lookup + structural querySelectors), `Date`, `setInterval`/`setTimeout`.
- **Instantiated by:** `renderer.js` (~line 340) as `window.mods.sysinfo`, in the panel boot block alongside `clock`, `hardwareInspector`, `cpuinfo`, `ramwatcher`, `toplist` — all sharing `#mod_column_left`.
- **Shared-container coupling (cross-panel):** Sysinfo is one of six panels appended into the same `#mod_column_left` via `innerHTML +=`. The staggered fade-in (`renderer.js`'s `tickHandle` setInterval over `#mod_column_left > div`) and the column `.activated` class drive its reveal. A native conversion of *only* Sysinfo must coexist with the still-JS siblings unless the whole column is migrated together.
- **Native-mount coupling:** `native_mount.rs` mounts a single NSView over `#mod_column_left` (the geometry source) and `body.native-left-active` hides the entire JS column. So enabling the native mount hides Sysinfo *and* all five siblings at once — the seam is column-granular, not panel-granular. The current pilot in the NSView is the clock layer only.
- **Writes back:** **nothing.** No state mutation, no settings/theme writes, no events emitted, no other class invoked.
- **No dependency on other `window.mods.*` instances.**

---

## 7. Native mapping proposal

### View structure (SwiftUI)
A single horizontal strip, four equal cells, each a label-over-value VStack:

```
SysinfoStrip (HStack, .distributed/.spaceBetween, top accent border + corner ticks)
 ├─ SysinfoCell(label: "",       value: yearString,   subValue/own layout for "MON DD")
 ├─ SysinfoCell(label: "UPTIME", value: uptimeString)   // "Nd HH:MM" with dimmed separators
 ├─ SysinfoCell(label: "TYPE",   value: "macOS")          // static
 └─ SysinfoCell(label: "POWER",  value: powerString)      // "NN%" / CHARGE / WIRED / ON
```

- Cell = `VStack(alignment: .leading)` with a 50%-opacity caption (`h1`) over a full-opacity value (`h2`). Date cell is the odd one (two stacked values, no dim label) — model it as its own cell variant.
- Accent color from theme RGB at 0.3 alpha for the top rule + the two corner ticks (overlay shapes). Use the `--font_main_light` equivalent (a custom registered font) for the strip text.
- Drive the staggered fade-in with a SwiftUI opacity transition keyed to an injected "activated" flag so it matches the column reveal timing.

### Data flow — **recommended: direct `SysinfoService` query, not the `nativeMount` text-poke bridge**
- A native renderer can hold an `Arc<SysinfoService>` (already `.manage()`d) and call `.uptime()` and `.battery()` directly — no `invoke()`, no `si_*` round-trip. This matches the stated migration goal.
- Replicate the JS cadence on a native timer: uptime every 60 s, battery every 3 s, date at local-midnight rollover (use `Calendar` to compute the next boundary rather than a fixed interval).
- The existing `native_mount_set_clock_text` style of pushing pre-formatted strings from JS is the *clock pilot's* pattern and is the wrong fit here — it would keep JS in the loop. Prefer the native view owning its own timers + service handle. The `native_mount.rs` NSView is still the right *host* (geometry over `#mod_column_left`); just give it a real sublayer/SwiftUI-hosted strip instead of a text layer.
- Do the day/hour/minute decomposition and the month-name mapping in Swift/Rust (the JS math is trivial to port: days/86400, etc.).

### Top 3 conversion risks
1. **Column-granular mount seam.** `body.native-left-active` + the single NSView hide/host the *entire* left column. You cannot natively render Sysinfo alone without either (a) migrating all six panels together, or (b) introducing finer-grained per-panel mount slots. This is the dominant architectural risk.
2. **Battery semantics & polling cost.** `si_battery` rebuilds `battery::Manager::new()` on every 3 s poll; the panel only needs 4 booleans/ints. The `acConnected`→`WIRED`, `isCharging`→`CHARGE` precedence (charging checked before AC) and the `hasBattery:false`→`ON` fallback must be reproduced exactly, and `BatteryInfo::absent()` sets `ac_connected:true` — easy to mis-map. Consider a lighter battery query for the native path.
3. **Date correctness across the midnight boundary.** The JS uses a self-rescheduling `setTimeout` to local midnight; a naive fixed-interval native timer will drift or update mid-day. Use a proper next-midnight calculation, and re-arm on system wake/timezone change (the JS version doesn't handle wake either — opportunity to improve, but watch for a stale date after sleep).

Minor: structural-selector fragility disappears in native (cells become typed views), and the uptime value's inline opacity spans become styled `Text` runs — straightforward.

---

## 8. Effort estimate

**S (small).** Four cells, two trivial backend reads (`uptime`, `battery`) already exposed on `SysinfoService`, no user interaction, no write-back, no animation beyond a shared fade-in. The only non-trivial pieces are the midnight date rollover and matching the battery state precedence. The *real* cost is the shared `#mod_column_left` mount-seam decision (risk #1), which is a column-wide concern rather than a Sysinfo-specific one — on its own, this panel is a half-day port.
