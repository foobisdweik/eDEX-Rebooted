# Slice 1 — Sysinfo Service Extraction + Inert Layout Seam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the backend prep half of the gpui panel port: a Tauri-agnostic `SysinfoService` that native code can call without `invoke()`, a JSON contract test suite that locks the wire format JS panels depend on, and an inert CSS seam (`body.native-left-active`) plus layout audit that Slice 1b/1c will consume — all with zero user-visible change.

**Architecture:** Rename the existing `SysinfoState` to `SysinfoService` and add 14 typed structs (one per `si_*` command) that derive `Serialize` so their JSON output exactly matches today's `serde_json::json!(...)` payloads. Service methods are sync (`fn cpu(&self) -> Result<CpuStats, String>`); Tauri command wrappers retain the existing `tokio::spawn_blocking` dispatch via a 3-line forwarding pattern. `mod_column.css` gains one specificity-`(1,1,1)` rule that hides `#mod_column_left` when `body.native-left-active` is set — never set in Slice 1. `NATIVE_PORT.md` gains an audit appendix and conversion-log row.

**Tech Stack:** Rust 2021 edition · `sysinfo = "0.32"` · `battery = "0.7"` · `tokio = "1"` (via `tauri::async_runtime`) · `serde = "1"` + `serde_json = "1"` (both already direct deps) · Cargo integration tests (`src-tauri/tests/`) · GitHub Actions on macos-latest · Tauri 2 + WKWebView · plain CSS.

---

## File Structure

**New files:**
- `src-tauri/src/sysinfo_service.rs` (~450 LOC) — Tauri-agnostic service. Owns the `Arc<Mutex<...>>`s, all 14 typed structs, and 14 sync query methods. No `tauri::*` imports.
- `src-tauri/tests/sysinfo_contract.rs` (~350 LOC) — 14 contract tests (one per struct) using deterministic fixtures + `serde_json::to_value` + `assert_eq!` against hand-written `json!({...})` shapes.

**Modified files:**
- `src-tauri/src/sysinfo_cmds.rs` — shrinks from 469 LOC to ~120 LOC. All `json!({...})` construction moves to `sysinfo_service.rs`; this file becomes 14 thin `#[tauri::command] async fn si_xxx(svc: State<'_, Arc<SysinfoService>>) -> Result<XxxStats, String>` wrappers + the `chrono_like_iso` / `days_to_date` helpers (these move with `processes`).
- `src-tauri/src/lib.rs` — line 4: add `mod sysinfo_service;`. Line 8: change `use sysinfo_cmds::SysinfoState;` to `use sysinfo_service::SysinfoService;` and add `use std::sync::Arc;`. Line 18: change `.manage(SysinfoState::new())` to `.manage(Arc::new(SysinfoService::new()))`.
- `src/assets/css/mod_column.css` — append one rule + a comment block (~10 LOC).
- `NATIVE_PORT.md` — insert "## Slice 1 layout audit" section between Inventory (line ~104) and Priorities (line ~106); append one row to Conversion log table.
- `.github/workflows/ci.yml` — add a `rust-test` job (~14 LOC) and add `rust-test` to the `tauri-build` job's `needs:` list.

**Unchanged but worth a note:**
- `src-tauri/Cargo.toml` — no edits. `serde` and `serde_json` are already direct deps (lines 26-27).
- `src/ui.html`, `src/renderer.js`, `src/bridge/*`, every `src/classes/*.class.js` — untouched. The CSS seam is inert; JS panels keep rendering.

**Why this split:** `sysinfo_service.rs` and `sysinfo_cmds.rs` separate by concern (data vs. transport). The service file is consumed by both the Tauri commands and (in Slice 1c) native gpui panel code. The command file's only job is the `#[tauri::command]` ABI + `spawn_blocking` dispatch. The integration-test crate (`tests/sysinfo_contract.rs`) compiles separately and uses `edex_ui_lib::sysinfo_service::*` as its public surface.

---

## Task 1: Set up the service module skeleton

**Files:**
- Create: `src-tauri/src/sysinfo_service.rs`
- Modify: `src-tauri/src/lib.rs:1-8`

- [ ] **Step 1: Create the empty service module**

```rust
// src-tauri/src/sysinfo_service.rs
//! Tauri-agnostic sysinfo service.
//!
//! Owns the cached sysinfo handles (System / Components / Networks / Disks)
//! and exposes typed query methods. Consumed by `sysinfo_cmds.rs` for the
//! JS-side #[tauri::command] surface and (Slice 1c) by the native gpui
//! panel renderer with no `invoke()` round-trip.
//!
//! All query methods are SYNC. Callers that need to keep an async runtime
//! free should wrap calls in `tokio::task::spawn_blocking` (the existing
//! Tauri command wrappers in sysinfo_cmds.rs do this).

use std::sync::{Arc, Mutex};
use sysinfo::{Components, Disks, Networks, System};

pub struct SysinfoService {
    pub(crate) sys: Arc<Mutex<System>>,
    pub(crate) disks: Arc<Mutex<Disks>>,
    pub(crate) networks: Arc<Mutex<Networks>>,
    pub(crate) components: Arc<Mutex<Components>>,
}

impl SysinfoService {
    pub fn new() -> Self {
        use sysinfo::RefreshKind;
        let mut sys = System::new_with_specifics(RefreshKind::everything());
        sys.refresh_all();
        Self {
            sys: Arc::new(Mutex::new(sys)),
            disks: Arc::new(Mutex::new(Disks::new_with_refreshed_list())),
            networks: Arc::new(Mutex::new(Networks::new_with_refreshed_list())),
            components: Arc::new(Mutex::new(Components::new_with_refreshed_list())),
        }
    }
}

impl Default for SysinfoService {
    fn default() -> Self {
        Self::new()
    }
}
```

- [ ] **Step 2: Register the module in lib.rs**

In `src-tauri/src/lib.rs`, change lines 1-8 from:

```rust
mod fs_cmds;
mod pty;
mod settings;
mod sysinfo_cmds;

use pty::PtyManager;
use settings::OverrideState;
use sysinfo_cmds::SysinfoState;
```

To:

```rust
mod fs_cmds;
mod pty;
mod settings;
mod sysinfo_cmds;
mod sysinfo_service;

use pty::PtyManager;
use settings::OverrideState;
use std::sync::Arc;
use sysinfo_cmds::SysinfoState;
use sysinfo_service::SysinfoService;
```

(We keep `SysinfoState` imported for now — it's still wired in `.manage()` on line 18. The swap happens in Task 9 once all services exist.)

- [ ] **Step 3: Verify it compiles**

Run: `cargo +stable build --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin`
Expected: success. May warn `unused import: sysinfo_service::SysinfoService` — that's fine, Task 2 uses it.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/sysinfo_service.rs src-tauri/src/lib.rs
git commit -m "Scaffold sysinfo_service module"
```

---

## Task 2: First service method (CPU) — TDD template

**Files:**
- Create: `src-tauri/tests/sysinfo_contract.rs`
- Modify: `src-tauri/src/sysinfo_service.rs`

This task establishes the TDD pattern for every subsequent struct. Each later task follows the same shape: write contract test → run and watch fail → write struct + method → run and watch pass → commit.

- [ ] **Step 1: Write the failing contract test**

Create `src-tauri/tests/sysinfo_contract.rs`:

```rust
//! JSON wire-shape contract for SysinfoService output.
//!
//! These tests guarantee the serde serialization of each *Stats struct
//! produces the exact JSON shape today's JS panels consume via
//! `window.si.X()` -> #[tauri::command] si_x. They use deterministic
//! fixture structs, NOT live sysinfo values, so they are stable across
//! machines and CI runs.
//!
//! When you rename a serde field or change a struct shape, the matching
//! test fails — that's the gate. If the shape change is intentional,
//! update the test and the JS consumer in the same commit.

use edex_ui_lib::sysinfo_service::*;
use serde_json::json;

#[test]
fn cpu_stats_wire_shape_is_stable() {
    let fixture = CpuStats {
        manufacturer: "Apple".to_string(),
        brand: "M1 Max".to_string(),
        cores: 10,
        physical_cores: 8,
        speed: "3.20".to_string(),
        speed_max: "3.20".to_string(),
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "manufacturer": "Apple",
        "brand": "M1 Max",
        "cores": 10,
        "physicalCores": 8,
        "speed": "3.20",
        "speedMax": "3.20",
    });
    assert_eq!(actual, expected);
}
```

- [ ] **Step 2: Make the test crate visible**

The integration test imports from `edex_ui_lib::sysinfo_service` — that requires the module to be `pub`. In `src-tauri/src/lib.rs` change `mod sysinfo_service;` to `pub mod sysinfo_service;`.

- [ ] **Step 3: Run the test and verify it fails to compile**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: compile error — `cannot find type CpuStats in this scope` or `no items found in sysinfo_service`.

- [ ] **Step 4: Add the CpuStats struct and cpu() method to the service**

Append to `src-tauri/src/sysinfo_service.rs`:

```rust
use serde::Serialize;

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CpuStats {
    pub manufacturer: String,
    pub brand: String,
    pub cores: usize,
    pub physical_cores: usize,
    pub speed: String,
    pub speed_max: String,
}

