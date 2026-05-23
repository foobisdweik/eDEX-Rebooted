//! Tauri command wrappers around SysinfoService.
//!
//! Data shapes and refresh semantics live in sysinfo_service.rs. These
//! wrappers preserve the JS-facing command names while dispatching sync
//! service methods onto blocking worker threads.

use crate::sysinfo_service::{
    BatteryInfo, BlockDevice, ChassisInfo, CpuStats, DiskInfo, LoadStats, MemStats, NetIface,
    NetStats, PanelSnapshot, ProcessList, SysinfoService, SystemInfo, TempStats,
};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tauri::{async_runtime, State};

async fn blocking<T, F>(f: F) -> Result<T, String>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, String> + Send + 'static,
{
    async_runtime::spawn_blocking(f)
        .await
        .map_err(|e| e.to_string())?
}

fn log_command_latency(name: &str, started: Instant, ok: bool) {
    let elapsed = started.elapsed();
    if elapsed >= Duration::from_millis(20) {
        eprintln!(
            "[perf][sysinfo] {name} {}ms status={}",
            elapsed.as_millis(),
            if ok { "ok" } else { "err" }
        );
    }
}

#[tauri::command]
pub async fn si_cpu(svc: State<'_, Arc<SysinfoService>>) -> Result<CpuStats, String> {
    let started = Instant::now();
    let svc = Arc::clone(&svc);
    let result = blocking(move || svc.cpu()).await;
    log_command_latency("si_cpu", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn si_current_load(svc: State<'_, Arc<SysinfoService>>) -> Result<LoadStats, String> {
    let started = Instant::now();
    let svc = Arc::clone(&svc);
    let result = blocking(move || svc.current_load()).await;
    log_command_latency("si_current_load", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn si_cpu_temperature(svc: State<'_, Arc<SysinfoService>>) -> Result<TempStats, String> {
    let started = Instant::now();
    let svc = Arc::clone(&svc);
    let result = blocking(move || svc.cpu_temperature()).await;
    log_command_latency("si_cpu_temperature", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn si_processes(svc: State<'_, Arc<SysinfoService>>) -> Result<ProcessList, String> {
    let started = Instant::now();
    let svc = Arc::clone(&svc);
    let result = blocking(move || svc.processes()).await;
    log_command_latency("si_processes", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn si_panel_snapshot(
    svc: State<'_, Arc<SysinfoService>>,
    collapse_threads_by_name: Option<bool>,
    top_limit: Option<usize>,
    include_process_list: Option<bool>,
) -> Result<PanelSnapshot, String> {
    let started = Instant::now();
    let svc = Arc::clone(&svc);
    let collapse_threads_by_name = collapse_threads_by_name.unwrap_or(false);
    let top_limit = top_limit.unwrap_or(5);
    let include_process_list = include_process_list.unwrap_or(false);
    let result = blocking(move || {
        svc.panel_snapshot(collapse_threads_by_name, top_limit, include_process_list)
    })
    .await;
    log_command_latency("si_panel_snapshot", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn si_mem(svc: State<'_, Arc<SysinfoService>>) -> Result<MemStats, String> {
    let started = Instant::now();
    let svc = Arc::clone(&svc);
    let result = blocking(move || svc.mem()).await;
    log_command_latency("si_mem", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn si_battery(svc: State<'_, Arc<SysinfoService>>) -> Result<BatteryInfo, String> {
    let started = Instant::now();
    let svc = Arc::clone(&svc);
    let result = blocking(move || svc.battery()).await;
    log_command_latency("si_battery", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn si_network_interfaces(
    svc: State<'_, Arc<SysinfoService>>,
) -> Result<Vec<NetIface>, String> {
    let started = Instant::now();
    let svc = Arc::clone(&svc);
    let result = blocking(move || svc.network_interfaces()).await;
    log_command_latency("si_network_interfaces", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn si_network_stats(
    svc: State<'_, Arc<SysinfoService>>,
    iface: Option<String>,
) -> Result<Vec<NetStats>, String> {
    let started = Instant::now();
    let svc = Arc::clone(&svc);
    let result = blocking(move || svc.network_stats(iface.as_deref())).await;
    log_command_latency("si_network_stats", started, result.is_ok());
    result
}

#[tauri::command]
pub fn si_network_connections() -> Vec<serde_json::Value> {
    SysinfoService::network_connections_stub()
}

#[tauri::command]
pub async fn si_fs_size(svc: State<'_, Arc<SysinfoService>>) -> Result<Vec<DiskInfo>, String> {
    let started = Instant::now();
    let svc = Arc::clone(&svc);
    let result = blocking(move || svc.fs_size()).await;
    log_command_latency("si_fs_size", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn si_block_devices(
    svc: State<'_, Arc<SysinfoService>>,
) -> Result<Vec<BlockDevice>, String> {
    let started = Instant::now();
    let svc = Arc::clone(&svc);
    let result = blocking(move || svc.block_devices()).await;
    log_command_latency("si_block_devices", started, result.is_ok());
    result
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
