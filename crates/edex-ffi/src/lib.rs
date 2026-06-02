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
                let is_json = path
                    .extension()
                    .and_then(|ext| ext.to_str())
                    .is_some_and(|ext| ext.eq_ignore_ascii_case("json"));
                if is_json {
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

/// One directory entry for the native filesystem panel (mirrors the Rust
/// `fs::DirEntry`, which is what `fs_readdir` returned to the JS panel).
/// `entry_type` carries the legacy `type` field (renamed because `type` is a
/// reserved word in Swift).
#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiDirEntry {
    pub name: String,
    pub category: String,
    pub hidden: bool,
    pub size: u64,
    pub entry_type: String,
}

impl From<edex_core::fs::DirEntry> for FfiDirEntry {
    fn from(entry: edex_core::fs::DirEntry) -> Self {
        Self {
            name: entry.name,
            category: entry.category,
            hidden: entry.hidden,
            size: entry.size,
            entry_type: entry.r#type,
        }
    }
}

/// A mounted filesystem's space accounting (filesystem panel disk-usage bar).
/// Mirrors `window.si.fsSize()` rows: `use_pct` is the 0–100 percentage the
/// legacy code read as `fsBlock.use`.
#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiDiskUsage {
    pub fs: String,
    pub disk_type: String,
    pub size: u64,
    pub used: u64,
    pub available: u64,
    pub use_pct: f64,
    pub mount: String,
}

impl From<edex_core::sysinfo::DiskInfo> for FfiDiskUsage {
    fn from(disk: edex_core::sysinfo::DiskInfo) -> Self {
        Self {
            fs: disk.fs,
            disk_type: disk.disk_type,
            size: disk.size,
            used: disk.used,
            available: disk.available,
            use_pct: disk.use_pct,
            mount: disk.mount,
        }
    }
}

/// A block device for the filesystem "Show disks" view. The native panel reads
/// the same subset the JS `readDevices()` did: name/label/mount classify the
/// row, `removable` + `device_type` pick the disk/usb/rom icon.
#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiBlockDevice {
    pub name: String,
    pub device_type: String,
    pub fs_type: String,
    pub mount: String,
    pub size: u64,
    pub removable: bool,
    pub label: String,
}

impl From<edex_core::sysinfo::BlockDevice> for FfiBlockDevice {
    fn from(device: edex_core::sysinfo::BlockDevice) -> Self {
        Self {
            name: device.name,
            device_type: device.device_type,
            fs_type: device.fs_type,
            mount: device.mount,
            size: device.size,
            removable: device.removable,
            label: device.label,
        }
    }
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

    /// Load shortcuts.json as a raw string (Phase 6.4).
    pub fn load_shortcuts_json(&self) -> Result<String, EdexError> {
        let path = edex_core::settings::paths().shortcuts_file;
        fs::read_to_string(path).map_err(EdexError::from)
    }

