# eDEX-UI v3 — frontend project notes

Scope: `src/` WKWebView frontend. Backend (`src-tauri/`) is verified correct against the symptoms tracked below — any apparent struct/command mismatch is intentional serde rename. Do not edit `src-tauri/` for cosmetic/UI work.

## Shipped on the `frontend-cleanup` pass

The seven targeted UI bugs have been resolved (one commit each):

1. **FS panel blank on boot** — `filesystem.class.js` no longer guards on the WKWebView-stripped `window.performance.navigation`; `readFS` fires at startup with a `window.term[currentTerm]` existence guard.
2. **On-screen-keyboard shell shortcut** — `keyboard.class.js` `pressKey` calls `term[linebreak ? "writelr" : "write"]` instead of the bare undefined idents.
3. **Fuzzy-finder Select** — `fuzzyFinder.class.js` uses the existing `_fsPathResolve` helper from `filesystem.class.js` (Node `path` global is gone under Tauri).
4. **cursorBlink ignores theme `false`** — `terminal.class.js` switched `||` to `??`.
5. **Acute É** — `keyboard.class.js` `addAcute` returns `"É"` (was bare `"E"`).
6. **Cedilla dead-key sticks** — `keyboard.class.js` sets `isNextCedilla = "false"` after applying, matching every other dead-key reset.
7. **`fit()` over-allocates cols/rows** — `terminal.class.js` dropped the `screen.width/height` GCD nudge. `FitAddon.proposeDimensions()` reads the actual parent box and is correct on its own; the legacy nudge was an Electron-fullscreen holdover that produced 1–3 stale extra cols/rows in windowed mode.

Plus three UX/UI additions on the same pass:

- **Cogwheel settings button** — persistent top-right button (`#settings_button`, augmented-ui `tl-clip br-clip exe`, theme-tinted via `--color_r/g/b`) makes settings discoverable without the `Ctrl+Shift+S` shortcut or the FS-panel pseudo-file. Hidden until `initUI()` adds `.ready`; guards against opening on top of an existing modal.
- **Reboot-required toast** — `writeSettingsFile` now snapshots `prevSettings` and diffs the reboot-required keys: `shell, shellArgs, cwd, username, monitor, nointro, forceFullscreen, allowWindowed, keepGeometry, theme, keyboard`. When any changed, appends a `.settingsRebootNotice` line under the status text. The modal's existing "Restart eDEX" button is the affordance.
- **`shellArgs` multi-arg split** — `renderer.js` splits the settings string on whitespace before constructing the `pty_spawn` array, so `"--login --interactive"` becomes two argv entries instead of one concatenated string.

## DO NOT TOUCH — verified, leave as-is

These have been audited end-to-end and are correct despite looking suspicious:

- **`attachCustomKeyEventHandler` always returns `true`** (`terminal.class.js`) — the on-screen `keydownHandler` only mutates DOM classes and plays audio; it never calls `term.write` or `pty_write`. Physical and on-screen input flow through two independent paths, so there is no double-input. Returning `false` would silently break physical typing.
- **`shellArgs` wire shape (JS array ↔ Rust `Vec<String>`)** — `renderer.js` always wraps before invoke and the backend's `SpawnArgs.args` deserializes a JS array directly. Default empty string falls through to `[]` and the backend itself injects `--login`. Protocol is sound.
- **`reCalculateDiskUsage` inverted `e.size/e.used*100`** — dead path. `renderDiskUsage` reads backend `use` (`use_pct`) first; the inverted branch only fires on `isNaN(e.use)`, which the backend never emits.
- **Battery panel `bat.hasBattery/isCharging/acConnected`** — Rust `BatteryInfo` has `#[serde(rename_all = "camelCase")]`. Shapes match.
- **`DiskInfo` / `BlockDevice` field names (`use`, `type`, `fsType`, `removable`)** — per-field serde renames match the frontend reads.
- **`si_network_connections` empty / conninfo absent** — intentional v0.2 stub per the project README.
- **"FALLBACK |-- " cwd branch in `filesystem.class.js`** — dead (the Rust side never emits the prefix), but harmless. Sweep with the rest of the dead-code pass if/when one is scheduled.

## Conventions

- No backend edits for UI work, **except** for tiny runtime-introspection facilities that the frontend can't derive on its own (e.g. the `is_dev_build` command added here, returning `cfg!(debug_assertions)` so the JS layer can branch dev-only UX). Behavior-changing backend edits remain off-limits.
- No dependency changes for UI work.
- Preserve existing minified style in already-minified files (filesystem/keyboard).
- No AI-generated explanatory comments. Match the surrounding terse style.
- One commit per numbered fix when working from a bug list; message format `fix(ui): <n> <short>`. UX/UI features can be combined as a single `feat(ui): ...` commit when cohesive.