impl SysinfoService {
    pub fn cpu(&self) -> Result<CpuStats, String> {
        let mut sys = self
            .sys
            .lock()
            .map_err(|_| "sysinfo lock poisoned".to_string())?;
        sys.refresh_cpu_all();
        let cpus = sys.cpus();
        let (brand, freq) = cpus
            .first()
            .map(|c| (c.brand().to_string(), c.frequency()))
            .unwrap_or_default();
        let speed_ghz = (freq as f64) / 1000.0;
        let (manufacturer, brand_only) = match brand.split_once(' ') {
            Some((m, rest)) => (m.to_string(), rest.to_string()),
            None => (String::new(), brand.clone()),
        };
        Ok(CpuStats {
            manufacturer,
            brand: brand_only,
            cores: cpus.len(),
            physical_cores: sys.physical_core_count().unwrap_or(cpus.len()),
            speed: format!("{:.2}", speed_ghz),
            speed_max: format!("{:.2}", speed_ghz),
        })
    }
}
```

- [ ] **Step 5: Run the test and verify it passes**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: `test cpu_stats_wire_shape_is_stable ... ok` — 1 passed.

- [ ] **Step 6: Verify the existing build still works**

Run: `cargo +stable build --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin`
Expected: success. The `SysinfoService` type is still unused by `lib.rs` — warning expected.

- [ ] **Step 7: Commit**

```bash
git add src-tauri/src/sysinfo_service.rs src-tauri/src/lib.rs src-tauri/tests/sysinfo_contract.rs
git commit -m "Add CpuStats + SysinfoService::cpu with wire-shape contract test"
```

---

## Task 3: Load + Temperature + Processes (CPU-family methods)

**Files:**
- Modify: `src-tauri/src/sysinfo_service.rs`
- Modify: `src-tauri/tests/sysinfo_contract.rs`

These three share patterns: all lock `sys` or `components`, all are called by `Cpuinfo`/`Toplist` panels.

- [ ] **Step 1: Write three failing contract tests**

Append to `src-tauri/tests/sysinfo_contract.rs`:

```rust
#[test]
fn load_stats_wire_shape_is_stable() {
    let fixture = LoadStats {
        avg_load: 42.5,
        current_load: 42.5,
        cpus: vec![
            CpuLoad { load: 10.0 },
            CpuLoad { load: 80.0 },
        ],
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "avgLoad": 42.5,
        "currentLoad": 42.5,
        "cpus": [{"load": 10.0}, {"load": 80.0}],
    });
    assert_eq!(actual, expected);
}

#[test]
fn temp_stats_wire_shape_is_stable() {
    let fixture = TempStats {
        main: 55.0,
        max: 67.5,
        cores: vec![55.0, 67.5],
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "main": 55.0,
        "max": 67.5,
        "cores": [55.0, 67.5],
    });
    assert_eq!(actual, expected);
}

