use serde::Serialize;
use std::fs;
use std::path::Path;

#[derive(Serialize)]
pub struct DirEntry {
    pub name: String,
    pub category: String,
    pub hidden: bool,
    pub size: u64,
    pub r#type: String,
}

#[tauri::command]
pub fn fs_readdir(path: String) -> Result<Vec<DirEntry>, String> {
    let mut out = Vec::new();
    let read = fs::read_dir(&path).map_err(|e| e.to_string())?;
    for entry in read.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let hidden = name.starts_with('.');
        let (category, size, t) = match entry.metadata() {
            Ok(md) => {
                if md.file_type().is_dir() {
                    ("dir".to_string(), 0u64, "dir".to_string())
                } else if md.file_type().is_symlink() {
                    ("symlink".to_string(), md.len(), "symlink".to_string())
                } else if md.file_type().is_file() {
                    ("file".to_string(), md.len(), "file".to_string())
                } else {
                    ("other".to_string(), md.len(), "other".to_string())
                }
            }
            Err(_) => ("other".to_string(), 0, "other".to_string()),
        };
        out.push(DirEntry {
            name,
            category,
            hidden,
            size,
            r#type: t,
        });
    }
    Ok(out)
}

#[tauri::command]
pub fn fs_stat(path: String) -> Result<serde_json::Value, String> {
    let md = fs::metadata(&path).map_err(|e| e.to_string())?;
    Ok(serde_json::json!({
        "size": md.len(),
        "isDirectory": md.is_dir(),
        "isFile": md.is_file(),
        "isSymlink": md.file_type().is_symlink(),
        "modified": md.modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs())
            .unwrap_or(0)
    }))
}

#[tauri::command]
pub fn fs_readfile(path: String) -> Result<String, String> {
    fs::read_to_string(&path).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn fs_writefile(path: String, content: String) -> Result<(), String> {
    fs::write(&path, content).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn fs_exists(path: String) -> bool {
    Path::new(&path).exists()
}

#[tauri::command]
pub fn fs_open_external(path: String) -> Result<(), String> {
    // macOS `open` opens with the default handler.
    std::process::Command::new("open")
        .arg(&path)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}
