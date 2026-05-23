use base64::Engine;
use portable_pty::{native_pty_system, CommandBuilder, MasterPty, PtySize};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{async_runtime, AppHandle, Emitter, State};

pub struct PtyHandle {
    master: Arc<Mutex<Box<dyn MasterPty + Send>>>,
    writer: Arc<Mutex<Box<dyn Write + Send>>>,
    pid: u32,
    child: Arc<Mutex<Box<dyn portable_pty::Child + Send + Sync>>>,
}

pub struct PtyManager {
    inner: Arc<Mutex<HashMap<u32, Arc<PtyHandle>>>>,
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

fn log_command_latency(name: &str, started: Instant, ok: bool) {
    let elapsed = started.elapsed();
    if elapsed >= Duration::from_millis(20) {
        eprintln!(
            "[perf][pty] {name} {}ms status={}",
            elapsed.as_millis(),
            if ok { "ok" } else { "err" }
        );
    }
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
pub async fn pty_spawn(
    app: AppHandle,
    state: State<'_, PtyManager>,
    opts: SpawnArgs,
) -> Result<u32, String> {
    let started = Instant::now();
    let inner = Arc::clone(&state.inner);
    let next_id = Arc::clone(&state.next_id);
    let result = blocking_pty(move || {
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
        let writer = Arc::new(Mutex::new(
            pair.master.take_writer().map_err(|e| e.to_string())?,
        ));
        let mut reader = pair.master.try_clone_reader().map_err(|e| e.to_string())?;
        let master = Arc::new(Mutex::new(pair.master));
        let child = Arc::new(Mutex::new(child));

        let id = {
            let mut n = next_id.lock().unwrap();
            let v = *n;
            *n += 1;
            v
        };

        {
            let mut map = inner.lock().unwrap();
            map.insert(
                id,
                Arc::new(PtyHandle {
                    master,
                    writer,
                    pid,
                    child,
                }),
            );
        }

        let app_for_reader = app.clone();
        let channel = format!("pty://{}/data", id);
        std::thread::spawn(move || {
            let mut buf = [0u8; 8192];
            let mut encoded = String::with_capacity(16 * 1024);
            loop {
                match reader.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        encoded.clear();
                        base64::engine::general_purpose::STANDARD
                            .encode_string(&buf[..n], &mut encoded);
                        let _ = app_for_reader.emit(&channel, encoded.clone());
                    }
                    Err(_) => break,
                }
            }
            let _ = app_for_reader.emit(&format!("pty://{}/exit", id), ());
        });

        Ok(id)
    })
    .await;
    log_command_latency("pty_spawn", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn pty_write(state: State<'_, PtyManager>, id: u32, data: String) -> Result<(), String> {
    let started = Instant::now();
    let inner = Arc::clone(&state.inner);
    let result = blocking_pty(move || {
        let handle = {
            let map = inner.lock().unwrap();
            map.get(&id).cloned().ok_or("pty not found")?
        };
        let mut writer = handle
            .writer
            .lock()
            .map_err(|_| "pty writer lock poisoned".to_string())?;
        writer.write_all(data.as_bytes()).map_err(|e| e.to_string())
    })
    .await;
    log_command_latency("pty_write", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn pty_resize(
    state: State<'_, PtyManager>,
    id: u32,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    let started = Instant::now();
    let inner = Arc::clone(&state.inner);
    let result = blocking_pty(move || {
        let handle = {
            let map = inner.lock().unwrap();
            map.get(&id).cloned().ok_or("pty not found")?
        };
        let master = handle
            .master
            .lock()
            .map_err(|_| "pty master lock poisoned".to_string())?;
        master
            .resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| e.to_string())
    })
    .await;
    log_command_latency("pty_resize", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn pty_kill(state: State<'_, PtyManager>, id: u32) -> Result<(), String> {
    let started = Instant::now();
    let inner = Arc::clone(&state.inner);
    let result = blocking_pty(move || {
        let handle = {
            let mut map = inner.lock().unwrap();
            map.remove(&id)
        };
        if let Some(handle) = handle {
            let _ = handle
                .child
                .lock()
                .map_err(|_| "pty child lock poisoned".to_string())?
                .kill();
        }
        Ok(())
    })
    .await;
    log_command_latency("pty_kill", started, result.is_ok());
    result
}

#[derive(Debug, Serialize)]
pub struct PtyMetadata {
    pub cwd: Option<String>,
    pub process: Option<String>,
}

fn read_pty_metadata(pid: u32) -> Result<PtyMetadata, String> {
    let cwd_out = std::process::Command::new("sh")
        .arg("-c")
        .arg(format!(
            "lsof -a -d cwd -p {} | tail -1 | awk '{{ for (i=9; i<=NF; i++) printf \"%s \", $i }}'",
            pid
        ))
        .output()
        .map_err(|e| e.to_string())?;
    let cwd = {
        let s = String::from_utf8_lossy(&cwd_out.stdout).trim().to_string();
        if s.is_empty() {
            None
        } else {
            Some(s)
        }
    };

    let proc_out = std::process::Command::new("sh")
        .arg("-c")
        .arg(format!("ps -o comm= -g {} 2>/dev/null | tail -1", pid))
        .output()
        .map_err(|e| e.to_string())?;
    let process = {
        let s = String::from_utf8_lossy(&proc_out.stdout).trim().to_string();
        if s.is_empty() {
            None
        } else {
            Some(s)
        }
    };

    Ok(PtyMetadata { cwd, process })
}

#[tauri::command]
pub async fn pty_metadata(state: State<'_, PtyManager>, id: u32) -> Result<PtyMetadata, String> {
    let started = Instant::now();
    let inner = Arc::clone(&state.inner);
    let result = blocking_pty(move || {
        let pid = {
            let map = inner
                .lock()
                .map_err(|_| "pty manager lock poisoned".to_string())?;
            map.get(&id).map(|h| h.pid).ok_or("pty not found")?
        };
        read_pty_metadata(pid)
    })
    .await;
    log_command_latency("pty_metadata", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn pty_cwd(state: State<'_, PtyManager>, id: u32) -> Result<Option<String>, String> {
    let started = Instant::now();
    let result = pty_metadata(state, id).await.map(|m| m.cwd);
    log_command_latency("pty_cwd", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn pty_process(state: State<'_, PtyManager>, id: u32) -> Result<Option<String>, String> {
    let started = Instant::now();
    let result = pty_metadata(state, id).await.map(|m| m.process);
    log_command_latency("pty_process", started, result.is_ok());
    result
}
