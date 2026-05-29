# Native Panel Slots — Phase 0 + Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a per-panel native NSView "slot" mechanism (Approach A) and use it to render the two trivial left-column text panels — `sysinfo` and `hardwareInspector` — as native CALayer content fed from JS, behind per-panel experimental flags, with the other four panels untouched.

**Architecture:** A new additive Rust module `native_panels.rs` owns a registry of independently-positioned NSViews ("slots"), one per DOM anchor id, each layered above the WKWebView and sized to that panel's bounding rect. The existing `native_mount.rs` clock pilot is left untouched. A JS bridge (`bridge/native_panels.js`) ships per-anchor rects (reusing the rAF-coalesce / epsilon-dedupe / seq latest-wins pattern from `native_mount.js`) and pushes formatted text per layer. A small `NativeThemeState` carries theme color + fonts to the native renderers. For this first cut, **JS keeps all formatting** (uptime math, battery state, `_trimDataString`) and pushes finished strings — the slot/theme/teardown infra is what's being proven; moving formatting into Rust is deferred to a later phase.

**Tech Stack:** Rust + Tauri 2 custom commands, `objc`/`cocoa`/`core-graphics` (the same AppKit stack already used in `native_mount.rs`), `dispatch::Queue::main` for main-thread hops, plain-JS WKWebView frontend, Node built-in test runner, `cargo test`.

---

## Design Notes (read before starting)

- **Why a new module, not a refactor of `native_mount.rs`:** the clock pilot works and is flag-gated; refactoring it risks the one native path that currently functions. `native_panels.rs` is purely additive and can absorb the clock pilot in a later phase.
- **Slots are per-panel, not per-column.** Each slot tracks the bounding rect of one panel element (`#mod_sysinfo`, `#mod_hardwareInspector`), not `#mod_column_left`. Only that panel's DOM is hidden, so the other four render normally. This is the core of Approach A.
- **No capability changes.** `native_panel_*` and `native_set_theme` are custom `#[tauri::command]`s, not core-plugin commands, so `capabilities/default.json` needs no edit (confirmed: the existing `native_mount_*` commands have no capability entries).
- **Anchor layouts live in Rust.** Rust knows the layer layout for each known anchor (`mod_sysinfo` = 4 cells × {label,value}; `mod_hardwareInspector` = 3 rows × {label,value}). JS never ships layout, only `(anchor, key, text)` updates. Keys are the stable strings defined in Task 4/Task 9.
- **AppKit code pattern:** model all NSView/CALayer/CATextLayer creation, `retain`, main-thread dispatch, and the web→AppKit y-flip on the existing template in `native_mount.rs:140-294`. Reuse `is_main_thread`, the `MountHandle`-style `usize` pointer stash, and `apply_rect`'s `content_h - (rect.y + rect.height)` flip verbatim in spirit.
- **Visual fidelity reference:** exact fonts/sizes/colors/positions for each panel are documented in `docs/native-migration/sysinfo.spec.md` and `docs/native-migration/hardwareInspector.spec.md`. The positions in this plan are a faithful starting layout; reconcile against those specs and the CSS during the manual smoke step.

## Execution Amendments (must apply before implementation)

- **Do not let the old whole-column mount run for per-panel slots.** `renderer.js` currently calls `window.bridge.nativeMount.activate()` when `experimentalNativePanels === true`, which adds `body.native-left-active` and hides the entire left column. Tighten that gate so the old path only runs when `experimentalNativeClock === true`. Sysinfo and hardwareInspector must use `bridge.nativePanels` only.
- **Add an explicit mount command.** The command surface is now `native_panel_mount`, `native_panel_set_rect`, `native_panel_set_visible`, `native_panel_set_text`, `native_panel_unmount`, and `native_set_theme`. `mountPanel(anchorId)` must call `native_panel_mount` before shipping rect/visible/text, so slot creation is not an implicit race inside `set_rect`.
- **Hide the panel element, not just its children.** Use `.native-panel-hidden { visibility: hidden; pointer-events: none; }`; this preserves layout space while hiding the element border and pseudo-elements too.
- **Theme updates must restyle existing slots.** `native_set_theme` stores the snapshot and applies it to any already-mounted label/value/border/tick layers. Slots mounted after theme push use the latest snapshot.
- **Default settings should document the new flags.** Add `"experimentalNativeSysinfo": false` and `"experimentalNativeHwInspector": false` to `settings.rs` defaults, even though user settings are free-form.
- **Visual layer parity matters enough for Phase 1.** Implement top border and side tick layers for both panels. Text opacity should follow the CSS: sysinfo labels/separators dimmed and values full opacity; hardwareInspector labels full opacity and values dimmed.

