# Multiple Terminal Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement reliable multiple terminal tabs in the Tauri eDEX-UI build, preserving the existing Ctrl+X then 1-5 shortcut model while giving each tab an independent PTY, lifecycle, title, focus state, and filesystem tracking.

**Architecture:** Keep the existing Rust PTY manager because it already supports multiple PTY ids. Move the renderer's ad hoc tab logic out of `renderer.js` into a dedicated `TerminalTabs` frontend controller that owns slot state, DOM activation, tab spawning, tab closing, focus, next/previous navigation, and compatibility with existing classes that still read `window.term[window.currentTerm]`.

**Tech Stack:** Tauri 2, Rust `portable-pty`, xterm.js UMD bundles, plain browser JavaScript, existing CSS in `src/assets/css/main_shell.css`.

---

## Planning Consolidation

All active implementation planning for terminal tabs lives in this file. `CLAUDE.md` is repository guidance only and should link here instead of duplicating backlog or implementation planning.

## Migration Contracts and Deprecations (Current Refactor)

- **PTY metadata contract (current):** `pty_metadata(id)` is the consolidated backend poll surface for terminal tab metadata and returns both `cwd` and foreground `process` in one call.
- **Sysinfo panel contract (current):** `si_panel_snapshot(collapseThreadsByName, topLimit, includeProcessList)` returns one refresh bundle for the left column. Bridge cache key: `collapse:topLimit:includeProcessList` (900ms TTL + in-flight dedupe).
- **PanelSnapshot JSON shape (camelCase):**
  - `cpu`, `currentLoad`, `cpuTemperature`, `processCount`, `topProcesses[]` — cpuinfo + toplist widget
  - `mem` — ramwatcher (`total`, `free`, `used`, `active`, `available`, swap fields)
  - `processList` — only when `includeProcessList: true` (toplist modal); same shape as legacy `si_processes` (`all`, `running`, `list[]` with `pid`, `name`, `cpu`, `mem`, `started`, `state`, `user`, `command`). Thread collapse by name runs in Rust when `collapseThreadsByName` is true.
- **Compatibility status:** Legacy split PTY poll paths `pty_cwd(id)` and `pty_process(id)` remain available; frontend polling falls back to them when `pty_metadata` is unavailable so mixed-version frontend/backend pairs keep working.
- **Deprecation expectation (non-breaking):** Legacy per-metric poll usage (`si.processes()`, `si.mem()`, etc.) is still supported for unchanged callers and modal/detail views; new/updated panel code should prefer `panelSnapshot` and avoid introducing new dependencies on split poll paths.

## Deferred Follow-Up

Mouse-based cursor relocation is explicitly deferred until after the managed tabs refactor lands. The follow-up should use shell-integration markers, not direct xterm cursor mutation: valid left-clicks inside the active editable prompt region should translate into normal keyboard navigation escape sequences, while drag selections, alternate-screen apps, mouse-reporting programs, and unreachable output regions should be ignored.

## Current State

The app already renders five tab labels and five `<pre id="terminalN">` containers from `src/renderer.js`, and `src-tauri/src/pty.rs` already allocates one PTY id per `pty_spawn` call. The weak part is the renderer lifecycle:

- Tab state is a sparse `window.term` object with implicit states: missing, `null`, or `Terminal`.
- Focus, spawn, process-title updates, filesystem following, and close cleanup are mixed into `window.focusShellTab`.
- `NEXT_TAB` and `PREVIOUS_TAB` only walk a few hard-coded offsets.
- Closing a spawned shell depends on `onclose` cleanup in the same function that created it.
- CSS positions inactive terminals with negative `top` offsets instead of stable absolute stacking.

The implementation should not rewrite `Terminal` or the PTY manager from scratch. It should make tab ownership explicit and then adjust the few compatibility callers.

## File Structure

**Create**

- `src/classes/terminalTabs.class.js` - owns tab slots and exposes `open`, `focus`, `close`, `next`, `previous`, `active`, `writeActive`, `writelrActive`, and `syncGlobals`.

**Modify**