    /// Validate and persist shortcuts.json (Phase 6.4).
    /// Rejects non-array or malformed JSON before writing.
    pub fn write_shortcuts_json(&self, contents: String) -> Result<(), EdexError> {
        let value: serde_json::Value = serde_json::from_str(&contents)?;
        if !value.is_array() {
            return Err(EdexError::Core {
                message: "shortcuts.json must be a JSON array".to_string(),
            });
        }
        let pretty = serde_json::to_string_pretty(&value)?;
        let path = edex_core::settings::paths().shortcuts_file;
        fs::write(path, pretty).map_err(EdexError::from)
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

    // MARK: - Filesystem panel (Phase 7.1)

    /// List a directory for the filesystem panel. Returns entries with the
    /// category/size/type the JS panel consumed; errors (missing dir,
    /// permission denied) propagate so the panel can show its failed state.
    pub fn fs_readdir(&self, path: String) -> Result<Vec<FfiDirEntry>, EdexError> {
        edex_core::fs::readdir(&path)
            .map(|entries| entries.into_iter().map(FfiDirEntry::from).collect())
            .map_err(EdexError::from)
    }

    /// Whether a path exists (filesystem "Show disks" view filters mounts that
    /// are not actually mounted, mirroring the legacy `fs_exists` check).
    pub fn fs_exists(&self, path: String) -> bool {
        edex_core::fs::exists(&path)
    }

    /// Open a path in the host's default application (Ctrl-click / non-text file).
    pub fn fs_open_external(&self, path: String) -> Result<(), EdexError> {
        edex_core::fs::open_external(&path).map_err(EdexError::from)
    }

    /// Read a text file for the editor modal (Phase 7.3 consumer).
    pub fn fs_read_text_file(&self, path: String) -> Result<String, EdexError> {
        edex_core::fs::readfile(&path).map_err(EdexError::from)
    }

    /// Write a text file back to disk (Phase 7.3 editor save).
    pub fn fs_write_text_file(&self, path: String, contents: String) -> Result<(), EdexError> {
        edex_core::fs::writefile(&path, &contents).map_err(EdexError::from)
    }

    /// Mounted-filesystem space accounting for the disk-usage bar.
    pub fn fs_size(&self) -> Result<Vec<FfiDiskUsage>, EdexError> {
        self.sysinfo
            .fs_size()
            .map(|disks| disks.into_iter().map(FfiDiskUsage::from).collect())
            .map_err(EdexError::from)
    }

    /// Block devices for the filesystem "Show disks" view.
    pub fn block_devices(&self) -> Result<Vec<FfiBlockDevice>, EdexError> {
        self.sysinfo
            .block_devices()
            .map(|devices| devices.into_iter().map(FfiBlockDevice::from).collect())
            .map_err(EdexError::from)
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

    #[test]
    fn write_shortcuts_json_validates_and_round_trips() {
        let core = EdexCore::new();
        core.ensure_userdata()
            .expect("ensure_userdata should succeed");
        let path = edex_core::settings::paths().shortcuts_file;
        let original = fs::read_to_string(&path).expect("shortcuts.json should exist");

        // RAII guard: restores the developer's real shortcuts.json even if an
        // assertion panics mid-test, preventing permanent file corruption.
        struct Cleanup {
            path: String,
            original: String,
        }
        impl Drop for Cleanup {
            fn drop(&mut self) {
                let _ = fs::write(&self.path, &self.original);
            }
        }
        let _guard = Cleanup {
            path: path.clone(),
            original: original.clone(),
        };

        // Non-JSON is rejected.
        assert!(core.write_shortcuts_json("{ not json".to_string()).is_err());
        // Non-array JSON is rejected.
        assert!(core
            .write_shortcuts_json(r#"{"key":"value"}"#.to_string())
            .is_err());
        // The file must be unmodified after a rejected write.
        assert_eq!(
            fs::read_to_string(&path).expect("shortcuts.json should still exist"),
            original,
            "a rejected write must not modify shortcuts.json"
        );

        // Valid array persists and round-trips.
        let minimal = r#"[{"type":"app","trigger":"Ctrl+Shift+C","action":"COPY","enabled":true}]"#;
        core.write_shortcuts_json(minimal.to_string())
            .expect("valid shortcuts JSON should write");
        let reloaded: serde_json::Value =
            serde_json::from_str(&core.load_shortcuts_json().unwrap()).unwrap();
        assert_eq!(reloaded[0]["action"], serde_json::json!("COPY"));
        // _guard.drop() restores the file here (or on panic).
    }

    #[test]
    fn fs_readdir_lists_entries_and_flags_dotfiles() {
        let core = EdexCore::new();
        let dir = std::env::temp_dir().join(format!("edex_ffi_readdir_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("visible.txt"), "hi").unwrap();
        fs::write(dir.join(".hidden"), "x").unwrap();
        fs::create_dir(dir.join("subdir")).unwrap();

        let entries = core.fs_readdir(dir.to_string_lossy().to_string()).unwrap();
        let _ = fs::remove_dir_all(&dir);

        let visible = entries.iter().find(|e| e.name == "visible.txt").unwrap();
        assert_eq!(visible.category, "file");
        assert_eq!(visible.entry_type, "file");
        assert!(!visible.hidden);
        assert_eq!(visible.size, 2);

        let hidden = entries.iter().find(|e| e.name == ".hidden").unwrap();
        assert!(hidden.hidden);

        let subdir = entries.iter().find(|e| e.name == "subdir").unwrap();
        assert_eq!(subdir.category, "dir");
    }

    #[test]
    fn fs_exists_reports_presence() {
        let core = EdexCore::new();
        assert!(core.fs_exists("/".to_string()));
        assert!(!core.fs_exists("/nonexistent-edex-path-xyz".to_string()));
    }

    #[test]
    fn fs_read_and_write_text_file_round_trip() {
        let core = EdexCore::new();
        let path = std::env::temp_dir()
            .join(format!("edex_ffi_textfile_{}.txt", std::process::id()))
            .to_string_lossy()
            .to_string();
        core.fs_write_text_file(path.clone(), "hello edex".to_string())
            .unwrap();
        assert_eq!(core.fs_read_text_file(path.clone()).unwrap(), "hello edex");
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn fs_size_reports_a_root_mount() {
        let core = EdexCore::new();
        let disks = core.fs_size().expect("fs_size should succeed");
        assert!(!disks.is_empty(), "a running host should report a mount");
        assert!(disks.iter().all(|d| (0.0..=100.0).contains(&d.use_pct)));
    }

    #[test]
    fn block_devices_reports_devices_with_mount_points() {
        let core = EdexCore::new();
        let devices = core.block_devices().expect("block_devices should succeed");
        assert!(!devices.is_empty(), "a running host should report a device");
        assert!(devices.iter().any(|d| !d.mount.is_empty()));
    }

    #[test]
    fn list_json_stems_is_case_insensitive_and_sorted() {
        let dir = std::env::temp_dir().join("edex_ffi_list_json_stems_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("beta.json"), "{}").unwrap();
        fs::write(dir.join("Alpha.JSON"), "{}").unwrap();
        fs::write(dir.join("notes.txt"), "x").unwrap();

        let stems = list_json_stems(&dir.to_string_lossy());
        let _ = fs::remove_dir_all(&dir);

        // .JSON is matched (case-insensitive) and .txt is ignored; output is sorted.
        assert_eq!(stems, vec!["Alpha".to_string(), "beta".to_string()]);
    }
}
