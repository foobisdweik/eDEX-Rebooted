# Native Panel Slots Phase 2 CPU and RAM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `cpuinfo` and `ramwatcher` from DOM/canvas renderers into native per-panel AppKit slots, with Rust polling `SysinfoService` directly so the frontend only creates measurable anchor elements.

**Architecture:** Reuse the merged `native_panels.rs` slot registry and add two new native panel renderers for `#mod_cpuinfo` and `#mod_ramwatcher`. The JS classes stay as thin boot anchors only: when their per-panel flag is enabled, they create the existing wrapper element, call `bridge.nativePanels.mountPanel()`, and start the Rust-side feed. Rust owns data refresh, formatting, chart/grid state, and AppKit layer updates.

**Tech Stack:** Rust + Tauri 2 commands, `SysinfoService`, AppKit/CALayer/CATextLayer/CAShapeLayer through `objc`/`cocoa`/`core-graphics`, `dispatch::Queue::main`, plain JS bridge/classes, Node built-in test runner, Cargo tests/clippy/fmt.

---

## Scope And Sequencing

This is the next safe conversion pass after sysinfo and hardwareInspector. `cpuinfo` and `ramwatcher` are read-only monitor panels and do not require modal, terminal, or keyboard focus infrastructure.

Do not convert `toplist` in this pass. It is interactive and needs a native content-bearing process table modal first.

Do not retire the old clock pilot in this pass. The current clock native path still uses `native_mount.rs`, which is whole-column. A later pass should move clock into `native_panels.rs` and then delete the old whole-column mount path.

Before executing, fast-forward the local branch to the merged PR base:

```bash
git status --short --branch
git fetch origin master post-web-runtime
git merge --ff-only origin/master
git status --short --branch
```

Expected:
- Branch remains `post-web-runtime`.
- `HEAD` moves to the PR #11 merge commit or newer `origin/master`.
- Known unrelated local drift may remain unstaged: `package.json`, `bun.lock`, `tsconfig.json`.
- If Git reports a local-change conflict, stop and inspect; do not overwrite user drift.

## File Structure

**Modify:**
- `src-tauri/src/native_panels.rs` - extend slot registry to support `mod_cpuinfo` and `mod_ramwatcher`; add renderer layers, pure calculation helpers, feed start commands, and AppKit layout/update code.
- `src-tauri/src/lib.rs` - register the two new Tauri commands.
- `src-tauri/src/settings.rs` - add default flags `experimentalNativeCpuinfo: false` and `experimentalNativeRamwatcher: false`.
- `src/bridge/native_panels.js` - add `startCpuinfo(anchorId, options)` and `startRamwatcher(anchorId)` wrappers.
- `src/bridge/native_panels.test.js` - test the new bridge command shapes and mount ordering.
- `src/classes/cpuinfo.class.js` - add native gate; native path creates only the anchor and starts the native CPU feed.
- `src/classes/ramwatcher.class.js` - add native gate; native path creates only the anchor and starts the native RAM feed.

**Do not modify:**
- `package.json`, `bun.lock`, `tsconfig.json` unless the user explicitly asks. They are unrelated local drift.
- `src-tauri/capabilities/default.json`. These are custom commands, so no capability entry is needed.

---

## Task 1: Add Pure Phase 2 Helpers And Tests

**Files:**
- Modify: `src-tauri/src/native_panels.rs`

- [ ] **Step 1: Add failing tests for CPU/RAM math**

Append these tests inside the existing `#[cfg(test)] mod tests` in `src-tauri/src/native_panels.rs`:

```rust
#[test]
fn cpu_half_averages_split_even_and_odd_core_counts() {
    assert_eq!(cpu_half_averages(&[10.0, 20.0, 30.0, 40.0]), (15, 35));
    assert_eq!(cpu_half_averages(&[10.0, 20.0, 30.0, 40.0, 50.0]), (15, 40));
    assert_eq!(cpu_half_averages(&[]), (0, 0));
}

#[test]
fn ram_grid_counts_match_legacy_rounding() {
    let counts = ram_grid_counts(1000, 400, 700, 600);
    assert_eq!(counts.active, 176);
    assert_eq!(counts.available, 44);
    assert_eq!(counts.free, 220);
}

#[test]
fn ram_grid_counts_clamp_invalid_totals() {
    let counts = ram_grid_counts(0, 400, 700, 600);
    assert_eq!(counts.active, 0);
    assert_eq!(counts.available, 0);
    assert_eq!(counts.free, 440);
}

#[test]
fn gib_tenths_uses_legacy_divisor() {
    assert_eq!(gib_tenths(1_073_742_000), "1.0");
    assert_eq!(gib_tenths(1_610_613_000), "1.5");
}

#[test]
fn swap_percent_handles_missing_swap_total() {
    assert_eq!(swap_percent(0, 0), 0);
    assert_eq!(swap_percent(50, 200), 25);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd src-tauri && cargo test --lib native_panels
```

Expected: FAIL with missing helper/type names such as `cpu_half_averages`, `RamGridCounts`, `ram_grid_counts`, `gib_tenths`, and `swap_percent`.