#[test]
fn process_list_wire_shape_is_stable() {
    let fixture = ProcessList {
        all: 2,
        running: 2,
        blocked: 0,
        sleeping: 0,
        list: vec![ProcessRow {
            pid: 42,
            name: "edex-ui".to_string(),
            cpu: 12.5,
            mem: 3.4,
            started: "2026-05-22T12:00:00Z".to_string(),
            state: "Run".to_string(),
            user: "501".to_string(),
            command: "/Applications/eDEX-UI.app/Contents/MacOS/edex-ui".to_string(),
        }],
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "all": 2,
        "running": 2,
        "blocked": 0,
        "sleeping": 0,
        "list": [{
            "pid": 42,
            "name": "edex-ui",
            "cpu": 12.5,
            "mem": 3.4,
            "started": "2026-05-22T12:00:00Z",
            "state": "Run",
            "user": "501",
            "command": "/Applications/eDEX-UI.app/Contents/MacOS/edex-ui",
        }],
    });
    assert_eq!(actual, expected);
}
```

- [ ] **Step 2: Run and watch fail**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: compile error — types `LoadStats`, `CpuLoad`, `TempStats`, `ProcessList`, `ProcessRow` not found.

- [ ] **Step 3: Add the three structs + service methods**

Append to `src-tauri/src/sysinfo_service.rs`:

```rust
#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CpuLoad {
    pub load: f64,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LoadStats {
    pub avg_load: f64,
    pub current_load: f64,
    pub cpus: Vec<CpuLoad>,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TempStats {
    pub main: f64,
    pub max: f64,
    pub cores: Vec<f32>,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProcessRow {
    pub pid: u32,
    pub name: String,
    pub cpu: f64,
    pub mem: f64,
    pub started: String,
    pub state: String,
    pub user: String,
    pub command: String,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProcessList {
    pub all: usize,
    pub running: usize,
    pub blocked: usize,
    pub sleeping: usize,
    pub list: Vec<ProcessRow>,
}

impl SysinfoService {
    pub fn current_load(&self) -> Result<LoadStats, String> {
        let mut sys = self
            .sys
            .lock()
            .map_err(|_| "sysinfo lock poisoned".to_string())?;
        sys.refresh_cpu_usage();
        let cpus: Vec<CpuLoad> = sys
            .cpus()
            .iter()
            .map(|c| CpuLoad { load: c.cpu_usage() as f64 })
            .collect();
        let avg = if cpus.is_empty() { 0.0 } else { sys.global_cpu_usage() as f64 };
        Ok(LoadStats { avg_load: avg, current_load: avg, cpus })
    }

    pub fn cpu_temperature(&self) -> Result<TempStats, String> {
        let mut comps = self
            .components
            .lock()
            .map_err(|_| "components lock poisoned".to_string())?;
        comps.refresh();
        let cores: Vec<f32> = comps
            .iter()
            .filter_map(|c| {
                let label = c.label().to_lowercase();
                if label.contains("cpu") || label.contains("core") || label.contains("package") {
                    Some(c.temperature())
                } else {
                    None
                }
            })
            .collect();
        let max = cores.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
        let max_v = if max.is_finite() { max as f64 } else { 0.0 };
        Ok(TempStats { main: max_v, max: max_v, cores })
    }

    pub fn processes(&self) -> Result<ProcessList, String> {
        use sysinfo::{ProcessRefreshKind, ProcessesToUpdate};
        let mut sys = self
            .sys
            .lock()
            .map_err(|_| "sysinfo lock poisoned".to_string())?;
        sys.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::everything(),
        );
        let total_mem = sys.total_memory() as f64;
        let list: Vec<ProcessRow> = sys
            .processes()
            .iter()
            .map(|(pid, p)| ProcessRow {
                pid: pid.as_u32(),
                name: p.name().to_string_lossy().to_string(),
                cpu: p.cpu_usage() as f64,
                mem: if total_mem > 0.0 { (p.memory() as f64) * 100.0 / total_mem } else { 0.0 },
                started: chrono_like_iso(p.start_time()),
                state: format!("{:?}", p.status()),
                user: p.user_id().map(|u| u.to_string()).unwrap_or_default(),
                command: p.cmd().iter().map(|s| s.to_string_lossy().to_string()).collect::<Vec<_>>().join(" "),
            })
            .collect();
        let n = list.len();
        Ok(ProcessList { all: n, running: n, blocked: 0, sleeping: 0, list })
    }
}

// Helpers (moved from sysinfo_cmds.rs; same code, scope changed to service).
fn chrono_like_iso(unix_secs: u64) -> String {
    let secs = unix_secs as i64;
    let days = secs / 86400;
    let mut s = secs % 86400;
    let hour = s / 3600;
    s %= 3600;
    let minute = s / 60;
    let second = s % 60;
    let (year, month, day) = days_to_date(days);
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hour, minute, second
    )
}

fn days_to_date(days_from_epoch: i64) -> (i32, u32, u32) {
    let days = days_from_epoch + 719468;
    let era = (if days >= 0 { days } else { days - 146096 }) / 146097;
    let doe = (days - era * 146097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe as i32 + (era * 400) as i32;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };
    (year, m, d)
}
```

- [ ] **Step 4: Run tests and verify all four pass**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: 4 passed (`cpu_stats_wire_shape_is_stable`, `load_stats_wire_shape_is_stable`, `temp_stats_wire_shape_is_stable`, `process_list_wire_shape_is_stable`).

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/sysinfo_service.rs src-tauri/tests/sysinfo_contract.rs
git commit -m "Add LoadStats/TempStats/ProcessList structs and service methods"
```

---

## Task 4: Memory + Battery

**Files:**
- Modify: `src-tauri/src/sysinfo_service.rs`
- Modify: `src-tauri/tests/sysinfo_contract.rs`

- [ ] **Step 1: Write failing contract tests**

Append to `src-tauri/tests/sysinfo_contract.rs`:

```rust
#[test]
fn mem_stats_wire_shape_is_stable() {
    let fixture = MemStats {
        total: 17_179_869_184,
        free: 4_294_967_296,
        used: 12_884_901_888,
        active: 12_884_901_888,
        available: 4_294_967_296,
        buffers: 0,
        cached: 0,
        slab: 0,
        buffcache: 0,
        swaptotal: 2_147_483_648,
        swapused: 0,
        swapfree: 2_147_483_648,
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "total": 17_179_869_184_u64,
        "free": 4_294_967_296_u64,
        "used": 12_884_901_888_u64,
        "active": 12_884_901_888_u64,
        "available": 4_294_967_296_u64,
        "buffers": 0,
        "cached": 0,
        "slab": 0,
        "buffcache": 0,
        "swaptotal": 2_147_483_648_u64,
        "swapused": 0,
        "swapfree": 2_147_483_648_u64,
    });
    assert_eq!(actual, expected);
}

#[test]
fn battery_present_wire_shape_is_stable() {
    let fixture = BatteryInfo {
        has_battery: true,
        cycle_count: 142,
        is_charging: false,
        designed_capacity: 99.6,
        max_capacity: 94.2,
        current_capacity: 67.5,
        voltage: 12.6,
        capacity_unit: "Wh".to_string(),
        percent: 71,
        time_remaining: 5400,
        ac_connected: false,
        battery_type: "Battery".to_string(),
        model: "bq40z651".to_string(),
        manufacturer: "SMP".to_string(),
        serial: "ABC123".to_string(),
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "hasBattery": true,
        "cycleCount": 142,
        "isCharging": false,
        "designedCapacity": 99.6,
        "maxCapacity": 94.2,
        "currentCapacity": 67.5,
        "voltage": 12.6,
        "capacityUnit": "Wh",
        "percent": 71,
        "timeRemaining": 5400,
        "acConnected": false,
        "type": "Battery",
        "model": "bq40z651",
        "manufacturer": "SMP",
        "serial": "ABC123",
    });
    assert_eq!(actual, expected);
}

#[test]
fn battery_absent_wire_shape_is_stable() {
    let fixture = BatteryInfo::absent();
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "hasBattery": false,
        "cycleCount": 0,
        "isCharging": false,
        "designedCapacity": 0.0,
        "maxCapacity": 0.0,
        "currentCapacity": 0.0,
        "voltage": 0.0,
        "capacityUnit": "",
        "percent": 0,
        "timeRemaining": -1,
        "acConnected": true,
        "type": "",
        "model": "",
        "manufacturer": "",
        "serial": "",
    });
    assert_eq!(actual, expected);
}
```

Note the battery `type` field uses `#[serde(rename = "type")]` because `type` is a reserved word in Rust. The struct field is `battery_type`.

- [ ] **Step 2: Run and watch fail**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: compile errors for `MemStats`, `BatteryInfo`, `BatteryInfo::absent`.

- [ ] **Step 3: Add structs + service methods**

Append to `src-tauri/src/sysinfo_service.rs`:

```rust
#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MemStats {
    pub total: u64,
    pub free: u64,
    pub used: u64,
    pub active: u64,
    pub available: u64,
    pub buffers: u64,
    pub cached: u64,
    pub slab: u64,
    pub buffcache: u64,
    pub swaptotal: u64,
    pub swapused: u64,
    pub swapfree: u64,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BatteryInfo {
    pub has_battery: bool,
    pub cycle_count: u32,
    pub is_charging: bool,
    pub designed_capacity: f64,
    pub max_capacity: f64,
    pub current_capacity: f64,
    pub voltage: f64,
    pub capacity_unit: String,
    pub percent: i64,
    pub time_remaining: i64,
    pub ac_connected: bool,
    #[serde(rename = "type")]
    pub battery_type: String,
    pub model: String,
    pub manufacturer: String,
    pub serial: String,
}

impl BatteryInfo {
    pub fn absent() -> Self {
        Self {
            has_battery: false,
            cycle_count: 0,
            is_charging: false,
            designed_capacity: 0.0,
            max_capacity: 0.0,
            current_capacity: 0.0,
            voltage: 0.0,
            capacity_unit: String::new(),
            percent: 0,
            time_remaining: -1,
            ac_connected: true,
            battery_type: String::new(),
            model: String::new(),
            manufacturer: String::new(),
            serial: String::new(),
        }
    }
}

impl SysinfoService {
    pub fn mem(&self) -> Result<MemStats, String> {
        let mut sys = self
            .sys
            .lock()
            .map_err(|_| "sysinfo lock poisoned".to_string())?;
        sys.refresh_memory();
        let total = sys.total_memory();
        let used = sys.used_memory();
        let free = sys.free_memory();
        let available = sys.available_memory();
        let free_strict = total.saturating_sub(used);
        Ok(MemStats {
            total,
            free: free_strict,
            used,
            active: used,
            available: available.max(free),
            buffers: 0,
            cached: 0,
            slab: 0,
            buffcache: 0,
            swaptotal: sys.total_swap(),
            swapused: sys.used_swap(),
            swapfree: sys.free_swap(),
        })
    }

    pub fn battery(&self) -> Result<BatteryInfo, String> {
        if let Ok(manager) = battery::Manager::new() {
            if let Ok(mut iter) = manager.batteries() {
                if let Some(Ok(bat)) = iter.next() {
                    let percent = (bat.state_of_charge().value * 100.0).round() as i64;
                    let state = bat.state();
                    let charging = matches!(state, battery::State::Charging);
                    let ac = matches!(
                        state,
                        battery::State::Charging | battery::State::Full | battery::State::Unknown
                    );
                    return Ok(BatteryInfo {
                        has_battery: true,
                        cycle_count: bat.cycle_count().unwrap_or(0),
                        is_charging: charging,
                        designed_capacity: bat.energy_full_design().value as f64,
                        max_capacity: bat.energy_full().value as f64,
                        current_capacity: bat.energy().value as f64,
                        voltage: bat.voltage().value as f64,
                        capacity_unit: "Wh".to_string(),
                        percent,
                        time_remaining: bat.time_to_empty().map(|t| t.value as i64).unwrap_or(-1),
                        ac_connected: ac,
                        battery_type: "Battery".to_string(),
                        model: bat.model().unwrap_or("").to_string(),
                        manufacturer: bat.vendor().unwrap_or("").to_string(),
                        serial: bat.serial_number().unwrap_or("").to_string(),
                    });
                }
            }
        }
        Ok(BatteryInfo::absent())
    }
}
```

- [ ] **Step 4: Run tests and verify all 7 pass**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/sysinfo_service.rs src-tauri/tests/sysinfo_contract.rs
git commit -m "Add MemStats + BatteryInfo structs and service methods"
```

---

## Task 5: Network (Interfaces + Stats + Connections)

**Files:**
- Modify: `src-tauri/src/sysinfo_service.rs`
- Modify: `src-tauri/tests/sysinfo_contract.rs`

`network_connections` is a stub returning an empty list (deferred to v0.2, was globe-only consumer). It still gets a struct + method so the wrapper in Task 9 can stay consistent.

- [ ] **Step 1: Write failing contract tests**

Append to `src-tauri/tests/sysinfo_contract.rs`:

```rust
#[test]
fn network_interface_wire_shape_is_stable() {
    let fixture = NetIface {
        iface: "en0".to_string(),
        iface_name: "en0".to_string(),
        default: false,
        ip4: "192.168.1.42".to_string(),
        ip6: "fe80::1".to_string(),
        mac: "aa:bb:cc:dd:ee:ff".to_string(),
        internal: false,
        is_virtual: false,
        operstate: "up".to_string(),
        iface_type: "wireless".to_string(),
        duplex: String::new(),
        mtu: 0,
        speed: -1,
        dhcp: false,
        dns_suffix: String::new(),
        ieee8021x_auth: String::new(),
        ieee8021x_state: String::new(),
        carrier_changes: 0,
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "iface": "en0",
        "ifaceName": "en0",
        "default": false,
        "ip4": "192.168.1.42",
        "ip6": "fe80::1",
        "mac": "aa:bb:cc:dd:ee:ff",
        "internal": false,
        "virtual": false,
        "operstate": "up",
        "type": "wireless",
        "duplex": "",
        "mtu": 0,
        "speed": -1,
        "dhcp": false,
        "dnsSuffix": "",
        "ieee8021xAuth": "",
        "ieee8021xState": "",
        "carrierChanges": 0,
    });
    assert_eq!(actual, expected);
}