- `src/ui.html` - load `classes/terminalTabs.class.js` after `terminal.class.js`.
- `src/renderer.js` - replace inline shell tab markup/state/focus code with `TerminalTabs`.
- `src/assets/css/main_shell.css` - make terminal panes stable stacked layers and add deterministic tab label behavior.
- `src/classes/terminal.class.js` - add an idempotent `dispose` method that wraps `close`, xterm disposal, and DOM cleanup.
- `src-tauri/src/pty.rs` - make `pty_kill` explicitly kill the child process before removing the handle.
- `src/classes/filesystem.class.js`, `src/classes/keyboard.class.js`, `src/classes/fuzzyFinder.class.js`, `src/classes/toplist.class.js` - keep compatibility through `window.term`/`window.currentTerm`; only touch these if runtime testing proves a direct active-terminal helper is needed.
- `README.md`, `CHANGELOG.md`, `CLAUDE.md` - document the final behavior after implementation.

---

### Task 1: Baseline Checks

**Files:**
- Read: `src/renderer.js`
- Read: `src/classes/terminal.class.js`
- Read: `src-tauri/src/pty.rs`

- [ ] **Step 1: Confirm the renderer parses before edits**

Run:

```bash
node --check src/renderer.js
```

Expected: exit code 0 and no syntax errors.

- [ ] **Step 2: Confirm the terminal class parses before edits**

Run:

```bash
node --check src/classes/terminal.class.js
```

Expected: exit code 0 and no syntax errors.

- [ ] **Step 3: Confirm the Rust backend checks before edits**

Run:

```bash
cargo +stable check
```

Expected: `Finished dev profile` with no Rust compile errors.

- [ ] **Step 4: Commit only if the baseline needed cleanup**

If the baseline required no changes, skip this step. If cleanup was required, commit only the cleanup files:

```bash
git add src/renderer.js src/classes/terminal.class.js src-tauri/src/pty.rs
git commit -m "chore: restore terminal tab baseline"
```

Expected: a small commit with no `.claude`, `.codex`, `.cursor`, or `.gemini` skill-directory changes.

---

### Task 2: Add TerminalTabs Controller

**Files:**
- Create: `src/classes/terminalTabs.class.js`

- [ ] **Step 1: Create the controller file**

Add `src/classes/terminalTabs.class.js` with this complete implementation:

