//! JSON wire-shape contract for SysinfoService output.
//!
//! These tests guarantee the serde serialization of each stats struct
//! produces the exact JSON shape today's JS panels consume via
//! `window.si.X()` -> #[tauri::command] si_x. They use deterministic
//! fixture structs, not live sysinfo values, so they are stable across
//! machines and CI runs.

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

#[test]
fn load_stats_wire_shape_is_stable() {
    let fixture = LoadStats {
        avg_load: 42.5,
        current_load: 42.5,
        cpus: vec![CpuLoad { load: 10.0 }, CpuLoad { load: 80.0 }],
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

#[test]
fn uptime_wire_shape_is_stable() {
    let actual = serde_json::to_value(123_456_u64).unwrap();
    assert_eq!(actual, json!(123_456));
}
