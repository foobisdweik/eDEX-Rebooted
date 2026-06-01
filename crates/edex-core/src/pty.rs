use libproc::proc_pid::{name, pidcwd};
use libproc::processes::{self, ProcFilter};
use portable_pty::{native_pty_system, CommandBuilder, MasterPty, PtySize};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};

pub struct PtyHandle {
    master: Arc<Mutex<Box<dyn MasterPty + Send>>>,
    writer: Arc<Mutex<Box<dyn Write + Send>>>,
    pid: u32,
    child: Arc<Mutex<Box<dyn portable_pty::Child + Send + Sync>>>,
    observer: Arc<dyn PtyOutputObserver>,
}

#[derive(Clone, Default)]
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

    pub fn spawn(
        &self,
        opts: SpawnArgs,
        observer: Arc<dyn PtyOutputObserver>,
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
            // Match _boot.js default: login shell on non-Windows.
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
            let mut n = self.next_id.lock().unwrap();
            let v = *n;
            *n += 1;
            v
        };

        {
            let mut map = self.inner.lock().unwrap();
            map.insert(
                id,
                Arc::new(PtyHandle {
                    master,
                    writer,
                    pid,
                    child,
                    observer: Arc::clone(&observer),
                }),
            );
        }

        if let Ok(metadata) = read_pty_metadata(pid) {
            observer.on_metadata(id, metadata.cwd, metadata.process);
        }

        let inner_for_reader = Arc::clone(&self.inner);
        std::thread::spawn(move || {
            let mut buf = [0u8; 8192];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => observer.on_output(id, buf[..n].to_vec()),
                    Err(_) => break,
                }
            }
            if let Ok(mut map) = inner_for_reader.lock() {
                if let Some(handle) = map.remove(&id) {
                    if let Ok(mut child) = handle.child.lock() {
                        let _ = child.kill();
                        let _ = child.wait();
                    }
                }
            }
            observer.on_exit(id, None);
        });

        Ok(id)
    }

    pub fn write(&self, id: u32, data: &str) -> Result<(), String> {
        let handle = self.handle(id)?;
        let mut writer = handle
            .writer
            .lock()
            .map_err(|_| "pty writer lock poisoned".to_string())?;
        writer.write_all(data.as_bytes()).map_err(|e| e.to_string())
    }

    pub fn resize(&self, id: u32, cols: u16, rows: u16) -> Result<(), String> {
        let handle = self.handle(id)?;
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
    }

    pub fn kill(&self, id: u32) -> Result<(), String> {
        let handle = {
            let mut map = self.inner.lock().unwrap();
            map.remove(&id)
        };
        if let Some(handle) = handle {
            let mut child = handle
                .child
                .lock()
                .map_err(|_| "pty child lock poisoned".to_string())?;
            let _ = child.kill();
            let _ = child.wait();
        }
        Ok(())
    }

    pub fn metadata(&self, id: u32) -> Result<PtyMetadata, String> {
        let handle = self.handle(id)?;
        let metadata = read_pty_metadata(handle.pid)?;
        handle
            .observer
            .on_metadata(id, metadata.cwd.clone(), metadata.process.clone());
        Ok(metadata)
    }

    pub fn cwd(&self, id: u32) -> Result<Option<String>, String> {
        read_pty_cwd(self.pid(id)?)
    }

    pub fn process(&self, id: u32) -> Result<Option<String>, String> {
        read_pty_process(self.pid(id)?)
    }

    fn handle(&self, id: u32) -> Result<Arc<PtyHandle>, String> {
        let map = self
            .inner
            .lock()
            .map_err(|_| "pty manager lock poisoned".to_string())?;
        map.get(&id).cloned().ok_or("pty not found".to_string())
    }

    fn pid(&self, id: u32) -> Result<u32, String> {
        Ok(self.handle(id)?.pid)
    }
}

pub trait PtyOutputObserver: Send + Sync + 'static {
    fn on_output(&self, id: u32, bytes: Vec<u8>);
    fn on_exit(&self, id: u32, status: Option<i32>);
    fn on_metadata(&self, id: u32, cwd: Option<String>, process: Option<String>);
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

#[derive(Debug, Serialize, Clone)]
pub struct PtyMetadata {
    pub cwd: Option<String>,
    pub process: Option<String>,
}

fn read_pty_cwd(pid: u32) -> Result<Option<String>, String> {
    if pid == 0 {
        return Ok(None);
    }
    match pidcwd(pid as i32) {
        Ok(path) => {
            let s = path.to_string_lossy().into_owned();
            Ok(if s.is_empty() { None } else { Some(s) })
        }
        Err(_) => Ok(None),
    }
}

/// Mirrors legacy `ps -o comm= -g {shell_pid} | tail -1` without spawning a shell.
fn read_pty_process(shell_pid: u32) -> Result<Option<String>, String> {
    if shell_pid == 0 {
        return Ok(None);
    }
    let shell_pid_i32 = shell_pid as i32;
    let pgid = unsafe { libc::getpgid(shell_pid_i32) };
    if pgid < 0 {
        return Ok(None);
    }
    let pids = processes::pids_by_type(ProcFilter::ByProgramGroup {
        pgrpid: pgid as u32,
    })
    .map_err(|e| e.to_string())?;
    let mut highest: Option<(i32, String)> = None;
    for pid in pids {
        let pid_i32 = pid as i32;
        if let Ok(comm) = name(pid_i32) {
            let comm = comm.trim().to_string();
            if !comm.is_empty() && highest.as_ref().map(|(p, _)| pid_i32 > *p).unwrap_or(true) {
                highest = Some((pid_i32, comm));
            }
        }
    }
    Ok(highest.map(|(_, comm)| comm))
}

fn read_pty_metadata(pid: u32) -> Result<PtyMetadata, String> {
    Ok(PtyMetadata {
        cwd: read_pty_cwd(pid)?,
        process: read_pty_process(pid)?,
    })
}