#[test]
fn network_stats_wire_shape_is_stable() {
    let fixture = NetStats {
        iface: "en0".to_string(),
        operstate: "up".to_string(),
        rx_bytes: 1_000_000,
        tx_bytes: 500_000,
        rx_dropped: 0,
        tx_dropped: 0,
        rx_errors: 0,
        tx_errors: 0,
        rx_sec: 1234,
        tx_sec: 567,
        ms: 1000,
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "iface": "en0",
        "operstate": "up",
        "rx_bytes": 1_000_000,
        "tx_bytes": 500_000,
        "rx_dropped": 0,
        "tx_dropped": 0,
        "rx_errors": 0,
        "tx_errors": 0,
        "rx_sec": 1234,
        "tx_sec": 567,
        "ms": 1000,
    });
    assert_eq!(actual, expected);
}

#[test]
fn network_connections_is_always_empty() {
    let actual = serde_json::to_value(SysinfoService::network_connections_stub()).unwrap();
    assert_eq!(actual, json!([]));
}
```

Note `iface_type` → `"type"`, `is_virtual` → `"virtual"`, `ieee8021x_auth` → `"ieee8021xAuth"` (sysinfo's serde rename behavior, not pure camelCase, for the latter — handled per-field). The `rx_bytes` / `tx_bytes` keys stay snake_case to match the existing wire format.

- [ ] **Step 2: Run and watch fail**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: compile errors for `NetIface`, `NetStats`, `network_connections_stub`.

- [ ] **Step 3: Add structs + methods**

Append to `src-tauri/src/sysinfo_service.rs`:

```rust
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct NetIface {
    pub iface: String,
    #[serde(rename = "ifaceName")]
    pub iface_name: String,
    pub default: bool,
    pub ip4: String,
    pub ip6: String,
    pub mac: String,
    pub internal: bool,
    #[serde(rename = "virtual")]
    pub is_virtual: bool,
    pub operstate: String,
    #[serde(rename = "type")]
    pub iface_type: String,
    pub duplex: String,
    pub mtu: u32,
    pub speed: i32,
    pub dhcp: bool,
    #[serde(rename = "dnsSuffix")]
    pub dns_suffix: String,
    #[serde(rename = "ieee8021xAuth")]
    pub ieee8021x_auth: String,
    #[serde(rename = "ieee8021xState")]
    pub ieee8021x_state: String,
    #[serde(rename = "carrierChanges")]
    pub carrier_changes: u32,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct NetStats {
    pub iface: String,
    pub operstate: String,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub rx_dropped: u64,
    pub tx_dropped: u64,
    pub rx_errors: u64,
    pub tx_errors: u64,
    pub rx_sec: u64,
    pub tx_sec: u64,
    pub ms: u64,
}

impl SysinfoService {
    pub fn network_interfaces(&self) -> Result<Vec<NetIface>, String> {
        let mut nets = self
            .networks
            .lock()
            .map_err(|_| "networks lock poisoned".to_string())?;
        nets.refresh();
        let mut list = Vec::new();
        for (name, data) in nets.iter() {
            let mut ip4 = String::new();
            let mut ip6 = String::new();
            for net in data.ip_networks() {
                let ip = net.addr;
                if ip.is_ipv4() && ip4.is_empty() {
                    ip4 = ip.to_string();
                } else if ip.is_ipv6() && ip6.is_empty() {
                    ip6 = ip.to_string();
                }
            }
            let internal =
                name == "lo" || name == "lo0" || name.starts_with("utun") || ip4 == "127.0.0.1";
            let operstate = if data.received() > 0 || data.transmitted() > 0 || !ip4.is_empty() {
                "up"
            } else {
                "down"
            };
            list.push(NetIface {
                iface: name.clone(),
                iface_name: name.clone(),
                default: false,
                ip4,
                ip6,
                mac: data.mac_address().to_string(),
                internal,
                is_virtual: false,
                operstate: operstate.to_string(),
                iface_type: "wireless".to_string(),
                duplex: String::new(),
                mtu: 0,
                speed: -1,
                dhcp: false,
                dns_suffix: String::new(),
                ieee8021x_auth: String::new(),
                ieee8021x_state: String::new(),
                carrier_changes: 0,
            });
        }
        Ok(list)
    }

    pub fn network_stats(&self, iface_filter: Option<&str>) -> Result<Vec<NetStats>, String> {
        let mut nets = self
            .networks
            .lock()
            .map_err(|_| "networks lock poisoned".to_string())?;
        nets.refresh();
        let mut out = Vec::new();
        for (name, data) in nets.iter() {
            if let Some(filter) = iface_filter {
                if name != filter {
                    continue;
                }
            }
            out.push(NetStats {
                iface: name.clone(),
                operstate: "up".to_string(),
                rx_bytes: data.total_received(),
                tx_bytes: data.total_transmitted(),
                rx_dropped: 0,
                tx_dropped: 0,
                rx_errors: 0,
                tx_errors: 0,
                rx_sec: data.received(),
                tx_sec: data.transmitted(),
                ms: 1000,
            });
        }
        Ok(out)
    }

    /// Stub — globe-only consumer was removed in v1; deferred to v0.2.
    pub fn network_connections_stub() -> Vec<serde_json::Value> {
        Vec::new()
    }
}
```

- [ ] **Step 4: Run tests and verify all 10 pass**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: 10 passed.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/sysinfo_service.rs src-tauri/tests/sysinfo_contract.rs
git commit -m "Add network interface/stats structs and service methods"
```

---

## Task 6: Disks (FsSize + BlockDevices)

**Files:**
- Modify: `src-tauri/src/sysinfo_service.rs`
- Modify: `src-tauri/tests/sysinfo_contract.rs`

- [ ] **Step 1: Write failing contract tests**

Append to `src-tauri/tests/sysinfo_contract.rs`:

```rust
#[test]
fn disk_info_wire_shape_is_stable() {
    let fixture = DiskInfo {
        fs: "/dev/disk3s1".to_string(),
        disk_type: "SSD".to_string(),
        size: 1_000_000_000_000,
        used: 250_000_000_000,
        available: 750_000_000_000,
        use_pct: 25.0,
        mount: "/".to_string(),
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "fs": "/dev/disk3s1",
        "type": "SSD",
        "size": 1_000_000_000_000_u64,
        "used": 250_000_000_000_u64,
        "available": 750_000_000_000_u64,
        "use": 25.0,
        "mount": "/",
    });
    assert_eq!(actual, expected);
}

#[test]
fn block_device_wire_shape_is_stable() {
    let fixture = BlockDevice {
        name: "/dev/disk3s1".to_string(),
        device_type: "disk".to_string(),
        fs_type: "\"apfs\"".to_string(),
        mount: "/".to_string(),
        size: 1_000_000_000_000,
        physical: "SSD".to_string(),
        uuid: String::new(),
        label: String::new(),
        model: String::new(),
        serial: String::new(),
        removable: false,
        protocol: String::new(),
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "name": "/dev/disk3s1",
        "type": "disk",
        "fsType": "\"apfs\"",
        "mount": "/",
        "size": 1_000_000_000_000_u64,
        "physical": "SSD",
        "uuid": "",
        "label": "",
        "model": "",
        "serial": "",
        "removable": false,
        "protocol": "",
    });
    assert_eq!(actual, expected);
}
```

The doubled quote characters in `fs_type` mirror the existing `format!("{:?}", d.file_system().to_string_lossy())` output — preserving the existing wire shape exactly, even where it looks awkward. JS panels parse this; changing it is out of scope.

- [ ] **Step 2: Run and watch fail**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: compile errors for `DiskInfo`, `BlockDevice`.

- [ ] **Step 3: Add structs + service methods**

Append to `src-tauri/src/sysinfo_service.rs`:

```rust
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct DiskInfo {
    pub fs: String,
    #[serde(rename = "type")]
    pub disk_type: String,
    pub size: u64,
    pub used: u64,
    pub available: u64,
    #[serde(rename = "use")]
    pub use_pct: f64,
    pub mount: String,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct BlockDevice {
    pub name: String,
    #[serde(rename = "type")]
    pub device_type: String,
    #[serde(rename = "fsType")]
    pub fs_type: String,
    pub mount: String,
    pub size: u64,
    pub physical: String,
    pub uuid: String,
    pub label: String,
    pub model: String,
    pub serial: String,
    pub removable: bool,
    pub protocol: String,
}

impl SysinfoService {
    pub fn fs_size(&self) -> Result<Vec<DiskInfo>, String> {
        let mut disks = self
            .disks
            .lock()
            .map_err(|_| "disks lock poisoned".to_string())?;
        disks.refresh();
        let list: Vec<DiskInfo> = disks
            .iter()
            .map(|d| {
                let total = d.total_space();
                let avail = d.available_space();
                let used = total.saturating_sub(avail);
                DiskInfo {
                    fs: d.name().to_string_lossy().to_string(),
                    disk_type: format!("{:?}", d.kind()),
                    size: total,
                    used,
                    available: avail,
                    use_pct: if total > 0 { (used as f64) * 100.0 / (total as f64) } else { 0.0 },
                    mount: d.mount_point().to_string_lossy().to_string(),
                }
            })
            .collect();
        Ok(list)
    }

    pub fn block_devices(&self) -> Result<Vec<BlockDevice>, String> {
        let mut disks = self
            .disks
            .lock()
            .map_err(|_| "disks lock poisoned".to_string())?;
        disks.refresh();
        let list: Vec<BlockDevice> = disks
            .iter()
            .map(|d| {
                let removable = d.is_removable();
                BlockDevice {
                    name: d.name().to_string_lossy().to_string(),
                    device_type: if removable { "usb".to_string() } else { "disk".to_string() },
                    fs_type: format!("{:?}", d.file_system().to_string_lossy()),
                    mount: d.mount_point().to_string_lossy().to_string(),
                    size: d.total_space(),
                    physical: "SSD".to_string(),
                    uuid: String::new(),
                    label: String::new(),
                    model: String::new(),
                    serial: String::new(),
                    removable,
                    protocol: String::new(),
                }
            })
            .collect();
        Ok(list)
    }
}
```

- [ ] **Step 4: Run tests and verify all 12 pass**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: 12 passed.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/sysinfo_service.rs src-tauri/tests/sysinfo_contract.rs
git commit -m "Add DiskInfo + BlockDevice structs and service methods"
```

---

## Task 7: System info (System + Chassis + Uptime)

**Files:**
- Modify: `src-tauri/src/sysinfo_service.rs`
- Modify: `src-tauri/tests/sysinfo_contract.rs`

These three are sync and stateless (no Mutex lock; static OS queries).

- [ ] **Step 1: Write failing contract tests**

Append to `src-tauri/tests/sysinfo_contract.rs`:

```rust
#[test]
fn system_info_wire_shape_is_stable() {
    let fixture = SystemInfo {
        manufacturer: "Apple".to_string(),
        model: "ferases-macbook".to_string(),
        version: "14.5".to_string(),
        serial: String::new(),
        uuid: String::new(),
        sku: String::new(),
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "manufacturer": "Apple",
        "model": "ferases-macbook",
        "version": "14.5",
        "serial": "",
        "uuid": "",
        "sku": "",
    });
    assert_eq!(actual, expected);
}

