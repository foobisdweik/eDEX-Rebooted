# eDEX-UI v3 Ultrareview Brief

## Project Context

This repository is a fork of a security-hardened fork of the original eDEX-UI: a fullscreen, cross-platform terminal emulator and system monitor with a sci-fi interface. The original application was Electron-based and mostly JavaScript/CSS/HTML.

The intermediate fork hardened the original terminal control path by accepting only local Electron `file://` connections, rejecting `http://` and `https://` connection attempts, and logging rejected attempts in `src/classes/terminal.class.js`.

This fork continues that security work by converting the hardened app from web/Electron architecture toward native Swift and Rust for Apple Silicon Macs running macOS Tahoe 26.x. The current implementation is a Tauri 2 app: Rust owns native capabilities and IPC, while `src/` remains a WKWebView frontend payload pending further native migration.

## Architecture Map

- `src/ui.html`: static WKWebView shell and script load order.
- `src/renderer.js`: boot sequence, settings, theme loading, shortcuts, terminal/tab initialization, and top-level UI commands.
- `src/bridge/`: frontend bridge shims for state, audio, events, sysinfo, and native panel mounting.
- `src/classes/`: active frontend modules for terminal, tabs, filesystem, keyboard, modals, media, and system panels.
- `src-tauri/src/`: Rust backend modules for Tauri command registration, PTY lifecycle, filesystem access, settings, sysinfo, native modal, native mount, and macOS window chrome.
- `src-tauri/capabilities/default.json`: Tauri 2 permission allow-list for the main window.
- `src-tauri/tauri.conf.json`: app config, CSP, bundle settings, and Tauri global exposure.
- `src-tauri/tests/sysinfo_contract.rs`: Rust-to-JS JSON wire-shape contract tests.

Ignore `src-tauri/target/`, vendored browser libraries in `src/assets/vendor/`, generated schemas, screenshots, and media assets unless a finding directly depends on them.

## Review Objective

Perform a total front-end to back-end code inspection. Prioritize runtime correctness, security boundaries, recoverability, native macOS behavior, and migration risks.

Treat the Tauri IPC boundary as the main trust boundary. Custom Rust commands are not protected by plugin scopes unless their implementation enforces path, argument, and capability constraints directly.

## Primary Review Targets

1. Frontend runtime paths:
   - `src/renderer.js`
   - `src/classes/terminal.class.js`
   - `src/classes/terminalTabs.class.js`
   - `src/classes/filesystem.class.js`
   - `src/classes/keyboard.class.js`
   - `src/classes/modal.class.js`
   - loaded panel classes and bridge files

2. Rust/Tauri backend paths:
   - `src-tauri/src/lib.rs`
   - `src-tauri/src/pty.rs`
   - `src-tauri/src/fs_cmds.rs`
   - `src-tauri/src/settings.rs`
   - `src-tauri/src/sysinfo_cmds.rs`
   - `src-tauri/src/sysinfo_service.rs`
   - `src-tauri/src/native_mount.rs`
   - `src-tauri/src/native_modal.rs`
   - `src-tauri/src/window_chrome.rs`

3. Configuration and permissions:
   - `src-tauri/capabilities/default.json`
   - `src-tauri/tauri.conf.json`
   - `src-tauri/Cargo.toml`
   - `src/package.json`

## Security Review Focus

- Tauri 2 capabilities and plugin permissions, especially shell, process, global shortcut, core window, and webview permissions.
- `withGlobalTauri`, CSP, inline handlers, dynamic HTML construction, and any path from local data into executable JS/HTML/CSS.
- Custom IPC command scope enforcement for filesystem, shell resolution, PTY spawning, settings writes, and native AppKit calls.
- Renderer compromise blast radius: what JS can read, write, execute, spawn, resize, or open through Rust/Tauri.
- Unsafe Rust/AppKit interop: null handling, main-thread assumptions, object lifetime, coordinate transforms, and async dispatch ordering.

## Runtime Review Focus

- Boot recovery if settings, shell, cwd, theme, keyboard layout, sysinfo, or PTY setup fails.
- PTY lifecycle: spawn, read, write, resize, metadata polling, natural process exit, tab close, app quit, and orphan cleanup.
- Frontend global state consistency: `window.term`, `window.currentTerm`, `window.keyboard`, `window.settings`, and bridge state.
- Event/timer cleanup: intervals, global shortcuts, modal listeners, media listeners, ResizeObserver, fullscreen handlers, and reload behavior.
- Panel polling and cache behavior under slow sysinfo calls.
- Filesystem navigation, disk display, file preview/editing, external open, and invalid path handling.

## Known Intentional Design Constraints

- macOS Apple Silicon is the only current target.
- Node/Electron runtime APIs should not be reintroduced.
- Network globe, connection list, PDF reader, and update checker are deferred.
- `si_network_connections` is currently a v0.2 stub.
- Frontend dependencies are vendored into `src/assets/vendor/`; the frontend package manifest records source versions but is not installed at runtime.
- Keep migration slices shippable; do not remove compatibility bridges in the same change that introduces a native replacement.

## Validation Commands

Use targeted checks first, then broaden if changes are made:

```bash
node --check src/renderer.js
node --test src/bridge/bridge.test.js src/bridge/native_mount.test.js src/classes/terminalTabs.class.test.js
cd src-tauri && cargo check
cd src-tauri && cargo test --test sysinfo_contract
cd src-tauri && cargo fmt --check
cd src-tauri && cargo clippy -- -D warnings
```

For release-readiness checks:

```bash
cd src-tauri && cargo tauri build --target aarch64-apple-darwin
```

## Finding Format

Report findings first, ordered by severity. Include exact file and line references, observed or plausible runtime impact, reproduction conditions when possible, and the minimal safe fix. Avoid broad rewrites unless required by a security boundary or migration constraint.
