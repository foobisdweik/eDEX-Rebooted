use serde_json::{json, Value};
use std::sync::Mutex;
use sysinfo::{Components, Disks, Networks, ProcessRefreshKind, RefreshKind, System};
use tauri::State;

pub struct SysinfoState {
    pub sys: Mutex<System>,
    pub disks: Mutex<Disks>,
    pub networks: Mutex<Networks>,
    pub components: Mutex<Components>,
}

impl SysinfoState {
    pub fn new() -> Self {
        let mut sys = System::new_with_specifics(RefreshKind::everything());
        sys.refresh_all();
        Self {
            sys: Mutex::new(sys),
            disks: Mutex::new(Disks::new_with_refreshed_list()),
            networks: Mutex::new(Networks::new_with_refreshed_list()),
            components: Mutex::new(Components::new_with_refreshed_list()),
        }
    }
}

#[tauri::command]
pub fn si_cpu(state: State<'_, SysinfoState>) -> Value {
    let mut sys = state.sys.lock().unwrap();
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

    json!({
        "manufacturer": manufacturer,
        "brand": brand_only,
        "cores": cpus.len(),
        "physicalCores": System::physical_core_count().unwrap_or(cpus.len()),
        "speed": format!("{:.2}", speed_ghz),
        "speedMax": format!("{:.2}", speed_ghz)
    })
}

#[tauri::command]
pub fn si_current_load(state: State<'_, SysinfoState>) -> Value {
    let mut sys = state.sys.lock().unwrap();
    sys.refresh_cpu_usage();
    let cpus: Vec<Value> = sys
        .cpus()
        .iter()
        .map(|c| json!({ "load": c.cpu_usage() as f64 }))
        .collect();
    let avg = if cpus.is_empty() {
        0.0
    } else {
        sys.global_cpu_usage() as f64
    };
    json!({
        "avgLoad": avg,
        "currentLoad": avg,
        "cpus": cpus
    })
}

#[tauri::command]
pub fn si_cpu_temperature(state: State<'_, SysinfoState>) -> Value {
    let mut comps = state.components.lock().unwrap();
    comps.refresh(true);
    let temps: Vec<f32> = comps
        .iter()
        .filter_map(|c| {
            let label = c.label().to_lowercase();
            if label.contains("cpu") || label.contains("core") || label.contains("package") {
                c.temperature()
            } else {
                None
            }
        })
        .collect();
    let max = temps
        .iter()
        .cloned()
        .fold(f32::NEG_INFINITY, f32::max);
    json!({
        "main": if max.is_finite() { max as f64 } else { 0.0 },
        "max": if max.is_finite() { max as f64 } else { 0.0 },
        "cores": temps
    })
}

#[tauri::command]
pub fn si_processes(state: State<'_, SysinfoState>) -> Value {
    let mut sys = state.sys.lock().unwrap();
    sys.refresh_processes_specifics(
        sysinfo::ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::everything(),
    );
    let total_mem = sys.total_memory() as f64;
    let list: Vec<Value> = sys
        .processes()
        .iter()
        .map(|(pid, p)| {
            let started_secs = p.start_time();
            let started_iso = chrono_like_iso(started_secs);
            json!({
                "pid": pid.as_u32(),
                "name": p.name().to_string_lossy(),
                "cpu": p.cpu_usage() as f64,
                "mem": if total_mem > 0.0 { (p.memory() as f64) * 100.0 / total_mem } else { 0.0 },
                "started": started_iso,
                "state": format!("{:?}", p.status()),
                "user": p.user_id().map(|u| u.to_string()).unwrap_or_default(),
                "command": p.cmd().iter().map(|s| s.to_string_lossy().to_string()).collect::<Vec<_>>().join(" ")
            })
        })
        .collect();

    json!({
        "all": list.len(),
        "running": list.len(),
        "blocked": 0,
        "sleeping": 0,
        "list": list
    })
}

