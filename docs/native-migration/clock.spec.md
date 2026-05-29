# Native-conversion spec: CLOCK panel

Source of truth (read these, do not re-derive):
- `src/classes/clock.class.js`
- `src/assets/css/mod_clock.css`
- `src/assets/css/mod_column.css` (shared column layout)
- `src/renderer.js` (instantiation at line 339; theme injection 106–146; settings 61–79)
- `src-tauri/src/native_mount.rs` (clock pilot backend)
- `src/bridge/native_mount.js` (clock pilot frontend)
- `src-tauri/src/settings.rs` (defaults, lines 77, 90–92)

---

## 1. Summary

The clock panel is the top-most module in the left column. It renders a live
wall-clock time as `HH:MM:SS` (24-hour) or `H:MM:SS AM/PM` (12-hour), updated
once per second. Each character is rendered as its own monospaced-width cell so
the digits sit on a fixed grid and the colons get tighter spacing; the AM/PM
suffix (12-hour mode only) is rendered smaller. The panel is purely a clock —
it has no calendar, date, timezone label, or any interaction.

---

## 2. Data contract

**No `window.si.*` / `SysinfoService` dependency at all.** The clock reads the
local system time via the JavaScript `new Date()` runtime API only. There is no
IPC, no `si_*` command, and no Rust query method involved in producing the
time value. (For reference, `SysinfoService::uptime()` / `si_uptime` exist but
the clock does **not** use them.) A native port can read the time directly from
`Date()` / `DispatchTime` / `Calendar` in Swift with zero backend calls.

### Polling cadence
- `setInterval(this.updateClock, 1000)` — one tick per second.
- `updateClock()` is also called once synchronously in the constructor for an
  immediate first paint.
- The interval handle is stored on `this.updater` but is **never cleared**
  (no teardown).

### Time fields consumed (from `new Date()`)
- `time.getHours()` (0–23)
- `time.getMinutes()` (0–59)
- `time.getSeconds()` (0–59)
- `this.lastTime = time` is stored each tick but is **never read anywhere** in
  this class — dead/forward-compat state.

### `window.settings.*` flags read (in constructor)
| Flag | Default | Effect |
|---|---|---|
| `settings.clockHours` | `24` | `=== 12` → 12-hour mode (`this.twelveHours`), adds AM/PM + `mod_clock_twelve` class |
| `settings.experimentalNativePanels` | `false` | Part of the `nativeClock` gate (all three must be true) |
| `settings.experimentalNativeClock` | `false` | Part of the `nativeClock` gate |

Defaults live in `src-tauri/src/settings.rs` (`clockHours: 24`,
`experimentalNativePanels/Clock/Modal: false`). `experimentalNativeModal` is
not read by this class.

### `window.bridge.*` read (in constructor, for the `nativeClock` gate)
- `window.bridge` truthy
- `window.bridge.nativeMount` truthy
- `typeof window.bridge.nativeMount.setClockText === "function"`

When all gate conditions hold, the class does **not** build any DOM; it pushes
the formatted string to `window.bridge.nativeMount.setClockText(plainClock)`
each tick (the existing native pilot path — see §7).

### `window.theme.*` read
None directly by the class. The panel's color/font come entirely from CSS
custom properties (`var(--color_r/g/b)`, `var(--font_main_light)`), which
`renderer.js::_loadTheme` injects into `:root` (renderer.js 118–140). See §4.

---

## 3. DOM structure

Built only in the **non-native** path (constructor lines 17–21), appended via
`this.parent.innerHTML +=` into the container passed to the constructor
(`mod_column_left`):

```
div#mod_clock                       (static; class "mod_clock_twelve" iff 12-hour)
  h1#mod_clock_text                 (static container)
    span / em ...                   (DYNAMIC — fully rebuilt every tick)
```

- **Static:** the `div#mod_clock` wrapper and the `h1#mod_clock_text` shell. The
  `mod_clock_twelve` class is set once at construction from `clockHours`.
