# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status

This is the security-patched fork of eDEX-UI (v2.2.8), modernized to Electron 37 / Node 20 / `@xterm/*` 5.5.0 in October 2025. The README, CHANGELOG, and current build pipeline all describe an actively-maintained Electron application.

**Active direction:** the project is being migrated off Electron to **Tauri + Rust**, targeting native `aarch64-apple-darwin` (Apple Silicon). The current de-jure plan lives at `~/Desktop/eDex-refactor-plan-draft.md`. **This plan is expected to be superseded shortly by an `ultraplan` output** — once that lands, treat the ultraplan as authoritative and this section as stale.

### Migration phases (per the de-jure draft)

1. **Isolate the modernized frontend.** Preserve `src/ui.html`, all of `src/assets/`, and the visual-only classes (`mediaPlayer.class.js`, `modal.class.js`, `audiofx.class.js`).
2. **Scorched-earth deletion of Electron/Node bindings.** Remove `src/_boot.js`, `src/_multithread.js`, `src/_renderer.js`, and the system-scraping classes (`sysinfo`, `cpuinfo`, `netstat`, `ramwatcher`, `filesystem`). Strip `terminal.class.js` down to the xterm DOM-mount only.
3. **Tauri + Apple Silicon swap.** `cargo tauri init`; replace node-pty with the `portable-pty` Rust crate; replace systeminformation with the `sysinfo` Rust crate (per-core polling for M-series perf/efficiency cores); replace Node `fs` with `#[tauri::command]` wrappers over `std::fs`.
4. **Build for `aarch64-apple-darwin`** via `cargo tauri build --target aarch64-apple-darwin`.

### Migration ground rules (load-bearing)

- **Phase 2 is destructive and irreversible** beyond `git restore`. Confirm with the user before deleting any file in the Phase 2 list, even though the migration direction is approved.
- **Do not strip the WebSocket `file://` origin check in `terminal.class.js` (the `verifyClient` block) until it's being replaced by Tauri IPC in the same change.** Removing it standalone re-introduces the critical RCE this fork was created to fix.
- **`file-icons-generator.js` + the `file-icons/` git submodules + `src/assets/icons/file-icons.json` + `src/assets/misc/file-icons-match.js`** are content, not legacy plumbing — keep them through the migration.
- Until Phase 3 lands, the Electron build must still work; treat `src/_boot.js` etc. as live code, not a graveyard.

## Current Electron architecture (what the migration acts on)

The app boots into Electron, which spawns one or more `node-pty` PTYs and exposes each over a local WebSocket. The renderer (a single `BrowserWindow` loading `src/ui.html`) connects back via `ws://127.0.0.1:<port>` using `@xterm/addon-attach`. The renderer has full Node integration; there is no sandboxed bridge.

