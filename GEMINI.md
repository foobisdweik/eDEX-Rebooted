# GEMINI.md - eDEX-UI (Security Patched / Tauri Port)

This project is **eDEX-UI v3.0.0**, a community-driven fork and native rewrite of the original eDEX-UI. It has been ported from Electron to **Tauri 2 + Rust**, specifically targeting **macOS Apple Silicon (`aarch64-apple-darwin`)**.

## Project Overview

eDEX-UI is a fullscreen terminal emulator and system monitor with a science-fiction inspired interface. The v3.0.0 release is a security-focused rewrite that eliminates the WebSocket-based terminal control channel, moving all terminal I/O into Tauri's in-process IPC.

### Main Technologies
- **Backend:** Rust (Tauri 2, `tokio`, `portable-pty`, `sysinfo`).
- **Frontend:** Vanilla HTML/JavaScript/CSS rendered via macOS WKWebView.
- **Frontend Libraries (Vendored):** xterm.js (terminal), augmented-ui (sci-fi frames), howler.js (audio), smoothie.js (charts).
- **Communication:** Tauri `invoke()` (commands) and `listen()` (events).

## Architecture Map

- **`src-tauri/` (Rust Backend):**
    - `src/lib.rs`: Entry point, plugin initialization, and command registration.
    - `src/pty.rs`: Manages PTY (Pseudo-Terminal) lifecycles using `portable-pty`.
    - `src/sysinfo_cmds.rs`: System monitoring commands (CPU, RAM, Processes, etc.) via `sysinfo`.
    - `src/fs_cmds.rs`: Filesystem operations (readdir, stat, read/write).
    - `src/settings.rs`: Persistence for settings, shortcuts, and themes in `~/Library/Application Support/eDEX-UI/`.
- **`src/` (Frontend):**
    - `ui.html`: Main entry point (no bundler used).
    - `renderer.js`: Bootstrapper, loads settings/themes, and initializes UI modules.
    - `classes/`: Module-specific logic (e.g., `Terminal`, `FilesystemDisplay`, `Keyboard`).
    - `assets/vendor/`: All third-party dependencies are vendored here as UMD bundles.

## Building and Running

### Requirements
- macOS 11+ on Apple Silicon.
- Rust toolchain (stable).
- `tauri-cli` v2 (`cargo install tauri-cli --version "^2.0" --locked`).
- Node.js (only for regenerating file-icons).

### Key Commands
- **Development:** `cargo tauri dev`
    - *Note:* Watches `src-tauri/` for changes. Manual reload (`Cmd+R`) is required for changes in `src/`.
- **Production Build:** `cargo tauri build --target aarch64-apple-darwin`
    - Artifacts land in `src-tauri/target/aarch64-apple-darwin/release/bundle/`.
- **Regenerate File Icons:**
    - `npm run init-file-icons` (one-time setup for submodules).
    - `npm run update-file-icons` (pulls latest icons and generates JSON).

## Development Conventions

### Coding Style
- **Backend (Rust):** Follow standard idiomatic Rust patterns. State is managed via Tauri's `.manage()` (e.g., `PtyManager`, `SysinfoService`).
- **Frontend (JavaScript):** Use the established Class-based pattern in `src/classes/`.
    - Frontend scripts are loaded via `<script>` tags in `ui.html`.
    - Avoid using `eval()` (it is explicitly disabled for security).
    - Use the `window.si` Proxy to call system information commands.

### Testing
- **No Automated Test Framework:** The project currently relies on manual smoke-testing.
- **Validation Checklist:**
    1. Run `cargo tauri dev`.
    2. Verify terminal echo and tab spawning (`Ctrl+X` then `1-5`).
    3. Check that visual panels (CPU, RAM, etc.) populate.
    4. Test theme swap (`Ctrl+Shift+S`) and settings modal.

### Important Gotchas
- **macOS Only:** Do not reintroduce Windows or Linux specific branches in the frontend JS; keep platform-specific logic in Rust commands.
- **Vendored Assets:** Do not attempt to use `npm install` for frontend dependencies. Use the UMD bundles in `src/assets/vendor/`.
- **Capabilities:** New backend commands must be allow-listed in `src-tauri/capabilities/default.json`.
- **Sysinfo Pinned:** The `sysinfo` crate is pinned to `0.32` due to API drift in newer versions.

## Troubleshooting
- **Frontend errors:** Inspect the WKWebView devtools (Cmd+Option+I if enabled/available).
- **Cargo failures:** Ensure you are using a current stable Rust toolchain (older versions may fail to parse dependency metadata).