```javascript
class TerminalTabs {
    constructor(opts) {
        if (!opts || !opts.containerId) throw new Error("Missing terminal tabs container");
        if (!opts.shell) throw new Error("Missing shell binary");

        this.container = document.getElementById(opts.containerId);
        if (!this.container) throw new Error(`Terminal tabs container not found: ${opts.containerId}`);

        this.shell = opts.shell;
        this.shellArgs = opts.shellArgs || [];
        this.defaultCwd = opts.defaultCwd || "/";
        this.maxTabs = opts.maxTabs || 5;
        this.onActiveCwdChange = opts.onActiveCwdChange || (() => {});
        this.onActiveProcessChange = opts.onActiveProcessChange || (() => {});
        this.onFocus = opts.onFocus || (() => {});
        this.slots = new Array(this.maxTabs).fill(null);
        this.activeIndex = 0;
    }

    mount() {
        const tabs = [];
        const panes = [];
        for (let index = 0; index < this.maxTabs; index++) {
            tabs.push(`<li id="shell_tab${index}" data-tab-index="${index}" class="${index === 0 ? "active" : ""}"><p>${index === 0 ? "MAIN SHELL" : "EMPTY"}</p></li>`);
            panes.push(`<pre id="terminal${index}" class="${index === 0 ? "active" : ""}"></pre>`);
        }

        this.container.innerHTML += `
            <ul id="main_shell_tabs">${tabs.join("")}</ul>
            <div id="main_shell_innercontainer">${panes.join("")}</div>`;

        document.querySelectorAll("#main_shell_tabs > li").forEach(node => {
            node.addEventListener("click", () => {
                this.openOrFocus(Number(node.dataset.tabIndex)).catch(e => console.error("tab focus failed:", e));
            });
        });
    }

    syncGlobals() {
        window.term = this.slots;
        window.currentTerm = this.activeIndex;
    }

    active() {
        return this.slots[this.activeIndex];
    }

    isOpen(index) {
        return Boolean(this.slots[index]);
    }

    label(index, text) {
        const tab = document.getElementById(`shell_tab${index}`);
        if (tab) tab.innerHTML = `<p>${window._escapeHtml(text)}</p>`;
    }

    setActiveDom(index) {
        document.querySelectorAll("#main_shell_tabs > li").forEach(node => node.classList.remove("active"));
        document.querySelectorAll("#main_shell_innercontainer > pre").forEach(node => node.classList.remove("active"));
        const tab = document.getElementById(`shell_tab${index}`);
        const pane = document.getElementById(`terminal${index}`);
        if (tab) tab.classList.add("active");
        if (pane) pane.classList.add("active");
    }

    async openOrFocus(index) {
        if (this.isOpen(index)) {
            this.focus(index);
            return this.slots[index];
        }
        return this.open(index);
    }

    async open(index, opts) {
        if (index < 0 || index >= this.maxTabs) throw new Error(`Tab index out of range: ${index}`);
        if (this.slots[index]) return this.openOrFocus(index);

        const cwd = (opts && opts.cwd) || (this.active() && this.active().cwd) || this.defaultCwd;
        this.label(index, "LOADING...");

        const terminal = new Terminal({
            role: "client",
            parentId: `terminal${index}`,
            shell: this.shell,
            args: this.shellArgs,
            cwd
        });

        this.slots[index] = terminal;
        this.syncGlobals();

        terminal.onprocesschange = processName => {
            const prefix = index === 0 ? "MAIN" : `#${index + 1}`;
            this.label(index, processName ? `${prefix} - ${processName}` : prefix);
            if (index === this.activeIndex) this.onActiveProcessChange(processName);
        };

        terminal.oncwdchange = cwd => {
            if (index === this.activeIndex) this.onActiveCwdChange(cwd);
        };

        terminal.onclose = () => {
            this.close(index, { fromProcessExit: true }).catch(e => console.warn("tab close failed:", e));
        };

        try {
            if (terminal._init) await terminal._init;
            if (index === 0) {
                terminal.term.writeln("\033[1m" + `Welcome to eDEX-UI v${window.appVersion} - Tauri/Rust port` + "\033[0m");
                this.label(index, "MAIN SHELL");
            } else {
                this.label(index, `#${index + 1}`);
            }
            this.focus(index);
            return terminal;
        } catch (e) {
            this.slots[index] = null;
            this.label(index, "ERROR");
            this.syncGlobals();
            throw e;
        }
    }

    focus(index) {
        if (!this.slots[index]) return false;
        this.activeIndex = index;
        this.syncGlobals();
        this.setActiveDom(index);
        this.slots[index].fit();
        this.slots[index].term.focus();
        this.slots[index].resendCWD();
        this.onFocus(index, this.slots[index]);
        return true;
    }

    async close(index, opts) {
        const terminal = this.slots[index];
        if (!terminal) return false;
        if (index === 0 && !(opts && opts.allowMainClose)) return false;

        this.slots[index] = null;
        this.syncGlobals();

        if (!(opts && opts.fromProcessExit)) {
            await terminal.close();
        }
        if (terminal.dispose) {
            await terminal.dispose();
        } else if (terminal.term && terminal.term.dispose) {
            terminal.term.dispose();
        }

        const pane = document.getElementById(`terminal${index}`);
        if (pane) pane.innerHTML = "";
        this.label(index, index === 0 ? "MAIN SHELL" : "EMPTY");

        if (this.activeIndex === index) {
            this.focus(this.previousOpenIndex(index) || 0);
        }
        return true;
    }

    next() {
        for (let step = 1; step <= this.maxTabs; step++) {
            const index = (this.activeIndex + step) % this.maxTabs;
            if (this.slots[index]) return this.focus(index);
        }
        return false;
    }

    previous() {
        for (let step = 1; step <= this.maxTabs; step++) {
            const index = (this.activeIndex - step + this.maxTabs) % this.maxTabs;
            if (this.slots[index]) return this.focus(index);
        }
        return false;
    }

    previousOpenIndex(fromIndex) {
        for (let step = 1; step <= this.maxTabs; step++) {
            const index = (fromIndex - step + this.maxTabs) % this.maxTabs;
            if (this.slots[index]) return index;
        }
        return 0;
    }

    resizeActive() {
        const terminal = this.active();
        if (terminal) terminal.fit();
    }

    writeActive(data) {
        const terminal = this.active();
        if (terminal) terminal.write(data);
    }

    writelrActive(data) {
        const terminal = this.active();
        if (terminal) terminal.writelr(data);
    }
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { TerminalTabs };
}
```

- [ ] **Step 2: Parse-check the new controller**

Run:

```bash
node --check src/classes/terminalTabs.class.js
```

Expected: exit code 0 and no syntax errors.

- [ ] **Step 3: Commit the controller**

```bash
git add src/classes/terminalTabs.class.js
git commit -m "feat: add terminal tab controller"
```

Expected: the commit contains only `src/classes/terminalTabs.class.js`.

---

### Task 3: Load TerminalTabs in the Frontend

**Files:**
- Modify: `src/ui.html`

- [ ] **Step 1: Add the script tag**

In `src/ui.html`, place the new controller immediately after the existing terminal class:

```html
<script src="classes/terminal.class.js"></script>
<script src="classes/terminalTabs.class.js"></script>
```

- [ ] **Step 2: Verify script order**

Run:

```bash
rg -n "terminal.class.js|terminalTabs.class.js" src/ui.html
```

Expected:

```text
src/ui.html:74:        <script src="classes/terminal.class.js"></script>
src/ui.html:75:        <script src="classes/terminalTabs.class.js"></script>
```

- [ ] **Step 3: Commit the script load**

```bash
git add src/ui.html
git commit -m "feat: load terminal tabs controller"
```

Expected: one-line HTML script-order commit.

---

### Task 4: Replace Inline Tab State in Renderer

**Files:**
- Modify: `src/renderer.js`

- [ ] **Step 1: Replace the shell tab markup block**

In `initUI`, replace the block that appends `<ul id="main_shell_tabs">...` and `<pre id="terminal0">...` with:

```javascript
window.terminalTabs = new TerminalTabs({
    containerId: "main_shell",
    shell: shellBin,
    shellArgs: window.settings.shellArgs ? [window.settings.shellArgs] : [],
    defaultCwd: window.settings.cwd || settingsDir,
    maxTabs: 5,
    onFocus: () => {
        if (window.fsDisp) window.fsDisp.followTab();
    }
});
window.terminalTabs.mount();
await window.terminalTabs.open(0, { cwd: window.settings.cwd || settingsDir });
```

Keep the existing shell resolution immediately before this code:

```javascript
let shellBin;
try {
    shellBin = await invoke("resolve_shell", { name: window.settings.shell || "zsh" });
} catch (_) {
    shellBin = window.settings.shell || "/bin/zsh";
}
window.__SHELL_BIN__ = shellBin;
```

- [ ] **Step 2: Remove the old `window.term = { 0: ... }` bootstrap**

Delete the old code that constructs `window.term = { 0: new Terminal(...) }`, sets `window.currentTerm = 0`, assigns `window.term[0].onprocesschange`, awaits `window.term[0]._init`, and writes the welcome banner. The controller now owns that lifecycle.

- [ ] **Step 3: Replace `window.focusShellTab`**

Replace the body of `window.focusShellTab` with:

```javascript
window.focusShellTab = async number => {
    window.audioManager.folder.play();
    if (!window.terminalTabs) return false;
    try {
        await window.terminalTabs.openOrFocus(number);
        if (window.fsDisp) window.fsDisp.followTab();
        return true;
    } catch (e) {
        console.error("TTY spawn failed:", e);
        const tab = document.getElementById("shell_tab" + number);
        if (tab) tab.innerHTML = "<p>ERROR</p>";
        return false;
    }
};
```

- [ ] **Step 4: Parse-check renderer**

Run:

```bash
node --check src/renderer.js
```

Expected: exit code 0 and no syntax errors.

- [ ] **Step 5: Commit the renderer handoff**

```bash
git add src/renderer.js
git commit -m "feat: route terminal tabs through controller"
```

Expected: commit touches only `src/renderer.js`.

---

### Task 5: Route Shortcuts Through TerminalTabs

**Files:**
- Modify: `src/renderer.js`

- [ ] **Step 1: Replace next/previous shortcut branches**

In `window.useAppShortcut`, replace the `NEXT_TAB` and `PREVIOUS_TAB` branches with:

```javascript
case "NEXT_TAB":
    if (window.terminalTabs) window.terminalTabs.next();
    return true;
