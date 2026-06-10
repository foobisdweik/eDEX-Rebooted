//! Tauri-agnostic sysinfo service.
//!
//! Owns the cached sysinfo handles (System / Components / Networks / Disks)
//! and exposes typed query methods. Consumed by `sysinfo_cmds.rs` for the
//! JS-side #[tauri::command] surface and by future native panel renderers
//! without an `invoke()` round-trip.

use serde::Serialize;
use std::collections::{hash_map::Entry, HashMap};
use std::sync::{Mutex, Once};
use std::time::{Duration, Instant};
use sysinfo::{Components, Disks, Networks, System};

static RAYON_POOL: Once = Once::new();

/// Cap rayon's global pool before sysinfo's parallel process refresh runs.
fn init_rayon_pool() {
    RAYON_POOL.call_once(|| {
        let _ = rayon::ThreadPoolBuilder::new()
            .num_threads(3)
            .build_global();
    });
}

pub struct SysinfoService {
    sys_state: Mutex<SystemState>,
    temp_cache: Mutex<SnapshotCache<TempStats>>,
    disks: Mutex<LazyList<Disks>>,
    networks: Mutex<LazyList<Networks>>,
    components: Mutex<LazyList<Components>>,
}

impl SysinfoService {
    /// Minimal, lazy construction (Finding #1).
    ///
    /// Previously this eagerly did `System::new_with_specifics(everything())`
    /// then `refresh_all()` (a full process-table scan — ~100 ms on launch) and
    /// list-refreshed all three resource handles. Now the `System` starts empty
    /// and every resource is list-populated on first use, so the app reaches an
    /// interactive state before full telemetry collection runs. The TTL-cached
    /// accessors below take care of the first real refresh on demand.
    pub fn new() -> Self {
        init_rayon_pool();
        Self {
            sys_state: Mutex::new(SystemState::new(System::new())),
            temp_cache: Mutex::new(SnapshotCache::default()),
            disks: Mutex::new(LazyList::new(Disks::new())),
            networks: Mutex::new(LazyList::new(Networks::new())),
            components: Mutex::new(LazyList::new(Components::new())),
        }
    }

    /// Total number of OS process-table refreshes performed since construction.
    /// Real instrumentation (not a test hook): used to verify the CPU panel
    /// never rebuilds the process table on its hot path (Findings #2/#3).
    pub fn process_refresh_count(&self) -> u64 {
        self.sys_state
            .lock()
            .map(|state| state.process_refresh_count)
            .unwrap_or(0)
    }

    pub fn cpu(&self) -> Result<CpuStats, String> {
        let mut state = self
            .sys_state
            .lock()
            .map_err(|_| "sysinfo lock poisoned".to_string())?;
        let now = Instant::now();
        if let Some(cpu) = state.cpu.read_fresh(now, CPU_SNAPSHOT_TTL) {
            return Ok(cpu);
        }

        state.sys.refresh_cpu_all();
        Ok(cpu_stats_from_sys(&state.sys)).inspect(|cpu| state.cpu.store(cpu.clone(), now))
    }

    pub fn current_load(&self) -> Result<LoadStats, String> {
        let mut state = self
            .sys_state
            .lock()
            .map_err(|_| "sysinfo lock poisoned".to_string())?;
        let now = Instant::now();
        if let Some(load) = state.load.read_fresh(now, LOAD_SNAPSHOT_TTL) {
            return Ok(load);
        }

        state.sys.refresh_cpu_usage();
        Ok(load_stats_from_sys(&state.sys)).inspect(|load| state.load.store(load.clone(), now))
    }

    pub fn cpu_temperature(&self) -> Result<TempStats, String> {
        let mut comps = self
            .components
            .lock()
            .map_err(|_| "components lock poisoned".to_string())?;
        Ok(temp_stats_from_components(comps.refreshed()))
    }