- **Dynamic:** the inner spans/`em`s. Each tick, `updateClock()` rebuilds
  `#mod_clock_text.innerHTML` from scratch:
  - every digit → `<span>D</span>`
  - every colon → `<em>:</em>`
  - 12-hour suffix → trailing `<span>AM</span>` / `<span>PM</span>`
  - Initial placeholder markup (before first tick) is a string of `?`-filled
    spans/`em`s: `?? : ?? : ??`.
- Zero-padding: any component whose string length ≠ 2 is prefixed with `"0"`
  (so `9` → `09`). Note in 12-hour mode the hour can be a single non-padded
  digit only when it equals 12→`12` or after the length check; the code pads
  to two chars uniformly, so `1`→`01` etc.

---

## 4. Visual spec (from `mod_clock.css` + shared `mod_column.css`)

All sizes are viewport-height relative (`vh`) — the whole UI scales with window
height. Colors are theme custom properties.

### Container `div#mod_clock`
- `display: flex; height: 7.41vh; padding-top: 0.645vh`
- `border-top: 0.092vh solid rgba(var(--color_r),var(--color_g),var(--color_b),0.3)`
  — a 1px-ish theme-tinted top rule at 30% opacity.
- `font-family: var(--font_main_light)` (theme's light display font, e.g.
  "United Sans Light").
- **`::before` / `::after` pseudo-elements:** short vertical tick marks (left
  and right) — `border-left`/`border-right` `0.092vh solid` theme color @ 30%,
  `height: 0.833vh`, nudged up `top: -1.111vh` and out `±0.092vh`. These form
  the little corner "ticks" framing the top border. **No `augmented-ui`** on
  this panel.

### Clock text `h1`
- `margin: auto` (centers in the flex row), `font-size: 4vh`.

### Cells
- `span, em { display: inline-block; text-align: center }`
- `span { margin: 0 0.2vh; width: 2.3vh }` — fixed digit cell width.
- `em { font-style: normal; margin: 0 0.3vh; width: 2.5vh }` — colon cell
  (slightly wider, wider margin) and overridden to non-italic.
- 12-hour AM/PM: `div#mod_clock.mod_clock_twelve h1 span:last-child { font-size: 1.5vh }`
  — the suffix renders at ~38% of the digit size.

### Column context (`mod_column.css`)
- `section.mod_column` is `width: 17%`, absolutely positioned, `padding: 1.39vh`,
  flex-column, `justify-content: space-between`. `#mod_column_left` is
  `align-items: flex-end` (panels right-aligned, hugging the terminal edge),
  `left: -0.555vh`.
- Column starts `opacity: 0`; `.activated` transitions it to `1` over `.5s`
  cubic-bezier. Each child `div` fades in via `@keyframes fadeIn` with
  `animation-play-state: paused`, switched to `running` by the staggered
  500ms boot reveal loop in renderer.js (349–361).
- **Native-mount seam:** `body.native-left-active #mod_column_left { visibility:
  hidden; pointer-events: none }` (specificity 1,1,1) hides the entire JS left
  column when the native NSView is active.

### Theme variables this panel depends on
- `--color_r`, `--color_g`, `--color_b` (RGB triplet, used in border/tick rgba)
- `--font_main_light` (display font)
- The text inherits the global `body` color `rgb(var(--color_r),...)`
  (main.css line 11).
Injected by `renderer.js::_loadTheme` from `theme.colors.{r,g,b}` and
`theme.cssvars.font_main_light`. No transitions/animations on the digits
themselves — the per-second change is an instant innerHTML swap.

---

## 5. Lifecycle

- **Constructor `Clock(parentId)`:** throws `"Missing parameters"` if `parentId`
  is falsy. Reads `twelveHours` and computes the `nativeClock` gate. Resolves
  `this.parent = document.getElementById(parentId)`. If **not** native, appends
  the `#mod_clock` markup. Sets `this.lastTime`. Calls `updateClock()` once,
  then starts the 1s `setInterval`.
