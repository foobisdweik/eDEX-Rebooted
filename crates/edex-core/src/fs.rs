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

pub fn readdir(path: &str) -> Result<Vec<DirEntry>, String> {
    let mut out = Vec::new();
    let read = fs::read_dir(path).map_err(|e| e.to_string())?;
    for entry in read.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let hidden = name.starts_with('.');
        let (category, size, t) = match entry.file_type() {
            Ok(ft) => {
                if ft.is_dir() {
                    ("dir".to_string(), 0u64, "dir".to_string())
                } else if ft.is_symlink() {
                    let len = fs::symlink_metadata(entry.path())
                        .map(|metadata| metadata.len())
                        .unwrap_or(0);
                    ("symlink".to_string(), len, "symlink".to_string())
                } else if ft.is_file() {
                    let len = entry.metadata().map(|metadata| metadata.len()).unwrap_or(0);
                    ("file".to_string(), len, "file".to_string())
                } else {
                    ("other".to_string(), 0, "other".to_string())
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

pub fn stat(path: &str) -> Result<serde_json::Value, String> {
    let md = fs::symlink_metadata(path).map_err(|e| e.to_string())?;
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

pub fn readfile(path: &str) -> Result<String, String> {
    fs::read_to_string(path).map_err(|e| e.to_string())
}

pub fn writefile(path: &str, content: &str) -> Result<(), String> {
    fs::write(path, content).map_err(|e| e.to_string())
}

pub fn exists(path: &str) -> bool {
    Path::new(path).exists()
}

pub fn open_external(path: &str) -> Result<(), String> {
    std::process::Command::new("open")
        .arg(path)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[cfg(unix)]
    fn temp_dir(name: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "edex-core-fs-{name}-{}-{nanos}",
            std::process::id()
        ));
        fs::create_dir(&dir).unwrap();
        dir
    }

    #[test]
    #[cfg(unix)]
    fn readdir_reports_broken_symlink_as_symlink() {
        let dir = temp_dir("readdir-symlink");
        let link = dir.join("broken-link");
        std::os::unix::fs::symlink(dir.join("missing-target"), &link).unwrap();

        let entries = readdir(dir.to_str().unwrap()).unwrap();
        let entry = entries
            .iter()
            .find(|entry| entry.name == "broken-link")
            .unwrap();
        assert_eq!(entry.category, "symlink");
        assert_eq!(entry.r#type, "symlink");

        fs::remove_file(&link).unwrap();
        fs::remove_dir(&dir).unwrap();
    }

    #[test]
    #[cfg(unix)]
    fn stat_reports_symlink_path_as_symlink() {
        let dir = temp_dir("stat-symlink");
        let target = dir.join("target");
        let link = dir.join("target-link");
        fs::write(&target, "target").unwrap();
        std::os::unix::fs::symlink(&target, &link).unwrap();

        let value = stat(link.to_str().unwrap()).unwrap();
        assert_eq!(value["isSymlink"], true);
        assert_eq!(value["isFile"], false);

        fs::remove_file(&link).unwrap();
        fs::remove_file(&target).unwrap();
        fs::remove_dir(&dir).unwrap();
    }
}