- [ ] **Step 3: Add minimal helper implementations**

Add this code above `#[cfg(test)] mod tests` in `src-tauri/src/native_panels.rs`:

```rust
const RAM_GRID_CELLS: usize = 440;
const LEGACY_GIB_DIVISOR: f64 = 1_073_742_000.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct RamGridCounts {
    active: usize,
    available: usize,
    free: usize,
}

fn cpu_half_averages(loads: &[f64]) -> (u32, u32) {
    if loads.is_empty() {
        return (0, 0);
    }
    let divide = loads.len() / 2;
    let first = average_rounded(&loads[..divide]);
    let second = average_rounded(&loads[divide..]);
    (first, second)
}

fn average_rounded(loads: &[f64]) -> u32 {
    if loads.is_empty() {
        return 0;
    }
    (loads.iter().copied().sum::<f64>() / loads.len() as f64).round() as u32
}

fn ram_grid_counts(total: u64, active: u64, available: u64, free: u64) -> RamGridCounts {
    if total == 0 {
        return RamGridCounts {
            active: 0,
            available: 0,
            free: RAM_GRID_CELLS,
        };
    }
    let active_cells = ((RAM_GRID_CELLS as f64 * active as f64) / total as f64).round();
    let available_bytes = available.saturating_sub(free);
    let available_cells = ((RAM_GRID_CELLS as f64 * available_bytes as f64) / total as f64).round();
    let active = (active_cells as usize).min(RAM_GRID_CELLS);
    let available = (available_cells as usize).min(RAM_GRID_CELLS.saturating_sub(active));
    RamGridCounts {
        active,
        available,
        free: RAM_GRID_CELLS.saturating_sub(active + available),
    }
}

fn gib_tenths(bytes: u64) -> String {
    let value = ((bytes as f64 / LEGACY_GIB_DIVISOR) * 10.0).round() / 10.0;
    format!("{value:.1}")
}

fn swap_percent(used: u64, total: u64) -> u32 {
    if total == 0 {
        return 0;
    }
    ((100.0 * used as f64) / total as f64).round() as u32
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd src-tauri && cargo test --lib native_panels
```

Expected: PASS, including the new helper tests.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/native_panels.rs
git commit -m "test(native): cover cpu and ram panel helper math"
```

---

## Task 2: Extend The Bridge For Rust-Owned Feeds

**Files:**
- Modify: `src/bridge/native_panels.js`
- Modify: `src/bridge/native_panels.test.js`

- [ ] **Step 1: Add failing bridge tests**

Append to `src/bridge/native_panels.test.js`:

```js
test("startCpuinfo mounts before starting native CPU feed", async () => {
    const h = freshBridge({ anchors: ["mod_cpuinfo"] });
    await h.window.bridge.nativePanels.startCpuinfo("mod_cpuinfo", { collapseThreadsByName: true });

    assert.deepEqual(h.invokeCalls.map(c => c.cmd), [
        "native_panel_mount",
        "native_panel_set_rect",
        "native_panel_set_visible",
        "native_panel_start_cpuinfo",
    ]);
    assert.deepEqual(h.invokeCalls[3].payload, {
        anchor: "mod_cpuinfo",
        collapseThreadsByName: true,
    });
});

