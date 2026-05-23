use include_dir::{include_dir, Dir};
use serde::Serialize;
use serde_json::Value;
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::{AppHandle, State};

// Bundled assets, embedded at compile time so the Rust side does not depend on
// `resource_dir()` plumbing. Mirrored into userData on first boot.
static THEMES_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../src/assets/themes");
static KB_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../src/assets/kb_layouts");
static FONTS_DIR: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../src/assets/fonts");
const BOOT_LOG: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../src/assets/misc/boot_log.txt"
));

#[derive(Default)]
pub struct OverrideState {
    pub theme: Mutex<Option<String>>,
    pub keyboard: Mutex<Option<String>>,
}

#[derive(Serialize, Clone)]
pub struct Paths {
    #[serde(rename = "userData")]
    pub user_data: String,
    #[serde(rename = "settingsFile")]
    pub settings_file: String,
    #[serde(rename = "shortcutsFile")]
    pub shortcuts_file: String,
    #[serde(rename = "lastWindowStateFile")]
    pub last_window_state_file: String,
    #[serde(rename = "themesDir")]
    pub themes_dir: String,
    #[serde(rename = "keyboardsDir")]
    pub keyboards_dir: String,
    #[serde(rename = "fontsDir")]
    pub fonts_dir: String,
}

fn user_data_dir() -> PathBuf {
    dirs::data_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("eDEX-UI")
}

fn paths_internal() -> Paths {
    let base = user_data_dir();
    Paths {
        user_data: base.to_string_lossy().to_string(),
        settings_file: base.join("settings.json").to_string_lossy().to_string(),
        shortcuts_file: base.join("shortcuts.json").to_string_lossy().to_string(),
        last_window_state_file: base
            .join("lastWindowState.json")
            .to_string_lossy()
            .to_string(),
        themes_dir: base.join("themes").to_string_lossy().to_string(),
        keyboards_dir: base.join("keyboards").to_string_lossy().to_string(),
        fonts_dir: base.join("fonts").to_string_lossy().to_string(),
    }
}

fn default_settings() -> Value {
    let base = user_data_dir().to_string_lossy().to_string();
    serde_json::json!({
        "shell": "zsh",
        "shellArgs": "",
        "cwd": base,
        "keyboard": "en-US",
        "theme": "tron",
        "termFontSize": 15,
        "audio": true,
        "audioVolume": 1.0,
        "disableFeedbackAudio": false,
        "clockHours": 24,
        "pingAddr": "1.1.1.1",
        "port": 3000,
        "nointro": false,
        "nocursor": false,
        "forceFullscreen": false,
        "allowWindowed": true,
        "keepGeometry": true,
        "excludeThreadsFromToplist": true,
        "hideDotfiles": false,
        "fsListView": false,
        "experimentalGlobeFeatures": false,
        "experimentalFeatures": false,
        "experimentalNativePanels": false
    })
}

fn default_shortcuts() -> Value {
    serde_json::json!([
        {"type": "app", "trigger": "Ctrl+Shift+C", "action": "COPY", "enabled": true},
        {"type": "app", "trigger": "Ctrl+Shift+V", "action": "PASTE", "enabled": true},
        {"type": "app", "trigger": "Ctrl+Tab", "action": "NEXT_TAB", "enabled": true},
        {"type": "app", "trigger": "Ctrl+Shift+Tab", "action": "PREVIOUS_TAB", "enabled": true},
        {"type": "app", "trigger": "Ctrl+X", "action": "TAB_X", "enabled": true},
        {"type": "app", "trigger": "Ctrl+Shift+S", "action": "SETTINGS", "enabled": true},
        {"type": "app", "trigger": "Ctrl+Shift+K", "action": "SHORTCUTS", "enabled": true},
        {"type": "app", "trigger": "Ctrl+Shift+F", "action": "FUZZY_SEARCH", "enabled": true},
        {"type": "app", "trigger": "Ctrl+Shift+L", "action": "FS_LIST_VIEW", "enabled": true},
        {"type": "app", "trigger": "Ctrl+Shift+H", "action": "FS_DOTFILES", "enabled": true},
        {"type": "app", "trigger": "Ctrl+Shift+P", "action": "KB_PASSMODE", "enabled": true},
        {"type": "app", "trigger": "Ctrl+Shift+I", "action": "DEV_DEBUG", "enabled": false},
        {"type": "app", "trigger": "Ctrl+Shift+F5", "action": "DEV_RELOAD", "enabled": true},
        {"type": "shell", "trigger": "Ctrl+Shift+Alt+Space", "action": "neofetch", "linebreak": true, "enabled": false}
    ])
}

fn default_window_state() -> Value {
    serde_json::json!({ "useFullscreen": false })
}