#[test]
fn chassis_info_wire_shape_is_stable() {
    let fixture = ChassisInfo {
        manufacturer: "Apple".to_string(),
        model: "ferases-macbook".to_string(),
        chassis_type: "Laptop".to_string(),
        version: "Darwin 25.5.0".to_string(),
        serial: String::new(),
        asset_tag: String::new(),
        sku: String::new(),
    };
    let actual = serde_json::to_value(&fixture).unwrap();
    let expected = json!({
        "manufacturer": "Apple",
        "model": "ferases-macbook",
        "type": "Laptop",
        "version": "Darwin 25.5.0",
        "serial": "",
        "assetTag": "",
        "sku": "",
    });
    assert_eq!(actual, expected);
}
```

`uptime` is a `u64` scalar — `serde_json::to_value(&42u64)` produces `Number(42)`. We test the type round-trip but the shape is trivial:

```rust
#[test]
fn uptime_wire_shape_is_stable() {
    let actual = serde_json::to_value(123_456_u64).unwrap();
    assert_eq!(actual, json!(123_456));
}
```

- [ ] **Step 2: Run and watch fail**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: compile errors for `SystemInfo`, `ChassisInfo`.

- [ ] **Step 3: Add structs + service methods**

Append to `src-tauri/src/sysinfo_service.rs`:

```rust
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct SystemInfo {
    pub manufacturer: String,
    pub model: String,
    pub version: String,
    pub serial: String,
    pub uuid: String,
    pub sku: String,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct ChassisInfo {
    pub manufacturer: String,
    pub model: String,
    #[serde(rename = "type")]
    pub chassis_type: String,
    pub version: String,
    pub serial: String,
    #[serde(rename = "assetTag")]
    pub asset_tag: String,
    pub sku: String,
}

impl SysinfoService {
    pub fn system(&self) -> SystemInfo {
        SystemInfo {
            manufacturer: "Apple".to_string(),
            model: System::host_name().unwrap_or_default(),
            version: System::os_version().unwrap_or_default(),
            serial: String::new(),
            uuid: String::new(),
            sku: String::new(),
        }
    }

    pub fn chassis(&self) -> ChassisInfo {
        ChassisInfo {
            manufacturer: "Apple".to_string(),
            model: System::host_name().unwrap_or_default(),
            chassis_type: "Laptop".to_string(),
            version: System::kernel_version().unwrap_or_default(),
            serial: String::new(),
            asset_tag: String::new(),
            sku: String::new(),
        }
    }

    pub fn uptime(&self) -> u64 {
        System::uptime()
    }
}
```

- [ ] **Step 4: Run tests and verify all 15 pass**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: 15 passed.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/sysinfo_service.rs src-tauri/tests/sysinfo_contract.rs
git commit -m "Add SystemInfo + ChassisInfo structs and uptime method"
```

---

## Task 8: Rewrite sysinfo_cmds.rs as thin wrappers

**Files:**
- Modify: `src-tauri/src/sysinfo_cmds.rs` (full rewrite)

This is the largest single-file change. Replace all 469 lines with a wrapper-only module that delegates to `SysinfoService`. Command names, signatures, and the `tauri::async_runtime::spawn_blocking` pattern are preserved so the JS side sees zero change.

- [ ] **Step 1: Replace the entire file contents**

Replace `src-tauri/src/sysinfo_cmds.rs` with:

```rust
//! Tauri command wrappers around SysinfoService.
//!
//! Each #[tauri::command] here is a 3-line forward: clone the service Arc,
//! dispatch the sync service method to a blocking thread (so the async
//! runtime stays free), return the typed result that Tauri's macro will
//! serialize to JSON.
//!
//! The data shapes, refresh semantics, and command names are owned by
//! sysinfo_service.rs and locked by tests/sysinfo_contract.rs.

use crate::sysinfo_service::{
    BatteryInfo, BlockDevice, ChassisInfo, CpuStats, DiskInfo, LoadStats, MemStats, NetIface,
    NetStats, ProcessList, SysinfoService, SystemInfo, TempStats,
};
use std::sync::Arc;
use tauri::{async_runtime, State};

/// Kept for now as an alias so existing `use sysinfo_cmds::SysinfoState;`
/// sites in lib.rs compile during the migration. Removed in Task 9 once
/// lib.rs switches to `SysinfoService` directly.
pub type SysinfoState = SysinfoService;

async fn blocking<T, F>(f: F) -> Result<T, String>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, String> + Send + 'static,
{
    async_runtime::spawn_blocking(f)
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn si_cpu(svc: State<'_, Arc<SysinfoService>>) -> Result<CpuStats, String> {
    let svc = Arc::clone(&svc);
    blocking(move || svc.cpu()).await
}

#[tauri::command]
pub async fn si_current_load(svc: State<'_, Arc<SysinfoService>>) -> Result<LoadStats, String> {
    let svc = Arc::clone(&svc);
    blocking(move || svc.current_load()).await
}

#[tauri::command]
pub async fn si_cpu_temperature(svc: State<'_, Arc<SysinfoService>>) -> Result<TempStats, String> {
    let svc = Arc::clone(&svc);
    blocking(move || svc.cpu_temperature()).await
}

#[tauri::command]
pub async fn si_processes(svc: State<'_, Arc<SysinfoService>>) -> Result<ProcessList, String> {
    let svc = Arc::clone(&svc);
    blocking(move || svc.processes()).await
}

#[tauri::command]
pub async fn si_mem(svc: State<'_, Arc<SysinfoService>>) -> Result<MemStats, String> {
    let svc = Arc::clone(&svc);
    blocking(move || svc.mem()).await
}

#[tauri::command]
pub async fn si_battery(svc: State<'_, Arc<SysinfoService>>) -> Result<BatteryInfo, String> {
    let svc = Arc::clone(&svc);
    blocking(move || svc.battery()).await
}

#[tauri::command]
pub async fn si_network_interfaces(
    svc: State<'_, Arc<SysinfoService>>,
) -> Result<Vec<NetIface>, String> {
    let svc = Arc::clone(&svc);
    blocking(move || svc.network_interfaces()).await
}

#[tauri::command]
pub async fn si_network_stats(
    svc: State<'_, Arc<SysinfoService>>,
    iface: Option<String>,
) -> Result<Vec<NetStats>, String> {
    let svc = Arc::clone(&svc);
    blocking(move || svc.network_stats(iface.as_deref())).await
}

#[tauri::command]
pub fn si_network_connections() -> Vec<serde_json::Value> {
    SysinfoService::network_connections_stub()
}

#[tauri::command]
pub async fn si_fs_size(svc: State<'_, Arc<SysinfoService>>) -> Result<Vec<DiskInfo>, String> {
    let svc = Arc::clone(&svc);
    blocking(move || svc.fs_size()).await
}

#[tauri::command]
pub async fn si_block_devices(
    svc: State<'_, Arc<SysinfoService>>,
) -> Result<Vec<BlockDevice>, String> {
    let svc = Arc::clone(&svc);
    blocking(move || svc.block_devices()).await
}

#[tauri::command]
pub fn si_system(svc: State<'_, Arc<SysinfoService>>) -> SystemInfo {
    svc.system()
}

#[tauri::command]
pub fn si_chassis(svc: State<'_, Arc<SysinfoService>>) -> ChassisInfo {
    svc.chassis()
}

#[tauri::command]
pub fn si_uptime(svc: State<'_, Arc<SysinfoService>>) -> u64 {
    svc.uptime()
}
```

- [ ] **Step 2: Verify it compiles (lib.rs still references SysinfoState alias)**

Run: `cargo +stable build --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin`
Expected: compile errors — `expected State<'_, Arc<SysinfoService>>, found State<'_, SysinfoState>`. That's because lib.rs still calls `.manage(SysinfoState::new())` which puts a bare `SysinfoService` (via the alias) into state, not an `Arc<SysinfoService>`. Task 9 fixes this. **Do not commit yet.**

(If the build succeeds because the type alias makes it equivalent, even better — proceed to Task 9. The point is: Tasks 8 and 9 land together because they're a coupled invariant.)

- [ ] **Step 3: Run contract tests — these should still pass**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --test sysinfo_contract`
Expected: 15 passed. The contract tests don't touch `sysinfo_cmds.rs`.

---

## Task 9: Wire `.manage(Arc::new(SysinfoService::new()))` in lib.rs

**Files:**
- Modify: `src-tauri/src/lib.rs:8, 18`

- [ ] **Step 1: Update the use line and the .manage() call**

In `src-tauri/src/lib.rs`:

Replace line 8:
```rust
use sysinfo_cmds::SysinfoState;
```
with (the `use sysinfo_service::SysinfoService;` and `use std::sync::Arc;` already added in Task 1):
```rust
// SysinfoState removed; lib.rs now manages Arc<SysinfoService> directly.
```

Replace line 18:
```rust
        .manage(SysinfoState::new())
```
with:
```rust
        .manage(Arc::new(SysinfoService::new()))
```

- [ ] **Step 2: Remove the temporary `SysinfoState` alias from sysinfo_cmds.rs**

In `src-tauri/src/sysinfo_cmds.rs` delete these four lines (added in Task 8 step 1):

```rust
/// Kept for now as an alias so existing `use sysinfo_cmds::SysinfoState;`
/// sites in lib.rs compile during the migration. Removed in Task 9 once
/// lib.rs switches to `SysinfoService` directly.
pub type SysinfoState = SysinfoService;
```

- [ ] **Step 3: Build and watch it pass**

Run: `cargo +stable build --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin`
Expected: success, no warnings.

- [ ] **Step 4: Run all tests**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin`
Expected: 15 passed (contract tests).

- [ ] **Step 5: Run clippy with the same flags CI uses**

Run: `cargo +stable clippy --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --all-targets -- -D warnings`
Expected: no warnings, no errors.

- [ ] **Step 6: Run fmt check**

Run: `cargo +stable fmt --manifest-path src-tauri/Cargo.toml --check`
Expected: no output. If formatting differs, run `cargo +stable fmt --manifest-path src-tauri/Cargo.toml` and re-verify.

- [ ] **Step 7: Commit**

```bash
git add src-tauri/src/sysinfo_cmds.rs src-tauri/src/lib.rs
git commit -m "Rewrite sysinfo_cmds as thin wrappers; manage Arc<SysinfoService>"
```

---

## Task 10: Local cargo tauri dev smoke test (mid-plan checkpoint)

**Files:** none modified.

A full app boot verifies all 14 command paths actually work end-to-end with the new service. The contract tests prove serialization shape; this proves the data still flows.

- [ ] **Step 1: Run the dev build**

Run: `cargo +stable tauri dev`
Wait for the boot screen to complete and the main shell to appear.

- [ ] **Step 2: Verify the six left-column panels are populated**

Visually confirm:
- **Clock** — ticking, current time shown.
- **Sysinfo** — date + uptime + battery percent (or "AC" if no battery).
- **HardwareInspector** — manufacturer / model / chassis lines populated.
- **Cpuinfo** — two charts streaming; usage %, temp °C, freq GHz, task count.
- **RAMwatcher** — pointmap filled, MEMORY label with usage.
- **Toplist** — process rows listed with name / cpu / mem.

If any panel shows `--` or `NONE` after 5 seconds, open DevTools (Cmd+Opt+I) and check the Console for `invoke('si_*')` errors.

- [ ] **Step 3: Spot-check theme + tabs still work**

Hit `Ctrl+Shift+S` (theme swap modal opens, pick another theme, panels recolor). Hit `Ctrl+X` then `2` (a second terminal tab spawns and gains focus).

- [ ] **Step 4: Quit cleanly with Cmd+Q. Nothing to commit.**

---

## Task 11: Add inert CSS seam to mod_column.css

**Files:**
- Modify: `src/assets/css/mod_column.css` (append rule + comment block)

- [ ] **Step 1: Append the seam to the end of mod_column.css**

Append to `src/assets/css/mod_column.css` (after line 60):

```css

/* ───────────────────────────────────────────────────────────────────
   Slice 1 native-mount seam.

   Toggled by Slice 1b once a sibling NSView/CAMetalLayer for the
   native gpui panel column is inserted into the Tauri NSWindow and
   sized from #mod_column_left's bounding rect.

   INACTIVE in Slice 1 — nothing toggles `body.native-left-active`,
   so JS panels render unchanged. Removing or renaming
   #mod_column_left will break Slice 1b's geometry source; do not
   touch until Slice 1c retires it.

   Specificity (1,1,1) beats the file's existing
   `section#mod_column_left` rules at (1,0,1) and the unprefixed
   selectors in extra_ratios.css, so the hide will apply regardless
   of cascade order once activated.
   ─────────────────────────────────────────────────────────────────── */
body.native-left-active #mod_column_left {
    visibility: hidden;
    pointer-events: none;
}
```

- [ ] **Step 2: Verify nothing visible changed**

Run: `cargo +stable tauri dev`
Open DevTools, in the Elements tab confirm `<body class="solidBackground">` (no `native-left-active`) and `#mod_column_left` is visible. Confirm the new CSS rule appears in the Styles inspector for `#mod_column_left` but is greyed/struck (selector doesn't match because body class isn't applied).

Quit with Cmd+Q.

- [ ] **Step 3: Commit**

```bash
git add src/assets/css/mod_column.css
git commit -m "Add inert body.native-left-active CSS seam for Slice 1b consumption"
```

---

## Task 12: NATIVE_PORT.md — Slice 1 layout audit appendix

**Files:**
- Modify: `NATIVE_PORT.md` (insert new section between Inventory and Priorities)

- [ ] **Step 1: Confirm panel→command map by running this grep**

Run: `grep -nE "window\.si\.(cpu|currentLoad|cpuTemp|processes|mem|battery|network|fsSize|blockDevices|system|chassis|uptime)" src/classes/clock.class.js src/classes/sysinfo.class.js src/classes/hardwareInspector.class.js src/classes/cpuinfo.class.js src/classes/ramwatcher.class.js src/classes/toplist.class.js 2>/dev/null`

Expected output should match (omitting netstat which is deferred):
```
src/classes/cpuinfo.class.js:18:        window.si.cpu().then(...
src/classes/cpuinfo.class.js:126:       window.si.currentLoad().then(...
src/classes/cpuinfo.class.js:153:       window.si.cpuTemperature().then(...
src/classes/cpuinfo.class.js:164:       window.si.cpu().then(...
src/classes/cpuinfo.class.js:177:       window.si.processes().then(...
src/classes/hardwareInspector.class.js:32:  window.si.system().then(...
src/classes/hardwareInspector.class.js:33:  window.si.chassis().then(...
src/classes/ramwatcher.class.js:41:     window.si.mem().then(...
src/classes/sysinfo.class.js:95:        ...await window.si.uptime()...
src/classes/sysinfo.class.js:113:       window.si.battery().then(...
src/classes/toplist.class.js:26:        window.si.processes().then(...
src/classes/toplist.class.js:103:       window.si.processes().then(...
```

If the actual output differs, fill the appendix below from the actual output, not the expected.

- [ ] **Step 2: Confirm clip-path / visual-shape source per panel**

The spec audit table originally had an "augmented-ui shape" column, but `grep -n "augmented" src/assets/css/mod_*.css` returns nothing — no panel uses augmented-ui. The CSS files use plain `border` / `background` / `clip-path` for visual shapes. The column is renamed to "Primary visual hooks" — the things Slice 1c's gpui renderer must recreate.

Run: `for f in src/assets/css/mod_clock.css src/assets/css/mod_sysinfo.css src/assets/css/mod_hardwareInspector.css src/assets/css/mod_cpuinfo.css src/assets/css/mod_ramwatcher.css src/assets/css/mod_toplist.css; do echo "=== $f ==="; grep -E "(clip-path|border-image|background-image|filter|@keyframes)" "$f" | head -5; done`

Note one or two characteristic visual features per panel from the output; they become the "Primary visual hooks" cells.

- [ ] **Step 3: Insert the audit section into NATIVE_PORT.md**

Open `NATIVE_PORT.md`. Find the line `## Priorities (TBD)` (around line 106). Insert *before* it:

```markdown
## Slice 1 layout audit

Snapshot taken 2026-05-22 during Slice 1 implementation. Slice 1b reads
this to drive sibling NSView geometry; Slice 1c rebuilds the panels in
gpui to match. Treat as authoritative until 1c retires the JS column.

### Panel inventory (left column → #mod_column_left)

All six panels are appended into `#mod_column_left` (created by
`src/renderer.js:279`, class `.mod_column`). Panel DOM roots are
inserted in this order:

