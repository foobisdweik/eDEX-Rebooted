# eDEX-UI → Tauri/Rust migration (time-optimized)

## Context

The repo is the security-patched eDEX-UI fork on Electron 37 / Node 20 / `@xterm/*` 5.5.0. The destination is a native `aarch64-apple-darwin` Tauri + Rust app — the Electron model is being replaced wholesale, and the macOS x64-under-Rosetta build is the catalyst.

The original draft (Phases 1–4, summarized in `CLAUDE.md`) is structurally correct but pays a large time tax in two places:

1. **It deletes the Node-using visual classes** (`sysinfo`, `cpuinfo`, `ramwatcher`, `netstat`, `toplist`, `conninfo`, `hardwareInspector`, `filesystem`) and tells us to re-implement what they did. But the only Node coupling in those files is `window.si.<method>()` and a handful of `fs`/`shell.openPath` calls. `window.si` is already a Proxy (`src/_renderer.js:178`) — a clean RPC seam. Swapping its backend is hours of work; rewriting the modules is weeks.
2. **It sequences Phase 2 (destructive deletes) before Phase 3 (Tauri scaffold)**, requiring "confirm before deletion" gates and a "keep Electron working" ground rule. We instead scaffold Tauri on a fresh branch, build the new app to feature-parity beside the old code, then delete in one final commit once parity is verified. No dual-build maintenance burden, no destructive intermediate state.

Net effect: fewer rewrites, no parallel-build tax, narrower v1 scope (defer globe/docReader/updateChecker/conninfo to v0.2). Single-target (Apple Silicon, macOS only) lets us delete all `process.platform === "win32"` / Linux conditionals as we touch each file.

## Shape of the change

```
BEFORE (current)                          AFTER (target)
─────────────────                         ─────────────
_boot.js (Electron main)                  src-tauri/src/main.rs
  ├─ Terminal({role:"server"})              ├─ #[command] pty_spawn/write/resize/kill
  │   ├─ node-pty.spawn                     │     (portable-pty + tokio task per pty)
  │   └─ ws.Server (verifyClient)           │     emits  pty://{id}/data  events
  ├─ _multithread.js                        ├─ #[command] si_* (one per window.si call)
  │   └─ cluster worker pool x 7            │     (sysinfo crate — single-threaded is fine)
  │       └─ systeminformation              ├─ #[command] fs_readdir/readfile/exists
  ├─ ipc: ttyspawn, theme/kb override       ├─ #[command] get/set_theme_override, kb_override
  └─ userData mirror of assets              └─ asset mirror on setup() (dirs::data_dir)
                  ↕ ipcRenderer/Main                       ↕ invoke() + listen()
ui.html + _renderer.js (Electron renderer)  ui.html + renderer.js (WKWebView)
  ├─ window.term[0..4] (xterm+WebSocket)     ├─ window.term[0..4] (xterm + Tauri events)  ← thin patch
  ├─ window.si Proxy → ipc → workers         ├─ window.si Proxy → invoke()                 ← shim swap
  ├─ window.mods.* (visual modules)          ├─ window.mods.* — UNCHANGED                  ← biggest savings
  └─ FilesystemDisplay (Node fs)             └─ FilesystemDisplay (fs_* invokes)           ← ~10 line patch
```

The `window.si` Proxy stays. The visual modules don't know whether their data comes from Electron IPC or Tauri invoke. That's the load-bearing simplification.

## Execution order

All work happens on a new branch `tauri-migration`. The `main` branch keeps the Electron build untouched as a safety net until the final delete commit.

### Step 1 — Tauri scaffold (in repo root, alongside `src/`)