- **Init:** none separate from the constructor.
- **Update loop:** `updateClock()` every 1000ms — formats time, then either
  (native) calls `setClockText(plainClock)` and returns, or (DOM) rebuilds
  `#mod_clock_text.innerHTML`. Guards the DOM write with
  `if (textNode)` so a missing node is a silent no-op.
- **Teardown:** **none.** No `stop()`/`destroy()`; `this.updater` is never
  cleared. (Matches every other panel in this codebase — they live for the app
  lifetime.)
- **Error / empty handling:** minimal. Constructor `parentId` guard; DOM-write
  null guard. No try/catch — `setClockText` itself swallows IPC errors inside
  `bridge/native_mount.js`.

---

## 6. Coupling & interactions

- **Globals read:** `window.settings` (clockHours + the two native flags),
  `window.bridge.nativeMount` (gate + `setClockText`), `document`.
- **Other classes:** none. The clock does not reference any sibling panel.
- **User interactions:** none. Not clickable, no events bound. The only
  user-facing control is the `clockHours` dropdown in the settings modal
  (renderer.js 532, persisted at 577) — changing it requires a restart to take
  effect since `twelveHours` is read once in the constructor.
- **Written back:** nothing persisted. `this.lastTime` is written but unread.
- **Cross-panel deps:** none in logic. The only shared coupling is structural:
  it is the first of six panels appended into the same `#mod_column_left`
  container (clock, sysinfo, hardwareInspector, cpuinfo, ramwatcher, toplist).
  Because all six share that container — and the native-mount seam hides the
  **whole** column — a native clock that uses the existing `nativeMount` NSView
  cannot be shipped in isolation without either (a) hiding only the clock's
  slice, or (b) porting the column wholesale. Flag this for the migration order.

---

## 7. Native pilot status (clock is THE pilot)

**Already wired natively (the `setClockText` path):**

- **JS gate (`clock.class.js`):** when `experimentalNativePanels` +
  `experimentalNativeClock` are on and `bridge.nativeMount.setClockText` exists,
  the class skips DOM creation entirely and pushes the formatted `plainClock`
  string (`H:MM:SS` or `H:MM:SS AM/PM`) to the bridge each second.
- **Bridge (`bridge/native_mount.js`):** `setClockText(text)` →
  `invoke("native_mount_set_clock_text", { text })`, errors swallowed with a
  `console.warn`. Also owns `activate()` which (a) adds
  `body.native-left-active` to hide the JS column, (b) ships
  `#mod_column_left`'s bounding rect to Rust via `native_mount_set_rect`
  (rAF-coalesced, epsilon-deduped, seq-numbered, latest-wins), and (c) calls
  `native_mount_set_visible({visible:true})`.