fn chrono_like_iso(unix_secs: u64) -> String {
    // Produce a string that JS Date.parse can read. We don't pull in chrono for one timestamp.
    use std::time::{Duration, UNIX_EPOCH};
    let t = UNIX_EPOCH + Duration::from_secs(unix_secs);
    // Format manually as RFC 3339 (UTC).
    let secs = unix_secs as i64;
    let days = secs / 86400;
    let mut s = secs % 86400;
    let hour = s / 3600;
    s %= 3600;
    let minute = s / 60;
    let second = s % 60;
    // Convert days since 1970-01-01 to date.
    let (year, month, day) = days_to_date(days);
    let _ = t;
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hour, minute, second
    )
}

fn days_to_date(days_from_epoch: i64) -> (i32, u32, u32) {
    let mut days = days_from_epoch + 719468;
    let era = (if days >= 0 { days } else { days - 146096 }) / 146097;
    let doe = (days - era * 146097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe as i32 + (era * 400) as i32;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };
    let _ = (&mut days,); // silence unused-mut on some toolchains
    (year, m, d)
}

#[tauri::command]
pub fn si_mem(state: State<'_, SysinfoState>) -> Value {
    let mut sys = state.sys.lock().unwrap();
    sys.refresh_memory();
    let total = sys.total_memory();
    let used = sys.used_memory();
    let free = sys.free_memory();
    let available = sys.available_memory();
    // The renderer expects free+used === total; sysinfo's "free" is strict free RAM. Use total-used.
    let free_strict = total.saturating_sub(used);
    json!({
        "total": total,
        "free": free_strict,
        "used": used,
        "active": used,
        "available": available.max(free),
        "buffers": 0u64,
        "cached": 0u64,
        "slab": 0u64,
        "buffcache": 0u64,
        "swaptotal": sys.total_swap(),
        "swapused": sys.used_swap(),
        "swapfree": sys.free_swap()
    })
}

#[tauri::command]
pub fn si_battery() -> Value {
    match battery::Manager::new() {
        Ok(manager) => match manager.batteries() {
            Ok(mut iter) => {
                if let Some(Ok(bat)) = iter.next() {
                    let percent = (bat.state_of_charge().value * 100.0).round() as i64;
                    let state = bat.state();
                    let charging = matches!(state, battery::State::Charging);
                    let ac = matches!(
                        state,
                        battery::State::Charging | battery::State::Full | battery::State::Unknown
                    );
                    return json!({
                        "hasBattery": true,
                        "cycleCount": bat.cycle_count().unwrap_or(0),
                        "isCharging": charging,
                        "designedCapacity": bat.energy_full_design().value as f64,
                        "maxCapacity": bat.energy_full().value as f64,
                        "currentCapacity": bat.energy().value as f64,
                        "voltage": bat.voltage().value as f64,
                        "capacityUnit": "Wh",
                        "percent": percent,
                        "timeRemaining": bat.time_to_empty().map(|t| t.value as i64).unwrap_or(-1),
                        "acConnected": ac,
                        "type": "Battery",
                        "model": bat.model().unwrap_or("").to_string(),
                        "manufacturer": bat.vendor().unwrap_or("").to_string(),
                        "serial": bat.serial_number().unwrap_or("").to_string()
                    });
                }
            }
            Err(_) => {}
        },
        Err(_) => {}
    }
    json!({
        "hasBattery": false,
        "isCharging": false,
        "acConnected": true,
        "percent": 0
    })
}

