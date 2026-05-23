//! Tauri command wrappers around SysinfoService.
//!
//! Data shapes and refresh semantics live in sysinfo_service.rs. These
//! wrappers preserve the JS-facing command names while dispatching sync
//! service methods onto blocking worker threads.

use crate::sysinfo_service::{
    BatteryInfo, BlockDevice, ChassisInfo, CpuStats, DiskInfo, LoadStats, MemStats, NetIface,
    NetStats, ProcessList, SysinfoService, SystemInfo, TempStats,
};
use std::sync::Arc;
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