## File Structure

**Create:**
- `src-tauri/src/native_panels.rs` — slot registry, `NativePanelsState`, `NativeThemeState`, pure helpers (`seq_wins`, `flip_y`), per-anchor renderers, and commands `native_panel_mount`, `native_panel_set_rect`, `native_panel_set_visible`, `native_panel_set_text`, `native_panel_unmount`, `native_set_theme`. Includes `#[cfg(test)]` unit tests for the pure helpers.
- `src/bridge/native_panels.js` — per-anchor rect shipping + `mountPanel`, `setPanelText`, `unmountPanel`, `setTheme`, `_resetForTests`.
- `src/bridge/native_panels.test.js` — Node tests for per-anchor coalesce/epsilon/seq bookkeeping.

**Modify:**
- `src-tauri/src/lib.rs:1-36` — declare `mod native_panels`; `.manage()` `NativePanelsState` + `NativeThemeState`; call `native_panels::install` in `setup()`; add the five new commands to `generate_handler!`.
- `src/ui.html:79` — add `<script src="bridge/native_panels.js"></script>` after the existing `bridge/native_mount.js` line.
- `src/classes/sysinfo.class.js` — native-path branch gated on `experimentalNativeSysinfo`.
- `src/classes/hardwareInspector.class.js` — native-path branch gated on `experimentalNativeHwInspector`.
- `src/renderer.js:~143` (after theme vars are set) — push theme to native; `src/renderer.js:369-372` (native activate block) — mount sysinfo/hwInspector slots when their flags are on.
- `src/assets/css/mod_column.css` — add per-panel hide rules `.native-panel-hidden { … }`.
- `src-tauri/src/settings.rs` — add default false values for `experimentalNativeSysinfo` and `experimentalNativeHwInspector`.

---

## Phase 0 — Infrastructure

### Task 1: Pure slot helpers (seq + rect flip) with unit tests

**Files:**
- Create: `src-tauri/src/native_panels.rs`
- Test: inline `#[cfg(test)]` module in the same file

- [ ] **Step 1: Write the failing tests**

Create `src-tauri/src/native_panels.rs` with ONLY the pure helpers + tests:

```rust
//! Approach A: per-panel native NSView "slots" mounted above the WKWebView.
//! See docs/superpowers/plans/2026-05-29-native-panel-slots-phase0-1.md.
#![allow(deprecated)]
#![allow(unexpected_cfgs)]

/// Latest-wins guard. Returns true if `seq` should be applied given the
/// previously-seen max `prev`. Mirrors native_mount.rs's fetch_max logic but
/// pulled out as a pure fn so it is unit-testable without AppKit.
pub(crate) fn seq_wins(prev: u64, seq: u64) -> bool {
    seq > prev
}

/// Web (top-left origin) → AppKit (bottom-left origin) y-flip.
/// `content_h` is the window contentView height in points.
/// Returns the AppKit-space y for a rect of height `h` at web-y `y`.
pub(crate) fn flip_y(content_h: f64, y: f64, h: f64) -> f64 {
    content_h - (y + h)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seq_wins_only_for_strictly_newer() {
        assert!(seq_wins(0, 1));
        assert!(seq_wins(5, 6));
        assert!(!seq_wins(5, 5));
        assert!(!seq_wins(5, 4));
    }

    #[test]
    fn flip_y_inverts_origin() {
        // 1000pt-tall window, a 100pt-tall panel at web-y=0 sits at AppKit-y=900.
        assert_eq!(flip_y(1000.0, 0.0, 100.0), 900.0);
        // Same panel at web-y=200 sits at AppKit-y=700.
        assert_eq!(flip_y(1000.0, 200.0, 100.0), 700.0);
    }
}
```

