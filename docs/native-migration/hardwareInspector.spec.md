# Native-conversion spec — `hardwareInspector` panel

Source of truth:
- `src/classes/hardwareInspector.class.js`
- `src/assets/css/mod_hardwareInspector.css`
- `src/assets/css/mod_column.css` (shared column layout)
- `src-tauri/src/sysinfo_service.rs` (`system()`, `chassis()`, structs `SystemInfo` / `ChassisInfo`)
- `src-tauri/src/sysinfo_cmds.rs` (`si_system`, `si_chassis`)
- `src/renderer.js:341` (instantiation), `src/renderer.js:118-145` (theme CSS-var injection)

---

## 1. Summary

`HardwareInspector` is one of the small static read-only info blocks in the left column. It shows three labeled fields — **MANUFACTURER**, **MODEL**, **CHASSIS** — describing the host machine. Each field is a small uppercase caption (`h1`) over a dimmed value (`h2`). The values are fetched from the Rust sysinfo backend once at construction and then re-polled every 20 seconds. There is no user interaction, no scrolling, no graphing — it is purely a three-line static display whose only dynamic behavior is occasionally rewriting three text nodes.

---

## 2. Data contract

### Backend calls

| JS call | Bridge command (camelCase → snake_case) | `SysinfoService` method | Args | Returns |
|---|---|---|---|---|
| `window.si.system()` | `si_system` | `SysinfoService::system()` | none | `SystemInfo` |
| `window.si.chassis()` | `si_chassis` | `SysinfoService::chassis()` | none | `ChassisInfo` |

Both commands are synchronous in Rust (no `blocking`/async wrapper — they return the struct directly) and on the JS side resolve as promises via `invoke()`.

### Polling cadence

- `updateInfo()` is called once in the constructor, then on a `setInterval(..., 20000)` — **every 20,000 ms (20 s)**.
- The interval handle is stored as `this.infoUpdater` but is **never cleared** (no teardown — see §5).

### Call chaining (important nesting)

`updateInfo()` chains the two calls — `chassis()` is only issued **inside** the `.then()` of `system()`, and the DOM is written only inside the inner `.then()`:

```js
window.si.system().then(d => {
    window.si.chassis().then(e => {
        // d = SystemInfo, e = ChassisInfo
        manufacturer.innerText = _trimDataString(d.manufacturer);
        model.innerText        = _trimDataString(d.model, d.manufacturer, e.type);
        chassis.innerText      = e.type;
    });
});
```

So a native port must await/serialize both queries before painting, or do one combined query.

### Response fields actually consumed

From `SystemInfo` (`d`):
- `d.manufacturer` → MANUFACTURER value (passed through `_trimDataString`, no filters → first 2 space-split words).
- `d.model` → MODEL value (passed through `_trimDataString` with filter list `[d.manufacturer, e.type]` → strips any word equal to the manufacturer or chassis type, then keeps first 2 words).

From `ChassisInfo` (`e`):
- `e.type` → CHASSIS value (used **raw**, no trimming) **and** as a filter word for the model.

Unused fields (present in the structs but never read): `SystemInfo.version/serial/uuid/sku`; `ChassisInfo.manufacturer/model/version/serial/assetTag/sku`.

### Current backend values (macOS stub)

The Rust implementations are **hardcoded stubs**, not real SMBIOS/IORegistry reads:
- `system()` → `manufacturer = "Apple"`, `model = System::host_name()`, rest empty.
- `chassis()` → `manufacturer = "Apple"`, `model = host_name()`, `type = "Laptop"`, `version = kernel_version()`, rest empty.

So today the panel renders roughly: MANUFACTURER = `Apple`, MODEL = host-name (first 2 words, with "Apple"/"Laptop" filtered), CHASSIS = `Laptop`. A native port inherits this stub limitation — if the goal is real Mac model/chassis data, that work belongs in `SysinfoService`, not in the view.

### `serde` field-rename note

