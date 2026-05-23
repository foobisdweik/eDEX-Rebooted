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

async fn with_service<T, F>(svc: State<'_, Arc<SysinfoService>>, f: F) -> Result<T, String>
where
    T: Send + 'static,
    F: FnOnce(Arc<SysinfoService>) -> Result<T, String> + Send + 'static,
{
    let svc = Arc::clone(&svc);
    blocking(move || f(svc)).await
}

#[tauri::command]
pub async fn si_cpu(svc: State<'_, Arc<SysinfoService>>) -> Result<CpuStats, String> {
    with_service(svc, |svc| svc.cpu()).await
}

#[tauri::command]
pub async fn si_current_load(svc: State<'_, Arc<SysinfoService>>) -> Result<LoadStats, String> {
    with_service(svc, |svc| svc.current_load()).await
}

#[tauri::command]
pub async fn si_cpu_temperature(svc: State<'_, Arc<SysinfoService>>) -> Result<TempStats, String> {
    with_service(svc, |svc| svc.cpu_temperature()).await
}

#[tauri::command]
pub async fn si_processes(svc: State<'_, Arc<SysinfoService>>) -> Result<ProcessList, String> {
    with_service(svc, |svc| svc.processes()).await
}

#[tauri::command]
pub async fn si_mem(svc: State<'_, Arc<SysinfoService>>) -> Result<MemStats, String> {
    with_service(svc, |svc| svc.mem()).await
}

#[tauri::command]
pub async fn si_battery(svc: State<'_, Arc<SysinfoService>>) -> Result<BatteryInfo, String> {
    with_service(svc, |svc| svc.battery()).await
}

#[tauri::command]
pub async fn si_network_interfaces(
    svc: State<'_, Arc<SysinfoService>>,
) -> Result<Vec<NetIface>, String> {
    with_service(svc, |svc| svc.network_interfaces()).await
}

#[tauri::command]
pub async fn si_network_stats(
    svc: State<'_, Arc<SysinfoService>>,
    iface: Option<String>,
) -> Result<Vec<NetStats>, String> {
    with_service(svc, move |svc| svc.network_stats(iface.as_deref())).await
}

#[tauri::command]
pub async fn si_network_connections() -> Result<Vec<serde_json::Value>, String> {
    Ok(SysinfoService::network_connections_stub())
}

#[tauri::command]
pub async fn si_fs_size(svc: State<'_, Arc<SysinfoService>>) -> Result<Vec<DiskInfo>, String> {
    with_service(svc, |svc| svc.fs_size()).await
}

#[tauri::command]
pub async fn si_block_devices(
    svc: State<'_, Arc<SysinfoService>>,
) -> Result<Vec<BlockDevice>, String> {
    with_service(svc, |svc| svc.block_devices()).await
}

#[tauri::command]
pub async fn si_system(svc: State<'_, Arc<SysinfoService>>) -> Result<SystemInfo, String> {
    Ok(svc.system())
}

#[tauri::command]
pub async fn si_chassis(svc: State<'_, Arc<SysinfoService>>) -> Result<ChassisInfo, String> {
    Ok(svc.chassis())
}

#[tauri::command]
pub async fn si_uptime(svc: State<'_, Arc<SysinfoService>>) -> Result<u64, String> {
    Ok(svc.uptime())
}
