use edex_core::pty::{PtyManager, PtyOutputObserver, SpawnArgs};
use edex_core::sysinfo::SysinfoService;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;

uniffi::setup_scaffolding!();

/// Sorted `.json` file stems in a directory (theme/keyboard listings). A missing
/// or unreadable directory yields an empty list rather than an error.
fn list_json_stems(dir: &str) -> Vec<String> {
    let mut names: Vec<String> = match fs::read_dir(dir) {
        Ok(entries) => entries
            .filter_map(|entry| entry.ok())
            .filter_map(|entry| {
                let path = entry.path();
                if path.extension().and_then(|ext| ext.to_str()) == Some("json") {
                    path.file_stem()
                        .and_then(|stem| stem.to_str())
                        .map(String::from)
                } else {
                    None
                }
            })
            .collect(),
        Err(_) => Vec::new(),
    };
    names.sort();
    names
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum EdexError {
    #[error("{message}")]
    Core { message: String },
}

impl From<String> for EdexError {
    fn from(message: String) -> Self {
        Self::Core { message }
    }
}

impl From<serde_json::Error> for EdexError {
    fn from(err: serde_json::Error) -> Self {
        Self::Core {
            message: err.to_string(),
        }
    }
}

impl From<std::io::Error> for EdexError {
    fn from(err: std::io::Error) -> Self {
        Self::Core {
            message: err.to_string(),
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiPaths {
    pub user_data: String,
    pub settings_file: String,
    pub shortcuts_file: String,
    pub last_window_state_file: String,
    pub themes_dir: String,
    pub keyboards_dir: String,
    pub fonts_dir: String,
}

impl From<edex_core::settings::Paths> for FfiPaths {
    fn from(paths: edex_core::settings::Paths) -> Self {
        Self {
            user_data: paths.user_data,
            settings_file: paths.settings_file,
            shortcuts_file: paths.shortcuts_file,
            last_window_state_file: paths.last_window_state_file,
            themes_dir: paths.themes_dir,
            keyboards_dir: paths.keyboards_dir,
            fonts_dir: paths.fonts_dir,
        }
    }
}

/// The subset of `BatteryInfo` the native sysinfo panel consumes for its POWER
/// cell (mirrors the JS `window.si.battery()` consumers in sysinfo.class.js).
#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiBattery {
    pub has_battery: bool,
    pub is_charging: bool,
    pub ac_connected: bool,
    pub percent: i64,
}

impl From<edex_core::sysinfo::BatteryInfo> for FfiBattery {
    fn from(battery: edex_core::sysinfo::BatteryInfo) -> Self {
        Self {
            has_battery: battery.has_battery,
            is_charging: battery.is_charging,
            ac_connected: battery.ac_connected,
            percent: battery.percent,
        }
    }
}

/// The subset of `SystemInfo` + `ChassisInfo` the native hardware-inspector
/// panel consumes (mirrors `window.si.system()`/`chassis()` in
/// hardwareInspector.class.js: manufacturer + model from system, type from chassis).
#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiHardware {
    pub manufacturer: String,
    pub model: String,
    pub chassis_type: String,
}

/// The fields of `PanelSnapshot` the native cpuinfo panel consumes (mirrors the
/// `window.si.panelSnapshot(...)` reads in cpuinfo.class.js). `loads` is the
/// per-logical-core current load 0–100, one entry per core.
#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiCpuSnapshot {
    pub manufacturer: String,
    pub brand: String,
    pub cores: u32,
    pub speed: String,
    pub speed_max: String,
    pub temperature_max: f64,
    pub process_count: u32,
    pub loads: Vec<f64>,
}

/// The `MemStats` fields the native ramwatcher panel consumes (mirrors the
/// `snapshot.mem` reads in ramwatcher.class.js): the active/available/free
/// breakdown for the 440-dot grid plus swap totals.
#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiMemSnapshot {
    pub total: u64,
    pub free: u64,
    pub active: u64,
    pub available: u64,
    pub swap_total: u64,
    pub swap_used: u64,
}