`ChassisInfo.chassis_type` is serialized as `"type"` (`#[serde(rename = "type")]`), which is exactly why the JS reads `e.type`. A native renderer calling `SysinfoService::chassis()` directly gets the Rust field name `chassis_type` and skips this rename entirely.

### `window.settings.*` flags read

- **None directly.** The panel reads no settings.
- Indirectly relevant: `window.settings.experimentalNativePanels` (gate in `renderer.js:369`) hides the entire `#mod_column_left` JS column via `body.native-left-active`, which would hide this panel too. There is no per-panel `experimentalNativeHardwareInspector` flag today (clock/modal have their own gates; this panel does not).

### `window.theme.*` values read

- **None read in JS.** The class never touches `window.theme`.
- The CSS consumes theme **CSS custom properties** injected into `:root` by `renderer.js:118-131`: `--color_r`, `--color_g`, `--color_b` (theme RGB), and `--font_main_light` (theme light font family). These come from `theme.colors.{r,g,b}` and `theme.cssvars.font_main_light`.

---

## 3. DOM structure

Built once in the constructor into the parent passed by id (`mod_column_left`):

```
#mod_hardwareInspector                 (outer div, appended to parent)
└─ #mod_hardwareInspector_inner        (flex row, wraps)
   ├─ div
   │  ├─ h1  "MANUFACTURER"            (static label)
   │  └─ h2#mod_hardwareInspector_manufacturer  "NONE"   (dynamic value)
   ├─ div
   │  ├─ h1  "MODEL"                   (static label)
   │  └─ h2#mod_hardwareInspector_model         "NONE"   (dynamic value)
   └─ div
      ├─ h1  "CHASSIS"                 (static label)
      └─ h2#mod_hardwareInspector_chassis       "NONE"   (dynamic value)
```

- **Static:** the wrapper divs, the three `h1` labels, the ids. Built once via `innerHTML`; never rebuilt.
- **Dynamic:** only the `.innerText` of the three `h2#...` elements. Initial placeholder text is `"NONE"` until the first `updateInfo()` resolves.
- `::before` / `::after` pseudo-elements on `#mod_hardwareInspector` draw two short vertical tick marks (decorative bracket flanks); no DOM nodes.

---

## 4. Visual spec

From `mod_hardwareInspector.css` (sizes are viewport-height units, `vh`):

### Outer container `#mod_hardwareInspector`
- `display: flex`.
- `border-top: 0.092vh solid rgba(var(--color_r), var(--color_g), var(--color_b), 0.3)` — thin theme-colored top rule at 30% alpha. This is the visual separator between stacked column panels.
- `font-family: var(--font_main_light)` (theme light font).
- `letter-spacing: 0.092vh`.
- `padding: 0.645vh 0`.

### Decorative tick marks
- `::before`: `border-left` 0.092vh solid theme color @30%, `height: 0.833vh`, offset `left: -0.092vh; top: -1.111vh`, `align-self: flex-start`. Small vertical tick on the left edge rising above the top border.
- `::after`: mirror on the right (`border-right`, `right: -0.092vh`, same height/top).
- Net effect: a thin top rule capped by two short vertical ticks — a subtle "bracket" header motif shared by the column panels.

### Inner row `#mod_hardwareInspector_inner`
- `display: flex; flex-direction: row; align-items: center; justify-content: space-evenly; flex-wrap: wrap; width: 100%`.
- The three field blocks are spaced evenly across the full width and wrap if the column is too narrow.

### Field blocks `> div`
- `text-align: left`.

### Text `> div > *` (all h1/h2)
- `font-size: 1.3vh; line-height: 1.5vh; margin: 0`.

### Value `> div > h2`
- `opacity: 0.5` — the value line is rendered at half opacity (dimmed) vs. the full-opacity label.

### Colors / theming summary
- Only theme-driven values are the **border/tick color** (`--color_r/g/b` at 0.3 alpha) and the **font** (`--font_main_light`). Text color itself is inherited (default body text color, typically the theme foreground via `body` styling), not set here.