    /// CPU temperature read through a short TTL cache (Finding #2 "optional
    /// cached path"). The CPU panel polls 1 Hz but SMC/thermal sensors move
    /// slowly, so we hit the components handle at most once per
    /// `TEMP_SNAPSHOT_TTL` and reuse the cached reading in between.
    fn cpu_temperature_cached(&self) -> Result<TempStats, String> {
        let now = Instant::now();
        {
            let cache = self
                .temp_cache
                .lock()
                .map_err(|_| "temp cache lock poisoned".to_string())?;
            if let Some(temp) = cache.read_fresh(now, TEMP_SNAPSHOT_TTL) {
                return Ok(temp);
            }
        }
        let temp = {
            let mut comps = self
                .components
                .lock()
                .map_err(|_| "components lock poisoned".to_string())?;
            temp_stats_from_components(comps.refreshed())
        };
        let mut cache = self
            .temp_cache
            .lock()
            .map_err(|_| "temp cache lock poisoned".to_string())?;
        cache.store(temp.clone(), now);
        Ok(temp)
    }

    pub fn processes(&self) -> Result<ProcessList, String> {
        use sysinfo::{ProcessRefreshKind, ProcessesToUpdate};

        let mut state = self
            .sys_state
            .lock()
            .map_err(|_| "sysinfo lock poisoned".to_string())?;
        let now = Instant::now();
        if let Some(processes) = state.processes.read_fresh(now, PROCESS_SNAPSHOT_TTL) {
            return Ok(processes);
        }

        state.sys.refresh_processes_specifics(
            ProcessesToUpdate::All,
            // sysinfo 0.32 names this flag remove_dead_processes.
            // Keep it true because this service is long-lived and si_processes is polled often.
            true,
            ProcessRefreshKind::everything(),
        );
        let list = collect_process_rows(&state.sys);

        Ok(process_list_from_rows(list))
            .inspect(|processes| state.processes.store(processes.clone(), now))
    }

    /// Combined snapshot retained for the (Swift-unused) `sysinfo_snapshot_json`
    /// FFI surface. The live native panels use the lighter `cpu_snapshot` /
    /// `toplist_snapshot` / `mem` paths below instead.
    pub fn panel_snapshot(
        &self,
        collapse_threads_by_name: bool,
        top_limit: usize,
        include_process_list: bool,
    ) -> Result<PanelSnapshot, String> {
        let (cpu, current_load, mem, process_count, top_processes, process_list) = {
            let mut state = self
                .sys_state
                .lock()
                .map_err(|_| "sysinfo lock poisoned".to_string())?;
            state.sys.refresh_cpu_all();
            state.sys.refresh_memory();
            let now = Instant::now();
            state.refresh_processes_if_stale(now, Duration::ZERO);

            let sys = &state.sys;
            let mem = mem_stats_from_system(sys);
            let cpu = cpu_stats_from_sys(sys);
            let current_load = load_stats_from_sys(sys);
            let process_count = state.process_count;
            let top_processes = top_rows_from_sys(sys, collapse_threads_by_name, top_limit);
            let process_list = if include_process_list {
                Some(process_list_payload(sys, collapse_threads_by_name))
            } else {
                None
            };
            (
                cpu,
                current_load,
                mem,
                process_count,
                top_processes,
                process_list,
            )
        };

        let cpu_temperature = self.cpu_temperature_cached()?;

        Ok(PanelSnapshot {
            cpu,
            current_load,
            cpu_temperature,
            process_count,
            top_processes,
            mem,
            process_list,
        })
    }

    /// CPU-only snapshot for the cpuinfo panel (Findings #2/#3).
    ///
    /// Refreshes CPU + per-core load and reads temperature through the TTL
    /// cache. It deliberately does **not** rebuild the process table: the only
    /// process work is a one-time seed of the TASKS count so the footer isn't
    /// zero before the first TOPLIST poll. After that the count is whatever the
    /// shared process producer (TOPLIST / modal) last published.
    pub fn cpu_snapshot(&self) -> Result<CpuPanelSnapshot, String> {
        let (cpu, current_load, process_count) = {
            let mut state = self
                .sys_state
                .lock()
                .map_err(|_| "sysinfo lock poisoned".to_string())?;
            state.sys.refresh_cpu_all();
            if state.processes_refreshed_at.is_none() {
                let now = Instant::now();
                state.refresh_processes_if_stale(now, Duration::ZERO);
            }
            let cpu = cpu_stats_from_sys(&state.sys);
            let current_load = load_stats_from_sys(&state.sys);
            (cpu, current_load, state.process_count)
        };

        let cpu_temperature = self.cpu_temperature_cached()?;

        Ok(CpuPanelSnapshot {
            cpu,
            current_load,
            cpu_temperature,
            process_count,
        })
    }

