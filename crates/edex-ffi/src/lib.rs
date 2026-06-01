use edex_core::pty::{PtyManager, PtyOutputObserver, SpawnArgs};
use edex_core::sysinfo::SysinfoService;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum EdexError {
    #[error("{message}")]
    Core { message: String },
}

impl From<String> for EdexError {
    fn from(message: String) -> Self {
        Self::Core { message }
    }
}

impl From<serde_json::Error> for EdexError {
    fn from(err: serde_json::Error) -> Self {
        Self::Core {
            message: err.to_string(),
        }
    }
}

impl From<std::io::Error> for EdexError {
    fn from(err: std::io::Error) -> Self {
        Self::Core {
            message: err.to_string(),
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiPaths {
    pub user_data: String,
    pub settings_file: String,
    pub shortcuts_file: String,
    pub last_window_state_file: String,
    pub themes_dir: String,
    pub keyboards_dir: String,
    pub fonts_dir: String,
}

impl From<edex_core::settings::Paths> for FfiPaths {
    fn from(paths: edex_core::settings::Paths) -> Self {
        Self {
            user_data: paths.user_data,
            settings_file: paths.settings_file,
            shortcuts_file: paths.shortcuts_file,
            last_window_state_file: paths.last_window_state_file,
            themes_dir: paths.themes_dir,
            keyboards_dir: paths.keyboards_dir,
            fonts_dir: paths.fonts_dir,
        }
    }
}

#[derive(Debug, uniffi::Record)]
pub struct FfiPtySpawnOptions {
    pub shell: String,
    pub args: Vec<String>,
    pub cwd: String,
    pub env_keys: Vec<String>,
    pub env_values: Vec<String>,
    pub cols: u16,
    pub rows: u16,
}

#[derive(Debug, uniffi::Record)]
pub struct FfiPtyMetadata {
    pub cwd: Option<String>,
    pub process: Option<String>,
}

#[uniffi::export(callback_interface)]
pub trait PtyOutputSink: Send + Sync {
    fn on_output(&self, id: u32, bytes: Vec<u8>);
    fn on_exit(&self, id: u32, status: Option<i32>);
    fn on_metadata(&self, id: u32, cwd: Option<String>, process: Option<String>);
}

struct FfiPtyObserver {
    sink: Box<dyn PtyOutputSink>,
}

impl PtyOutputObserver for FfiPtyObserver {
    fn on_output(&self, id: u32, bytes: Vec<u8>) {
        self.sink.on_output(id, bytes);
    }

    fn on_exit(&self, id: u32, status: Option<i32>) {
        self.sink.on_exit(id, status);
    }

    fn on_metadata(&self, id: u32, cwd: Option<String>, process: Option<String>) {
        self.sink.on_metadata(id, cwd, process);
    }
}

#[derive(uniffi::Object)]
pub struct EdexCore {
    sysinfo: SysinfoService,
    pty: PtyManager,
}

#[uniffi::export]
impl EdexCore {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            sysinfo: SysinfoService::new(),
            pty: PtyManager::new(),
        })
    }

    pub fn paths(&self) -> FfiPaths {
        edex_core::settings::paths().into()
    }

    pub fn ensure_userdata(&self) -> Result<(), EdexError> {
        edex_core::settings::ensure_userdata().map_err(|err| EdexError::Core {
            message: err.to_string(),
        })
    }

    pub fn load_settings_json(&self) -> Result<String, EdexError> {
        let path = edex_core::settings::paths().settings_file;
        fs::read_to_string(path).map_err(EdexError::from)
    }

    pub fn load_theme_json(&self, name: String) -> Result<String, EdexError> {
        let paths = edex_core::settings::paths();
        let path = PathBuf::from(paths.themes_dir).join(format!("{name}.json"));
        fs::read_to_string(path).map_err(EdexError::from)
    }

    pub fn load_keyboard_json(&self, name: String) -> Result<String, EdexError> {
        let paths = edex_core::settings::paths();
        let path = PathBuf::from(paths.keyboards_dir).join(format!("{name}.json"));
        fs::read_to_string(path).map_err(EdexError::from)
    }

    pub fn sysinfo_snapshot_json(&self) -> Result<String, EdexError> {
        let snapshot = self.sysinfo.panel_snapshot(true, 5, true)?;
        serde_json::to_string(&snapshot).map_err(EdexError::from)
    }

    pub fn spawn_pty(
        &self,
        opts: FfiPtySpawnOptions,
        sink: Box<dyn PtyOutputSink>,
    ) -> Result<u32, EdexError> {
        if opts.env_keys.len() != opts.env_values.len() {
            return Err(EdexError::Core {
                message: "env_keys and env_values must have the same length".to_string(),
            });
        }

        let env = opts
            .env_keys
            .into_iter()
            .zip(opts.env_values)
            .collect::<std::collections::HashMap<_, _>>();
        let args = SpawnArgs {
            shell: opts.shell,
            args: opts.args,
            cwd: opts.cwd,
            env,
            cols: opts.cols,
            rows: opts.rows,
        };
        let observer: Arc<dyn PtyOutputObserver> = Arc::new(FfiPtyObserver { sink });
        self.pty.spawn(args, observer).map_err(EdexError::from)
    }

    pub fn write_pty(&self, id: u32, data: String) -> Result<(), EdexError> {
        self.pty.write(id, &data).map_err(EdexError::from)
    }

    pub fn resize_pty(&self, id: u32, cols: u16, rows: u16) -> Result<(), EdexError> {
        self.pty.resize(id, cols, rows).map_err(EdexError::from)
    }

    pub fn kill_pty(&self, id: u32) -> Result<(), EdexError> {
        self.pty.kill(id).map_err(EdexError::from)
    }

    pub fn pty_metadata(&self, id: u32) -> Result<FfiPtyMetadata, EdexError> {
        let metadata = self.pty.metadata(id)?;
        Ok(FfiPtyMetadata {
            cwd: metadata.cwd,
            process: metadata.process,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct NoopSink;

    impl PtyOutputSink for NoopSink {
        fn on_output(&self, _id: u32, _bytes: Vec<u8>) {}
        fn on_exit(&self, _id: u32, _status: Option<i32>) {}
        fn on_metadata(&self, _id: u32, _cwd: Option<String>, _process: Option<String>) {}
    }

    #[test]
    fn spawn_pty_rejects_mismatched_env_vectors() {
        let core = EdexCore::new();
        let result = core.spawn_pty(
            FfiPtySpawnOptions {
                shell: "/bin/sh".to_string(),
                args: vec!["-c".to_string(), "sleep 1".to_string()],
                cwd: "/".to_string(),
                env_keys: vec!["ONE".to_string()],
                env_values: vec![],
                cols: 80,
                rows: 24,
            },
            Box::new(NoopSink),
        );

        if let Ok(id) = result {
            let _ = core.kill_pty(id);
            panic!("mismatched env vectors should be rejected before spawning a PTY");
        }
        assert!(matches!(
            result,
            Err(EdexError::Core { message })
                if message == "env_keys and env_values must have the same length"
        ));
    }
}