| Panel              | JS class file                       | DOM root id              | CSS file(s)                          | Primary visual hooks                                                  |
|--------------------|-------------------------------------|--------------------------|--------------------------------------|-----------------------------------------------------------------------|
| Clock              | classes/clock.class.js              | #mod_clock               | mod_clock.css                        | <fill from grep step 2>                                               |
| Sysinfo            | classes/sysinfo.class.js            | #mod_sysinfo             | mod_sysinfo.css                      | <fill from grep step 2>                                               |
| HardwareInspector  | classes/hardwareInspector.class.js  | #mod_hardwareInspector   | mod_hardwareInspector.css            | <fill from grep step 2>                                               |
| Cpuinfo            | classes/cpuinfo.class.js            | #mod_cpuinfo             | mod_cpuinfo.css                      | <fill from grep step 2>; uses vendored smoothie.js for the two canvas charts |
| RAMwatcher         | classes/ramwatcher.class.js         | #mod_ramwatcher_inner    | mod_ramwatcher.css                   | <fill from grep step 2>                                               |
| Toplist            | classes/toplist.class.js            | #mod_toplist             | mod_toplist.css, processlist.css     | <fill from grep step 2>                                               |

### Sysinfo commands consumed per panel

Confirmed by grepping each panel for `window.si.*` calls. The
SysinfoService landed in Slice 1 exposes typed methods covering every
command in this table (plus `fs_size`, `block_devices`,
`network_interfaces`, `network_stats`, `network_connections` — those
serve filesystem.class.js and the deferred netstat.class.js, not the
left column).