    /// TOPLIST snapshot — the single producer of process-table data
    /// (Finding #3). `dedup_ttl` collapses overlapping polls (the 5 s compact
    /// panel and the 1 s modal) onto one refresh; pass `Duration::ZERO` to force
    /// a refresh every call.
    pub fn toplist_snapshot(
        &self,
        collapse_threads_by_name: bool,
        top_limit: usize,
        include_process_list: bool,
        dedup_ttl: Duration,
    ) -> Result<ToplistData, String> {
        let mut state = self
            .sys_state
            .lock()
            .map_err(|_| "sysinfo lock poisoned".to_string())?;
        let now = Instant::now();
        state.refresh_processes_if_stale(now, dedup_ttl);
        // MEM% is `process_memory / total_memory`, and with lazy `System::new()`
        // the system total is 0 until something refreshes memory. Seed it once
        // here (physical RAM never changes) so the first TOPLIST poll doesn't
        // report 0% for every process before the RAM panel has run.
        if state.sys.total_memory() == 0 {
            state.sys.refresh_memory();
        }

        let sys = &state.sys;
        let top_processes = top_rows_from_sys(sys, collapse_threads_by_name, top_limit);
        let process_list = if include_process_list {
            Some(process_list_payload(sys, collapse_threads_by_name))
        } else {
            None
        };

        Ok(ToplistData {
            top_processes,
            process_list,
        })
    }