- [ ] **Step 2: Wire the module so it compiles**

In `src-tauri/src/lib.rs`, add `mod native_panels;` after line 3 (`mod native_mount;`):

```rust
mod native_modal;
mod native_mount;
mod native_panels;
mod pty;
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `cd src-tauri && cargo test --lib native_panels`
Expected: PASS (2 tests). `cargo check` clean.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/native_panels.rs src-tauri/src/lib.rs
git commit -m "feat(native): add native_panels module with pure slot helpers"
```

---

### Task 2: NativeThemeState + native_set_theme command

**Files:**
- Modify: `src-tauri/src/native_panels.rs`
- Modify: `src-tauri/src/lib.rs:23-36` (manage + handler)

- [ ] **Step 1: Write the failing test**

Add to the `#[cfg(test)]` module in `native_panels.rs`:

```rust
#[test]
fn theme_state_defaults_to_white_and_stores_rgb() {
    let st = ThemeSnapshot::default();
    assert_eq!((st.r, st.g, st.b), (255, 255, 255));
    let updated = ThemeSnapshot { r: 0, g: 170, b: 255, font_main: "Font A".into(), font_main_light: "Font B".into() };
    assert_eq!(updated.r, 0);
    assert_eq!(updated.font_main_light, "Font B");
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src-tauri && cargo test --lib native_panels`
Expected: FAIL — `ThemeSnapshot` not defined.

- [ ] **Step 3: Implement ThemeSnapshot + NativeThemeState + command**

Add to `native_panels.rs`:

```rust
use std::sync::Mutex;
use serde::Deserialize;
use tauri::State;

#[derive(Clone, Debug)]
pub(crate) struct ThemeSnapshot {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub font_main: String,
    pub font_main_light: String,
}

impl Default for ThemeSnapshot {
    fn default() -> Self {
        Self { r: 255, g: 255, b: 255, font_main: "Menlo".into(), font_main_light: "Menlo".into() }
    }
}

#[derive(Default)]
pub struct NativeThemeState {
    inner: Mutex<ThemeSnapshot>,
}

impl NativeThemeState {
    pub(crate) fn snapshot(&self) -> ThemeSnapshot {
        self.inner.lock().map(|g| g.clone()).unwrap_or_default()
    }
}

#[derive(Deserialize)]
pub struct ThemePayload {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub font_main: String,
    pub font_main_light: String,
}

#[tauri::command]
pub async fn native_set_theme(state: State<'_, NativeThemeState>, theme: ThemePayload) -> Result<(), String> {
    let mut guard = state.inner.lock().map_err(|_| "native_panels: theme lock poisoned".to_string())?;
    *guard = ThemeSnapshot {
        r: theme.r, g: theme.g, b: theme.b,
        font_main: theme.font_main, font_main_light: theme.font_main_light,
    };
    Ok(())
}
```

- [ ] **Step 4: Manage state + register command in lib.rs**

In `src-tauri/src/lib.rs`, add to the `.manage()` chain after line 30 (`.manage(NativeMountState::default())`):

```rust
            .manage(native_panels::NativeThemeState::default())
            .manage(native_panels::NativePanelsState::default())
```

(`NativePanelsState` lands in Task 3; add both now and stub `NativePanelsState` as `#[derive(Default)] pub struct NativePanelsState;` temporarily — Task 3 fills it in.)

In the `generate_handler!` macro, after the `// native modal pilot` block (lib.rs:~92), add:

```rust
            // native panels (Approach A)
            native_panels::native_set_theme,
```

- [ ] **Step 5: Run tests + check**

Run: `cd src-tauri && cargo test --lib native_panels && cargo check`
Expected: PASS, clean check.

- [ ] **Step 6: Commit**

```bash
git add src-tauri/src/native_panels.rs src-tauri/src/lib.rs
git commit -m "feat(native): add NativeThemeState and native_set_theme command"
```

---

### Task 3: Slot registry + AppKit slot view (mount/rect/visible/unmount)