| Panel             | Commands called (via window.si)              |
|-------------------|----------------------------------------------|
| Clock             | _(none — local Date)_                        |
| Sysinfo           | si_uptime, si_battery                        |
| HardwareInspector | si_system, si_chassis                        |
| Cpuinfo           | si_cpu, si_current_load, si_cpu_temperature, si_processes |
| RAMwatcher        | si_mem                                       |
| Toplist           | si_processes                                 |

### Rect-source contract

Slice 1b reads `getBoundingClientRect()` on `#mod_column_left` and
positions the sibling NSView/CAMetalLayer accordingly. The element
MUST NOT be renamed or removed until Slice 1c retires the JS column
entirely. A small bridge module added in Slice 1b will forward
`resize` / DPR-change events from the WKWebView to the Rust side so
the native view tracks layout reflows.

### CSS seam status

`body.native-left-active` was added to `src/assets/css/mod_column.css`
in Slice 1 and is inert. Slice 1b activates it.

```

- [ ] **Step 4: Add the conversion-log row**

In `NATIVE_PORT.md`, find the Conversion log table (near the bottom). Replace its body:

```markdown
| _empty_ | | | | |
```

with:

```markdown
| 2026-05-?? | Slice 1 backend prep | n/a → SysinfoService + JSON contract tests + inert CSS seam | <commit hash> | No user-visible change. Slice 1b adds NSView mount; Slice 1c renders panels in gpui. |
```

(Replace `2026-05-??` with today's date and `<commit hash>` with the short SHA after Task 16 commits the final state.)

- [ ] **Step 5: Commit**

```bash
git add NATIVE_PORT.md
git commit -m "Add Slice 1 layout audit + conversion log row to NATIVE_PORT.md"
```

---

## Task 13: Add rust-test job to CI

**Files:**
- Modify: `.github/workflows/ci.yml` (add new job + update `needs:`)

- [ ] **Step 1: Add the rust-test job and update the build gate**

In `.github/workflows/ci.yml`, after the `rust-clippy` job (after line 38) insert:

```yaml

  rust-test:
    name: Rust tests
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          targets: aarch64-apple-darwin
      - uses: Swatinem/rust-cache@v2
        with:
          workspaces: src-tauri
      - run: cargo test --target aarch64-apple-darwin
        working-directory: src-tauri