    pub fn mem(&self) -> Result<MemStats, String> {
        let mut state = self
            .sys_state
            .lock()
            .map_err(|_| "sysinfo lock poisoned".to_string())?;
        let now = Instant::now();
        if let Some(mem) = state.mem.read_fresh(now, MEM_SNAPSHOT_TTL) {
            return Ok(mem);
        }

        state.sys.refresh_memory();

        Ok(mem_stats_from_system(&state.sys)).inspect(|mem| state.mem.store(mem.clone(), now))
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
                        designed_capacity: joules_to_wh(bat.energy_full_design().value as f64),
                        max_capacity: joules_to_wh(bat.energy_full().value as f64),
                        current_capacity: joules_to_wh(bat.energy().value as f64),
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

    pub fn network_interfaces(&self) -> Result<Vec<NetIface>, String> {
        let mut nets = self
            .networks
            .lock()
            .map_err(|_| "networks lock poisoned".to_string())?;
        let nets = nets.refreshed();
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
        let nets = nets.refreshed();
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

    /// Stub: globe-only consumer was removed in v1; deferred to v0.2.
    pub fn network_connections_stub() -> Vec<serde_json::Value> {
        Vec::new()
    }

    pub fn fs_size(&self) -> Result<Vec<DiskInfo>, String> {
        let mut disks = self
            .disks
            .lock()
            .map_err(|_| "disks lock poisoned".to_string())?;
        let list: Vec<DiskInfo> = disks
            .refreshed()
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
                    use_pct: if total > 0 {
                        (used as f64) * 100.0 / (total as f64)
                    } else {
                        0.0
                    },
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
        let list: Vec<BlockDevice> = disks
            .refreshed()
            .iter()
            .map(|d| {
                let removable = d.is_removable();
                BlockDevice {
                    name: d.name().to_string_lossy().to_string(),
                    device_type: if removable {
                        "usb".to_string()
                    } else {
                        "disk".to_string()
                    },
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

const CPU_SNAPSHOT_TTL: Duration = Duration::from_secs(30);
const LOAD_SNAPSHOT_TTL: Duration = Duration::from_millis(350);
const MEM_SNAPSHOT_TTL: Duration = Duration::from_millis(1000);
const PROCESS_SNAPSHOT_TTL: Duration = Duration::from_millis(1000);
/// CPU temperature read cache window (Finding #2).
///
/// `Components::refresh()` is the single most expensive telemetry call in the
/// app: ~110 ms per read on Apple Silicon (an SMC/IOKit enumeration), and it
/// returns no usable sensor on this hardware to begin with. The old code paid
/// that on every 1 Hz CPU poll and every TOPLIST poll. Thermal values move on a
/// seconds-to-minutes scale, so we read at most once per 15 s and reuse the
/// cached value — cutting ~60 reads/min to ~4 while keeping the gauge live.
const TEMP_SNAPSHOT_TTL: Duration = Duration::from_millis(15_000);

struct SystemState {
    sys: System,
    cpu: SnapshotCache<CpuStats>,
    load: SnapshotCache<LoadStats>,
    mem: SnapshotCache<MemStats>,
    processes: SnapshotCache<ProcessList>,
    /// Shared process-table producer state (Finding #3). When the table was
    /// last rebuilt, the last published process count, and a lifetime counter
    /// of actual OS refreshes (for instrumentation/tests).
    processes_refreshed_at: Option<Instant>,
    process_count: usize,
    process_refresh_count: u64,
}

impl SystemState {
    fn new(sys: System) -> Self {
        Self {
            sys,
            cpu: SnapshotCache::default(),
            load: SnapshotCache::default(),
            mem: SnapshotCache::default(),
            processes: SnapshotCache::default(),
            processes_refreshed_at: None,
            process_count: 0,
            process_refresh_count: 0,
        }
    }

    /// Rebuild the OS process table at most once per `ttl`. Returns whether a
    /// refresh actually ran. This is the single producer: TOPLIST/modal drive
    /// it; the CPU panel only triggers the one-time seed.
    fn refresh_processes_if_stale(&mut self, now: Instant, ttl: Duration) -> bool {
        use sysinfo::{ProcessRefreshKind, ProcessesToUpdate};
        if let Some(at) = self.processes_refreshed_at {
            if now.duration_since(at) <= ttl {
                return false;
            }
        }
        self.sys.refresh_processes_specifics(
            ProcessesToUpdate::All,
            // sysinfo 0.32 names this flag remove_dead_processes.
            true,
            ProcessRefreshKind::everything(),
        );
        self.process_count = self.sys.processes().len();
        self.processes_refreshed_at = Some(now);
        self.process_refresh_count += 1;
        true
    }
}

/// A `sysinfo` resource handle (`Disks` / `Networks` / `Components`) whose list
/// is populated lazily on first use (Finding #1). Construction is free; the
/// first `refreshed()` enumerates the list, and later calls only refresh data.
struct LazyList<T: Listable> {
    inner: T,
    listed: bool,
}

impl<T: Listable> LazyList<T> {
    fn new(inner: T) -> Self {
        Self {
            inner,
            listed: false,
        }
    }

    fn refreshed(&mut self) -> &mut T {
        if self.listed {
            self.inner.refresh_data();
        } else {
            // First access lists AND fetches data, matching the original
            // `new_with_refreshed_list()` + `.refresh()` two-step. `refresh_list`
            // alone only enumerates resources (and is a no-op for `Components`
            // on macOS), so without the data refresh the first poll would read
            // zero/stale metrics — and for temperature that zero gets cached.
            self.inner.refresh_list();
            self.inner.refresh_data();
            self.listed = true;
        }
        &mut self.inner
    }
}

/// List/data refresh seam for the lazily-populated resource handles.
trait Listable {
    fn refresh_list(&mut self);
    fn refresh_data(&mut self);
}

macro_rules! impl_listable {
    ($t:ty) => {
        impl Listable for $t {
            fn refresh_list(&mut self) {
                <$t>::refresh_list(self)
            }
            fn refresh_data(&mut self) {
                <$t>::refresh(self)
            }
        }
    };
}

impl_listable!(Disks);
impl_listable!(Networks);
impl_listable!(Components);

struct SnapshotCache<T> {
    data: Option<T>,
    refreshed_at: Option<Instant>,
}

impl<T> Default for SnapshotCache<T> {
    fn default() -> Self {
        Self {
            data: None,
            refreshed_at: None,
        }
    }
}

impl<T: Clone> SnapshotCache<T> {
    fn read_fresh(&self, now: Instant, ttl: Duration) -> Option<T> {
        let refreshed_at = self.refreshed_at?;
        if now.duration_since(refreshed_at) <= ttl {
            self.data.clone()
        } else {
            None
        }
    }

    fn store(&mut self, data: T, now: Instant) {
        self.data = Some(data);
        self.refreshed_at = Some(now);
    }
}

impl Default for SysinfoService {
    fn default() -> Self {
        Self::new()
    }
}

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

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProcessTopRow {
    pub pid: u32,
    pub name: String,
    pub cpu: f64,
    pub mem: f64,
}

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PanelSnapshot {
    pub cpu: CpuStats,
    pub current_load: LoadStats,
    pub cpu_temperature: TempStats,
    pub process_count: usize,
    pub top_processes: Vec<ProcessTopRow>,
    pub mem: MemStats,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub process_list: Option<ProcessList>,
}

/// CPU-only snapshot consumed by `EdexCore::cpu_snapshot` (Findings #2/#3).
/// Carries everything the cpuinfo panel reads without any process-table work
/// beyond the cached `process_count`.
#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CpuPanelSnapshot {
    pub cpu: CpuStats,
    pub current_load: LoadStats,
    pub cpu_temperature: TempStats,
    pub process_count: usize,
}

/// TOPLIST payload produced from the shared process snapshot (Finding #3).
#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ToplistData {
    pub top_processes: Vec<ProcessTopRow>,
    pub process_list: Option<ProcessList>,
}

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

fn cpu_stats_from_sys(sys: &System) -> CpuStats {
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

    CpuStats {
        manufacturer,
        brand: brand_only,
        cores: cpus.len(),
        physical_cores: sys.physical_core_count().unwrap_or(cpus.len()),
        speed: format!("{speed_ghz:.2}"),
        speed_max: format!("{speed_ghz:.2}"),
    }
}

fn load_stats_from_sys(sys: &System) -> LoadStats {
    let cpus: Vec<CpuLoad> = sys
        .cpus()
        .iter()
        .map(|c| CpuLoad {
            load: c.cpu_usage() as f64,
        })
        .collect();
    let avg = if cpus.is_empty() {
        0.0
    } else {
        sys.global_cpu_usage() as f64
    };

    LoadStats {
        avg_load: avg,
        current_load: avg,
        cpus,
    }
}

fn temp_stats_from_components(comps: &Components) -> TempStats {
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

    TempStats {
        main: max_v,
        max: max_v,
        cores,
    }
}

fn mem_stats_from_system(sys: &System) -> MemStats {
    let total = sys.total_memory();
    let used = sys.used_memory();
    let available = sys.available_memory();
    let free_strict = total.saturating_sub(used);

    MemStats {
        total,
        free: free_strict,
        used,
        active: used,
        // Clamp against the same `free_strict` we store, not the raw
        // `sys.free_memory()`, so the reported `available >= free` invariant
        // (relied on by the ramwatcher `available - free` partition) always holds.
        available: available.max(free_strict),
        buffers: 0,
        cached: 0,
        slab: 0,
        buffcache: 0,
        swaptotal: sys.total_swap(),
        swapused: sys.used_swap(),
        swapfree: sys.free_swap(),
    }
}

fn collect_process_rows(sys: &System) -> Vec<ProcessRow> {
    let total_mem = sys.total_memory() as f64;
    sys.processes()
        .iter()
        .map(|(pid, p)| ProcessRow {
            pid: pid.as_u32(),
            name: p.name().to_string_lossy().to_string(),
            cpu: p.cpu_usage() as f64,
            mem: if total_mem > 0.0 {
                (p.memory() as f64) * 100.0 / total_mem
            } else {
                0.0
            },
            started: chrono_like_iso(p.start_time()),
            state: format!("{:?}", p.status()),
            user: p.user_id().map(|u| u.to_string()).unwrap_or_default(),
            command: p
                .cmd()
                .iter()
                .map(|s| s.to_string_lossy().to_string())
                .collect::<Vec<_>>()
                .join(" "),
        })
        .collect()
}

/// Build the ranked compact top-process rows from the last-refreshed process
/// table. Shared by `panel_snapshot` and `toplist_snapshot` (Finding #3) so the
/// ranking math lives in one place.
fn top_rows_from_sys(
    sys: &System,
    collapse_threads_by_name: bool,
    top_limit: usize,
) -> Vec<ProcessTopRow> {
    let total_mem = sys.total_memory() as f64;
    let rows = sys.processes().iter().map(|(pid, p)| ProcessTopRow {
        pid: pid.as_u32(),
        name: p.name().to_string_lossy().to_string(),
        cpu: p.cpu_usage() as f64,
        mem: if total_mem > 0.0 {
            (p.memory() as f64) * 100.0 / total_mem
        } else {
            0.0
        },
    });
    let mut top_candidates: Vec<ProcessTopRow> = if collapse_threads_by_name {
        collapse_top_rows_by_name(rows.collect())
    } else {
        rows.collect()
    };

    top_candidates.sort_by(|a, b| {
        let score_a = a.cpu * 100.0 + a.mem;
        let score_b = b.cpu * 100.0 + b.mem;
        score_b
            .partial_cmp(&score_a)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    top_candidates.truncate(top_limit.max(1));
    top_candidates
}

/// Build the full process-list payload (expanded modal) from the last-refreshed
/// process table. Shared by `panel_snapshot` and `toplist_snapshot`.
fn process_list_payload(sys: &System, collapse_threads_by_name: bool) -> ProcessList {
    let mut rows = collect_process_rows(sys);
    if collapse_threads_by_name {
        rows = collapse_process_rows_by_name(rows);
    }
    process_list_from_rows(rows)
}

fn process_list_from_rows(list: Vec<ProcessRow>) -> ProcessList {
    let n = list.len();
    ProcessList {
        all: n,
        running: n,
        blocked: 0,
        sleeping: 0,
        list,
    }
}

/// Group rows by `name`; on collision, callers merge via `merge` (typically sum cpu/mem, lowest pid wins).
fn collapse_named_rows<T>(
    rows: Vec<T>,
    name_key: impl Fn(&T) -> String,
    mut merge: impl FnMut(&mut T, T),
) -> Vec<T> {
    let mut collapsed: HashMap<String, T> = HashMap::new();
    for row in rows {
        match collapsed.entry(name_key(&row)) {
            Entry::Occupied(mut slot) => {
                merge(slot.get_mut(), row);
            }
            Entry::Vacant(slot) => {
                slot.insert(row);
            }
        }
    }
    collapsed.into_values().collect()
}

/// Aggregate processes that share the same name: sum cpu/mem, keep lowest pid.
fn collapse_process_rows_by_name(rows: Vec<ProcessRow>) -> Vec<ProcessRow> {
    collapse_named_rows(
        rows,
        |row| row.name.clone(),
        |slot, row| {
            if slot.pid > row.pid {
                slot.pid = row.pid;
                slot.started = row.started.clone();
                slot.state = row.state.clone();
                slot.user = row.user.clone();
                slot.command = row.command.clone();
            }
            slot.cpu += row.cpu;
            slot.mem += row.mem;
        },
    )
}

/// Aggregate processes that share the same name: sum cpu/mem, keep lowest pid.
fn collapse_top_rows_by_name(rows: Vec<ProcessTopRow>) -> Vec<ProcessTopRow> {
    collapse_named_rows(
        rows,
        |row| row.name.clone(),
        |slot, row| {
            if slot.pid > row.pid {
                slot.pid = row.pid;
            }
            slot.cpu += row.cpu;
            slot.mem += row.mem;
        },
    )
}

fn chrono_like_iso(unix_secs: u64) -> String {
    let secs = unix_secs as i64;
    let days = secs / 86400;
    let mut s = secs % 86400;
    let hour = s / 3600;
    s %= 3600;
    let minute = s / 60;
    let second = s % 60;
    let (year, month, day) = days_to_date(days);

    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z")
}

fn joules_to_wh(joules: f64) -> f64 {
    joules / 3600.0
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

#[cfg(test)]
mod tests {
    use super::*;

    // Process refresh fans out across rayon's global pool; cap it once at
    // construction so idle telemetry doesn't wake one thread per core.
    #[test]
    fn new_caps_rayon_global_thread_pool() {
        let _service = SysinfoService::new();
        assert!(
            rayon::current_num_threads() <= 3,
            "rayon global pool should be capped at 3 threads (got {})",
            rayon::current_num_threads()
        );
    }

    // Finding #1: constructing the service must not eagerly scan the process
    // table (the heavy startup cost). A fresh service has refreshed zero times.
    #[test]
    fn new_does_not_eagerly_refresh_processes() {
        let service = SysinfoService::new();
        assert_eq!(service.process_refresh_count(), 0);
    }

    // Finding #2/#3: the CPU panel polls 1 Hz but must NOT rebuild the process
    // table every tick. It seeds the process count exactly once (so the TASKS
    // footer isn't zero at launch), then never refreshes processes again.
    #[test]
    fn cpu_snapshot_seeds_process_count_once_then_never_refreshes() {
        let service = SysinfoService::new();
        for _ in 0..6 {
            let snap = service.cpu_snapshot().expect("cpu snapshot");
            assert!(!snap.current_load.cpus.is_empty(), "per-core loads present");
            assert!(snap.process_count > 0, "TASKS count seeded, not zero");
        }
        assert_eq!(
            service.process_refresh_count(),
            1,
            "CPU path refreshes the process table exactly once (the seed)"
        );
    }

    // Finding #3: overlapping TOPLIST polls (panel + open modal) within the
    // dedup window reuse one process refresh instead of rebuilding twice.
    #[test]
    fn toplist_snapshot_dedups_within_ttl() {
        let service = SysinfoService::new();
        let ttl = Duration::from_secs(10);
        let _ = service.toplist_snapshot(false, 5, false, ttl).unwrap();
        let _ = service.toplist_snapshot(false, 5, false, ttl).unwrap();
        assert_eq!(
            service.process_refresh_count(),
            1,
            "second call within TTL reuses the cached process table"
        );
    }

    // Finding #3: with no dedup window, each TOPLIST poll refreshes (the modal's
    // high-frequency path). Proves the TTL guard, not a permanent freeze.
    #[test]
    fn toplist_snapshot_refreshes_each_call_with_zero_ttl() {
        let service = SysinfoService::new();
        let _ = service
            .toplist_snapshot(false, 5, false, Duration::ZERO)
            .unwrap();
        let _ = service
            .toplist_snapshot(false, 5, false, Duration::ZERO)
            .unwrap();
        assert_eq!(service.process_refresh_count(), 2);
    }

    // Finding #3: TOPLIST still produces the compact top rows and (on demand)
    // the full process list from the shared snapshot.
    #[test]
    fn toplist_snapshot_yields_top_rows_and_optional_list() {
        let service = SysinfoService::new();
        let compact = service
            .toplist_snapshot(false, 5, false, Duration::ZERO)
            .unwrap();
        assert!(compact.top_processes.len() <= 5);
        assert!(compact.process_list.is_none());

        let full = service
            .toplist_snapshot(false, 5, true, Duration::ZERO)
            .unwrap();
        assert!(full.process_list.is_some());
        assert!(!full.process_list.unwrap().list.is_empty());
    }

    // Regression (BugBot): with lazy `System::new()`, the system memory total is
    // 0 until refreshed, so MEM% was 0 for every process on the first TOPLIST
    // poll. The seed in `toplist_snapshot` must populate it before ranking.
    #[test]
    fn toplist_snapshot_reports_nonzero_memory_on_fresh_service() {
        let service = SysinfoService::new();
        let snap = service
            .toplist_snapshot(false, 5, false, Duration::ZERO)
            .unwrap();
        assert!(
            snap.top_processes.iter().any(|row| row.mem > 0.0),
            "MEM% must be nonzero once the memory total is seeded (got {:?})",
            snap.top_processes.iter().map(|r| r.mem).collect::<Vec<_>>()
        );
    }

    #[test]
    fn collapse_top_rows_by_name_sums_once_and_keeps_lowest_pid() {
        let rows = vec![
            ProcessTopRow {
                pid: 200,
                name: "Chrome".to_string(),
                cpu: 10.0,
                mem: 2.0,
            },
            ProcessTopRow {
                pid: 100,
                name: "Chrome".to_string(),
                cpu: 5.0,
                mem: 1.0,
            },
            ProcessTopRow {
                pid: 50,
                name: "Safari".to_string(),
                cpu: 3.0,
                mem: 0.5,
            },
        ];
        let mut collapsed = collapse_top_rows_by_name(rows);
        collapsed.sort_by_key(|r| r.name.clone());

        assert_eq!(collapsed.len(), 2);
        let chrome = &collapsed[0];
        assert_eq!(chrome.name, "Chrome");
        assert_eq!(chrome.pid, 100);
        assert!((chrome.cpu - 15.0).abs() < f64::EPSILON);
        assert!((chrome.mem - 3.0).abs() < f64::EPSILON);

        let safari = &collapsed[1];
        assert_eq!(safari.name, "Safari");
        assert_eq!(safari.pid, 50);
        assert!((safari.cpu - 3.0).abs() < f64::EPSILON);
        assert!((safari.mem - 0.5).abs() < f64::EPSILON);
    }
}