- `cargo tauri init` → creates `src-tauri/`. Point `tauri.conf.json` `frontendDist` at `src/` (so existing `ui.html` and `assets/` are served unmodified). Set `productName: "eDEX-UI"`, `identifier: "dev.edex.ui"`, window `width/height` matching primary display + `fullscreen: true`, `decorations: false`.
- `src-tauri/Cargo.toml` deps: `tauri = { version = "2", features = ["macos-private-api"] }`, `portable-pty = "0.8"`, `sysinfo = "0.32"`, `battery = "0.7"` (sysinfo has no battery on macOS), `tokio = { version = "1", features = ["full"] }`, `serde`, `serde_json`, `dirs = "5"`, `tauri-plugin-shell = "2"` (for `shell.openPath` parity).
- Target only `aarch64-apple-darwin` — no Windows/Linux build config.

### Step 2 — Rust commands (`src-tauri/src/`)

Layout: `main.rs` + `pty.rs` + `sysinfo_cmds.rs` + `fs_cmds.rs` + `settings.rs`.

- **`pty.rs`** — `PtyManager` holds `HashMap<u32, PtyHandle>` behind a `Mutex`. Commands:
  - `pty_spawn(shell, args, cwd, env, cols, rows) -> u32` (returns id); spawns `portable-pty::native_pty_system()`, takes `master.try_clone_reader()` into a `tokio::spawn` task that reads and `app_handle.emit_to(window, &format!("pty://{id}/data"), bytes_as_b64)`.
  - `pty_write(id, data)`, `pty_resize(id, cols, rows)`, `pty_kill(id)`.
  - `pty_cwd(id) -> Option<String>` via `lsof -a -d cwd -p <pid>` (existing logic, lifted from `terminal.class.js:332`); `pty_process(id) -> Option<String>` via `ps -o comm -p <pid>`. macOS-only — no OS switch.
  - Replaces `terminal.class.js` role:"server" block entirely; the `verifyClient` origin gate is gone because there is no WebSocket — invoke is process-local.
- **`sysinfo_cmds.rs`** — one `#[command]` per `window.si.<x>()` call site (see grep results: `cpu`, `currentLoad`, `cpuTemperature`, `processes`, `mem`, `battery`, `networkInterfaces`, `networkStats`, `fsSize`, `blockDevices`, `system`, `chassis`). Each returns a `serde_json::Value` matching the shape `systeminformation` returned — these are tiny adapter functions:
  - `cpu` → `System::cpus()[0].brand()` + cores count → `{manufacturer, brand, cores, speed, speedMax}`.
  - `currentLoad` → `sys.refresh_cpu(); { cpus: cpus.iter().map(|c| {load: c.cpu_usage()}) }`.
  - `cpuTemperature` → `Components::new_with_refreshed_list()` → max temp.
  - `mem` → `sys.refresh_memory(); {total, free, used, active, available}`.
  - `processes` → `sys.refresh_processes(); {all: processes.len(), list: [{pid, name, cpu, mem}]}`.
  - `battery` → `battery::Manager` → `{hasBattery, isCharging, acConnected, percent}`.
  - `networkInterfaces` / `networkStats` → `sys.networks()` rx/tx deltas; cache previous tick.
  - `blockDevices` / `fsSize` → `sys.disks()` → mount/label/total/used.
  - `system` / `chassis` → `System::name()/os_version()/host_name()/kernel_version()`.
  - **Defer:** `networkConnections` (globe-only) — return `[]` for v1.
- **`fs_cmds.rs`** — `fs_readdir(path) -> Vec<{name, type, size, hidden}>`, `fs_stat(path)`, `fs_readfile(path) -> String`, `fs_writefile(path, content)`, `fs_open_external(path)` (shells out to `open`). Replaces direct Node `fs.*` calls in `filesystem.class.js`.
- **`settings.rs`** — port `_boot.js:46-167`: paths via `dirs::data_dir().join("eDEX-UI")`, mirror `src/assets/{themes,kb_layouts,fonts}/*` into userData on `setup()`, write defaults for `settings.json`/`shortcuts.json`/`lastWindowState.json`. Theme/kb override state stays in a `Mutex<Option<String>>` in `App::manage()`. Commands: `get_settings`, `get_shortcuts`, `get_theme_override`, `set_theme_override`, `get_kb_override`, `set_kb_override`, `write_settings`, `write_window_state`.