### `augmented-ui`
- **Not used** by this panel. No `data-augmented-ui` attribute, no `--aug-*` vars. (Contrast with `main_shell.css` which does use it.)

### Animations / transitions
- This panel's own CSS has **none**.
- It inherits the column fade-in from `mod_column.css`: each `section.mod_column > div` runs the `fadeIn` keyframe (opacity 0→1, 0.5s, `cubic-bezier(0.4,0,1,1)`, `forwards`, initially `paused`). The renderer's staggered boot loop (`renderer.js:352-359`) flips `animation-play-state: running` panel-by-panel with an audio cue, producing the sequential reveal. The column section itself also has `opacity 0 → 1` transition (0.5s) gated by the `.activated` class.

---

## 5. Lifecycle

- **Constructor:** `new HardwareInspector(parentId)`. Throws `"Missing parameters"` if `parentId` is falsy. `parentId` is the **element id string** (`"mod_column_left"`), not a node — it does `document.getElementById(parentId)` and `append`s its element. (Note: other column panels pass an id too; this one is an id-string contract.)
- **Init:** builds DOM via `innerHTML`, appends, calls `updateInfo()` immediately, then starts `setInterval(updateInfo, 20000)`.
- **Update loop:** `updateInfo()` — chained `system().then(chassis().then(...))`, writes three `innerText`s. Runs every 20s.
- **Teardown:** **none.** No `destroy()`/`dispose()` method; `this.infoUpdater` interval is never cleared and `this._element` is never removed. The panel lives for the lifetime of the WKWebView. (Relevant for native: a native view will need an explicit stop for its polling timer.)
- **Error / empty handling:** **none.** No `.catch()` on either promise; if `si_system`/`si_chassis` rejects, the chain silently fails and the fields keep their previous value (or the `"NONE"` placeholder on first load). `_trimDataString` assumes `str` is a string and calls `.trim()` — a `null`/`undefined` field would throw inside the (uncaught) promise. Given the Rust stubs always return strings, this never fires today.

### `_trimDataString(str, ...filters)` behavior
- `str.trim().split(" ")` → words.
- Filters out any word present in `filters` (the `typeof filters !== "object"` guard is effectively dead — rest params are always an array/object — so the filter list always applies).
- `.slice(0, 2)` → keep at most first 2 words; `.join(" ")`.
- Used to compress potentially long manufacturer/model strings to two words and drop redundant words (e.g. don't repeat "Apple" inside the model when it's already the manufacturer).

---

## 6. Coupling & interactions

- **Container coupling:** mounted into `#mod_column_left` (left column) alongside `clock`, `sysinfo`, `cpuinfo`, `ramwatcher`, `toplist` (`renderer.js:339-344`). Render order matters only for the staggered fade-in animation; no data sharing between panels.
- **Globals consumed:** `window.si` (the sysinfo Proxy from `bridge/sysinfo.js`) and `document`. Nothing else.
- **Globals written:** registers itself at `window.mods.hardwareInspector` (done by renderer, not by the class). The class writes nothing back to any shared state, settings, or backend — it is read-only.
- **User interactions:** **none.** No click/hover/keyboard handlers. Purely passive display.
- **Cross-panel deps:** **none functional.** The only shared concern is the `body.native-left-active` seam (`mod_column.css:76`): activating the experimental native mount hides the whole left JS column, so this panel cannot be migrated to native in isolation while the others stay JS *unless* the native column hosts all six (or the migration uses per-panel slotting). Flag: **the native mount currently replaces the entire `#mod_column_left`, not individual panels.**
- **Theme dependency:** indirect, via injected CSS vars (§2/§4). No JS coupling to `window.theme`.

---

## 7. Native mapping proposal

