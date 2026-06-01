# Full Native Swift+Rust Conversion: Plan

## Goal

Drive eDEX-UI from its current **Tauri 2 + Rust backend / WKWebView (JS/CSS/HTML) frontend** state (as merged in PR #11) to an end-state where **virtually all web-dev code is replaced by native Swift + Rust**, on `aarch64-apple-darwin` / macOS Tahoe — improving functionality and UX while reproducing the original UI's look and behavior with extreme fidelity.

> **Execution status (2026-05-30):** Phase 1 (Rust core extraction, items 1.1–1.5) is **COMPLETE and validated** — `crates/edex-core` (tauri-free) + `crates/edex-ffi` (UniFFI) created; Tauri commands are thin adapters; PTY observer re-wraps into the existing `Channel<Vec<u8>>` (frontend untouched); Swift bindings generate; 1.5 decision recorded in `docs/plans/ffi-throughput-decision-2026-05-30.md` (UniFFI control-plane now, C-ABI reserved for terminal streaming). Parallel wave in progress: Phase 3.1/3.2 (Swift shell) + Phase 2.1/2.3 (slot stabilization).

## Background

> Distilled from five parallel explore scouts (native infra, web-dev inventory, Rust backend surface, prior-art/PR#11, external architecture). Load-bearing refs only.

### Current architecture (post PR #11)
- **Stack:** Tauri 2 + Rust backend, WKWebView frontend. macOS-only (`aarch64-apple-darwin`). No bundler; `ui.html` loads script tags in order; `renderer.js` is the boot IIFE.
- **Trust/IPC boundary is `invoke()`, in-process.** No socket, no sidecar.
- **There is NO Swift in the codebase yet** — "native" today means Rust calling AppKit via `objc`/`cocoa`. Introducing Swift is itself a net-new step.
- **PTY data path (correction to CLAUDE.md):** PTY bytes flow over a Tauri `Channel<Vec<u8>>` passed to `pty_spawn` (`pty.rs:131-146`, consumed in `terminal.class.js:129-170`). The `pty://{id}/exit` event is **exit-only** (`pty.rs:145`); there is no `pty://{id}/data` event. CWD/process come from polling `pty_metadata`.

### Native-migration infra already landed (Approach A — per-panel slots)
- `src-tauri/src/native_panels.rs` — per-panel `NSView` slot registry: `NativePanelsState` (:75), `NativeThemeState` (:63), `Slot` (:88), `flip_y` (:29), `restyle_slot` (:710). Commands: `native_set_theme`, `native_panel_mount/set_rect/set_visible/set_text/unmount` (`lib.rs:96-103`).
- **Only `mod_sysinfo` + `mod_hardwareInspector` are wired natively** — hard gate `valid_anchor()` at `native_panels.rs:152-153`. Builders `build_sysinfo_layers` (:442), `build_hardware_layers` (:463).
- `src-tauri/src/native_mount.rs` — **older column-granular** pilot (hides all of `#mod_column_left`); now used only for the **clock** text pilot (`native_mount_set_clock_text` :336, used `clock.class.js:48`).
- `src-tauri/src/native_modal.rs` — `NSAlert`-only `native_modal_notify` (info/warn/error; no custom content).
- **Gating flags** (all default `false`, `settings.rs:90-94`): `experimentalNativePanels` (master), `experimentalNativeClock`, `experimentalNativeSysinfo`, `experimentalNativeHwInspector`, `experimentalNativeModal`.
- **Phase 1 keeps JS formatting/polling** and pushes finished strings into native `CATextLayer`s via `native_panel_set_text`. Theme is pushed explicitly via `native_set_theme` (native views have no `:root`/CSS vars).
- **AppKit interop pattern:** `objc`/`cocoa`; every `*mut Object` stashed as `usize` (Send+Sync), deref'd only inside `dispatch::Queue::main().exec_async`; web→AppKit rects need `flip_y(content_h, y, h)`; layers `retain`ed. Reuses Tauri's transitive stack (no new crates).

### Rust backend command surface (`lib.rs:36-104`)
- **PTY:** `pty_spawn/write/resize/kill/metadata/cwd/process`. `PtyManager` owns `HashMap<u32, Arc<PtyHandle>>`. Not exposed as a typed native service the way sysinfo is.
- **Sysinfo:** 15 `si_*` commands. **`SysinfoService` (`sysinfo_service.rs`) is Tauri-agnostic** and exposes typed methods native renderers can call **without an `invoke()` round-trip**: `cpu/current_load/cpu_temperature/processes/panel_snapshot/mem/battery/network_interfaces/network_stats/fs_size/block_devices/system/chassis/uptime`. JSON wire shapes are the `Serialize` structs (mostly `camelCase`).
- **FS:** `fs_readdir/stat/readfile/writefile/exists/open_external`.
- **Settings:** ~20 commands (paths, settings, shortcuts, themes, keyboards, window state, overrides, `resolve_shell`, `get_username`, `get_displays`).
- **`window.si` seam** lives in `src/bridge/sysinfo.js:26-84` — a Proxy mapping camelCase → `si_*` snake_case `invoke`. Consumers: cpuinfo/ramwatcher/toplist use `panelSnapshot(...)`; sysinfo uses `uptime()/battery()`; hardwareInspector uses `system()/chassis()`; filesystem uses `blockDevices()/fsSize()`.

### Remaining web-dev surface to replace (size · native-conversion difficulty)
- **Terminal core (heavy, xterm.js):** `terminal.class.js` ~332 · `terminalTabs.class.js` ~206. xterm loaded `ui.html:36-50`; CSS coupling `main_shell.css:116-207`.
- **Left-column panels:** `clock` ~71 (moderate) · `sysinfo` ~156 (**native done**) · `hardwareInspector` ~67 (**native done**) · `cpuinfo` ~169 (heavy — SmoothieChart `cpuinfo.class.js:11-95`) · `ramwatcher` ~93 (moderate — 440-cell dot grid) · `toplist` ~226 (moderate/heavy — interactive, needs custom modal).
- **Other UI:** `keyboard.class.js` ~1310 (**largest** — layouts/modifiers/input forwarding) · `filesystem.class.js` ~576 (heavy — listing/icons/FS IPC) · `fuzzyFinder` ~135 · `mediaPlayer` ~184 · `modal.class.js` ~240 (augmented-ui) · `netstat` ~186 (not loaded) · `audiofx.class.js` ~40 (Howler).
- **Orchestration:** `renderer.js` ~803 (boot/layout/shortcuts/IPC glue) · `ui.html` ~113.
- **Bridge shims:** `audio/events/native_mount/native_panels/state/sysinfo` (thin JS).
- **CSS:** ~20 files; `main_shell.css` (xterm DOM), `modal.css` (augmented-ui), `mod_cpuinfo.css` (smoothie) are the coupled ones.
- **Vendored heavy libs** (all UMD under `src/assets/vendor/`): xterm + addons (fit/ligatures/webgl), SmoothieChart, Howler, augmented-ui.

### Prior art / design of record
- **Approach A (per-panel slots)** is authoritative: `docs/superpowers/specs/2026-05-29-native-panel-conversion-design.md`.
- **Phase 0 (infra) + Phase 1 (sysinfo + hwInspector) LANDED in PR #11** — merge `7a81b0d`; commits `3e9100d` (per-panel slots), `91ff30f` (lifetime hardening), `df5ed19` (reset to master).
- **Phase 2 (cpuinfo + ramwatcher)** documented but not landed: `docs/superpowers/plans/2026-05-29-native-panel-slots-phase2-cpu-ram.md`.
- **Phase 3:** `toplist` last — needs a content-bearing native modal; **no OS-pid kill exists** (`pty_kill` only closes internal PTY handles).
- `CONVERSION_WORKFLOW.md` broad slice map: S1 pilots (clock/modal/audiofx) · S2 telemetry panels · S3 filesystem/keyboard/fuzzyFinder · S4 terminal renderer · S5 web-runtime decommission.
- **v0.2 backlog (not present):** `locationGlobe`, `conninfo`, `docReader`, `updateChecker`; `si_network_connections` is a stub.
- `Ultrareview.md` (PR #10 hardening): renderer IPC is powerful → DOM injection = host RCE; fewer web surfaces = smaller attack surface (a conversion benefit).

### End-state architecture options (external research — the strategic fork)
The phrase "Swift+Rust" implies introducing Swift, which the codebase does not yet have. Three documented shapes:
1. **Stay Tauri + native AppKit views over the webview (current trajectory, Rust-only via `objc`).** Incremental; keeps Rust command structure & bundling. But a *fully* native UI fights Tauri's webview-centric model, and "Swift" never really enters.
2. **Tauri shell with a hidden/empty webview, UI fully native.** Possible at the tao/wry windowing layer, but architecturally awkward — you lose Tauri's value-add (webview IPC, capabilities, plugins) while still paying for it.
3. **Pure SwiftUI/AppKit app + Rust core as `staticlib`/`cdylib` via FFI.** Cleanest native macOS result (Apple UI, accessibility, menus, SwiftUI). Interop via **swift-bridge** (Swift-specific), **UniFFI** (Mozilla, generated bindings), or **cxx** (C++-oriented). Cost: replace `invoke` with FFI; rebuild packaging/signing/notarization around Xcode/SwiftPM + Cargo. Terminal would move xterm.js → a native Swift terminal (e.g. **SwiftTerm**).

## Approach

### Strategic decision: Option 3 (pure Swift/AppKit + Rust core via FFI)

**Recommended end-state:** a native macOS app (Apple Silicon / Tahoe) where **SwiftUI** owns app/window/scene/settings/menus, **AppKit + CALayer + Metal/CoreText** render the high-fidelity sci-fi surfaces (panels, modals, terminal, boot screen), and a **Tauri-independent Rust core (`edex-core`)** owns PTY, terminal-emulation state, sysinfo, filesystem, settings/userdata, and theme/keyboard JSON parsing. Swift reaches Rust through **UniFFI**-generated bindings (with a narrow C-ABI escape hatch reserved for terminal streaming — see 1.5). No WKWebView, no Tauri runtime, no vendored web libraries, no JS/CSS/HTML runtime UI.

**Why not Option 1 (stay in Tauri, drive AppKit from Rust/`objc`):** the landed `native_panels.rs` proves it works, but it is a poor *final* foundation — Tauri is a WebView shell that becomes dead weight once the web UI is gone; Rust/`objc` AppKit code is verbose, unsafe, and easy to mis-thread; and terminal rendering, focus, menus, accessibility, and media are all first-class in Swift/AppKit. It also never actually introduces "Swift," which the brief calls for.

**Why Option 2 (hidden webview) is dominated:** it keeps the embedded web runtime and IPC attack surface the migration exists to remove. Useful only as a temporary harness, never as a destination.

**How the existing Approach-A slot work is used:** treat it as a **short-term bridge** — good for proving AppKit geometry, theme translation, and panel fidelity while the Swift shell is built; *not* a place to invest further. Whether to convert cpuinfo/ramwatcher/toplist into `native_panels.rs` is an explicit checkpoint taken **after** the Phase-3 shell spike (Item 2.2), not now.

**Staging principle:** keep the Tauri app shippable the whole way. Extract the Rust core *first* (behind unchanged `invoke` shapes), stand up a *parallel* Swift app that links that core, port surfaces into it, and only delete the WKWebView once the deletion gate (below) is fully green.

### Target architecture

- **Workspace layout:** `crates/edex-core/` (Tauri-free logic) + `crates/edex-ffi/` (UniFFI `edex.udl` + bindings) + existing `src-tauri/` (interim adapter, retired last) + new `macos/eDEXNative/` (Xcode/SwiftPM app target).
- **FFI boundary:** typed shapes, not JSON strings — e.g. `EdexCore.loadSettings()/loadTheme()/sysinfoSnapshot()/fsReadDir()/spawnTerminal(opts, sink)`. PTY/terminal output arrives via a callback observer (`onOutput/onExit/onMetadata`) that may fire on Rust worker threads; Swift hops every UI mutation to `MainActor`. High-frequency terminal streaming gets its own throughput decision (1.5).
- **UI stack:** SwiftUI for lifecycle/settings/commands; AppKit `NSView` hierarchy for focus/input/draggable modal chrome; CALayer for borders/text panels/RAM grid/boot effects; Metal/CoreText where CALayer can't keep up (terminal renderer). Do **not** try to rebuild the eDEX look in pure SwiftUI layout. Concrete native type/class breakdowns are the implementation's call — this plan names *what* is replaced, not the Swift class graph.
- **Theme & fidelity:** keep the existing `src/assets/themes/*.json` as source of truth; translate CSS vars into a native theme model; reproduce geometry with a native `vh = contentHeight/100`, `vw = contentWidth/100` layout metric so frames match the original CSS proportions. `injectCSS` cannot be supported natively — built-in themes that rely on it (e.g. `cyborg-focus.json`) get explicit native override structs; custom-theme `injectCSS` is ignored with a visible settings warning (a documented breaking change).
- **Terminal:** keep PTY in Rust and add **Rust-side terminal emulation** (a mature crate such as `alacritty_terminal` — confirm in Open Questions) inside `edex-core`; Rust owns the grid/scrollback/escape-parsing and emits dirty-cell updates over the streaming boundary chosen in 1.5; Swift owns rendering, selection, clipboard, cursor, font atlas, and tabs. Avoid writing an xterm parser in Swift.

## Work Items

Size scale: **S** 1–3 days · **M** 3–7 days · **L** 1–3 weeks · **XL** 3+ weeks. Phases are ordered; within a phase, items may overlap. "Fork impact" is noted only where the Option-3 choice changes the work. "Key files" point at the JS/CSS/Rust being *replaced or referenced*; native type names are illustrative, not prescriptive.

### Phase 0 — Decide, baseline, capture fidelity
- **0.1 Commit the strategic decision.** Goal: record Option 3 as final, Approach-A slots as interim. Done when: `CONVERSION_WORKFLOW.md`, `README.md`, `CLAUDE.md`, `AGENTS.md` agree the target is Swift/AppKit + Rust core, not Tauri. Deps: none. Size: S.
- **0.2 Fidelity baseline pack.** Goal: capture screenshots, timings, layout measurements, behavior notes before anything is replaced. Done when: baseline covers boot, terminal, all left panels, filesystem, keyboard, settings modal, fuzzy finder, process list, media modal, across at least `tron`, `cyborg`, `nord`, `cyborg-focus`. Key files: `src/assets/css/*`, `src/assets/themes/*`, `src/assets/misc/{boot_log.txt,grid.json}`. Deps: running app. Size: M.
- **0.3 Acceptance matrix + continuous validation gate.** Goal: both an explicit per-subsystem deletion map *and* the running mechanism that enforces fidelity over a months-long migration. Done when: (a) a new `docs/native-migration-checklist.md` maps each JS/CSS file → native replacement → validation status; (b) documented/CI commands exist for Rust tests, Swift tests, a **screenshot-diff harness with a named tolerance metric and threshold** (this *defines* the "within tolerance" used throughout — resolving the otherwise-circular acceptance bar), startup-timing, and a terminal+panel smoke pass. Deps: 0.1, 0.2. Size: M.

### Phase 1 — Extract the Rust core (Tauri stays shippable)
- **1.1 Create `edex-core`.** Goal: move Tauri-independent logic into a reusable crate. Done when: `SysinfoService`, settings/path logic, theme + keyboard loading, and fs helpers compile in `crates/edex-core` with no `tauri` import. Key files: new `crates/edex-core/src/*`; existing `sysinfo_service.rs`, `settings.rs`, `fs_cmds.rs`. Deps: 0.1. Size: L. **Fork impact:** required for Option 3.
- **1.2 Convert Tauri commands to thin adapters.** Goal: keep the current app working while logic moves. Done when: `sysinfo_cmds.rs`, `fs_cmds.rs`, `settings.rs` are thin wrappers over `edex-core` and **JS call shapes are unchanged**. Deps: 1.1. Size: M.
- **1.3 Extract PTY manager into core + define the output observer.** Goal: make PTY usable from both Tauri and Swift *without breaking the current JS terminal*. Done when: (a) `PtyManager` no longer depends on Tauri `AppHandle`/`Emitter`/`Channel`; (b) the core defines a single output-observer abstraction (`on_output(id, bytes)` / `on_exit(id, status)` / `on_metadata(id, cwd, process)`); (c) the Tauri adapter (1.2) implements that observer by **re-wrapping bytes back into the existing `Channel<Vec<u8>>`** so `terminal.class.js:129-170` is untouched; (d) the same observer is what Swift's `PtyOutputSink` will implement. This is the highest-leverage seam — it blocks 9.1 and the Swift sink. Key files: `pty.rs` → `crates/edex-core/src/pty/*`. Deps: 1.1. Size: L. **Fork impact:** Option-3 critical.
- **1.4 Add the UniFFI crate.** Goal: expose the core to Swift. Done when: Swift can call paths/settings-load/theme-load/sysinfo-snapshot through generated bindings, and the PTY observer (1.3) is callable from Swift. Note: the **terminal-streaming** portion of the surface is gated on 1.5's throughput decision. Key files: new `crates/edex-ffi/{src/lib.rs,edex.udl}` + build scripts. Deps: 1.1, 1.3. Size: M. **Fork impact:** Option-3 only.
- **1.5 FFI throughput spike (pulled early from Phase 9).** Goal: decide *before* committing the full FFI terminal surface how high-frequency grid/dirty-cell updates cross the boundary. Done when: a measured comparison records whether UniFFI callbacks carry terminal streaming at target frame rates, or whether a **narrow C ABI for terminal byte/diff streaming only** is needed; the chosen mechanism is documented and feeds 1.4 and 9.2. Key files: prototype in `crates/edex-ffi`, throwaway Swift harness. Deps: 1.4 (binding scaffold). Size: S–M. **Fork impact:** Option-3 only; reorders the terminal FFI decision out of Phase 9.

### Phase 2 — Finish the interim slot pilots, but cap investment
- **2.1 Stabilize existing per-panel slots.** Goal: make `mod_sysinfo` + `mod_hardwareInspector` reliable interim panels. Done when: native slots match DOM within the 0.3 tolerance and survive theme reload, resize, fullscreen toggle, and panel animation. Key files: `native_panels.rs`, `bridge/native_panels.js`, the two panel classes + their CSS. Deps: Approach A. Size: M.
- **2.2 CPU/RAM/toplist interim slots — decision deferred to the post-3.1 checkpoint.** Goal: avoid over-investing in Rust/`objc`. Done when: at the checkpoint gated on 3.1's shell-viability assessment, either (a) the Swift shell is viable → **skip** these slots and convert them natively in Phase 5, or (b) it has slipped → implement them as temporary user-visible wins. This item carries **0 or three L–XL** items depending on that outcome; it is intentionally not actionable until 3.1 reports. Deps: 3.1. Size: 0 / L–XL. **Fork impact:** Option 1 builds all; Option 3 expects to skip.
- **2.3 Freeze/retire the `native_mount.rs` clock pilot.** Goal: prevent two overlay systems growing. Done when: no new work lands in `native_mount.rs`; clock stays DOM (or moves to slot infra) until its Swift replacement. Size: S.

### Phase 3 — Native Swift app shell
- **3.1 Create the macOS app target + shell-viability assessment.** Goal: a parallel Swift app linking the Rust core, plus the signal that resolves the 2.2 checkpoint. Done when: it launches a themed window, calls `EdexCore.paths()`/`loadSettings()`, and a short written assessment states whether the shell is a viable home for panels (informs 2.2). Key files: new `macos/eDEXNative/*` + FFI build config. Deps: 1.4. Size: M. **Fork impact:** Option-3 only.
- **3.2 Recreate window chrome.** Goal: match `window_chrome.rs` behavior. Done when: transparent titlebar, windowed traffic lights, fullscreen, 16:10 geometry lock when `keepGeometry`, F11 toggle. Key files: `window_chrome.rs` (reference). Deps: 3.1. Size: M.
- **3.3 Native app state model + minimal terminal/CWD interface.** Goal: replace `renderer.js` global state, and provide the *interface* Phases 7–8 depend on before the full native terminal exists. Done when: native state objects cover app/theme/settings/shortcuts and panel models, **and** a minimal terminal-tabs model exposes active-tab, CWD (polled via `pty_metadata`), and input routing — backed by the interim terminal until Phase 9 replaces the backend. Key files: `renderer.js`, `terminalTabs.class.js` (reference). Deps: 3.1. Size: L.

### Phase 4 — Theme, layout, and design primitives
- **4.1 Native theme loader.** Goal: load theme JSON into native models. Done when: the app switches built-in themes and applies colors/fonts to placeholder surfaces. Deps: 3.3. Size: M.
- **4.2 eDEX layout engine.** Goal: translate CSS `vh`/`vw` to native frames. Done when: left column, terminal shell, right-column placeholder, filesystem, and keyboard regions match current CSS proportions. Key files: `main.css`, `mod_column.css`, `main_shell.css`, `filesystem.css`, `keyboard.css`, `extra_ratios.css`. Deps: 4.1. Size: L.
- **4.3 Augmented-border primitives.** Goal: replace augmented-ui CSS with reusable CALayer/AppKit primitives (clipped corners, tick marks, opacity accents, theme outlines) used by panels/shell/modals/buttons. Key files: `augmented-ui.css` + all border CSS. Deps: 4.2. Size: L.

### Phase 5 — Native telemetry panels
- **5.1 Clock** (replace `clock.class.js`): 12/24h, per-second update, typography parity, respects `clockHours`. Deps: 4.3. Size: S.
- **5.2 Sysinfo** (replace `sysinfo.class.js`): date/uptime/type/power with same formatting + polling. Deps: 4.3, 1.4. Size: M.
- **5.3 Hardware inspector** (replace `hardwareInspector.class.js`): manufacturer/model/chassis with same trimming. Deps: 5.2. Size: S.
- **5.4 CPU panel** (replace `cpuinfo.class.js` + Smoothie): two live charts, avg counters, temp/speed/max/tasks, matching cadence/style. Deps: 4.3, 1.4. Size: L.
- **5.5 RAM watcher** (replace `ramwatcher.class.js`): shuffled 440-point grid, swap bar, equivalent update behavior. Deps: 4.3, 1.4. Size: M.
- **5.6 Toplist panel** (replace `toplist.class.js`): 2s updates; the panel itself renders in Phase 5, but its click-through **process-list modal completes after the modal manager (6.2)** — schedule the modal portion into Phase 6. Deps: 4.3; modal portion blocked by 6.2. Size: L.

### Phase 6 — Modal, audio, boot, settings
- **6.1 Audio manager** (replace `audiofx.class.js`/howler): all WAV cues with settings enable/volume/feedback-disable. Deps: 3.3. Size: M.
- **6.2 Modal manager** (replace `modal.class.js` + `native_modal.rs`): info/warning/error/custom, draggable sci-fi chrome, z-order focus, close callbacks, keyboard detach/reattach. Unblocks 5.6's process modal and 7.3/10.1. Deps: 4.3, 6.1. Size: L.
- **6.3 Settings editor** (replace the `renderer.js` settings modal): edit all settings, write `settings.json`, restart-required notices, open external config, preserve defaults. Deps: 6.2, 1.4. Size: L.
- **6.4 Shortcuts + registration** (replace global-shortcut plugin + shortcuts modal): register while focused, unregister on blur if desired, app + shell actions. Deps: 3.3. Size: M.
- **6.5 Boot screen** (replace `renderer.js` boot + `boot_screen.css`): boot-log cadence, audio cues, title/glitch animation, `nointro` behavior, transition to main UI. Deps: 4.3, 6.1. Size: L.

### Phase 7 — Filesystem, fuzzy finder, file editor
- **7.1 Filesystem display** (replace `filesystem.class.js`): follows active-tab CWD (via the 3.3 interface), grid/list modes, dotfile hiding, disk-usage bar, disk view, file icons, theme/keyboard/settings shortcuts, open-external. Key files incl. `file-icons.json`, `file-icons-match.js`, `fs_cmds.rs`. Deps: 1.4, 4.3, 3.3. Size: XL.
- **7.2 Fuzzy finder** (replace `fuzzyFinder.class.js`): search current list, keyboard nav/select/enter, no-results, writes quoted path to active terminal via the 3.3 input interface. Deps: 7.1, 3.3. Size: M.
- **7.3 Text file editor modal** (replace `FilesystemDisplay.openFile`): open/edit/save text via core, report success/failure. Deps: 6.2, 7.1. Size: M.

### Phase 8 — On-screen keyboard and input routing
- **8.1 Keyboard layout loader**: load all `kb_layouts/*.json` → key rows/labels/commands. Deps: 1.4. Size: M.
- **8.2 Keyboard view** (replace `keyboard.class.js` rendering): rows, key sizes, modifier states, caps/fn/password opacity, active/blink animations, theme color. Deps: 8.1, 4.3. Size: XL.
- **8.3 Input router** (replace JS shortcut/modifier logic): route physical + on-screen input to terminal or active modal via the 3.3 interface, incl. app and shell shortcuts. Deps: 8.2, 3.3, 6.2. Size: L.

### Phase 9 — Native terminal core and renderer (critical path)
- **9.1 Rust terminal emulation core**: PTY output (via the 1.3 observer) updates a grid + scrollback model independent of xterm.js. Key files: `crates/edex-core/src/terminal/*`. Deps: 1.3. Size: XL. **Highest-risk item — start early (parallel with Phases 3–8), test standalone.**
- **9.2 Swift terminal renderer prototype**: render the Rust grid — prompt, output, cursor, colors, resize, scrollback — at acceptable performance over the 1.5 streaming mechanism. Renderer tech (CALayer vs Metal/CoreText) is a build-time choice driven by the 1.5 measurement. Key files: `terminal.class.js`, `main_shell.css` (reference). Deps: 9.1, 1.5, 4.1. Size: XL.
- **9.3 Native terminal tabs** (replace `terminalTabs.class.js` backend): promote the 3.3 minimal tabs interface to the full native renderer — five tabs, labels, active switching, close, process-title updates, CWD propagation, welcome text. Deps: 9.2, 3.3. Size: L.
- **9.4 Clipboard/selection/paste/mouse**: copy-on-select, paste, scroll wheel + touchpad, mouse reporting, readonly helper, focus behavior. Deps: 9.2. Size: L.
- **9.5 Terminal compatibility burn-in**: shell, vim, nano, top/htop, tmux, ssh, ANSI colors, Unicode, resize, scrollback pass manual + automated tests. Deps: 9.4. Size: XL. **WKWebView deletion is blocked until this is green.**

### Phase 10 — Media and non-text files
- **10.1 Media viewer** (replace `mediaPlayer.class.js`): image/audio/video modal with play/pause, progress, time, volume, mute, fullscreen, theme-styled controls (AVKit/AVFoundation). Deps: 6.2, 7.1. Size: L.
- **10.2 PDF behavior**: preserve the v1 "deferred" message, or implement a native PDFKit viewer as an explicit enhancement. Deps: 6.2. Size: S (deferred) / M (PDFKit).

### Phase 11 — Renderer + web decommission
- **11.1 Freeze the web frontend.** New work lands only in Swift/Rust unless required to keep the transition build working. Size: S.
- **11.2 Delete + retire.** Once Phases 5–10 reach parity and the Deletion gate is green: drop the runtime dependency on `renderer.js`, remove `ui.html`/`classes`/`bridge`/CSS from the shipping bundle, retire the vendored web libs (xterm/howler/smoothie/augmented-ui; `src/package.json` becomes archival), and retire the Tauri app shell so release builds use the native target (`tauri.conf.json`, `capabilities/`, the `src-tauri` release path removed/archived). Deps: Phases 5–10, Deletion gate. Size: L. **Option-3 final step.**

## Asset disposition

**Keep as data (not web-dev runtime), ideally moved to a shared `assets/` bundle:** `themes/*.json`, `kb_layouts/*.json`, `fonts/*`, `audio/*.wav`, `misc/boot_log.txt`, `icons/file-icons.json`. **Treat as visual spec, then archive after parity is approved:** all `src/assets/css/*.css`.

## Sequencing & risks
- **Terminal is the schedule-dominating critical path.** Start 9.1 early (parallel with Phases 3–8) and resolve the FFI streaming mechanism in 1.5 *before* the renderer (9.2). Do not delete xterm until 9.5 burn-in is green.
- **The 3.3 minimal terminal/CWD interface unblocks Phases 7–8** without waiting for the full native terminal (Phase 9) — this is the seam that resolves the otherwise-backward 7→9 / 8→9 dependencies.
- **Theme fidelity:** CSS hides implicit layout tricks — rely on the 0.2 baselines, the `vh`/`vw` metric, the 0.3 screenshot-diff gate, and "CSS-as-spec until parity approved."
- **`injectCSS` breakage** is an accepted, release-noted regression for custom CSS-heavy themes.
- **Data compatibility:** keep the `~/Library/Application Support/eDEX-UI/` path and JSON shapes; new native fields must be additive; the Tauri build keeps working until 11.2.
- **AppKit threading:** Rust callbacks may arrive off-main-thread → update model queues there, mutate UI only on `MainActor`.
- **Security (a conversion win):** removing WKWebView eliminates the DOM-XSS→IPC escalation class from `Ultrareview.md`. Do not reintroduce localhost terminal sockets, webview command channels, or unscoped network APIs.

## Deletion gate — what must be true before WKWebView is removed
This is the authoritative dependency closure for Phases 5–10 (other sections reference it, not restate it): native app owns the window lifecycle · built-in theme loading works · boot screen (or accepted `nointro` path) works · terminal supports real daily use (9.5 green) · terminal tabs match current behavior · filesystem follows active-tab CWD · keyboard + shortcuts route input correctly · settings editor reads/writes current settings · modals cover info/warning/error/custom · process-list modal exists · audio cues work · media viewer works.

## Open Questions
These are the genuinely-unresolved decisions (order-changing ones have been folded into the plan body — FFI throughput → 1.5, terminal/CWD interface → 3.3, fidelity gate → 0.3, Phase-2 checkpoint → post-3.1):
- **Terminal emulation crate:** the plan assumes a mature Rust engine (`alacritty_terminal`) inside `edex-core`. Confirm it (vs. e.g. `vte`/`wezterm-term`) before 9.1 — it's the load-bearing dependency of the critical path.
- **FFI generator:** UniFFI is the recommended default (typed, multi-language). Confirm vs. `swift-bridge` in 1.4; note 1.5 may add a narrow C ABI alongside it regardless.
- **`injectCSS` themes:** is silently dropping custom-theme `injectCSS` (with a warning) acceptable, or should a small allowlist of safe overrides be supported?

## References
- Design of record: `docs/superpowers/specs/2026-05-29-native-panel-conversion-design.md`
- Phase 0/1 plan: `docs/superpowers/plans/2026-05-29-native-panel-slots-phase0-1.md`
- Phase 2 plan: `docs/superpowers/plans/2026-05-29-native-panel-slots-phase2-cpu-ram.md`
- Per-panel specs: `docs/native-migration/{clock,sysinfo,hardwareInspector,cpuinfo,ramwatcher,toplist}.spec.md`
- Broad slice map: `CONVERSION_WORKFLOW.md` · Security context: `Ultrareview.md`
- PR #11 merge: `7a81b0d` (commits `3e9100d`, `91ff30f`, `df5ed19`)
- Tauri windowing: https://docs.rs/tauri/latest/tauri/window/struct.WindowBuilder.html · tao: https://docs.rs/tao/latest/tao/window/struct.Window.html
- Swift↔Rust interop: swift-bridge https://docs.rs/swift-bridge · UniFFI https://mozilla.github.io/uniffi-rs/latest/swift/overview.html · cxx https://cxx.rs/
- Native terminal: SwiftTerm https://github.com/migueldeicaza/SwiftTerm · `alacritty_terminal` https://docs.rs/alacritty_terminal · NSHostingView https://developer.apple.com/documentation/swiftui/nshostingview

---

## Execution status (orchestrated run, 2026-06-01)

- **Phase 1 (Rust core) — DONE & validated.** `crates/edex-core` (tauri-free) + `crates/edex-ffi` (UniFFI 0.31.1) extracted. 1.3 PTY observer (`on_output/on_exit/on_metadata`) implemented; Tauri adapter re-wraps into the existing `Channel<Vec<u8>>` (JS terminal untouched). UniFFI Swift bindgen smoke-tested. Validation: edex-core/edex-ffi/Tauri all build; `cargo test`, `--test sysinfo_contract` (15/15), `cargo fmt --check`, `cargo clippy -D warnings` green. 1.5 throughput decision recorded by the gate agent.
- **Phase 2.1 + 2.3 — DONE & validated.** Native sysinfo/hwInspector slots hardened (re-ship rects on resize/fullscreen/animation/viewport/theme; seq latest-wins; zero-rect hide; listener cleanup; non-finite/negative rect + DPR sanitize; `flip_y` clamps + unit tests; async panel updates seq-guarded). `native_mount.rs` clock pilot **retired/frozen** (DOM clock unconditional; `nativeMount.activate()` removed from `renderer.js`). Tests: bridge 23/23, cargo suite + clippy/fmt green, `node --check` clean.
- **Phase 3.1 + 3.2 — DONE & validated.** `macos/eDEXNative/` SwiftPM app links the Rust core via UniFFI; `swift run --smoke-window` proved `ensureUserdata/paths/loadSettingsJson(763B)/loadThemeJson(tron)` across FFI, plus window chrome (transparent titlebar, traffic lights, fullscreen, 16:10 `keepGeometry`, F11). Caveat: packaging/signing/notarization still dev-level.
- **Item 2.2 — RESOLVED → SKIP.** Shell-viability verdict is "viable", so interim Tauri CPU/RAM/toplist slots are skipped; those panels go native in Phase 5.
- **Not committed.** All work is uncommitted in the working tree (Phase-1 adapters + Phase-2 + new `crates/` + `macos/` coexist cleanly). Next: review + commit, then Phase 4 (theme/layout/primitives) unblocks the native panel wave.