impl From<edex_core::sysinfo::MemStats> for FfiMemSnapshot {
    fn from(mem: edex_core::sysinfo::MemStats) -> Self {
        Self {
            total: mem.total,
            free: mem.free,
            active: mem.active,
            available: mem.available,
            swap_total: mem.swaptotal,
            swap_used: mem.swapused,
        }
    }
}

/// The compact top-process row consumed by the native TOPLIST mini panel.
#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiTopProcessRow {
    pub pid: u32,
    pub name: String,
    pub cpu: f64,
    pub mem: f64,
}

impl From<edex_core::sysinfo::ProcessTopRow> for FfiTopProcessRow {
    fn from(row: edex_core::sysinfo::ProcessTopRow) -> Self {
        Self {
            pid: row.pid,
            name: row.name,
            cpu: row.cpu,
            mem: row.mem,
        }
    }
}

/// The expanded process-list row consumed by the native process modal.
#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiProcessRow {
    pub pid: u32,
    pub name: String,
    pub user: String,
    pub cpu: f64,
    pub mem: f64,
    pub state: String,
    pub started: String,
}

impl From<edex_core::sysinfo::ProcessRow> for FfiProcessRow {
    fn from(row: edex_core::sysinfo::ProcessRow) -> Self {
        Self {
            pid: row.pid,
            name: row.name,
            user: row.user,
            cpu: row.cpu,
            mem: row.mem,
            state: row.state,
            started: row.started,
        }
    }
}

/// Full process-list payload for the expanded TOPLIST modal. Counts mirror the
/// Rust core contract, but the Swift UI currently renders only `list`.
#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiProcessList {
    pub all: u32,
    pub running: u32,
    pub blocked: u32,
    pub sleeping: u32,
    pub list: Vec<FfiProcessRow>,
}

impl From<edex_core::sysinfo::ProcessList> for FfiProcessList {
    fn from(processes: edex_core::sysinfo::ProcessList) -> Self {
        Self {
            all: processes.all as u32,
            running: processes.running as u32,
            blocked: processes.blocked as u32,
            sleeping: processes.sleeping as u32,
            list: processes
                .list
                .into_iter()
                .map(FfiProcessRow::from)
                .collect(),
        }
    }
}

/// Native TOPLIST panel payload: five top rows for the compact panel, plus an
/// optional full process list when the expanded modal is open.
#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiToplistSnapshot {
    pub top_processes: Vec<FfiTopProcessRow>,
    pub process_list: Option<FfiProcessList>,
}

#[derive(Debug, uniffi::Record)]
pub struct FfiPtySpawnOptions {
    pub shell: String,
    pub args: Vec<String>,
    pub cwd: String,
    pub env_keys: Vec<String>,
    pub env_values: Vec<String>,
    pub cols: u16,
    pub rows: u16,
}

#[derive(Debug, uniffi::Record)]
pub struct FfiPtyMetadata {
    pub cwd: Option<String>,
    pub process: Option<String>,
}

#[uniffi::export(callback_interface)]
pub trait PtyOutputSink: Send + Sync {
    fn on_output(&self, id: u32, bytes: Vec<u8>);
    fn on_exit(&self, id: u32, status: Option<i32>);
    fn on_metadata(&self, id: u32, cwd: Option<String>, process: Option<String>);
}

struct FfiPtyObserver {
    sink: Box<dyn PtyOutputSink>,
}

impl PtyOutputObserver for FfiPtyObserver {
    fn on_output(&self, id: u32, bytes: Vec<u8>) {
        self.sink.on_output(id, bytes);
    }

    fn on_exit(&self, id: u32, status: Option<i32>) {
        self.sink.on_exit(id, status);
    }

    fn on_metadata(&self, id: u32, cwd: Option<String>, process: Option<String>) {
        self.sink.on_metadata(id, cwd, process);
    }
}

#[derive(uniffi::Object)]
pub struct EdexCore {
    sysinfo: SysinfoService,
    pty: PtyManager,
}