**Files:**
- Modify: `src-tauri/src/native_panels.rs`
- Modify: `src-tauri/src/lib.rs` (install in setup, register commands)

- [ ] **Step 1: Implement the slot registry and AppKit view ops**

Replace the temporary `NativePanelsState` stub with the real registry. Model the AppKit calls on `native_mount.rs:140-294` (same imports: `cocoa::base`, `cocoa::foundation`, `core_graphics::color::CGColor`, `dispatch::Queue`, `objc` macros). Add at the top of `native_panels.rs`:

```rust
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use cocoa::base::{id, nil, NO, YES};
use cocoa::foundation::{NSPoint, NSRect, NSSize, NSString};
use core_foundation::base::TCFType;
use core_graphics::color::CGColor;
use dispatch::Queue;
use objc::{class, msg_send, sel, sel_impl};
use tauri::{AppHandle, Manager};
```

Each slot stores opaque pointers as `usize` (Send+Sync per the `native_mount.rs:54-58` rationale):

```rust
#[derive(Clone)]
struct Slot {
    view: usize,
    /// Ordered text layers, addressable by stable key (e.g. "uptime_value").
    layers: HashMap<String, usize>,
    last_seq: u64,
}

#[derive(Default)]
pub struct NativePanelsState {
    slots: Mutex<HashMap<String, Slot>>,
    seq_guard: Mutex<HashMap<String, AtomicU64>>, // per-anchor latest-wins
}
```

Add `install(app: &AppHandle)` that grabs the `ns_window`/`contentView` once (copy the lookup from `native_mount.rs:107-116`) and stores the `contentView`+webview pointers in the state for later `addSubview`. Add a private `build_slot(anchor: &str, ns_window: id) -> Slot` that, for a known anchor, creates the NSView (`setWantsLayer:YES`, `setHidden:YES`, black backing layer) and the labelled CATextLayers for that anchor's layout (see Task 4 for `mod_sysinfo`, Task 9 for `mod_hardwareInspector`), `retain`s each, and adds the view above the webview exactly as `native_mount.rs:201-215`.

Then the commands:

```rust
#[tauri::command]
pub async fn native_panel_set_rect(
    state: State<'_, NativePanelsState>,
    anchor: String, rect: WebRect, dpr: f64, seq: u64,
) -> Result<(), String> { /* per-anchor seq_wins guard, then Queue::main apply_slot_rect with flip_y */ }

#[tauri::command]
pub async fn native_panel_set_visible(
    state: State<'_, NativePanelsState>, anchor: String, visible: bool,
) -> Result<(), String> { /* main-thread setHidden, like native_mount_set_visible */ }

#[tauri::command]
pub async fn native_panel_set_text(
    state: State<'_, NativePanelsState>, theme: State<'_, NativeThemeState>,
    anchor: String, key: String, text: String,
) -> Result<(), String> { /* main-thread: setString on layers[key]; apply theme foreground color + font */ }

#[tauri::command]
pub async fn native_panel_unmount(
    state: State<'_, NativePanelsState>, anchor: String,
) -> Result<(), String> { /* main-thread: removeFromSuperview + release; drop slot from map */ }
```

Add the explicit mount command before the other slot commands:

```rust
#[tauri::command]
pub async fn native_panel_mount(
    state: State<'_, NativePanelsState>,
    theme: State<'_, NativeThemeState>,
    anchor: String,
) -> Result<(), String> { /* create hidden slot on main thread if absent */ }
```

`native_panel_mount` must reject unknown anchors with `Ok(())` after logging, and it must be idempotent for already-mounted anchors. `WebRect` is identical to `native_mount.rs:81-87` — define a local copy (or move it to a shared spot; a local copy keeps modules decoupled). `apply_slot_rect` uses `flip_y(content_h, rect.y, rect.height)` from Task 1.

- [ ] **Step 2: Register in lib.rs**

Add `native_panels::install(app.handle())?;` to `setup()` after `native_mount::install` (lib.rs:34). Add the four commands to `generate_handler!`:

