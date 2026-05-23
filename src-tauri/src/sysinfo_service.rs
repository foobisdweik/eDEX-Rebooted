//! Tauri-agnostic sysinfo service.
//!
//! Owns the cached sysinfo handles (System / Components / Networks / Disks)
//! and exposes typed query methods. Consumed by `sysinfo_cmds.rs` for the
//! JS-side #[tauri::command] surface and by future native panel renderers
//! without an `invoke()` round-trip.

use serde::Serialize;
use std::collections::{hash_map::Entry, HashMap};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use sysinfo::{Components, Disks, Networks, System};

pub struct SysinfoService {
    sys_state: Mutex<SystemState>,
    disks: Mutex<Disks>,
    networks: Mutex<Networks>,
    components: Mutex<Components>,
}

impl SysinfoService {
    pub fn new() -> Self {
        use sysinfo::RefreshKind;

        let mut sys = System::new_with_specifics(RefreshKind::everything());
        sys.refresh_all();
        Self {
            sys_state: Mutex::new(SystemState::new(sys)),
            disks: Mutex::new(Disks::new_with_refreshed_list()),
            networks: Mutex::new(Networks::new_with_refreshed_list()),
            components: Mutex::new(Components::new_with_refreshed_list()),
        }
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
        comps.refresh();
        Ok(temp_stats_from_components(&comps))
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
        let total_mem = state.sys.total_memory() as f64;
        let list: Vec<ProcessRow> = state
            .sys
            .processes()
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
            .collect();
        let n = list.len();

        Ok(ProcessList {
            all: n,
            running: n,
            blocked: 0,
            sleeping: 0,
            list,
        })
        .inspect(|processes| state.processes.store(processes.clone(), now))
    }

    pub fn panel_snapshot(
        &self,
        collapse_threads_by_name: bool,
        top_limit: usize,
    ) -> Result<PanelSnapshot, String> {
        use sysinfo::{ProcessRefreshKind, ProcessesToUpdate};

        let mut state = self
            .sys_state
            .lock()
            .map_err(|_| "sysinfo lock poisoned".to_string())?;
        let sys = &mut state.sys;
        sys.refresh_cpu_all();
        sys.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::everything(),
        );

        let cpu = cpu_stats_from_sys(sys);

        let current_load = load_stats_from_sys(sys);

        let process_count = sys.processes().len();
        let total_mem = sys.total_memory() as f64;
        let mut top_candidates: Vec<ProcessTopRow> = if collapse_threads_by_name {
            let rows = sys
                .processes()
                .iter()
                .map(|(pid, p)| ProcessTopRow {
                    pid: pid.as_u32(),
                    name: p.name().to_string_lossy().to_string(),
                    cpu: p.cpu_usage() as f64,
                    mem: if total_mem > 0.0 {
                        (p.memory() as f64) * 100.0 / total_mem
                    } else {
                        0.0
                    },
                })
                .collect();
            collapse_top_rows_by_name(rows)
        } else {
            sys.processes()
                .iter()
                .map(|(pid, p)| ProcessTopRow {
                    pid: pid.as_u32(),
                    name: p.name().to_string_lossy().to_string(),
                    cpu: p.cpu_usage() as f64,
                    mem: if total_mem > 0.0 {
                        (p.memory() as f64) * 100.0 / total_mem
                    } else {
                        0.0
                    },
                })
                .collect()
        };

        top_candidates.sort_by(|a, b| {
            let score_a = a.cpu * 100.0 + a.mem;
            let score_b = b.cpu * 100.0 + b.mem;
            score_b
                .partial_cmp(&score_a)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        top_candidates.truncate(top_limit.max(1));

        drop(state);

        let mut comps = self
            .components
            .lock()
            .map_err(|_| "components lock poisoned".to_string())?;
        comps.refresh();
        let cpu_temperature = temp_stats_from_components(&comps);

        Ok(PanelSnapshot {
            cpu,
            current_load,
            cpu_temperature,
            process_count,
            top_processes: top_candidates,
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
        let total = state.sys.total_memory();
        let used = state.sys.used_memory();
        let free = state.sys.free_memory();
        let available = state.sys.available_memory();
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
            swaptotal: state.sys.total_swap(),
            swapused: state.sys.used_swap(),
            swapfree: state.sys.free_swap(),
        })
        .inspect(|mem| state.mem.store(mem.clone(), now))
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

    /// Stub: globe-only consumer was removed in v1; deferred to v0.2.
    pub fn network_connections_stub() -> Vec<serde_json::Value> {
        Vec::new()
    }

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
        disks.refresh();
        let list: Vec<BlockDevice> = disks
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

struct SystemState {
    sys: System,
    cpu: SnapshotCache<CpuStats>,
    load: SnapshotCache<LoadStats>,
    mem: SnapshotCache<MemStats>,
    processes: SnapshotCache<ProcessList>,
}

impl SystemState {
    fn new(sys: System) -> Self {
        Self {
            sys,
            cpu: SnapshotCache::default(),
            load: SnapshotCache::default(),
            mem: SnapshotCache::default(),
            processes: SnapshotCache::default(),
        }
    }
}

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

/// Aggregate processes that share the same name: sum cpu/mem, keep lowest pid.
fn collapse_top_rows_by_name(rows: Vec<ProcessTopRow>) -> Vec<ProcessTopRow> {
    let mut collapsed: HashMap<String, ProcessTopRow> = HashMap::new();
    for row in rows {
        match collapsed.entry(row.name.clone()) {
            Entry::Occupied(mut slot) => {
                let slot = slot.get_mut();
                if slot.pid > row.pid {
                    slot.pid = row.pid;
                }
                slot.cpu += row.cpu;
                slot.mem += row.mem;
            }
            Entry::Vacant(slot) => {
                slot.insert(row);
            }
        }
    }
    collapsed.into_values().collect()
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