#[tauri::command]
pub fn si_network_interfaces(state: State<'_, SysinfoState>) -> Value {
    let mut nets = state.networks.lock().unwrap();
    nets.refresh(true);

    // Pull /sbin/ifconfig parsing only if needed; sysinfo gives MAC + IP via ip_networks.
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
        let internal = name == "lo" || name == "lo0" || name.starts_with("utun") || ip4 == "127.0.0.1";
        let operstate = if data.received() > 0 || data.transmitted() > 0 || !ip4.is_empty() {
            "up"
        } else {
            "down"
        };
        list.push(json!({
            "iface": name,
            "ifaceName": name,
            "default": false,
            "ip4": ip4,
            "ip6": ip6,
            "mac": data.mac_address().to_string(),
            "internal": internal,
            "virtual": false,
            "operstate": operstate,
            "type": "wireless",
            "duplex": "",
            "mtu": data.mtu(),
            "speed": -1,
            "dhcp": false,
            "dnsSuffix": "",
            "ieee8021xAuth": "",
            "ieee8021xState": "",
            "carrierChanges": 0
        }));
    }
    Value::Array(list)
}

#[tauri::command]
pub fn si_network_stats(state: State<'_, SysinfoState>, iface: Option<String>) -> Value {
    let mut nets = state.networks.lock().unwrap();
    nets.refresh(true);
    let mut out = Vec::new();
    for (name, data) in nets.iter() {
        if let Some(filter) = &iface {
            if name != filter {
                continue;
            }
        }
        out.push(json!({
            "iface": name,
            "operstate": "up",
            "rx_bytes": data.total_received(),
            "tx_bytes": data.total_transmitted(),
            "rx_dropped": 0u64,
            "tx_dropped": 0u64,
            "rx_errors": 0u64,
            "tx_errors": 0u64,
            "rx_sec": data.received(),
            "tx_sec": data.transmitted(),
            "ms": 1000u64
        }));
    }
    Value::Array(out)
}

#[tauri::command]
pub fn si_network_connections() -> Value {
    // Deferred to v0.2 — globe-only consumer was removed from v1.
    Value::Array(Vec::new())
}

#[tauri::command]
pub fn si_fs_size(state: State<'_, SysinfoState>) -> Value {
    let mut disks = state.disks.lock().unwrap();
    disks.refresh(true);
    let list: Vec<Value> = disks
        .iter()
        .map(|d| {
            let total = d.total_space();
            let avail = d.available_space();
            let used = total.saturating_sub(avail);
            json!({
                "fs": d.name().to_string_lossy(),
                "type": format!("{:?}", d.kind()),
                "size": total,
                "used": used,
                "available": avail,
                "use": if total > 0 { (used as f64) * 100.0 / (total as f64) } else { 0.0 },
                "mount": d.mount_point().to_string_lossy()
            })
        })
        .collect();
    Value::Array(list)
}

#[tauri::command]
pub fn si_block_devices(state: State<'_, SysinfoState>) -> Value {
    let mut disks = state.disks.lock().unwrap();
    disks.refresh(true);
    let list: Vec<Value> = disks
        .iter()
        .map(|d| {
            let mount = d.mount_point().to_string_lossy().to_string();
            let name = d.name().to_string_lossy().to_string();
            let removable = d.is_removable();
            json!({
                "name": name,
                "type": if removable { "usb" } else { "disk" },
                "fsType": format!("{:?}", d.file_system().to_string_lossy()),
                "mount": mount,
                "size": d.total_space(),
                "physical": "SSD",
                "uuid": "",
                "label": "",
                "model": "",
                "serial": "",
                "removable": removable,
                "protocol": ""
            })
        })
        .collect();
    Value::Array(list)
}

#[tauri::command]
pub fn si_system() -> Value {
    json!({
        "manufacturer": "Apple",
        "model": System::host_name().unwrap_or_default(),
        "version": System::os_version().unwrap_or_default(),
        "serial": "",
        "uuid": "",
        "sku": ""
    })
}

#[tauri::command]
pub fn si_chassis() -> Value {
    json!({
        "manufacturer": "Apple",
        "model": System::host_name().unwrap_or_default(),
        "type": "Laptop",
        "version": System::kernel_version().unwrap_or_default(),
        "serial": "",
        "assetTag": "",
        "sku": ""
    })
}