### Step 3 — Frontend rewire (in `src/`)

This is the only place we modify existing JS. Create `src/renderer.js` as the replacement for `_renderer.js`.

- **`src/renderer.js`** — copy `_renderer.js` verbatim, then surgically swap:
  - Replace `const electron = require("electron"); const remote = require("@electron/remote"); const ipc = electron.ipcRenderer;` with `const { invoke } = window.__TAURI__.core; const { listen, emit } = window.__TAURI__.event;`.
  - `remote.app.getPath("userData")` → injected by `settings.rs::get_settings` into a `window.__USER_DATA__` global at boot.
  - `ipc.send("getThemeOverride")` / `ipc.once(...)` → `await invoke("get_theme_override")`.
  - `electron.remote.getCurrentWindow()` / `setFullScreen` → `window.__TAURI__.window.getCurrentWindow()` + `setFullscreen`.
  - `globalShortcut.register(...)` → `tauri-plugin-global-shortcut` (already a Tauri plugin); same shortcut strings work.
  - `electron.remote.app.relaunch()/quit()` → `process.relaunch()/exit()` from `@tauri-apps/plugin-process`.
  - Strip `initSystemInformationProxy()` ipc round-trip; replace with simpler shim (see next bullet).
- **`window.si` shim** — replaces the `nanoid`/`ipc.once` round-trip in `_renderer.js:178-201`:
  ```js
  window.si = new Proxy({}, {
    get: (_, prop) => (...args) => invoke(`si_${prop}`, { args })
  });
  ```
  Rust side names commands `si_cpu`, `si_current_load`, etc. (camelCase → snake_case mapping done in the shim). All `cpuinfo.class.js`, `ramwatcher.class.js`, `sysinfo.class.js`, `toplist.class.js`, `hardwareInspector.class.js`, `netstat.class.js` keep working unchanged.
- **`terminal.class.js`** — keep the entire `role: "client"` block. Two surgical edits in the client branch:
  - Replace `this.socket = new WebSocket(...)` + `AttachAddon(this.socket)` with: `await invoke("pty_spawn", {...}); this.term.onData(d => invoke("pty_write", {id, data: d})); listen(\`pty://${id}/data\`, e => this.term.write(atob(e.payload)));`.
  - Replace `this.Ipc.send("terminal_channel-…")` resize/CWD plumbing with direct `invoke("pty_resize"/"pty_cwd"/"pty_process")` calls; CWD/process tracking happens on a `setInterval` in the client (same cadence as `terminal.class.js:366` server tick).
  - Delete the entire `role: "server"` branch (lines 302–488). The `verifyClient` block goes with it — its replacement is the absence of a network socket.
