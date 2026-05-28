# eDEX-UI v3 — UI Bug Fix Pass (frontend JS only)

Scope: `src/` WKWebView frontend. Do NOT touch `src-tauri/` — backend verified correct against these symptoms. All struct/command shapes confirmed matching; any apparent mismatch is intentional serde rename.

## CONFIRMED — fix these

### 1. FS panel blank on boot — `src/classes/filesystem.class.js`
`window.performance.navigation` is removed in WKWebView; `.navigation.type === 0` gate is `undefined`, so initial `readFS` never fires. Panel stays blank until first cwd change.
Fix: delete the `window.performance.navigation && ...type===0` guard; call `this.readFS(window.term[window.currentTerm].cwd || window.settings.cwd)` directly (guard `window.term[window.currentTerm]` for existence first).

### 2. On-screen-keyboard shell shortcut throws — `src/classes/keyboard.class.js`, `pressKey()`
`let t = e.linebreak ? writelr : write;` — `writelr`/`write` are bare undefined identifiers → ReferenceError, shell shortcut dead.
Fix: call method on term, not bare ident:
`window.term[window.currentTerm][e.linebreak ? "writelr" : "write"](e.action);`

### 3. Fuzzy-finder Select inserts nothing — `src/classes/fuzzyFinder.class.js`, `submit()`
`path.resolve(...)` — Node `path` global gone under Tauri → ReferenceError.
Fix: use existing helper `_fsPathResolve(window.fsDisp.dirpath, file)` (defined in filesystem.class.js, global scope).

### 4. cursorBlink ignores theme `false` — `src/classes/terminal.class.js`
`cursorBlink: window.theme.terminal.cursorBlink || true` forces blink on; `false` unreachable.
Fix: `cursorBlink: window.theme.terminal.cursorBlink ?? true` (nullish coalesce). Same file: leave `allowTransparency || false` as-is (harmless).

### 5. Acute É wrong — `src/classes/keyboard.class.js`, `addAcute()`
`case "E": return "E";` — returns plain E, not É.
Fix: `return "É";`

### 6. Cedilla sticks — `src/classes/keyboard.class.js`, `pressKey()`
After applying cedilla: `this.container.dataset.isNextCedilla = "true"` — should clear.
Fix: set `"false"` (matches all other dead-key resets).

## DO NOT TOUCH — verified correct, do not "fix"

- `reCalculateDiskUsage` inverted `e.size/e.used*100`: dead path. `renderDiskUsage` reads backend `use` (`use_pct`) first; inverted branch only on `isNaN(e.use)`, never reached. Leave it.
- Battery panel `bat.hasBattery/isCharging/acConnected`: backend `BatteryInfo` has `#[serde(rename_all="camelCase")]`. Shapes match. Leave it.
- `DiskInfo`/`BlockDevice` field names: per-field serde renames match frontend (`use`, `type`, `fsType`, `removable`). Leave it.
- `si_network_connections` empty / conninfo absent: intentional v0.2 stub per README. Leave it.
- "FALLBACK |-- " cwd branch in filesystem.class.js: dead (Rust never emits prefix), but harmless. Leave unless doing dead-code sweep.

## LOWER CONFIDENCE — verify before fixing

- `attachCustomKeyEventHandler` returns `true` always (terminal.class.js): on-screen kbd + physical may double-input. Test before changing return logic.
- `screen.width/height` GCD aspect nudge in `fit()` uses physical screen, not window — wrong cols/rows when `allowWindowed`. Confirm windowed-mode overflow first.
- `shellArgs` is `""` (string) in default settings; `SpawnArgs.args` is `Vec<String>`. Confirm renderer splits shellArgs→array before `pty_spawn` (check `_boot`/tabs open path).

## Constraints
- No backend edits. No dependency changes. Preserve existing minified style in already-minified files (filesystem/keyboard).
- Strip AI-generated comments per repo convention.
- One commit per numbered fix; message `fix(ui): <n> <short>`.
