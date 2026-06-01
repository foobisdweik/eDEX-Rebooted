use tauri::async_runtime;

pub use edex_core::fs::DirEntry;

async fn blocking_fs<T, F>(f: F) -> Result<T, String>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, String> + Send + 'static,
{
    async_runtime::spawn_blocking(f)
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn fs_readdir(path: String) -> Result<Vec<DirEntry>, String> {
    blocking_fs(move || edex_core::fs::readdir(&path)).await
}

#[tauri::command]
pub async fn fs_stat(path: String) -> Result<serde_json::Value, String> {
    blocking_fs(move || edex_core::fs::stat(&path)).await
}

#[tauri::command]
pub async fn fs_readfile(path: String) -> Result<String, String> {
    blocking_fs(move || edex_core::fs::readfile(&path)).await
}

#[tauri::command]
pub async fn fs_writefile(path: String, content: String) -> Result<(), String> {
    blocking_fs(move || edex_core::fs::writefile(&path, &content)).await
}

#[tauri::command]
pub async fn fs_exists(path: String) -> Result<bool, String> {
    blocking_fs(move || Ok(edex_core::fs::exists(&path))).await
}

#[tauri::command]
pub async fn fs_open_external(path: String) -> Result<(), String> {
    blocking_fs(move || edex_core::fs::open_external(&path)).await
}
