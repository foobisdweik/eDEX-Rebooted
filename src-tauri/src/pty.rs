use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::ipc::Channel;
use tauri::{async_runtime, AppHandle, Emitter, State};

use edex_core::pty::PtyOutputObserver;
pub use edex_core::pty::{PtyManager, PtyMetadata, SpawnArgs};

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

struct TauriPtyObserver {
    app: AppHandle,
    on_data: Mutex<Channel<Vec<u8>>>,
}

impl TauriPtyObserver {
    fn new(app: AppHandle, on_data: Channel<Vec<u8>>) -> Self {
        Self {
            app,
            on_data: Mutex::new(on_data),
        }
    }
}

impl PtyOutputObserver for TauriPtyObserver {
    fn on_output(&self, _id: u32, bytes: Vec<u8>) {
        if let Ok(on_data) = self.on_data.lock() {
            let _ = on_data.send(bytes);
        }
    }

    fn on_exit(&self, id: u32, _status: Option<i32>) {
        let _ = self.app.emit(&format!("pty://{id}/exit"), ());
    }

    fn on_metadata(&self, _id: u32, _cwd: Option<String>, _process: Option<String>) {
        // Current WKWebView clients poll pty_metadata explicitly. The callback
        // exists for the Swift adapter, but the Tauri adapter intentionally
        // keeps the existing JS contract unchanged.
    }
}

#[tauri::command]
pub async fn pty_spawn(
    app: AppHandle,
    state: State<'_, PtyManager>,
    opts: SpawnArgs,
    on_data: Channel<Vec<u8>>,
) -> Result<u32, String> {
    let started = Instant::now();
    let manager = state.inner().clone();
    let observer: Arc<dyn PtyOutputObserver> = Arc::new(TauriPtyObserver::new(app, on_data));
    let result = blocking_pty(move || manager.spawn(opts, observer)).await;
    log_command_latency("pty_spawn", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn pty_write(state: State<'_, PtyManager>, id: u32, data: String) -> Result<(), String> {
    let started = Instant::now();
    let manager = state.inner().clone();
    let result = blocking_pty(move || manager.write(id, &data)).await;
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
    let manager = state.inner().clone();
    let result = blocking_pty(move || manager.resize(id, cols, rows)).await;
    log_command_latency("pty_resize", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn pty_kill(state: State<'_, PtyManager>, id: u32) -> Result<(), String> {
    let started = Instant::now();
    let manager = state.inner().clone();
    let result = blocking_pty(move || manager.kill(id)).await;
    log_command_latency("pty_kill", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn pty_metadata(state: State<'_, PtyManager>, id: u32) -> Result<PtyMetadata, String> {
    let started = Instant::now();
    let manager = state.inner().clone();
    let result = blocking_pty(move || manager.metadata(id)).await;
    log_command_latency("pty_metadata", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn pty_cwd(state: State<'_, PtyManager>, id: u32) -> Result<Option<String>, String> {
    let started = Instant::now();
    let manager = state.inner().clone();
    let result = blocking_pty(move || manager.cwd(id)).await;
    log_command_latency("pty_cwd", started, result.is_ok());
    result
}

#[tauri::command]
pub async fn pty_process(state: State<'_, PtyManager>, id: u32) -> Result<Option<String>, String> {
    let started = Instant::now();
    let manager = state.inner().clone();
    let result = blocking_pty(move || manager.process(id)).await;
    log_command_latency("pty_process", started, result.is_ok());
    result
}
