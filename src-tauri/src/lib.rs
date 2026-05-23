mod fs_cmds;
mod native_mount;
mod pty;
mod settings;
mod sysinfo_cmds;
pub mod sysinfo_service;

use native_mount::NativeMountState;
use pty::PtyManager;
use settings::OverrideState;
use std::sync::Arc;
use sysinfo_service::SysinfoService;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .manage(PtyManager::new())
        .manage(OverrideState::default())
        .manage(Arc::new(SysinfoService::new()))
        .manage(NativeMountState::default())
        .setup(|app| {
            settings::ensure_userdata(app.handle())?;
            native_mount::install(app.handle())?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            // pty
            pty::pty_spawn,
            pty::pty_write,
            pty::pty_resize,
            pty::pty_kill,
            pty::pty_cwd,
            pty::pty_process,
            // sysinfo
            sysinfo_cmds::si_cpu,
            sysinfo_cmds::si_current_load,
            sysinfo_cmds::si_cpu_temperature,
            sysinfo_cmds::si_processes,
            sysinfo_cmds::si_mem,
            sysinfo_cmds::si_battery,
            sysinfo_cmds::si_network_interfaces,
            sysinfo_cmds::si_network_stats,
            sysinfo_cmds::si_network_connections,
            sysinfo_cmds::si_fs_size,
            sysinfo_cmds::si_block_devices,
            sysinfo_cmds::si_system,
            sysinfo_cmds::si_chassis,
            sysinfo_cmds::si_uptime,
            // fs
            fs_cmds::fs_readdir,
            fs_cmds::fs_stat,
            fs_cmds::fs_readfile,
            fs_cmds::fs_writefile,
            fs_cmds::fs_exists,
            fs_cmds::fs_open_external,
            // settings
            settings::get_paths,
            settings::get_settings,
            settings::get_shortcuts,
            settings::write_settings,
            settings::write_shortcuts,
            settings::write_window_state,
            settings::get_window_state,
            settings::get_theme,
            settings::get_keyboard_layout,
            settings::list_themes,
            settings::list_keyboards,
            settings::get_boot_log,
            settings::get_theme_override,
            settings::set_theme_override,
            settings::get_kb_override,
            settings::set_kb_override,
            settings::get_app_version,
            settings::resolve_shell,
            settings::get_username,
            settings::get_displays,
            // native mount
            native_mount::native_mount_set_rect,
            native_mount::native_mount_set_visible,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
