use serde_json::Value;
use std::sync::Mutex;
use tauri::{async_runtime, AppHandle, State};

pub use edex_core::settings::{DisplayInfo, Paths};

#[derive(Default)]
pub struct OverrideState {
    pub theme: Mutex<Option<String>>,
    pub keyboard: Mutex<Option<String>>,
}

pub fn ensure_userdata(_app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    edex_core::settings::ensure_userdata()
}

#[tauri::command]
pub fn get_paths() -> Paths {
    edex_core::settings::paths()
}

#[tauri::command]
pub async fn get_settings() -> Result<Value, String> {
    edex_core::settings::get_settings().await
}

#[tauri::command]
pub async fn write_settings(contents: Value) -> Result<(), String> {
    edex_core::settings::write_settings(contents).await
}

#[tauri::command]
pub async fn get_shortcuts() -> Result<Value, String> {
    edex_core::settings::get_shortcuts().await
}

#[tauri::command]
pub async fn write_shortcuts(contents: Value) -> Result<(), String> {
    edex_core::settings::write_shortcuts(contents).await
}

#[tauri::command]
pub async fn get_window_state() -> Result<Value, String> {
    edex_core::settings::get_window_state().await
}

#[tauri::command]
pub async fn write_window_state(contents: Value) -> Result<(), String> {
    edex_core::settings::write_window_state(contents).await
}

#[tauri::command]
pub async fn get_theme(name: String) -> Result<Value, String> {
    edex_core::settings::get_theme(&name).await
}

#[tauri::command]
pub async fn get_keyboard_layout(name: String) -> Result<Value, String> {
    edex_core::settings::get_keyboard_layout(&name).await
}

#[tauri::command]
pub async fn list_themes() -> Vec<String> {
    edex_core::settings::list_themes().await
}

#[tauri::command]
pub async fn list_keyboards() -> Vec<String> {
    edex_core::settings::list_keyboards().await
}

#[tauri::command]
pub fn get_boot_log() -> String {
    edex_core::settings::get_boot_log()
}

pub fn keep_geometry_enabled_startup() -> bool {
    edex_core::settings::keep_geometry_enabled_startup()
}

#[tauri::command]
pub fn get_theme_override(state: State<'_, OverrideState>) -> Option<String> {
    state.theme.lock().unwrap().clone()
}

#[tauri::command]
pub fn set_theme_override(state: State<'_, OverrideState>, theme: Option<String>) {
    *state.theme.lock().unwrap() = theme;
}

#[tauri::command]
pub fn get_kb_override(state: State<'_, OverrideState>) -> Option<String> {
    state.keyboard.lock().unwrap().clone()
}

#[tauri::command]
pub fn set_kb_override(state: State<'_, OverrideState>, layout: Option<String>) {
    *state.keyboard.lock().unwrap() = layout;
}

#[tauri::command]
pub fn get_app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

#[tauri::command]
pub async fn resolve_shell(name: String) -> Result<String, String> {
    async_runtime::spawn_blocking(move || edex_core::settings::resolve_shell(&name))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub fn get_username() -> String {
    edex_core::settings::get_username()
}

#[tauri::command]
pub fn get_displays() -> Vec<DisplayInfo> {
    // Enumerating monitors in Tauri 2 needs an existing Window handle; the
    // settings UI only uses .length for a dropdown, so a single-entry list is
    // adequate for v1. Expand via app.available_monitors() in v0.2.
    edex_core::settings::get_displays()
}