pub fn ensure_userdata(_app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let p = paths_internal();
    fs::create_dir_all(&p.user_data)?;
    fs::create_dir_all(&p.themes_dir)?;
    fs::create_dir_all(&p.keyboards_dir)?;
    fs::create_dir_all(&p.fonts_dir)?;

    if !PathBuf::from(&p.settings_file).exists() {
        fs::write(
            &p.settings_file,
            serde_json::to_string_pretty(&default_settings())?,
        )?;
    }
    if !PathBuf::from(&p.shortcuts_file).exists() {
        fs::write(
            &p.shortcuts_file,
            serde_json::to_string_pretty(&default_shortcuts())?,
        )?;
    }
    if !PathBuf::from(&p.last_window_state_file).exists() {
        fs::write(
            &p.last_window_state_file,
            serde_json::to_string_pretty(&default_window_state())?,
        )?;
    }

    // Mirror bundled built-ins (overwrites existing — user customizations live
    // in user-added files, which survive). Matches _boot.js behavior.
    for entry in THEMES_DIR.files() {
        if let Some(name) = entry.path().file_name() {
            fs::write(PathBuf::from(&p.themes_dir).join(name), entry.contents())?;
        }
    }
    for entry in KB_DIR.files() {
        if let Some(name) = entry.path().file_name() {
            fs::write(PathBuf::from(&p.keyboards_dir).join(name), entry.contents())?;
        }
    }
    for entry in FONTS_DIR.files() {
        if let Some(name) = entry.path().file_name() {
            fs::write(PathBuf::from(&p.fonts_dir).join(name), entry.contents())?;
        }
    }

    Ok(())
}

#[tauri::command]
pub fn get_paths() -> Paths {
    paths_internal()
}

#[tauri::command]
pub async fn get_settings() -> Result<Value, String> {
    let p = paths_internal();
    let contents = tokio::fs::read_to_string(&p.settings_file)
        .await
        .map_err(|e| e.to_string())?;
    serde_json::from_str(&contents).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn write_settings(contents: Value) -> Result<(), String> {
    let p = paths_internal();
    let s = serde_json::to_string_pretty(&contents).map_err(|e| e.to_string())?;
    tokio::fs::write(&p.settings_file, s)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_shortcuts() -> Result<Value, String> {
    let p = paths_internal();
    let contents = tokio::fs::read_to_string(&p.shortcuts_file)
        .await
        .map_err(|e| e.to_string())?;
    serde_json::from_str(&contents).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn write_shortcuts(contents: Value) -> Result<(), String> {
    let p = paths_internal();
    let s = serde_json::to_string_pretty(&contents).map_err(|e| e.to_string())?;
    tokio::fs::write(&p.shortcuts_file, s)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_window_state() -> Result<Value, String> {
    let p = paths_internal();
    let contents = tokio::fs::read_to_string(&p.last_window_state_file)
        .await
        .map_err(|e| e.to_string())?;
    serde_json::from_str(&contents).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn write_window_state(contents: Value) -> Result<(), String> {
    let p = paths_internal();
    let s = serde_json::to_string_pretty(&contents).map_err(|e| e.to_string())?;
    tokio::fs::write(&p.last_window_state_file, s)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_theme(name: String) -> Result<Value, String> {
    let p = paths_internal();
    let path = PathBuf::from(&p.themes_dir).join(format!("{}.json", name));
    let contents = tokio::fs::read_to_string(&path)
        .await
        .map_err(|e| e.to_string())?;
    serde_json::from_str(&contents).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_keyboard_layout(name: String) -> Result<Value, String> {
    let p = paths_internal();
    let path = PathBuf::from(&p.keyboards_dir).join(format!("{}.json", name));
    let contents = tokio::fs::read_to_string(&path)
        .await
        .map_err(|e| e.to_string())?;
    serde_json::from_str(&contents).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn list_themes() -> Vec<String> {
    list_json_basenames(&paths_internal().themes_dir).await
}

#[tauri::command]
pub async fn list_keyboards() -> Vec<String> {
    list_json_basenames(&paths_internal().keyboards_dir).await
}

async fn list_json_basenames(dir: &str) -> Vec<String> {
    let mut out = Vec::new();
    if let Ok(mut read) = tokio::fs::read_dir(dir).await {
        while let Ok(Some(entry)) = read.next_entry().await {
            let name = entry.file_name().to_string_lossy().to_string();
            if let Some(stripped) = name.strip_suffix(".json") {
                out.push(stripped.to_string());
            }
        }
    }
    out.sort();
    out
}

#[tauri::command]
pub fn get_boot_log() -> String {
    BOOT_LOG.to_string()
}

pub fn keep_geometry_enabled_startup() -> bool {
    let p = paths_internal();
    let Ok(contents) = fs::read_to_string(&p.settings_file) else {
        return true;
    };
    let Ok(json) = serde_json::from_str::<Value>(&contents) else {
        return true;
    };
    json.get("keepGeometry")
        .and_then(Value::as_bool)
        .unwrap_or(true)
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
    tauri::async_runtime::spawn_blocking(move || {
        which::which(&name)
            .map(|p| p.to_string_lossy().to_string())
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub fn get_username() -> String {
    std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .unwrap_or_else(|_| String::from("user"))
}

#[derive(Serialize)]
pub struct DisplayInfo {
    pub index: usize,
    pub primary: bool,
}

#[tauri::command]
pub fn get_displays() -> Vec<DisplayInfo> {
    // Enumerating monitors in Tauri 2 needs an existing Window handle; the
    // settings UI only uses .length for a dropdown, so a single-entry list is
    // adequate for v1. Expand via app.available_monitors() in v0.2.
    vec![DisplayInfo {
        index: 0,
        primary: true,
    }]
}
