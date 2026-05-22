use base64::Engine;
use portable_pty::{native_pty_system, CommandBuilder, MasterPty, PtySize};
use serde::Deserialize;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};
use tauri::{async_runtime, AppHandle, Emitter, State};

pub struct PtyHandle {
    master: Box<dyn MasterPty + Send>,
    writer: Box<dyn Write + Send>,
    pid: u32,
    _child: Box<dyn portable_pty::Child + Send + Sync>,
}

pub struct PtyManager {
    inner: Arc<Mutex<HashMap<u32, PtyHandle>>>,
    next_id: Arc<Mutex<u32>>,
}

impl PtyManager {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(HashMap::new())),
            next_id: Arc::new(Mutex::new(1)),
        }
    }
}

async fn blocking_pty<T, F>(f: F) -> Result<T, String>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, String> + Send + 'static,
{
    async_runtime::spawn_blocking(f)
        .await
        .map_err(|e| e.to_string())?
}

#[derive(Debug, Deserialize)]
pub struct SpawnArgs {
    pub shell: String,
    #[serde(default)]
    pub args: Vec<String>,
    pub cwd: String,
    #[serde(default)]
    pub env: HashMap<String, String>,
    pub cols: u16,
    pub rows: u16,
}

#[tauri::command]
pub fn pty_spawn(
    app: AppHandle,
    state: State<'_, PtyManager>,
    opts: SpawnArgs,
) -> Result<u32, String> {
    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(PtySize {
            rows: opts.rows,
            cols: opts.cols,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|e| e.to_string())?;

    let mut cmd = CommandBuilder::new(&opts.shell);
    if opts.args.is_empty() {
        // Match _boot.js default: login shell on non-Windows
        cmd.arg("--login");
    } else {
        for a in &opts.args {
            cmd.arg(a);
        }
    }
    cmd.cwd(&opts.cwd);
    for (k, v) in &opts.env {
        cmd.env(k, v);
    }

    let child = pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;
    let pid = child.process_id().unwrap_or(0);
    let writer = pair.master.take_writer().map_err(|e| e.to_string())?;
    let mut reader = pair.master.try_clone_reader().map_err(|e| e.to_string())?;

    let id = {
        let mut n = state.next_id.lock().unwrap();
        let v = *n;
        *n += 1;
        v
    };

    {
        let mut map = state.inner.lock().unwrap();
        map.insert(
            id,
            PtyHandle {
                master: pair.master,
                writer,
                pid,
                _child: child,
            },
        );
    }

    let app_for_reader = app.clone();
    let channel = format!("pty://{}/data", id);
    std::thread::spawn(move || {
        let mut buf = [0u8; 8192];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    let encoded = base64::engine::general_purpose::STANDARD.encode(&buf[..n]);
                    let _ = app_for_reader.emit(&channel, encoded);
                }
                Err(_) => break,
            }
        }
        let _ = app_for_reader.emit(&format!("pty://{}/exit", id), ());
    });

    Ok(id)
}

#[tauri::command]
pub fn pty_write(state: State<'_, PtyManager>, id: u32, data: String) -> Result<(), String> {
    let mut map = state.inner.lock().unwrap();
    let handle = map.get_mut(&id).ok_or("pty not found")?;
    handle
        .writer
        .write_all(data.as_bytes())
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn pty_resize(
    state: State<'_, PtyManager>,
    id: u32,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    let map = state.inner.lock().unwrap();
    let handle = map.get(&id).ok_or("pty not found")?;
    handle
        .master
        .resize(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn pty_kill(state: State<'_, PtyManager>, id: u32) -> Result<(), String> {
    let mut map = state.inner.lock().unwrap();
    map.remove(&id);
    Ok(())
}

#[tauri::command]
pub async fn pty_cwd(state: State<'_, PtyManager>, id: u32) -> Result<Option<String>, String> {
    let inner = Arc::clone(&state.inner);
    blocking_pty(move || {
        let pid = {
            let map = inner
                .lock()
                .map_err(|_| "pty manager lock poisoned".to_string())?;
            map.get(&id).map(|h| h.pid).ok_or("pty not found")?
        };
        // Lifted from terminal.class.js:332 — macOS only.
        let out = std::process::Command::new("sh")
            .arg("-c")
            .arg(format!(
                "lsof -a -d cwd -p {} | tail -1 | awk '{{ for (i=9; i<=NF; i++) printf \"%s \", $i }}'",
                pid
            ))
            .output()
            .map_err(|e| e.to_string())?;
        let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if s.is_empty() {
            Ok(None)
        } else {
            Ok(Some(s))
        }
    })
    .await
}

#[tauri::command]
pub async fn pty_process(state: State<'_, PtyManager>, id: u32) -> Result<Option<String>, String> {
    let inner = Arc::clone(&state.inner);
    blocking_pty(move || {
        let pid = {
            let map = inner
                .lock()
                .map_err(|_| "pty manager lock poisoned".to_string())?;
            map.get(&id).map(|h| h.pid).ok_or("pty not found")?
        };
        // Lifted from terminal.class.js:351
        let out = std::process::Command::new("sh")
            .arg("-c")
            .arg(format!("ps -o comm= -g {} 2>/dev/null | tail -1", pid))
            .output()
            .map_err(|e| e.to_string())?;
        let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if s.is_empty() {
            Ok(None)
        } else {
            Ok(Some(s))
        }
    })
    .await
}