```

Then change line 54 (the `tauri-build` job's `needs:`):

```yaml
    needs: [rust-fmt, rust-clippy, js-tests]
```

to:

```yaml
    needs: [rust-fmt, rust-clippy, rust-test, js-tests]
```

- [ ] **Step 2: Validate the YAML locally**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ok')"`
Expected: `ok`. If `yaml` module isn't installed: `python3 -m pip install --user pyyaml` and retry. If that's not available either, a quick `grep -E "^[a-z_-]+:" .github/workflows/ci.yml | sort` should show the five top-level job keys: `js-tests`, `rust-clippy`, `rust-fmt`, `rust-test`, `tauri-build`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "CI: add rust-test job; gate tauri-build on it"
```

---

## Task 14: Full local verification before push

**Files:** none modified.

A final sweep mirroring everything CI will run.

- [ ] **Step 1: cargo fmt --check**

Run: `cargo +stable fmt --manifest-path src-tauri/Cargo.toml --check`
Expected: no output.

- [ ] **Step 2: cargo clippy -D warnings**

Run: `cargo +stable clippy --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin --all-targets -- -D warnings`
Expected: no warnings, no errors.

- [ ] **Step 3: cargo test**

Run: `cargo +stable test --manifest-path src-tauri/Cargo.toml --target aarch64-apple-darwin`
Expected: 15 passed (the sysinfo_contract integration tests).

- [ ] **Step 4: JS tests (verify js-tests CI job still passes locally)**

Run: `find src -name '*.test.js' -print0 | xargs -0 node --test`
Expected: existing bridge tests + terminalTabs.class.test pass.

- [ ] **Step 5: Full Tauri build (mirrors the tauri-build CI job)**

Run: `cargo +stable tauri build --target aarch64-apple-darwin --no-bundle`
Expected: success; binary at `src-tauri/target/aarch64-apple-darwin/release/edex-ui`.

- [ ] **Step 6: Final smoke test**

Run: `cargo +stable tauri dev`
Confirm all six panels populate; theme swap (Ctrl+Shift+S) works; tab spawn (Ctrl+X then 2) works; quit with Cmd+Q.

Nothing to commit — this is verification only.

---

## Task 15: Push branch and open PR

**Files:** none modified.

- [ ] **Step 1: Confirm clean tree + commits ready**

Run: `git status && git log --oneline -10`
Expected: working tree clean; the most recent ~7 commits are the Slice 1 work (scaffold, CPU, Load/Temp/Processes, Mem/Battery, Network, Disks, System/Chassis/Uptime, cmds rewrite, lib.rs wiring, CSS seam, NATIVE_PORT audit, CI rust-test).

- [ ] **Step 2: Update the conversion-log row with the actual final commit hash**

Run: `git log --oneline -1 NATIVE_PORT.md` to find the audit commit, then run `git log --oneline -1` for the current HEAD. If they differ, amend the NATIVE_PORT row to point at HEAD. (If they're the same — the audit commit is HEAD — leave it; the row already points at the right commit semantically.)

If amending: edit `NATIVE_PORT.md` to replace `<commit hash>` with the 7-char short SHA, then `git add NATIVE_PORT.md && git commit -m "NATIVE_PORT: point Slice 1 row at final commit"`.

- [ ] **Step 3: Push**

Run: `git push`
(The branch already tracks `origin/slice-1-panels-gpui` from the gpui-decision commit; no `-u` needed.)

- [ ] **Step 4: Open the PR**

Run:

```bash
gh pr create --base post-web-runtime --title "Slice 1: SysinfoService extraction + inert layout seam" --body "$(cat <<'EOF'
## Summary

Backend prep for the native (gpui) panel port. Zero user-visible change.

- Extract `SysinfoService` (Tauri-agnostic, typed structs, sync methods) from `sysinfo_cmds.rs`. The cmd file shrinks to thin `spawn_blocking` wrappers. Native gpui code in Slice 1c will call `SysinfoService` directly without `invoke()`.
- Add `tests/sysinfo_contract.rs` — 15 deterministic-fixture tests that lock the JSON wire shape for every command the JS panels consume. Wire format changes that would silently break the frontend now fail CI.
- Add inert `body.native-left-active` CSS seam in `mod_column.css`. Never toggled in Slice 1; Slice 1b activates it.
- Audit appendix in `NATIVE_PORT.md` documenting panel → DOM → CSS → si_* command mappings, and the `#mod_column_left` rect-source contract Slice 1b depends on.
- New `rust-test` CI job; `tauri-build` now gates on it.

Design spec: `docs/superpowers/specs/2026-05-22-slice-1-panels-prep-design.md`
Plan: `docs/superpowers/plans/2026-05-22-slice-1-panels-prep.md`

## Test plan

- [ ] `cargo +stable tauri build --target aarch64-apple-darwin` green
- [ ] `cargo +stable test --target aarch64-apple-darwin` — 15 contract tests pass
- [ ] `cargo +stable clippy --target aarch64-apple-darwin --all-targets -- -D warnings` clean
- [ ] `cargo +stable fmt --check` clean
- [ ] `cargo tauri dev` boots; all six panels populate; theme swap works; tab spawn works
- [ ] DevTools confirms `body` has no `native-left-active` class and `#mod_column_left` is visible
EOF
)"
```

- [ ] **Step 5: Verify CI starts**

Run: `gh pr checks` (a few seconds after PR creation).
Expected: five jobs queued — `rust-fmt`, `rust-clippy`, `rust-test`, `js-tests`, `tauri-build`. The fifth `(tauri-build)` shows `waiting` until the others pass.

---

## Self-Review

**1. Spec coverage:** Every spec section maps to a task.

- *Sysinfo service shape* → Tasks 1-7 (one per struct/method group), Task 8 (cmd wrappers), Task 9 (lib.rs wiring).
- *Contract tests* → Tasks 2-7 (test added with each struct), Task 13 (CI rust-test job).
- *CSS seam* → Task 11.
- *NATIVE_PORT.md audit appendix + conversion log* → Task 12.
- *Verification (steps 1-5)* → Task 14 (build + clippy + fmt + test + dev), Task 10 (mid-plan dev smoke test).
- *PR creation* → Task 15.

Spec table inaccuracy (Sysinfo doesn't call si_system/si_chassis; Cpuinfo also calls si_processes; no panel uses augmented-ui) is corrected during Task 12 step 1-2 (grep-driven) rather than carrying the spec's draft text verbatim. The spec's audit text was explicitly marked as "to be populated during implementation."

**2. Placeholder scan:**

- `<fill from grep step 2>` in Task 12 step 3 — intentional: filled at execution time from the command in step 2. Not a planning placeholder.
- `<commit hash>` and `2026-05-??` in the conversion log row — intentional, filled in Task 15 step 2. The same pattern appears in the design spec.

**3. Type consistency:**

- `SysinfoService` — used in `sysinfo_service.rs`, `sysinfo_cmds.rs`, `lib.rs`, all tests. Consistent.
- `Arc<SysinfoService>` — what `.manage()` stores and what command wrappers ask for via `State<'_, Arc<SysinfoService>>`. Consistent.
- Struct names — `CpuStats`, `LoadStats`, `CpuLoad`, `TempStats`, `ProcessRow`, `ProcessList`, `MemStats`, `BatteryInfo`, `NetIface`, `NetStats`, `DiskInfo`, `BlockDevice`, `SystemInfo`, `ChassisInfo`. Each is defined once (Task N) and used downstream in Task 8's wrappers. No name drift.
- Method names — `cpu`, `current_load`, `cpu_temperature`, `processes`, `mem`, `battery`, `network_interfaces`, `network_stats`, `network_connections_stub` (associated fn, not method), `fs_size`, `block_devices`, `system`, `chassis`, `uptime`. Matches Task 8 wrapper bodies.
- Field name annotations — `#[serde(rename = "type")]` on `BatteryInfo::battery_type`, `NetIface::iface_type`, `DiskInfo::disk_type`, `BlockDevice::device_type`, `ChassisInfo::chassis_type`. `#[serde(rename = "virtual")]` on `NetIface::is_virtual`. `#[serde(rename = "use")]` on `DiskInfo::use_pct`. `#[serde(rename = "fsType")]` on `BlockDevice::fs_type`. All marked rusts-reserved-word or camelCase-edge-case fields are consistently renamed.

No issues found; plan is internally consistent.