- **Backend (`native_mount.rs`):** `install()` (Tauri setup hook, main thread)
  builds a hidden, layer-backed `NSView` placed **above** the WKWebView in the
  window's `contentView`, holding three sublayers: a 1px **cyan border**, a
  cyan Menlo-11 **"S1B native" label** (top-left), and a **clock `CATextLayer`**
  (Menlo-Bold 28pt, cyan, right-aligned, 260×36, top-right with 8/16pt margins).
  Commands: `native_mount_set_rect` (web→AppKit y-flip, repositions all layers,
  applies `dpr` to `contentsScale`), `native_mount_set_visible`,
  `native_mount_set_clock_text` (sets the clock layer's `string`).

**What remains to fully replace the DOM render with a faithful native clock:**

1. **It's a placeholder, not a port.** Current native output is cyan Menlo-Bold
   text in a cyan-bordered black box with a debug "S1B native" label — it does
   **not** reproduce the theme color, `font_main_light` display font, the
   per-cell fixed-width digit grid, the smaller AM/PM, or the top border + tick
   pseudo-elements. To "replace the DOM render" the native view must adopt theme
   color/font and the typographic layout, and drop the debug label/cyan chrome.
2. **No theme awareness.** Colors/fonts are hardcoded cyan/Menlo in Rust; the
   native layer never reads `theme.colors` / `theme.cssvars`. A theme→native
   color/font channel is missing.
3. **Single layer for the whole column.** The pilot mounts one NSView sized to
   the entire `#mod_column_left`, but only renders the clock into it. The other
   five panels are simply hidden, not ported — so enabling the flag today blanks
   sysinfo/cpuinfo/ramwatcher/toplist/hardwareInspector. A real clock-only
   migration needs per-panel native slots or a full-column native renderer.
4. **String-push model.** Time formatting still happens in JS and crosses IPC
   once per second. A fully native clock would format in Swift/Rust and drop the
   JS class entirely (including the `setInterval`).

---

## 8. Native mapping proposal

### Suggested view structure (SwiftUI)
A self-contained `ClockView` is the cleanest unit — the panel has no backend
data dependency, so it needs no `SysinfoService` plumbing.

```
ClockView (SwiftUI)
 ├─ top border rule + corner ticks   (Rectangle / Path, theme color @ 0.30 alpha)
 └─ HStack(spacing: 0) of fixed-width digit/colon cells
      ├─ DigitCell(width≈2.3vh) ×6     (monospaced-positioned digits)
      ├─ ColonCell(width≈2.5vh) ×2     (":")
      └─ optional AMPMText (smaller)   (12-hour mode)
    .font(theme.displayFont, size ≈ 4vh-equiv)
    .foregroundStyle(theme.color)
```

- Drive ticks with a SwiftUI `TimerPublisher` (`Timer.publish(every: 1.0)`)
  or, for crisp top-of-second alignment, schedule to the next whole second.
- Read `clockHours` once (and react to a live settings change if desired —
  improving on the JS "restart required" behavior).
- Express the `vh` sizing as a fraction of the view's height via `GeometryReader`
  to preserve the height-relative scaling the CSS relies on.

### Data-flow choice
- **Recommended: direct, in-view time + theme injected as a struct.** Time comes
  from `Date()` natively — do **not** route it through `nativeMount`'s
  `setClockText` (that keeps JS-side formatting and a per-second IPC hop alive).
  The only external input the native clock needs is the **theme** (RGB + display
  font name) and the `clockHours` flag, which should be pushed once from
  `_loadTheme` (and on theme change) via a new lightweight command, not polled.
- The existing `nativeMount` NSView + rect-shipping geometry plumbing is
  reusable as the mount host; replace its hardcoded cyan `CATextLayer` with a
  theme-aware, properly-laid-out clock (or host a SwiftUI `NSHostingView`).

### Top 3 conversion risks
1. **Whole-column coupling.** The native seam hides all of `#mod_column_left`,
   so shipping only the clock natively visually deletes the other five panels.
   Either restructure to per-panel native slots or commit to porting the column
   in one slice. (Highest risk — it's an architecture decision, not a clock
   detail.)
2. **Theme fidelity.** Reproducing `var(--color_*)`, `font_main_light`, the
   fixed-width per-cell digit grid, the smaller AM/PM, and the top border +
   tick pseudo-elements pixel-faithfully — plus piping live theme changes into
   the native layer — is the bulk of the real work.
3. **`vh` scaling + DPR.** The CSS is fully viewport-height relative and the
   layer uses `contentsScale = dpr`. The native view must recompute sizes from
   the live `#mod_column_left` rect (already shipped) and handle Retina scale,
   or the clock will look mis-sized vs. the rest of the UI on resize / display
   moves.

---

## 9. Effort estimate

**S** (the clock unit itself) — trivial data model (local `Date()`, no backend,
no IPC), tiny logic (format + 1s tick), and the mount/geometry/IPC scaffolding
already exists from the pilot. The only non-trivial work is theme-faithful
typography.

Caveat: if the migration must also solve the **whole-column hide** coupling
(so the other five panels survive while only the clock goes native), that
surrounding work is **M–L** — but that cost belongs to the column architecture,
not to the clock.