case "PREVIOUS_TAB":
    if (window.terminalTabs) window.terminalTabs.previous();
    return true;
```

- [ ] **Step 2: Keep numbered tab shortcuts as open-or-focus**

Leave the numbered branches in place, but make sure they call `window.focusShellTab`:

```javascript
case "TAB_1": window.focusShellTab(0); return true;
case "TAB_2": window.focusShellTab(1); return true;
case "TAB_3": window.focusShellTab(2); return true;
case "TAB_4": window.focusShellTab(3); return true;
case "TAB_5": window.focusShellTab(4); return true;
```

- [ ] **Step 3: Replace active resize**

At the bottom of `src/renderer.js`, replace the `window.onresize` body with:

```javascript
window.onresize = () => {
    if (window.terminalTabs) window.terminalTabs.resizeActive();
};
```

- [ ] **Step 4: Parse-check renderer**

Run:

```bash
node --check src/renderer.js
```

Expected: exit code 0 and no syntax errors.

- [ ] **Step 5: Commit shortcut routing**

```bash
git add src/renderer.js
git commit -m "feat: simplify terminal tab shortcuts"
```

Expected: shortcut behavior is owned by `TerminalTabs`.

---

### Task 6: Stabilize Terminal Pane CSS

**Files:**
- Modify: `src/assets/css/main_shell.css`

- [ ] **Step 1: Replace pane positioning**

Replace the `div#main_shell_innercontainer` and `pre` positioning block with:

```css
div#main_shell_innercontainer {
    height: 100%;
    width: 100%;
    margin: 0;
    overflow: hidden;
    position: relative;
}

div#main_shell_innercontainer pre {
    position: absolute;
    inset: 0;
    z-index: 0;
    opacity: 0;
    margin: 0;
    overflow: hidden;
    pointer-events: none;
}

div#main_shell_innercontainer pre.active {
    z-index: 1;
    opacity: 1;
    pointer-events: auto;
}
```

- [ ] **Step 2: Delete negative offset rules**

Delete these obsolete rules:

```css
div#main_shell_innercontainer pre#terminal1 { top: -100%; }
div#main_shell_innercontainer pre#terminal2 { top: -200%; }
div#main_shell_innercontainer pre#terminal3 { top: -300%; }
div#main_shell_innercontainer pre#terminal4 { top: -400%; }
```

- [ ] **Step 3: Fix active tab stacking**

In `ul#main_shell_tabs > li.active`, replace `z-index: -1;` with:

```css
z-index: 1;
```

- [ ] **Step 4: Run CSS diff check**

Run:

```bash
git diff --check -- src/assets/css/main_shell.css
```

Expected: no whitespace errors.

- [ ] **Step 5: Commit CSS**

```bash
git add src/assets/css/main_shell.css
git commit -m "fix: stack terminal tab panes predictably"
```

Expected: only terminal shell CSS changes.

---

### Task 7: Make Terminal Disposal Idempotent

**Files:**
- Modify: `src/classes/terminal.class.js`

- [ ] **Step 1: Add a disposed flag**

Near the existing runtime fields, after `this._lastProc = null;`, add:

```javascript
this._disposed = false;
```

- [ ] **Step 2: Replace `this.close` with an idempotent version**

Replace the existing `this.close = async () => { ... }` block with:

```javascript
this.close = async () => {
    if (this._poll) { clearInterval(this._poll); this._poll = null; }
    if (this._unlistenData) { this._unlistenData(); this._unlistenData = null; }
    if (this._unlistenExit) { this._unlistenExit(); this._unlistenExit = null; }
    if (this.ptyId !== null) {
        try { await invoke("pty_kill", { id: this.ptyId }); } catch (_) {}
        this.ptyId = null;
    }
};

this.dispose = async () => {
    if (this._disposed) return;
    this._disposed = true;
    await this.close();
    if (this.term && this.term.dispose) this.term.dispose();
};
```

- [ ] **Step 3: Parse-check terminal class**

Run:

```bash
node --check src/classes/terminal.class.js
```

Expected: exit code 0 and no syntax errors.

- [ ] **Step 4: Commit terminal disposal**

```bash
git add src/classes/terminal.class.js
git commit -m "fix: make terminal disposal idempotent"
```

Expected: one terminal lifecycle commit.

---

### Task 8: Kill PTY Children Explicitly

**Files:**
- Modify: `src-tauri/src/pty.rs`

- [ ] **Step 1: Update `pty_kill`**

Replace the current `pty_kill` function with:

```rust
#[tauri::command]
pub fn pty_kill(state: State<'_, PtyManager>, id: u32) -> Result<(), String> {
    let mut map = state.inner.lock().unwrap();
    if let Some(mut handle) = map.remove(&id) {
        let _ = handle._child.kill();
    }
    Ok(())
}
```

- [ ] **Step 2: Format Rust**

Run:

```bash
cargo fmt
```

Expected: no output on success.

- [ ] **Step 3: Check Rust**

Run:

```bash
cargo +stable check
```

Expected: `Finished dev profile` with no Rust compile errors.

- [ ] **Step 4: Commit PTY cleanup**

```bash
git add src-tauri/src/pty.rs
git commit -m "fix: terminate closed tab ptys"
```

Expected: PTY cleanup commit only.

---

### Task 9: Runtime Smoke Test

**Files:**
- Exercise: built app only

- [ ] **Step 1: Start the app**

Run:

```bash
cargo +stable tauri dev
```