### Data-flow choice
**Direct `SysinfoService` query — no `invoke()`, no `nativeMount` text-push bridge.** The native view should hold an `Arc<SysinfoService>` (already a managed Tauri state) and call `service.system()` + `service.chassis()` directly on a 20 s timer on the Rust/native side. These are cheap synchronous stub reads; there is no benefit to round-tripping through JS. (The existing `nativeMount.setClockText` push-from-JS pattern used for the clock pilot is the wrong fit here — that exists because the clock value is computed in JS; hardware info originates in Rust, so pull it natively.)

### Suggested view structure (SwiftUI)
A tiny three-row info block. SwiftUI is the natural fit:

```swift
struct HardwareInspectorView: View {
    @StateObject var model: HardwareInspectorModel   // polls every 20s
    var body: some View {
        VStack(spacing: 0) {
            TopRuleWithTicks()                        // border-top + ::before/::after ticks
            HStack(alignment: .center) {              // #..._inner: row, space-evenly, wrap
                Spacer()
                field("MANUFACTURER", model.manufacturer)
                Spacer()
                field("MODEL", model.model)
                Spacer()
                field("CHASSIS", model.chassis)
                Spacer()
            }
        }
    }
    func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).opacity(1.0)                  // h1
            Text(value).opacity(0.5)                  // h2 (dimmed)
        }
    }
}
```

- `HardwareInspectorModel` (`@MainActor` `ObservableObject`): a `Timer.publish(every: 20)` (plus an immediate first fire) that calls into Rust (`service.system()/chassis()`), applies the `_trimDataString` logic in Swift, and publishes `manufacturer/model/chassis`.
- Port `_trimDataString` verbatim: `str.split(" ").filter { !filters.contains($0) }.prefix(2).joined(separator: " ")`. CHASSIS stays raw.
- **Styling:** theme color (`--color_r/g/b`) and font (`--font_main_light`) must be supplied to the native view from the same theme source the WKWebView uses (`theme.colors` / `theme.cssvars`). The top rule + two tick marks can be a thin `Path`/`Rectangle` overlay at 30% theme alpha; the `vh`-based sizing maps to a function of the column's pixel height (the native mount already ships `#mod_column_left`'s bounding rect to Rust — reuse that geometry for sizing).
- No `augmented-ui`, no animation inside the panel; the column-level fade-in can be reproduced with a SwiftUI `.opacity`/`.transition` if the whole native column is staged, or skipped.

### Top 3 conversion risks
1. **Theme propagation.** Today the look is driven entirely by injected CSS custom properties (`--color_r/g/b`, `--font_main_light`). A native view has no `:root`. A theme-bridge (push current `theme.colors`/`cssvars` into native, and re-push on `themeChanger`) must exist before any column panel can look right — this is shared infrastructure, not panel-specific, and likely the gating dependency.
2. **All-or-nothing column mount.** The `body.native-left-active` seam hides the *entire* `#mod_column_left`. You cannot ship a native HardwareInspector while clock/sysinfo/cpuinfo/ramwatcher/toplist remain JS in the same column unless the native host either (a) renders all six, or (b) the seam is reworked to per-panel slots. Sequencing risk more than code risk.
3. **`vh` → pixel sizing fidelity.** Every dimension is `vh` (border 0.092vh, font 1.3vh, ticks 0.833vh, etc.). Reproducing the exact proportions natively requires deriving sizes from the live column rect (and reacting to window resize / DPR), or the panel will look visually "off" next to surviving JS panels. The DPR-aware rect plumbing in `native_mount.rs` (`apply_rect` with `dpr`) is the model to follow.

Minor: the stub backend means a native port shows the same placeholder-ish data ("Apple" / host-name / "Laptop"); if richer Mac model/chassis strings are wanted, extend `SysinfoService` — out of scope for the view conversion.

---

## 8. Effort estimate

**S (small).**

Justification: three static labels + three text fields, one 20 s poll, two synchronous Rust stub calls already available, no interaction, no animation of its own, no scrolling, no `augmented-ui`. The only non-trivial bits — theme-var propagation to native and the all-or-nothing column-mount seam — are **shared cross-panel infrastructure**, not work owned by this panel; once that scaffolding exists, this panel itself is a few-hours port.