- **`src/_boot.js`** — Electron main. Single-instance lock, settings/themes/keyboards/fonts mirrored from `src/assets/*` into `electron.app.getPath("userData")/` on **every** startup (built-ins overwrite user copies; custom files survive). Creates the main `Terminal({role:"server"})` on `settings.port` (default 3000) and allocates up to 4 extra TTYs on `port+2 … port+5` (note: `port+1` is skipped — see `basePort = Number(basePort) + 2`).
- **`src/_multithread.js`** — Node `cluster`-based worker pool for `systeminformation` calls. Spawns `min(os.cpus().length - 1, 7)` workers. The renderer's `window.si` is a Proxy that round-trips `systeminformation-call` IPC → master → worker → reply, keyed by a `nanoid`. Calls with >1 arg or zero workers fall back to in-process.
- **`src/_renderer.js`** — Loaded by `ui.html` as the last script. Disables `eval`, defines `_escapeHtml`/`_purifyCSS`/`_encodePathURI` as the only sanitizers, boots the UI, instantiates every `window.mods.*` (clock/sysinfo/cpuinfo/ramwatcher/toplist/netstat/globe/conninfo) and the per-tab `window.term[0..4]`. Settings/shortcuts editor + the global-shortcut registration live here.
- **`src/classes/terminal.class.js`** — Dual-role class. **`role:"server"`** spawns `node-pty`, opens a `ws.Server` (with the load-bearing `verifyClient` origin gate at lines ~422-436), tracks CWD via `/proc/<pid>/cwd` on Linux and `lsof -a -d cwd -p <pid>` on macOS (Windows hits "Unsupported OS" and falls back), and tracks the foreground process via `ps -o comm`. **`role:"client"`** mounts `@xterm/xterm` with WebGL + ligatures + fit addons, applies the theme's `colorFilter` chain via the `color` library, and bridges xterm ↔ WebSocket.
- **IPC channel naming convention:** `terminal_channel-<port>` for renderer↔main TTY messages; `systeminformation-call` / `systeminformation-reply-<nanoid>` for the worker pool; `getThemeOverride` / `setThemeOverride` / `getKbOverride` / `setKbOverride` / `ttyspawn` for live config swaps.
- **`src/ui.html`** — Plain script tags, no bundler. CSP is permissive: `default-src file: 'unsafe-inline'; connect-src ws: file:`. Order of `<script>` tags matters because classes are registered onto `window`.
- **Renderer security model:** `nodeIntegration: true`, `contextIsolation: false`, `@electron/remote` enabled. Do not "modernize" this in isolation — the entire renderer would need porting. It's also moot post-Phase-3 since Tauri replaces the model wholesale.

## Build & dev commands

There is no test framework. `npm test` runs `snyk` against a fresh `prebuild-src/`. Manual verification only.

```bash
# Install (Linux / Windows have their own scripts because of native rebuilds)
npm run install-linux              # npm i && cd src && npm i && electron-rebuild -f -w node-pty
npm run install-windows            # same, Windows paths

# macOS has no install script; run the equivalent manually:
npm install && cd src && npm install && ../node_modules/.bin/electron-rebuild -f -w node-pty

# Run the app from source
npm start                          # electron src --nointro

# Prebuild pipeline (rsync src/ → prebuild-src/, minify in-place, then `npm install` inside prebuild-src)
npm run prebuild-linux             # or prebuild-darwin / prebuild-windows
npm run build-linux                # or build-darwin / build-windows — electron-builder, output → dist/

# File-icons regeneration (submodule-driven, edits src/assets/icons/file-icons.json + file-icons-match.js)
npm run init-file-icons            # git submodule update --init
npm run update-file-icons          # pull submodules + run file-icons-generator.js
```

### Non-obvious gotchas

- **Two `package.json` files.** Root is build orchestration (electron, electron-builder, terser, clean-css). `src/package.json` is the runtime app deps (xterm, node-pty, systeminformation, ws, @electron/remote). Production builds use `prebuild-src/` as the app dir (`build.directories.app`), not `src/`.
- **`prebuild-minify.js` mutates files in place** inside `prebuild-src/` — never run it against `src/`. It skips `*.json` except `*icons.json`, and skips `file-icons-match.js`.
- **macOS build target is x64 only** (`build.mac.target.arch: ["x64"]`). Apple Silicon currently runs under Rosetta — fixing this is one motivation for the Tauri migration.
- **node-pty must be rebuilt against Electron's ABI** after any dep change. If the app crashes on terminal spawn, that's usually it.
- **Single-instance lock** silently exits the second launch (`app.requestSingleInstanceLock()`). If "the app won't start", check for an existing process.
- **Settings live in Electron's userData**, not the repo. On macOS: `~/Library/Application Support/eDEX-UI/{settings.json,shortcuts.json,themes/,keyboards/,fonts/}`. Built-in themes/keyboards/fonts are re-mirrored every boot.
- **No automated tests.** Verify changes by running `npm start` and exercising the affected feature — terminal I/O, theme swap, keyboard swap, multi-tab spawn (Ctrl+X then 2/3/4/5), filesystem panel, system-info graphs.