```rust
            native_panels::native_panel_mount,
            native_panels::native_panel_set_rect,
            native_panels::native_panel_set_visible,
            native_panels::native_panel_set_text,
            native_panels::native_panel_unmount,
```

- [ ] **Step 3: Verify build + existing tests**

Run: `cd src-tauri && cargo check && cargo test --lib native_panels && cargo clippy -- -D warnings && cargo fmt --check`
Expected: clean. (No new unit tests this task — AppKit paths are exercised in the manual smoke step; the pure helpers they call are already covered.)

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/native_panels.rs src-tauri/src/lib.rs
git commit -m "feat(native): per-panel slot registry with mount/rect/visible/unmount"
```

---

### Task 4: sysinfo slot layout (Rust renderer layers)

**Files:**
- Modify: `src-tauri/src/native_panels.rs` (`build_slot` arm for `"mod_sysinfo"`)

- [ ] **Step 1: Implement the `mod_sysinfo` layer set**

In `build_slot`, for `anchor == "mod_sysinfo"`, create eight CATextLayers (4 cells × {label, value}) using the same CATextLayer pattern as `native_mount.rs:163-192`. Label layers are static strings ("", set once); value layers are keyed for updates. Keys: `date_value`, `uptime_value`, `type_value`, `power_value`; static label text: "", "UPTIME", "TYPE", "POWER" (date cell's label is the year — treat year as part of `date_value`). Use a simple vertical 4-cell stack; foreground color + font come from the theme snapshot at `set_text` time. Reconcile exact positions/sizes against `docs/native-migration/sysinfo.spec.md` and `src/assets/css/mod_sysinfo.css` during smoke.

```rust
// inside build_slot, after creating `view` + root layer:
"mod_sysinfo" => {
    let keys = ["date_value", "uptime_value", "type_value", "power_value"];
    let labels = ["", "UPTIME", "TYPE", "POWER"];
    for (i, (k, lbl)) in keys.iter().zip(labels.iter()).enumerate() {
        // static label (skip empty), then value layer registered under *k.
        // position each cell at y = i * cell_h; see sysinfo.spec.md.
        make_label_layer(root_layer, lbl, /* rect */);
        let value_layer = make_value_layer(root_layer, /* rect */);
        layers.insert((*k).to_string(), value_layer as usize);
    }
}
```

Add private helpers `make_label_layer`/`make_value_layer` wrapping the `CATextLayer` boilerplate from `native_mount.rs:177-192` (alloc, setString, setForegroundColor from theme, setFontSize, setFont, setFrame, setWrapped:NO, addSublayer, retain).

- [ ] **Step 2: Verify build**

Run: `cd src-tauri && cargo check && cargo clippy -- -D warnings`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add src-tauri/src/native_panels.rs
git commit -m "feat(native): sysinfo slot layer layout"
```

---

### Task 5: JS bridge — per-anchor rect shipping + text/theme push

**Files:**
- Create: `src/bridge/native_panels.js`
- Modify: `src/ui.html:79`

- [ ] **Step 1: Write the failing tests**