#[uniffi::export]
impl EdexCore {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            sysinfo: SysinfoService::new(),
            pty: PtyManager::new(),
        })
    }

    pub fn paths(&self) -> FfiPaths {
        edex_core::settings::paths().into()
    }

    pub fn ensure_userdata(&self) -> Result<(), EdexError> {
        edex_core::settings::ensure_userdata().map_err(|err| EdexError::Core {
            message: err.to_string(),
        })
    }

    pub fn load_settings_json(&self) -> Result<String, EdexError> {
        let path = edex_core::settings::paths().settings_file;
        fs::read_to_string(path).map_err(EdexError::from)
    }

    pub fn load_theme_json(&self, name: String) -> Result<String, EdexError> {
        let paths = edex_core::settings::paths();
        let path = PathBuf::from(paths.themes_dir).join(format!("{name}.json"));
        fs::read_to_string(path).map_err(EdexError::from)
    }

    pub fn load_keyboard_json(&self, name: String) -> Result<String, EdexError> {
        let paths = edex_core::settings::paths();
        let path = PathBuf::from(paths.keyboards_dir).join(format!("{name}.json"));
        fs::read_to_string(path).map_err(EdexError::from)
    }

    /// Validate and persist the full settings document (Phase 6.3 editor save).
    /// Parses to reject malformed JSON before touching the file, then writes it
    /// pretty-printed to match `edex_core::settings::write_settings`.
    pub fn write_settings_json(&self, contents: String) -> Result<(), EdexError> {
        let value: serde_json::Value = serde_json::from_str(&contents)?;
        let pretty = serde_json::to_string_pretty(&value)?;
        let path = edex_core::settings::paths().settings_file;
        fs::write(path, pretty).map_err(EdexError::from)
    }

    /// Available theme names (settings editor theme picker). Missing dir → empty.
    pub fn list_themes(&self) -> Vec<String> {
        list_json_stems(&edex_core::settings::paths().themes_dir)
    }

    /// Available keyboard layout codes (settings editor keyboard picker).
    pub fn list_keyboards(&self) -> Vec<String> {
        list_json_stems(&edex_core::settings::paths().keyboards_dir)
    }

    pub fn sysinfo_snapshot_json(&self) -> Result<String, EdexError> {
        let snapshot = self.sysinfo.panel_snapshot(true, 5, true)?;
        serde_json::to_string(&snapshot).map_err(EdexError::from)
    }

    /// System uptime in seconds (sysinfo panel UPTIME cell).
    pub fn uptime(&self) -> u64 {
        self.sysinfo.uptime()
    }

    /// Battery/power state (sysinfo panel POWER cell).
    pub fn battery(&self) -> Result<FfiBattery, EdexError> {
        self.sysinfo
            .battery()
            .map(FfiBattery::from)
            .map_err(EdexError::from)
    }

    /// Live CPU snapshot for the cpuinfo panel: identity, clock, temperature,
    /// task count, and per-core load. Always a fresh refresh (panel polls 1 Hz).
    pub fn cpu_snapshot(&self) -> Result<FfiCpuSnapshot, EdexError> {
        let snapshot = self.sysinfo.panel_snapshot(false, 5, false)?;
        Ok(FfiCpuSnapshot {
            manufacturer: snapshot.cpu.manufacturer,
            brand: snapshot.cpu.brand,
            cores: snapshot.cpu.cores as u32,
            speed: snapshot.cpu.speed,
            speed_max: snapshot.cpu.speed_max,
            temperature_max: snapshot.cpu_temperature.max,
            process_count: snapshot.process_count as u32,
            loads: snapshot
                .current_load
                .cpus
                .into_iter()
                .map(|cpu| cpu.load)
                .collect(),
        })
    }

    /// Memory snapshot for the ramwatcher panel. Uses the lighter cached
    /// `mem()` accessor (not the full panel snapshot the JS over-fetched).
    pub fn mem_snapshot(&self) -> Result<FfiMemSnapshot, EdexError> {
        self.sysinfo
            .mem()
            .map(FfiMemSnapshot::from)
            .map_err(EdexError::from)
    }

    /// Live TOPLIST payload. The compact panel consumes `top_processes`; the
    /// expanded process modal requests `include_process_list = true` for rows.
    pub fn toplist_snapshot(
        &self,
        collapse_threads_by_name: bool,
        include_process_list: bool,
    ) -> Result<FfiToplistSnapshot, EdexError> {
        let snapshot =
            self.sysinfo
                .panel_snapshot(collapse_threads_by_name, 5, include_process_list)?;
        Ok(FfiToplistSnapshot {
            top_processes: snapshot
                .top_processes
                .into_iter()
                .map(FfiTopProcessRow::from)
                .collect(),
            process_list: snapshot.process_list.map(FfiProcessList::from),
        })
    }

    /// Host hardware identity (hardware-inspector panel). Combines the two
    /// sources the JS panel reads: manufacturer/model from `system()` and the
    /// chassis type from `chassis()`.
    pub fn hardware(&self) -> FfiHardware {
        let system = self.sysinfo.system();
        let chassis = self.sysinfo.chassis();
        FfiHardware {
            manufacturer: system.manufacturer,
            model: system.model,
            chassis_type: chassis.chassis_type,
        }
    }

    pub fn spawn_pty(
        &self,
        opts: FfiPtySpawnOptions,
        sink: Box<dyn PtyOutputSink>,
    ) -> Result<u32, EdexError> {
        if opts.env_keys.len() != opts.env_values.len() {
            return Err(EdexError::Core {
                message: "env_keys and env_values must have the same length".to_string(),
            });
        }

        let env = opts
            .env_keys
            .into_iter()
            .zip(opts.env_values)
            .collect::<std::collections::HashMap<_, _>>();
        let args = SpawnArgs {
            shell: opts.shell,
            args: opts.args,
            cwd: opts.cwd,
            env,
            cols: opts.cols,
            rows: opts.rows,
        };
        let observer: Arc<dyn PtyOutputObserver> = Arc::new(FfiPtyObserver { sink });
        self.pty.spawn(args, observer).map_err(EdexError::from)
    }

    pub fn write_pty(&self, id: u32, data: String) -> Result<(), EdexError> {
        self.pty.write(id, &data).map_err(EdexError::from)
    }

    pub fn resize_pty(&self, id: u32, cols: u16, rows: u16) -> Result<(), EdexError> {
        self.pty.resize(id, cols, rows).map_err(EdexError::from)
    }

    pub fn kill_pty(&self, id: u32) -> Result<(), EdexError> {
        self.pty.kill(id).map_err(EdexError::from)
    }

    pub fn pty_metadata(&self, id: u32) -> Result<FfiPtyMetadata, EdexError> {
        let metadata = self.pty.metadata(id)?;
        Ok(FfiPtyMetadata {
            cwd: metadata.cwd,
            process: metadata.process,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct NoopSink;

    impl PtyOutputSink for NoopSink {
        fn on_output(&self, _id: u32, _bytes: Vec<u8>) {}
        fn on_exit(&self, _id: u32, _status: Option<i32>) {}
        fn on_metadata(&self, _id: u32, _cwd: Option<String>, _process: Option<String>) {}
    }

    #[test]
    fn ffi_battery_maps_absent_battery_fields() {
        let battery = FfiBattery::from(edex_core::sysinfo::BatteryInfo::absent());
        assert!(!battery.has_battery);
        assert!(!battery.is_charging);
        // absent() reports AC connected (a desktop is "ON"/wired).
        assert!(battery.ac_connected);
        assert_eq!(battery.percent, 0);
    }

    #[test]
    fn hardware_reports_apple_manufacturer_and_a_chassis_type() {
        let core = EdexCore::new();
        let hw = core.hardware();
        // edex-core hard-codes Apple on the macOS-only target.
        assert_eq!(hw.manufacturer, "Apple");
        assert!(!hw.chassis_type.is_empty());
    }

    #[test]
    fn mem_snapshot_reports_consistent_totals() {
        let core = EdexCore::new();
        let mem = core.mem_snapshot().expect("mem snapshot should succeed");
        assert!(mem.total > 0, "a running host should report total memory");
        assert!(mem.free <= mem.total);
        assert!(
            mem.available >= mem.free,
            "available is max(available, free)"
        );
    }

    #[test]
    fn cpu_snapshot_reports_one_load_per_core() {
        let core = EdexCore::new();
        let snapshot = core.cpu_snapshot().expect("cpu snapshot should succeed");
        assert!(snapshot.cores > 0, "a running host should report cores");
        assert_eq!(
            snapshot.loads.len(),
            snapshot.cores as usize,
            "one load sample per logical core"
        );
        assert!(snapshot.loads.iter().all(|&l| (0.0..=100.0).contains(&l)));
    }

    #[test]
    fn toplist_snapshot_reports_five_top_processes_without_full_list() {
        let core = EdexCore::new();
        let snapshot = core
            .toplist_snapshot(false, false)
            .expect("toplist snapshot should succeed");
        assert!(
            !snapshot.top_processes.is_empty(),
            "a running host should report top processes"
        );
        assert!(
            snapshot.top_processes.len() <= 5,
            "mini panel should request the legacy five-row limit"
        );
        assert!(snapshot.process_list.is_none());
    }

    #[test]
    fn toplist_snapshot_can_include_full_process_list() {
        let core = EdexCore::new();
        let snapshot = core
            .toplist_snapshot(false, true)
            .expect("toplist snapshot should succeed");
        let process_list = snapshot
            .process_list
            .expect("expanded process modal should request process rows");
        assert!(
            !process_list.list.is_empty(),
            "a running host should report process rows"
        );
        assert_eq!(process_list.all, process_list.list.len() as u32);
    }

    #[test]
    fn uptime_returns_nonzero_on_a_running_host() {
        let core = EdexCore::new();
        assert!(
            core.uptime() > 0,
            "a running host should report positive uptime"
        );
    }

    #[test]
    fn spawn_pty_rejects_mismatched_env_vectors() {
        let core = EdexCore::new();
        let result = core.spawn_pty(
            FfiPtySpawnOptions {
                shell: "/bin/sh".to_string(),
                args: vec!["-c".to_string(), "sleep 1".to_string()],
                cwd: "/".to_string(),
                env_keys: vec!["ONE".to_string()],
                env_values: vec![],
                cols: 80,
                rows: 24,
            },
            Box::new(NoopSink),
        );

        if let Ok(id) = result {
            let _ = core.kill_pty(id);
            panic!("mismatched env vectors should be rejected before spawning a PTY");
        }
        assert!(matches!(
            result,
            Err(EdexError::Core { message })
                if message == "env_keys and env_values must have the same length"
        ));
    }

    #[test]
    fn write_settings_json_validates_and_round_trips() {
        let core = EdexCore::new();
        core.ensure_userdata()
            .expect("ensure_userdata should succeed");
        let path = edex_core::settings::paths().settings_file;
        let original = fs::read_to_string(&path).expect("settings.json should exist");

        // Malformed JSON is rejected before the file is touched.
        assert!(core.write_settings_json("{ not json".to_string()).is_err());
        assert_eq!(
            fs::read_to_string(&path).expect("settings.json should still exist"),
            original,
            "a rejected write must not modify settings.json"
        );

        // Valid JSON persists and round-trips, including editor-unknown keys.
        core.write_settings_json(r#"{"theme":"tron","customExtra":42}"#.to_string())
            .expect("valid settings JSON should write");
        let reloaded: serde_json::Value =
            serde_json::from_str(&core.load_settings_json().unwrap()).unwrap();
        assert_eq!(reloaded["theme"], serde_json::json!("tron"));
        assert_eq!(reloaded["customExtra"], serde_json::json!(42));

        // Restore the developer's real settings file.
        fs::write(&path, original).expect("restore original settings.json");
    }

    #[test]
    fn list_themes_and_keyboards_include_builtins() {
        let core = EdexCore::new();
        core.ensure_userdata()
            .expect("ensure_userdata should succeed");
        assert!(core.list_themes().contains(&"tron".to_string()));
        assert!(core.list_keyboards().contains(&"en-US".to_string()));
    }
}