- **`filesystem.class.js`** — replace `require("fs")` with `fs_*` invokes (lines 5, 11–12 still load JSON content directly from the bundle via fetch instead). Replace `electron.shell.openPath(...)` + `electronWin.minimize()` (lines 312–313) with `invoke("fs_open_external", { path })`.
- **`updateChecker.class.js`** — uses `https.get` and `@electron/remote`. Drop from v1 (comment out the `new UpdateChecker()` in `renderer.js`).
- **`locationGlobe.class.js`, `conninfo.class.js`** — depend on `networkConnections` + geolite2. Drop from v1 (comment out the `<script>` tags in `ui.html` and the `window.mods.globe`/`conninfo` instantiations).
- **`docReader.class.js`** + `pdfjs-dist` — drop from v1 (remove `<script src="node_modules/pdfjs-dist/...">` from `ui.html`).
- **`ui.html`** — remove the `node_modules/` `<script>` tag for `pdf.js`, the `node_modules/augmented-ui/augmented.css` link is replaced by copying `augmented.css` into `assets/css/` (since `node_modules` won't exist at runtime). Replace `<script src="_renderer.js">` with `<script src="renderer.js">`. CSP unchanged (Tauri injects its own).

### Step 4 — Build & flip

- `cargo tauri dev` from repo root → runs the app. Verify: terminal I/O, theme swap, kb swap, multi-tab spawn (Ctrl+X then 2–5), filesystem panel, sysinfo/cpuinfo/ramwatcher/toplist graphs, battery indicator.
- `cargo tauri build --target aarch64-apple-darwin` → produces `.app` and `.dmg` in `src-tauri/target/aarch64-apple-darwin/release/bundle/`.
- Once verified working: single delete commit removes `src/_boot.js`, `src/_multithread.js`, `src/_renderer.js`, `src/classes/{docReader,locationGlobe,conninfo,updateChecker}.class.js`, the `geolite2-redist`/`maxmind`/`pdfjs-dist`/`howler`-keep/`@electron/remote`/`@xterm/addon-attach`/`electron`/`electron-builder`/`electron-rebuild`/`node-pty`/`ws`/`systeminformation`/`signale`/`shell-env`/`which`/`username`/`@electron/remote` from both `package.json` files (keep `@xterm/*`, `color`, `mime-types`, `smoothie`, `augmented-ui`, `howler`, `nanoid`, `pretty-bytes`). Delete `prebuild-minify.js`, both `package-lock.json`s, and the `prebuild-*`/`build-*` npm scripts.
- File-icons content is kept: `file-icons-generator.js`, `file-icons/` submodules, `src/assets/icons/file-icons.json`, `src/assets/misc/file-icons-match.js`.

### Step 5 — Update `CLAUDE.md`

Replace the "Migration phases" and "Current Electron architecture" sections with the post-migration architecture and the `cargo tauri dev` / `cargo tauri build` commands. Note v0.2 backlog (globe, docReader, updateChecker, conninfo, Windows/Linux targets).

## Files modified vs untouched

**Modified (frontend):** `src/ui.html`, `src/classes/terminal.class.js`, `src/classes/filesystem.class.js`. New: `src/renderer.js`.

**Untouched (frontend, but require `window.si` shim working):** `src/classes/{sysinfo,cpuinfo,ramwatcher,toplist,netstat,hardwareInspector,clock,fuzzyFinder,modal,mediaPlayer,audiofx,keyboard}.class.js`, all of `src/assets/`.

**New (Rust):** `src-tauri/` tree as described.

**Deleted (final commit only):** `src/_boot.js`, `src/_multithread.js`, `src/_renderer.js`, four `.class.js` files listed in Step 4, root `package.json` Electron build scripts, `prebuild-minify.js`.

## Verification

There is no test framework — the project relies on manual verification (per `CLAUDE.md`'s "No automated tests" note). Smoke-test checklist after `cargo tauri dev`:

1. App launches fullscreen, boot intro plays, drops into terminal.
2. Type in main shell — characters echo, prompt rendered with theme colors.
3. `Ctrl+X` then `2`/`3`/`4`/`5` — extra tabs spawn, each gets its own PTY.
4. `Ctrl+Shift+S` → settings modal → change theme → reload → new theme applied.
5. `Ctrl+Shift+K` → shortcuts modal renders.
6. Filesystem panel updates when shell `cd`s; click a directory to navigate; click "Show disks" → disk list renders.
7. CPU graphs animate; per-core values plausible on M-series (perf vs efficiency cores).
8. RAM grid populates; swap bar shows reasonable value.
9. Battery indicator shows percent / CHARGE / WIRED.
10. Top processes list populates and refreshes.
11. `cargo tauri build --target aarch64-apple-darwin` produces a `.app` that launches from `/Applications` and shows `aarch64` in `file Contents/MacOS/eDEX-UI`.

## Out of scope (v0.2 backlog)

- Network globe + `networkConnections` (`netstat2` crate) + geolite2 download.
- conninfo external-IP lookup.
- docReader (PDF viewer).
- updateChecker.
- Windows/Linux Tauri targets.
- Code signing + notarization (separate workstream).