test("startRamwatcher mounts before starting native RAM feed", async () => {
    const h = freshBridge({ anchors: ["mod_ramwatcher"] });
    await h.window.bridge.nativePanels.startRamwatcher("mod_ramwatcher");

    assert.deepEqual(h.invokeCalls.map(c => c.cmd), [
        "native_panel_mount",
        "native_panel_set_rect",
        "native_panel_set_visible",
        "native_panel_start_ramwatcher",
    ]);
    assert.deepEqual(h.invokeCalls[3].payload, { anchor: "mod_ramwatcher" });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
node --test src/bridge/native_panels.test.js
```

Expected: FAIL because `startCpuinfo` and `startRamwatcher` are not functions.

- [ ] **Step 3: Implement bridge wrappers**

In `src/bridge/native_panels.js`, add these functions after `setPanelText`:

```js
    async function startCpuinfo(anchorId, options = {}) {
        await mountPanel(anchorId);
        try {
            await invoke("native_panel_start_cpuinfo", {
                anchor: anchorId,
                collapseThreadsByName: options.collapseThreadsByName === true,
            });
        } catch (e) {
            console.warn("native_panel_start_cpuinfo failed:", e);
        }
    }

    async function startRamwatcher(anchorId) {
        await mountPanel(anchorId);
        try {
            await invoke("native_panel_start_ramwatcher", { anchor: anchorId });
        } catch (e) {
            console.warn("native_panel_start_ramwatcher failed:", e);
        }
    }
```

Update the export object at the bottom from:

```js
    globalScope.bridge.nativePanels = { mountPanel, setPanelText, unmountPanel, setTheme, _resetForTests };
```

to:

```js
    globalScope.bridge.nativePanels = {
        mountPanel,
        setPanelText,
        startCpuinfo,
        startRamwatcher,
        unmountPanel,
        setTheme,
        _resetForTests,
    };
```

- [ ] **Step 4: Run bridge checks**

Run:

```bash
node --check src/bridge/native_panels.js
node --test src/bridge/native_panels.test.js
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/bridge/native_panels.js src/bridge/native_panels.test.js
git commit -m "feat(native): add native panel feed bridge methods"
```

---

## Task 3: Add Settings Flags And Frontend Native Gates

**Files:**
- Modify: `src-tauri/src/settings.rs`
- Modify: `src/classes/cpuinfo.class.js`
- Modify: `src/classes/ramwatcher.class.js`

- [ ] **Step 1: Add default settings flags**

In `src-tauri/src/settings.rs`, add the new defaults near the other native flags:

```rust
        "experimentalNativeCpuinfo": false,
        "experimentalNativeRamwatcher": false,
```

The block should read:

```rust
        "experimentalNativePanels": false,
        "experimentalNativeClock": false,
        "experimentalNativeSysinfo": false,
        "experimentalNativeHwInspector": false,
        "experimentalNativeCpuinfo": false,
        "experimentalNativeRamwatcher": false,
        "experimentalNativeModal": false
```

- [ ] **Step 2: Convert `Cpuinfo` constructor to a native anchor path**

In `src/classes/cpuinfo.class.js`, after `this.container = document.getElementById("mod_cpuinfo");`, insert:

```js
        this.native = window.settings.experimentalNativePanels === true
            && window.settings.experimentalNativeCpuinfo === true
            && window.bridge
            && window.bridge.nativePanels
            && typeof window.bridge.nativePanels.startCpuinfo === "function";

        if (this.native) {
            window.bridge.nativePanels.startCpuinfo("mod_cpuinfo", {
                collapseThreadsByName: window.settings.excludeThreadsFromToplist === true,
            });
            return;
        }
```

This leaves `#mod_cpuinfo` in the DOM so the bridge can measure it, but skips smoothie, canvases, and the JS polling interval.

- [ ] **Step 3: Convert `RAMwatcher` constructor to a native anchor path**

In `src/classes/ramwatcher.class.js`, after `this.parent.append(modExtContainer);`, insert:

```js
        this.native = window.settings.experimentalNativePanels === true
            && window.settings.experimentalNativeRamwatcher === true
            && window.bridge
            && window.bridge.nativePanels
            && typeof window.bridge.nativePanels.startRamwatcher === "function";

        if (this.native) {
            window.bridge.nativePanels.startRamwatcher("mod_ramwatcher");
            return;
        }
```

This leaves the existing anchor markup measurable. It skips the 440 DOM point shuffle, the JS `panelSnapshot` poll, and DOM writes when the native flag is on.

- [ ] **Step 4: Run JS syntax checks**

Run:

```bash
node --check src/classes/cpuinfo.class.js
node --check src/classes/ramwatcher.class.js
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/settings.rs src/classes/cpuinfo.class.js src/classes/ramwatcher.class.js
git commit -m "feat(native): gate cpu and ram panels behind native flags"
```

---

## Task 4: Build CPUINFO Native Slot Renderer

**Files:**
- Modify: `src-tauri/src/native_panels.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Extend valid anchors and slot storage**

In `native_panels.rs`, update `valid_anchor`:

```rust
fn valid_anchor(anchor: &str) -> bool {
    matches!(
        anchor,
        "mod_sysinfo" | "mod_hardwareInspector" | "mod_cpuinfo" | "mod_ramwatcher"
    )
}
```

Extend `Slot` with these fields:

```rust
    shape_layers: HashMap<String, usize>,
    fill_layers: HashMap<String, usize>,
    point_layers: Vec<usize>,
    feed_seq: u64,
    cpu_load_history: Vec<Vec<f64>>,
```

Initialize them in `build_slot`:

```rust
        shape_layers: HashMap::new(),
        fill_layers: HashMap::new(),
        point_layers: Vec::new(),
        feed_seq: 0,
        cpu_load_history: Vec::new(),
```

Include these collections in `set_contents_scale` and `release_slot` so shape/fill/point layers receive `contentsScale` and are released on unmount.

- [ ] **Step 2: Add CPU layers**

Add this arm in `build_slot`:

```rust
        "mod_cpuinfo" => build_cpuinfo_layers(root_layer, &mut slot),
```

Add this builder:

```rust
unsafe fn build_cpuinfo_layers(root_layer: id, slot: &mut Slot) {
    for (key, text, size) in [
        ("cpu_title", "CPU USAGE", 11.0),
        ("cpu_name", "", 9.0),
        ("cpu_group_0", "# 1 - 0", 10.0),
        ("cpu_avg_0", "Avg. --%", 10.0),
        ("cpu_group_1", "# 1 - 0", 10.0),
        ("cpu_avg_1", "Avg. --%", 10.0),
        ("cpu_temp_label", "TEMP", 10.0),
        ("cpu_speed_label", "SPD", 10.0),
        ("cpu_max_label", "MAX", 10.0),
        ("cpu_tasks_label", "TASKS", 10.0),
    ] {
        let layer = make_text_layer(root_layer, text, size, "left");
        slot.text_layers.insert(key.to_string(), layer as usize);
        slot.label_layers.push(layer as usize);
    }

    for key in ["cpu_temp", "cpu_speed", "cpu_max", "cpu_tasks"] {
        let layer = make_text_layer(root_layer, "--", 10.0, "center");
        slot.text_layers.insert(key.to_string(), layer as usize);
        slot.value_layers.push(layer as usize);
    }

    for key in ["cpu_graph_0_top", "cpu_graph_0_bottom", "cpu_graph_1_top", "cpu_graph_1_bottom", "cpu_footer_dash"] {
        let layer: id = msg_send![class!(CALayer), layer];
        let _: () = msg_send![root_layer, addSublayer: layer];
        let _: id = msg_send![layer, retain];
        slot.border_layers.push(layer as usize);
        slot.fill_layers.insert(key.to_string(), layer as usize);
    }
}
```

- [ ] **Step 3: Add CPU layout**

In `layout_slot`, add:

```rust
        "mod_cpuinfo" => layout_cpuinfo(slot, width, height),
```

Add this layout function:

```rust
unsafe fn layout_cpuinfo(slot: &Slot, width: f64, height: f64) {
    let pad_x = 6.0;
    let title_h = (height * 0.12).clamp(10.0, 16.0);
    let row_h = (height * 0.24).clamp(32.0, 54.0);
    let graph_w = width * 0.76;
    let label_w = (width - graph_w - pad_x * 3.0).max(42.0);
    let graph_x = width - graph_w - pad_x;
    let row1_y = height * 0.46;
    let row2_y = height * 0.20;
    let footer_y = 3.0;
    let footer_h = (height * 0.16).clamp(16.0, 24.0);

    set_layer_frame(slot.text_layers["cpu_title"] as id, pad_x, height - title_h - 4.0, width * 0.45, title_h);
    set_layer_frame(slot.text_layers["cpu_name"] as id, width * 0.30, height - title_h - 5.0, width * 0.65, title_h);

    set_layer_frame(slot.text_layers["cpu_group_0"] as id, pad_x, row1_y + row_h * 0.45, label_w, 13.0);
    set_layer_frame(slot.text_layers["cpu_avg_0"] as id, pad_x, row1_y + row_h * 0.18, label_w, 13.0);
    set_layer_frame(slot.text_layers["cpu_group_1"] as id, pad_x, row2_y + row_h * 0.45, label_w, 13.0);
    set_layer_frame(slot.text_layers["cpu_avg_1"] as id, pad_x, row2_y + row_h * 0.18, label_w, 13.0);

    for (key, y) in [("cpu_graph_0_top", row1_y + row_h), ("cpu_graph_0_bottom", row1_y), ("cpu_graph_1_top", row2_y + row_h), ("cpu_graph_1_bottom", row2_y)] {
        set_layer_frame(slot.fill_layers[key] as id, graph_x, y, graph_w, 1.0);
    }
    set_layer_frame(slot.fill_layers["cpu_footer_dash"] as id, width * 0.025, footer_y + footer_h + 3.0, width * 0.95, 1.0);

    let cell_w = width * 0.95 / 4.0;
    let labels = ["cpu_temp_label", "cpu_speed_label", "cpu_max_label", "cpu_tasks_label"];
    let values = ["cpu_temp", "cpu_speed", "cpu_max", "cpu_tasks"];
    for i in 0..4 {
        let x = width * 0.025 + i as f64 * cell_w;
        set_layer_frame(slot.text_layers[labels[i]] as id, x, footer_y + 10.0, cell_w, 11.0);
        set_layer_frame(slot.text_layers[values[i]] as id, x, footer_y, cell_w, 11.0);
    }
}
```

- [ ] **Step 4: Add CPU feed command skeleton**

At the top of `native_panels.rs`, add:

```rust
use std::sync::Arc;
use std::time::Duration;
use crate::sysinfo_service::{PanelSnapshot, SysinfoService};
```

Add command:

```rust
#[tauri::command(rename_all = "camelCase")]
pub async fn native_panel_start_cpuinfo(
    app: AppHandle,
    state: State<'_, NativePanelsState>,
    svc: State<'_, Arc<SysinfoService>>,
    anchor: String,
    collapse_threads_by_name: bool,
) -> Result<(), String> {
    if anchor != "mod_cpuinfo" {
        eprintln!("native_panels: native_panel_start_cpuinfo called for `{anchor}`");
        return Ok(());
    }
    let feed_seq = bump_feed_seq(&state, &anchor)?;
    let svc = Arc::clone(&svc);
    tauri::async_runtime::spawn(async move {
        loop {
            if !feed_is_current(&app, &anchor, feed_seq) {
                break;
            }
            match panel_snapshot_blocking(Arc::clone(&svc), collapse_threads_by_name).await {
                Ok(snapshot) => update_cpuinfo_slot(&app, &anchor, snapshot),
                Err(e) => eprintln!("native_panels: cpuinfo snapshot failed: {e}"),
            }
            tauri::async_runtime::sleep(Duration::from_millis(1000)).await;
        }
    });
    Ok(())
}
```

Add helpers:

```rust
fn bump_feed_seq(state: &NativePanelsState, anchor: &str) -> Result<u64, String> {
    let mut slots = state
        .slots
        .lock()
        .map_err(|_| "native_panels: feed lock poisoned".to_string())?;
    let Some(slot) = slots.get_mut(anchor) else {
        return Ok(0);
    };
    slot.feed_seq = slot.feed_seq.saturating_add(1);
    Ok(slot.feed_seq)
}

fn feed_is_current(app: &AppHandle, anchor: &str, feed_seq: u64) -> bool {
    let state = app.state::<NativePanelsState>();
    let Ok(slots) = state.slots.lock() else {
        return false;
    };
    slots.get(anchor).map(|slot| slot.feed_seq == feed_seq).unwrap_or(false)
}

async fn panel_snapshot_blocking(
    svc: Arc<SysinfoService>,
    collapse_threads_by_name: bool,
) -> Result<PanelSnapshot, String> {
    tauri::async_runtime::spawn_blocking(move || {
        svc.panel_snapshot(collapse_threads_by_name, 5, false)
    })
    .await
    .map_err(|e| e.to_string())?
}
```

Register `native_panels::native_panel_start_cpuinfo` in `src-tauri/src/lib.rs` near the other native panel commands.

- [ ] **Step 5: Implement CPU text/chart updates**

Add:

```rust
fn update_cpuinfo_slot(app: &AppHandle, anchor: &str, snapshot: PanelSnapshot) {
    let anchor = anchor.to_string();
    Queue::main().exec_async(move || unsafe {
        let state = app.state::<NativePanelsState>();
        let Ok(mut slots) = state.slots.lock() else {
            eprintln!("native_panels: cpuinfo update lock poisoned");
            return;
        };
        let Some(slot) = slots.get_mut(&anchor) else {
            return;
        };
        apply_cpuinfo_snapshot(slot, snapshot);
    });
}

unsafe fn apply_cpuinfo_snapshot(slot: &mut Slot, snapshot: PanelSnapshot) {
    let cpu = snapshot.cpu;
    let loads: Vec<f64> = snapshot.current_load.cpus.iter().map(|cpu| cpu.load).collect();
    let divide = loads.len() / 2;
    if slot.cpu_load_history.len() != loads.len() {
        slot.cpu_load_history = vec![Vec::new(); loads.len()];
    }
    for (idx, load) in loads.iter().copied().enumerate() {
        let history = &mut slot.cpu_load_history[idx];
        history.push(load.clamp(0.0, 100.0));
        if history.len() > 90 {
            let drain = history.len() - 90;
            history.drain(0..drain);
        }
    }
    let (avg0, avg1) = cpu_half_averages(&loads);
    set_text(slot, "cpu_name", &format!("{}{}", cpu.manufacturer, cpu.brand).chars().take(30).collect::<String>());
    set_text(slot, "cpu_group_0", &format!("# 1 - {divide}"));
    set_text(slot, "cpu_avg_0", &format!("Avg. {avg0}%"));
    set_text(slot, "cpu_group_1", &format!("# {} - {}", divide + 1, loads.len()));
    set_text(slot, "cpu_avg_1", &format!("Avg. {avg1}%"));
    set_text(slot, "cpu_temp", &format!("{}°C", snapshot.cpu_temperature.max));
    set_text(slot, "cpu_speed", &format!("{}GHz", cpu.speed));
    set_text(slot, "cpu_max", &format!("{}GHz", cpu.speed_max));
    set_text(slot, "cpu_tasks", &format!("{}", snapshot.process_count));
    redraw_cpu_graphs(slot, divide);
}
```

Add `set_text`:

```rust
unsafe fn set_text(slot: &Slot, key: &str, text: &str) {
    let Some(layer) = slot.text_layers.get(key).copied() else {
        return;
    };
    let ns_text = NSString::alloc(nil).init_str(text);
    let _: () = msg_send![layer as id, setString: ns_text];
    let _: () = msg_send![ns_text, release];
}
```

For `redraw_cpu_graphs`, create one `CAShapeLayer` per CPU history key on demand and set its path to a polyline inside the graph frame. The `core-graphics` version in this repo exposes immutable path wrappers, so use the small raw Core Graphics path FFI below for mutable line paths:

```rust
use core_graphics::sys::CGPathRef;
use std::os::raw::c_void;

type CGMutablePathRef = *mut c_void;

unsafe extern "C" {
    fn CGPathCreateMutable() -> CGMutablePathRef;
    fn CGPathMoveToPoint(path: CGMutablePathRef, m: *const c_void, x: f64, y: f64);
    fn CGPathAddLineToPoint(path: CGMutablePathRef, m: *const c_void, x: f64, y: f64);
    fn CGPathRelease(path: CGPathRef);
}
```

Implementation:

```rust
unsafe fn redraw_cpu_graphs(slot: &mut Slot, divide: usize) {
    let graph_frames = [
        (
            layer_frame(slot.fill_layers["cpu_graph_0_top"] as id),
            layer_frame(slot.fill_layers["cpu_graph_0_bottom"] as id),
        ),
        (
            layer_frame(slot.fill_layers["cpu_graph_1_top"] as id),
            layer_frame(slot.fill_layers["cpu_graph_1_bottom"] as id),
        ),
    ];
    for core_idx in 0..slot.cpu_load_history.len() {
        let graph_idx = if core_idx < divide { 0 } else { 1 };
        let (top_frame, bottom_frame) = graph_frames[graph_idx];
        let graph_x = top_frame.origin.x;
        let graph_w = top_frame.size.width;
        let graph_y = bottom_frame.origin.y;
        let graph_h = (top_frame.origin.y - bottom_frame.origin.y).max(1.0);
        let key = format!("cpu_line_{core_idx}");
        let layer = get_or_make_shape_layer(slot, &key);
        let path = CGPathCreateMutable();
        let history = &slot.cpu_load_history[core_idx];
        for (i, value) in history.iter().enumerate() {
            let denom = (history.len().saturating_sub(1)).max(1) as f64;
            let x = graph_x + (i as f64 / denom) * graph_w;
            let y = graph_y + graph_h - ((*value / 100.0) * graph_h);
            if i == 0 {
                CGPathMoveToPoint(path, std::ptr::null(), x, y);
            } else {
                CGPathAddLineToPoint(path, std::ptr::null(), x, y);
            }
        }
        let _: () = msg_send![layer, setPath: path as CGPathRef];
        CGPathRelease(path as CGPathRef);
    }
}
```

If `layer_frame` or `get_or_make_shape_layer` does not exist yet, add:

```rust
unsafe fn layer_frame(layer: id) -> NSRect {
    msg_send![layer, frame]
}

unsafe fn get_or_make_shape_layer(slot: &mut Slot, key: &str) -> id {
    if let Some(layer) = slot.shape_layers.get(key).copied() {
        return layer as id;
    }
    let layer: id = msg_send![class!(CAShapeLayer), layer];
    let color = themed_color(&ThemeSnapshot::default(), 1.0);
    let _: () = msg_send![layer, setStrokeColor: color.as_concrete_TypeRef()];
    let _: () = msg_send![layer, setFillColor: nil];
    let _: () = msg_send![layer, setLineWidth: 1.7_f64];
    let _: () = msg_send![slot.root_layer(), addSublayer: layer];
    let _: id = msg_send![layer, retain];
    slot.shape_layers.insert(key.to_string(), layer as usize);
    layer
}
```

- [ ] **Step 6: Run Rust checks**

Run:

```bash
cd src-tauri && cargo test --lib native_panels && cargo check
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src-tauri/src/native_panels.rs src-tauri/src/lib.rs
git commit -m "feat(native): render cpuinfo in native panel slot"
```

---

## Task 5: Build RAMWATCHER Native Slot Renderer

**Files:**
- Modify: `src-tauri/src/native_panels.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Add RAM layer builder**

Add this arm in `build_slot`:

```rust
        "mod_ramwatcher" => build_ramwatcher_layers(root_layer, &mut slot),
```

Add builder:

```rust
unsafe fn build_ramwatcher_layers(root_layer: id, slot: &mut Slot) {
    for (key, text, size) in [
        ("ram_title", "MEMORY", 11.0),
        ("ram_info", "", 9.0),
        ("ram_swap_label", "SWAP", 10.0),
        ("ram_swap_text", "0.0 GiB", 10.0),
    ] {
        let layer = make_text_layer(root_layer, text, size, "left");
        slot.text_layers.insert(key.to_string(), layer as usize);
        slot.label_layers.push(layer as usize);
    }

    let track: id = msg_send![class!(CALayer), layer];
    let fill: id = msg_send![class!(CALayer), layer];
    let _: () = msg_send![root_layer, addSublayer: track];
    let _: () = msg_send![root_layer, addSublayer: fill];
    let _: id = msg_send![track, retain];
    let _: id = msg_send![fill, retain];
    slot.fill_layers.insert("ram_swap_track".to_string(), track as usize);
    slot.fill_layers.insert("ram_swap_fill".to_string(), fill as usize);

    for _ in 0..RAM_GRID_CELLS {
        let dot: id = msg_send![class!(CALayer), layer];
        let _: () = msg_send![root_layer, addSublayer: dot];
        let _: id = msg_send![dot, retain];
        slot.point_layers.push(dot as usize);
    }
    shuffle_ram_points(&mut slot.point_layers);
}
```

Add deterministic shuffle so tests/smoke are stable:

```rust
fn shuffle_ram_points(points: &mut [usize]) {
    let mut seed = 0xEDEX_2026_u64;
    for i in (1..points.len()).rev() {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
        let j = (seed as usize) % (i + 1);
        points.swap(i, j);
    }
}
```

- [ ] **Step 2: Add RAM layout**

In `layout_slot`, add:

```rust
        "mod_ramwatcher" => layout_ramwatcher(slot, width, height),
```

Add:

```rust
unsafe fn layout_ramwatcher(slot: &Slot, width: f64, height: f64) {
    let pad_x = 6.0;
    let title_h = (height * 0.14).clamp(10.0, 16.0);
    set_layer_frame(slot.text_layers["ram_title"] as id, pad_x, height - title_h - 4.0, width * 0.35, title_h);
    set_layer_frame(slot.text_layers["ram_info"] as id, width * 0.30, height - title_h - 4.0, width * 0.68, title_h);

    let grid_x = pad_x;
    let grid_y = height * 0.26;
    let grid_w = width - pad_x * 2.0;
    let grid_h = height * 0.48;
    let col_gap = grid_w / 40.0;
    let row_gap = grid_h / 11.0;
    let dot_w = (col_gap * 0.28).max(1.0);
    let dot_h = (row_gap * 0.34).max(1.0);

    for visual_idx in 0..slot.point_layers.len() {
        let col = visual_idx / 11;
        let row = visual_idx % 11;
        let x = grid_x + col as f64 * col_gap;
        let y = grid_y + (10 - row) as f64 * row_gap;
        set_layer_frame(slot.point_layers[visual_idx] as id, x, y, dot_w, dot_h);
    }

    let swap_y = 5.0;
    set_layer_frame(slot.text_layers["ram_swap_label"] as id, pad_x, swap_y, width * 0.15, 12.0);
    set_layer_frame(slot.fill_layers["ram_swap_track"] as id, width * 0.18, swap_y + 5.0, width * 0.62, 2.0);
    set_layer_frame(slot.fill_layers["ram_swap_fill"] as id, width * 0.18, swap_y + 4.0, 0.0, 3.0);
    set_layer_frame(slot.text_layers["ram_swap_text"] as id, width * 0.80, swap_y, width * 0.18, 12.0);
}
```

- [ ] **Step 3: Add RAM feed command**

Add imports:

```rust
use crate::sysinfo_service::MemStats;
```

Add command:

```rust
#[tauri::command]
pub async fn native_panel_start_ramwatcher(
    app: AppHandle,
    state: State<'_, NativePanelsState>,
    svc: State<'_, Arc<SysinfoService>>,
    anchor: String,
) -> Result<(), String> {
    if anchor != "mod_ramwatcher" {
        eprintln!("native_panels: native_panel_start_ramwatcher called for `{anchor}`");
        return Ok(());
    }
    let feed_seq = bump_feed_seq(&state, &anchor)?;
    let svc = Arc::clone(&svc);
    tauri::async_runtime::spawn(async move {
        loop {
            if !feed_is_current(&app, &anchor, feed_seq) {
                break;
            }
            match mem_blocking(Arc::clone(&svc)).await {
                Ok(mem) => update_ramwatcher_slot(&app, &anchor, mem),
                Err(e) => eprintln!("native_panels: ramwatcher mem failed: {e}"),
            }
            tauri::async_runtime::sleep(Duration::from_millis(1500)).await;
        }
    });
    Ok(())
}

async fn mem_blocking(svc: Arc<SysinfoService>) -> Result<MemStats, String> {
    tauri::async_runtime::spawn_blocking(move || svc.mem())
        .await
        .map_err(|e| e.to_string())?
}
```

Register `native_panels::native_panel_start_ramwatcher` in `src-tauri/src/lib.rs`.

- [ ] **Step 4: Implement RAM updates**

Add:

```rust
fn update_ramwatcher_slot(app: &AppHandle, anchor: &str, mem: MemStats) {
    let anchor = anchor.to_string();
    Queue::main().exec_async(move || unsafe {
        let state = app.state::<NativePanelsState>();
        let Ok(slots) = state.slots.lock() else {
            eprintln!("native_panels: ramwatcher update lock poisoned");
            return;
        };
        let Some(slot) = slots.get(&anchor) else {
            return;
        };
        apply_ramwatcher_snapshot(slot, mem);
    });
}

unsafe fn apply_ramwatcher_snapshot(slot: &Slot, mem: MemStats) {
    if mem.total == 0 || mem.free.saturating_add(mem.used) != mem.total {
        return;
    }
    let counts = ram_grid_counts(mem.total, mem.active, mem.available, mem.free);
    set_text(slot, "ram_info", &format!("USING {} OUT OF {} GiB", gib_tenths(mem.active), gib_tenths(mem.total)));
    set_text(slot, "ram_swap_text", &format!("{} GiB", gib_tenths(mem.swapused)));

    for (idx, layer) in slot.point_layers.iter().copied().enumerate() {
        let opacity = if idx < counts.active {
            1.0_f32
        } else if idx < counts.active + counts.available {
            0.3_f32
        } else {
            0.1_f32
        };
        let _: () = msg_send![layer as id, setOpacity: opacity];
    }

    let percent = swap_percent(mem.swapused, mem.swaptotal).min(100);
    let track_frame = layer_frame(slot.fill_layers["ram_swap_track"] as id);
    set_layer_frame(
        slot.fill_layers["ram_swap_fill"] as id,
        track_frame.origin.x,
        track_frame.origin.y - 1.0,
        track_frame.size.width * (percent as f64 / 100.0),
        3.0,
    );
}
```

- [ ] **Step 5: Ensure theme restyles RAM/CPU layers**

In `restyle_slot`, after text colors are applied, also color shape/fill/point layers:

```rust
    let border = themed_color(theme, BORDER_ALPHA);
    let text = themed_color(theme, 1.0);
    let track = themed_color(theme, 0.4);

    for layer in slot.shape_layers.values() {
        let _: () = msg_send![*layer as id, setStrokeColor: text.as_concrete_TypeRef()];
    }
    for (key, layer) in &slot.fill_layers {
        let color = if key.contains("track") { &track } else { &border };
        let _: () = msg_send![*layer as id, setBackgroundColor: color.as_concrete_TypeRef()];
    }
    for layer in &slot.point_layers {
        let _: () = msg_send![*layer as id, setBackgroundColor: text.as_concrete_TypeRef()];
    }
```

- [ ] **Step 6: Run Rust checks**

Run:

```bash
cd src-tauri && cargo test --lib native_panels && cargo check
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src-tauri/src/native_panels.rs src-tauri/src/lib.rs
git commit -m "feat(native): render ramwatcher in native panel slot"
```

---

## Task 6: Full Validation And Smoke

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run JS checks**

Run:

```bash
node --check src/bridge/native_panels.js
node --check src/classes/cpuinfo.class.js
node --check src/classes/ramwatcher.class.js
node --test src/bridge/native_panels.test.js src/bridge/native_mount.test.js src/bridge/bridge.test.js src/classes/terminalTabs.class.test.js
```

Expected: all tests pass. Current baseline is 41 tests before Phase 2; the added bridge tests should increase the count by 2.

- [ ] **Step 2: Run Rust checks**

Run:

```bash
cd src-tauri
cargo test
cargo fmt --check
cargo clippy -- -D warnings
```

Expected: all pass.

- [ ] **Step 3: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 4: Manual smoke with CPU/RAM flags**

Temporarily enable:

```json
{
  "experimentalNativePanels": true,
  "experimentalNativeSysinfo": true,
  "experimentalNativeHwInspector": true,
  "experimentalNativeCpuinfo": true,
  "experimentalNativeRamwatcher": true
}
```

Run:

```bash
cd src-tauri && cargo +stable tauri dev
```

Expected visual checks:
- `sysinfo`, `hardwareInspector`, `cpuinfo`, and `ramwatcher` render as native overlays.
- `clock` and `toplist` remain DOM unless their own native flags are enabled.
- `body.native-left-active` is absent unless `experimentalNativeClock` is also true.
- CPU panel shows the brand, two graph bands, average labels, temp/speed/max/tasks, and refreshes about once per second.
- RAM panel shows the memory header, scattered dot grid, swap bar/text, and refreshes about every 1.5 seconds.
- Resize the window; all four native panel overlays continue tracking their own DOM anchors.

Restore the original settings file after the smoke run.

- [ ] **Step 5: Commit final validation notes if docs changed**

If the implementation needed deviations from this plan, update this plan's "Execution Notes" section before the final commit:

```bash
git add docs/superpowers/plans/2026-05-29-native-panel-slots-phase2-cpu-ram.md
git commit -m "docs(native): record phase 2 execution notes"
```

If no doc changes are needed, do not create a docs-only commit.

---

## Execution Notes

This section starts empty. During execution, append only concrete deviations from the plan, such as a safer AppKit lifetime pattern or a different chart-layer implementation required by compiler/runtime evidence.

## Self-Review

**Spec coverage:** `cpuinfo` native rendering covers the header, two graph regions, average labels, footer stats, 1 second cadence, theme color/font, and direct `SysinfoService::panel_snapshot` data. `ramwatcher` covers the header readout, 440-cell dot grid with legacy rounding and one-time shuffle, swap bar/text, 1.5 second cadence, theme color/font, and direct `SysinfoService::mem()` data.

**Deferred by design:** `toplist` remains DOM because it needs a native content modal/table first. `clock` remains on the existing pilot path until the old whole-column `native_mount.rs` can be retired safely. Killing OS processes is still out of scope and remains net-new privileged work.

**Placeholder scan:** The plan contains no `TBD`, no unspecified tests, and no instruction to add generic "appropriate handling" without exact behavior.

**Type consistency:** New command names are `native_panel_start_cpuinfo` and `native_panel_start_ramwatcher`; bridge methods are `startCpuinfo` and `startRamwatcher`; flags are `experimentalNativeCpuinfo` and `experimentalNativeRamwatcher`; anchors are `mod_cpuinfo` and `mod_ramwatcher`.