Expected: app launches and reaches the main terminal.

- [ ] **Step 2: Verify main tab**

In the app:

```text
Type: pwd
Press: Enter
```

Expected: output prints in tab 1, and filesystem panel follows the printed working directory.

- [ ] **Step 3: Verify tab creation**

Use the configured shortcut sequence:

```text
Press: Ctrl+X then 2
Type: echo tab2
Press: Enter
Press: Ctrl+X then 3
Type: echo tab3
Press: Enter
```

Expected: tabs 2 and 3 spawn independent shells. Returning to tab 2 still shows `tab2`; returning to tab 3 still shows `tab3`.

- [ ] **Step 4: Verify next/previous navigation**

Use:

```text
Press: Ctrl+Tab
Press: Ctrl+Shift+Tab
```

Expected: focus cycles only through open tabs and wraps around.

- [ ] **Step 5: Verify close cleanup**

In tab 2:

```text
Type: exit
Press: Enter
```

Expected: tab 2 label returns to `EMPTY`, focus falls back to an open tab, and the app remains responsive.

- [ ] **Step 6: Verify keyboard and filesystem compatibility**

Use the on-screen keyboard and click a directory in the filesystem panel.

Expected: input goes to the active terminal, and filesystem commands are written to the active tab only.

---

### Task 10: Production Build and Documentation

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Production build**

Run:

```bash
cargo +stable tauri build --target aarch64-apple-darwin
```

Expected artifacts:

```text
src-tauri/target/aarch64-apple-darwin/release/bundle/macos/eDEX-UI.app
src-tauri/target/aarch64-apple-darwin/release/bundle/dmg/eDEX-UI_3.0.0_aarch64.dmg
```

- [ ] **Step 2: Update README behavior line**

In `README.md`, make the verified status mention independent tab PTYs:

```markdown
Boots fullscreen, terminal echoes, terminal tabs spawn independent PTYs (Ctrl+X then 1-5, Ctrl+Tab, Ctrl+Shift+Tab), filesystem panel follows the active tab, sysinfo/cpuinfo/ramwatcher/toplist panels populate, hardware inspector renders, on-screen keyboard renders and swaps layouts, theme swap (Ctrl+Shift+S), settings modal opens, audio cues fire.
```

- [ ] **Step 3: Update changelog**

In `CHANGELOG.md`, add a bullet under `v3.0.0`:

```markdown
- Reworked terminal tabs into an explicit frontend controller so each tab owns an independent PTY lifecycle, active focus state, process label, and filesystem tracking hook.
```

- [ ] **Step 4: Keep planning consolidated**

In `CLAUDE.md`, keep only a short pointer to this file:

```markdown
Active implementation planning lives in `ULTRAPLAN.md`. Do not duplicate implementation plans or backlog lists in this guidance file.
```

- [ ] **Step 5: Final verification**

Run:

```bash
node --check src/renderer.js
node --check src/classes/terminal.class.js
node --check src/classes/terminalTabs.class.js
git diff --check -- README.md CHANGELOG.md CLAUDE.md ULTRAPLAN.md src/renderer.js src/classes/terminal.class.js src/classes/terminalTabs.class.js src/assets/css/main_shell.css src-tauri/src/pty.rs
cargo +stable check
```

Expected: all commands pass.

- [ ] **Step 6: Final commit**

Stage only the intended implementation and documentation files:

```bash
git add README.md CHANGELOG.md CLAUDE.md ULTRAPLAN.md src/ui.html src/renderer.js src/classes/terminal.class.js src/classes/terminalTabs.class.js src/assets/css/main_shell.css src-tauri/src/pty.rs
git commit -m "feat: implement managed terminal tabs"
```

Expected: no `.claude`, `.codex`, `.cursor`, or `.gemini` skill-directory files are staged or committed.

---

## Acceptance Criteria

- `Ctrl+X` then `1` through `5` opens or focuses the corresponding terminal tab.
- `Ctrl+Tab` and `Ctrl+Shift+Tab` cycle through open tabs only and wrap.
- Every open tab has its own PTY id and keeps its own shell scrollback.
- Closing a shell with `exit` cleans up the tab UI and kills/removes the PTY handle.
- The filesystem panel follows the active terminal tab's CWD.
- On-screen keyboard input and custom shell shortcuts target the active tab.
- Resizing the window refits only the active xterm instance.
- `node --check` passes for modified JS files.
- `cargo +stable check` passes.
- `cargo +stable tauri build --target aarch64-apple-darwin` produces the `.app` and `.dmg`.