Create `src/bridge/native_panels.test.js` (Node test runner, mirroring `src/bridge/native_mount.test.js`'s invoke-stub style):

```js
const test = require("node:test");
const assert = require("node:assert");

function loadBridge(invokeCalls) {
    const win = {
        __TAURI__: { core: { invoke: (cmd, args) => { invokeCalls.push({ cmd, args }); return Promise.resolve(); } } },
        document: { getElementById: () => ({ getBoundingClientRect: () => ({ left: 10, top: 20, width: 100, height: 50 }) }) },
        devicePixelRatio: 2,
        requestAnimationFrame: (fn) => { fn(); return 1; },
        ResizeObserver: class { observe() {} disconnect() {} },
        addEventListener: () => {},
        matchMedia: () => null,
    };
    const mod = { exports: null };
    const fn = require("fs").readFileSync(require("path").join(__dirname, "native_panels.js"), "utf8");
    new Function("window", "module", fn)(win, mod);
    return win.bridge.nativePanels;
}

test("setPanelText invokes native_panel_set_text with anchor/key/text", async () => {
    const calls = [];
    const np = loadBridge(calls);
    await np.setPanelText("mod_sysinfo", "uptime_value", "1d00:05");
    const c = calls.find(c => c.cmd === "native_panel_set_text");
    assert.deepEqual(c.args, { anchor: "mod_sysinfo", key: "uptime_value", text: "1d00:05" });
});

test("mountPanel ships an initial rect with seq=1 for that anchor", async () => {
    const calls = [];
    const np = loadBridge(calls);
    await np.mountPanel("mod_sysinfo");
    const rectCall = calls.find(c => c.cmd === "native_panel_set_rect");
    assert.equal(rectCall.args.anchor, "mod_sysinfo");
    assert.equal(rectCall.args.seq, 1);
    assert.deepEqual(rectCall.args.rect, { x: 10, y: 20, width: 100, height: 50 });
});

test("setTheme forwards rgb + fonts", async () => {
    const calls = [];
    const np = loadBridge(calls);
    await np.setTheme({ r: 0, g: 170, b: 255, font_main: "A", font_main_light: "B" });
    const c = calls.find(c => c.cmd === "native_set_theme");
    assert.deepEqual(c.args.theme, { r: 0, g: 170, b: 255, font_main: "A", font_main_light: "B" });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test src/bridge/native_panels.test.js`
Expected: FAIL — `native_panels.js` not found / `bridge.nativePanels` undefined.

- [ ] **Step 3: Implement the bridge**

Create `src/bridge/native_panels.js`, generalizing `native_mount.js` to a per-anchor map (each anchor gets its own `{mountPromise, seq, lastRect, lastDpr, rafId, observer}`). Public surface: `mountPanel(anchorId)`, `setPanelText(anchorId, key, text)`, `unmountPanel(anchorId)`, `setTheme(payload)`, `_resetForTests()`. Reuse `epsilonDiffers` and the rAF coalesce verbatim, keyed per anchor. `mountPanel` adds `native-panel-hidden` to the anchor element, calls `native_panel_mount {anchor}`, observes it, ships the initial rect synchronously, then `native_panel_set_visible {anchor, visible:true}`. `setPanelText` waits for an existing `mountPromise` when present so constructor-time text pushes cannot beat slot creation.

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test src/bridge/native_panels.test.js`
Expected: PASS (3 tests).

- [ ] **Step 5: Load in ui.html**

Add after `src/ui.html:79` (`<script src="bridge/native_mount.js"></script>`):

```html
        <script src="bridge/native_panels.js"></script>
```

- [ ] **Step 6: Syntax-check + commit**

Run: `node --check src/bridge/native_panels.js`

```bash
git add src/bridge/native_panels.js src/bridge/native_panels.test.js src/ui.html
git commit -m "feat(native): JS bridge for per-anchor native panel slots"
```

---

### Task 6: Per-panel hide CSS + theme push on boot

**Files:**
- Modify: `src/assets/css/mod_column.css`
- Modify: `src/renderer.js` (theme push after vars set, ~line 143)

- [ ] **Step 1: Add the per-panel hide rule**

Append to `src/assets/css/mod_column.css`:

```css
/* Approach A: hide a single panel's DOM when its native slot is mounted.
   Unlike body.native-left-active (whole column), this is per-element so the
   other panels keep rendering. */
.native-panel-hidden {
    visibility: hidden;
    pointer-events: none;
}
```

- [ ] **Step 2: Push theme to native after CSS vars are applied**

In `src/renderer.js`, immediately after the block that sets `window.theme.r/g/b` (currently lines 143-145), add:

```js
        if (window.settings.experimentalNativePanels === true && window.bridge && window.bridge.nativePanels) {
            window.bridge.nativePanels.setTheme({
                r: Number(theme.colors.r), g: Number(theme.colors.g), b: Number(theme.colors.b),
                font_main: theme.cssvars.font_main, font_main_light: theme.cssvars.font_main_light
            }).catch(e => console.warn("native setTheme failed:", e));
        }
```

- [ ] **Step 3: Verify**

Run: `node --check src/renderer.js`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add src/assets/css/mod_column.css src/renderer.js
git commit -m "feat(native): per-panel hide CSS and boot-time theme push"
```

---

## Phase 1 — Convert sysinfo and hardwareInspector

### Task 7: sysinfo native path branch

**Files:**
- Modify: `src/classes/sysinfo.class.js`

- [ ] **Step 1: Add a native gate in the constructor**

At the top of `Sysinfo`'s constructor, compute:

```js
        this.native = window.settings.experimentalNativePanels === true
            && window.settings.experimentalNativeSysinfo === true
            && window.bridge && window.bridge.nativePanels;
```

When `this.native`, still build the DOM (so layout/measurement of `#mod_sysinfo` works for the slot rect) but mount the slot: after the existing `this.parent.innerHTML += …`, add:

```js
        if (this.native) { window.bridge.nativePanels.mountPanel("mod_sysinfo"); }
```

- [ ] **Step 2: Route each updater to native when gated**

In `updateUptime`, `updateBattery`, and `updateDate`, after computing the display string, branch: if `this.native`, push instead of writing the DOM node. Example for uptime (replace the final `document.querySelector(...).innerHTML = …`):

```js
        const uptimeStr = uptime.days + "d" + uptime.hours + ":" + uptime.minutes;
        if (this.native) {
            window.bridge.nativePanels.setPanelText("mod_sysinfo", "uptime_value", uptimeStr);
        } else {
            document.querySelector("#mod_sysinfo > div:nth-child(2) > h2").innerHTML =
                uptime.days + '<span style="opacity:0.5;">d</span>' + uptime.hours + '<span style="opacity:0.5;">:</span>' + uptime.minutes;
        }
```

Do the equivalent for `date_value` (year + month/day), `power_value` (CHARGE/WIRED/`percent%`/ON), and `type_value` (static "macOS", pushed once in the constructor when native).

- [ ] **Step 3: Verify**

Run: `node --check src/classes/sysinfo.class.js`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add src/classes/sysinfo.class.js
git commit -m "feat(native): sysinfo renders via native slot when gated"
```

---

### Task 8: Mount sysinfo slot at boot + manual smoke

**Files:**
- Modify: `src/renderer.js:369-372` (native activate block)

- [ ] **Step 1: Confirm flag plumbing**

`experimentalNativeSysinfo` is read straight from `window.settings`. Add the default key in `settings.rs`, but no schema migration is required because settings is a free-form JSON object. The slot mounts itself from the panel class (Task 7). Also tighten `renderer.js:369-372` so the old `nativeMount.activate()` path runs only when `experimentalNativeClock === true`.

- [ ] **Step 2: Manual smoke test**

```bash
# Enable the flags in the running settings file, then launch:
#   ~/Library/Application Support/eDEX-UI/settings.json
#   { ..., "experimentalNativePanels": true, "experimentalNativeSysinfo": true }
cd /Users/iphoobis/Projects/eDEX-UI-security-patched && cargo +stable tauri dev
```

Verify: `#mod_sysinfo` DOM is hidden; a native box renders DATE/UPTIME/TYPE/POWER in the theme color/font; values update (uptime every 60s, battery every 3s); resizing the window keeps the native box aligned to the panel; the other five panels (clock/hwInspector/cpuinfo/ramwatcher/toplist) still render as DOM; no console errors; quitting is clean.

- [ ] **Step 3: Commit (smoke notes only if any tweak was needed)**

```bash
git commit --allow-empty -m "test(native): manual smoke — sysinfo native slot verified"
```

---

### Task 9: hardwareInspector slot layout + native path

**Files:**
- Modify: `src-tauri/src/native_panels.rs` (`build_slot` arm for `"mod_hardwareInspector"`)
- Modify: `src/classes/hardwareInspector.class.js`

- [ ] **Step 1: Add the `mod_hardwareInspector` layer set**

In `build_slot`, add an arm for `"mod_hardwareInspector"` with three rows × {label, value}; keys `manufacturer_value`, `model_value`, `chassis_value`; labels "MANUFACTURER", "MODEL", "CHASSIS". Same `make_label_layer`/`make_value_layer` helpers from Task 4. Positions per `docs/native-migration/hardwareInspector.spec.md`.

- [ ] **Step 2: Native branch in the class**

In `HardwareInspector`'s constructor add the same `this.native` gate (flag `experimentalNativeHwInspector`) and `mountPanel("mod_hardwareInspector")`. In `updateInfo`, when `this.native`, push the three values instead of `innerText`:

```js
    updateInfo() {
        window.si.system().then(d => {
            window.si.chassis().then(e => {
                const man = this._trimDataString(d.manufacturer);
                const mod = this._trimDataString(d.model, d.manufacturer, e.type);
                if (this.native) {
                    const np = window.bridge.nativePanels;
                    np.setPanelText("mod_hardwareInspector", "manufacturer_value", man);
                    np.setPanelText("mod_hardwareInspector", "model_value", mod);
                    np.setPanelText("mod_hardwareInspector", "chassis_value", e.type);
                } else {
                    document.getElementById("mod_hardwareInspector_manufacturer").innerText = man;
                    document.getElementById("mod_hardwareInspector_model").innerText = mod;
                    document.getElementById("mod_hardwareInspector_chassis").innerText = e.type;
                }
            });
        });
    }
```

- [ ] **Step 3: Verify**

Run: `node --check src/classes/hardwareInspector.class.js && cd src-tauri && cargo check && cargo clippy -- -D warnings && cargo fmt --check`
Expected: clean.

- [ ] **Step 4: Manual smoke**

Enable `experimentalNativeHwInspector` alongside the sysinfo flags; relaunch; verify the hardwareInspector panel renders natively (MANUFACTURER/MODEL/CHASSIS) with theme styling, the other panels unaffected. Confirm `body.native-left-active` is absent unless `experimentalNativeClock` is also true.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/native_panels.rs src/classes/hardwareInspector.class.js
git commit -m "feat(native): hardwareInspector renders via native slot when gated"
```

---

### Task 10: Full validation gate

- [ ] **Step 1: Run the complete check suite**

```bash
node --check src/renderer.js
node --test src/bridge/native_panels.test.js src/bridge/native_mount.test.js src/bridge/bridge.test.js
cd src-tauri && cargo test && cargo fmt --check && cargo clippy -- -D warnings
```

Expected: all green.

- [ ] **Step 2: Regression smoke with flags OFF**

Launch with no experimental flags; confirm sysinfo + hardwareInspector render exactly as before (DOM path), proving the native path is fully opt-in and the default experience is unchanged.

- [ ] **Step 3: Final commit**

```bash
git commit --allow-empty -m "test(native): phase 0+1 validation gate green"
```

---

## Self-Review

**Spec coverage:** Phase 0 (slot registry T3, theme bridge T2/T6, teardown via `native_panel_unmount` T3, per-panel hide T6) and Phase 1 (sysinfo T4/T7/T8, hardwareInspector T9) are each covered by tasks. Deferred items (cpuinfo charting, ramwatcher dot grid, toplist + native custom modal, moving formatting into Rust) are explicitly out of scope for this plan and get their own spec→plan cycles.

**Placeholder scan:** AppKit view-construction steps (T3/T4/T9) reference the concrete `native_mount.rs:140-294` template and name exact layers/keys/positions rather than saying "build the view" — the engineer copies a working pattern. Pure logic and all tests carry complete code.

**Type consistency:** `ThemeSnapshot`/`ThemePayload` fields (`r,g,b,font_main,font_main_light`), layer keys (`date_value`, `date_subvalue`, `uptime_value`, `type_value`, `power_value`, `manufacturer_value`, `model_value`, `chassis_value`), command names (`native_panel_mount/_set_rect/_set_visible/_set_text/_unmount`, `native_set_theme`), and the JS surface (`mountPanel/setPanelText/unmountPanel/setTheme/_resetForTests`) are used consistently across tasks.

**Known follow-ups (not blockers):** the `native_panel_unmount` teardown is wired but unused in Phase 1 (slots live until reload, matching the existing DOM panels which leak intervals and rely on `location.reload()`); a later phase formalizes a `NativePanel` trait + Rust-side polling and migrates the clock pilot into this registry.
