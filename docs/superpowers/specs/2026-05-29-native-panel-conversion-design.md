# Native Panel Conversion — Design Spec (Approach A)

**Status:** Approved (autonomous execution authorized by user; review gate waived).
**Scope of this spec:** the overall design for converting the six left-column WKWebView panels to native AppKit renderers, plus the detailed design of the **first cut** — Phase 0 (infrastructure) and Phase 1 (sysinfo + hardwareInspector). Later phases are sketched here and get their own spec→plan cycles.
**Implementation plan:** `docs/superpowers/plans/2026-05-29-native-panel-slots-phase0-1.md`.
**Per-panel research:** `docs/native-migration/*.spec.md`.

---

## 1. Context & goal

eDEX-UI v3 is a Tauri 2 + Rust app whose frontend is still a WKWebView payload (plain-JS classes + CSS). The migration goal is to replace the JS/CSS panels with native AppKit renderers fed by Rust. System data already lives in Rust (`SysinfoService`), so for the read-only monitor panels only the *rendering* needs to move.

The six left-column panels — clock, sysinfo, hardwareInspector, cpuinfo, ramwatcher, toplist — all instantiate into the `#mod_column_left` container (`renderer.js` ~339-344) and are all fed by `si_*` commands via the `window.si` Proxy.

**Goal of the chosen approach:** make panels convertible **one at a time**, default-off, reversible, with the other panels unaffected — the "fastest safe path."

## 2. Verified findings that shaped the design

These were established by a six-way panel analysis and spot-checked against source:

1. **The existing native-mount seam is column-granular.** `native_mount.js` toggles `body.native-left-active`, and `mod_column.css` hides the *entire* `#mod_column_left`. Converting one panel through it would blank the other five. **This is the blocker the design must solve.**
2. **The clock "pilot" is a debug placeholder** (cyan Menlo box labelled "S1B native"), not a theme-aware render. The `setClockText` plumbing is real and end-to-end, but the output is scaffolding.
3. **Only cpuinfo uses smoothie** (live graphs). ramwatcher is a dot-matrix grid + swap bar — no chart library.
4. **There is no process-kill flow anywhere.** toplist's modal is a read-only sortable viewer; `pty_kill` only closes internal PTY handles by eDEX id, not OS PIDs. Any future kill is net-new and privileged.
5. **Native views have no `:root`/CSS variables**, so theme color + fonts must be pushed into native explicitly — a shared prerequisite for every panel.
6. **Custom commands need no capability entry** — only core-plugin permissions go in `capabilities/default.json`.

## 3. Approach A — per-panel native slots

Generalize the single column NSView into a **registry of per-panel "slots."** Each slot is one NSView, layered above the WKWebView, sized to a single panel's bounding rect, hosting that panel's CALayer content. Only the converted panel's DOM is hidden (per-element, not per-column), so unconverted panels keep rendering as DOM.

Considered and rejected: a single column NSView with native subviews ("holes" for unconverted panels) — an opaque column view covers the DOM panels and forcing transparency for the holes is fragile, effectively forcing whole-column conversion. That contradicts the incremental goal.

### 3.1 Components

**Rust — new module `native_panels.rs` (additive; `native_mount.rs` clock pilot left intact):**
- `NativePanelsState` — `Mutex<HashMap<anchor, Slot>>` + per-anchor latest-wins seq guard. A `Slot` holds the NSView pointer and a `HashMap<key, CATextLayer>` (pointers as `usize`, Send+Sync, touched only on the main thread).
- `NativeThemeState` — `Mutex<ThemeSnapshot>` carrying `{r, g, b, font_main, font_main_light}`; consumed by slot renderers when they set layer text.
- Anchor layouts are **known in Rust** (no layout shipped over IPC): `mod_sysinfo` = 4 cells × {label, value}; `mod_hardwareInspector` = 3 rows × {label, value}.
- Commands (all custom, no capability changes): `native_set_theme`, `native_panel_set_rect`, `native_panel_set_visible`, `native_panel_set_text`, `native_panel_unmount`.
- Pure, unit-tested helpers: `seq_wins(prev, seq)` (latest-wins) and `flip_y(content_h, y, h)` (web→AppKit origin flip).

**JS — new bridge `bridge/native_panels.js`:** per-anchor rect shipping reusing `native_mount.js`'s rAF-coalesce / 0.5pt epsilon-dedupe / monotonic seq pattern, keyed per anchor. Surface: `mountPanel(anchorId)`, `setPanelText(anchorId, key, text)`, `unmountPanel(anchorId)`, `setTheme(payload)`, `_resetForTests()`.

**CSS — `mod_column.css`:** a `.native-panel-hidden` rule that hides one panel's DOM (`visibility:hidden` + `pointer-events:none`), distinct from the existing whole-column `body.native-left-active`.

**Settings:** master flag `experimentalNativePanels` + per-panel flags (`experimentalNativeSysinfo`, `experimentalNativeHwInspector`, …). `settings.json` is free-form JSON, so no schema change.

### 3.2 Data flow (Phase 1 decision: JS keeps formatting)

```
SysinfoService (Rust)  ──si_*──►  window.si Proxy  ──►  panel class (JS)
                                                          │ formats string
                                                          ▼
   CATextLayer  ◄── native_panel_set_text(anchor,key,text) ◄── bridge.nativePanels
        ▲                                                         │
        └── theme color/font from NativeThemeState ◄── native_set_theme (boot)

   panel element rect ──ResizeObserver/rAF──► native_panel_set_rect(anchor,rect,dpr,seq)
                                                  │ per-anchor latest-wins
                                                  ▼  Queue::main → setFrame (flip_y)
```

For Phase 1 the JS classes keep all existing formatting (uptime math, battery state, `_trimDataString`) and push finished strings. **Rationale:** the slot/theme/teardown infrastructure is what is being proven; reusing tested formatting is faster and lower-risk than porting it to Rust. Moving formatting + polling into Rust (querying `SysinfoService` directly, the eventual "no-JS" target) is deferred to a later phase once the infra is proven.

### 3.3 Lifecycle & teardown

A panel class, when its flag is on, still builds its DOM (so the element exists and can be measured) but adds `native-panel-hidden`, calls `mountPanel`, and routes its updaters to `setPanelText`. `native_panel_unmount` removes the NSView and releases layers; it is wired in Phase 0 but unused in Phase 1 (slots live until `location.reload()`, matching today's DOM panels, which leak their intervals and rely on the reload-on-theme/keyboard-change). A later phase formalizes a `NativePanel` trait with explicit `mount/update/teardown` and Rust-side polling, and migrates the clock pilot into this registry.

## 4. Scope

**In scope (Phase 0 + Phase 1):** the slot registry, theme bridge, per-panel hide CSS, and native rendering of **sysinfo** and **hardwareInspector** behind per-panel flags.

**Deferred (own spec→plan cycles):**
- **Phase 2:** cpuinfo (replace smoothie with CAShapeLayer/Core Animation scrolling graphs) and ramwatcher (native dot-grid + swap bar). Parallelizable once Phase 0 lands.
- **Phase 3:** toplist — requires a content-bearing native custom modal (`native_modal` is NSAlert-only today) and, if a kill feature is ever wanted, a net-new privileged `proc_kill` Rust command.
- Migrate the clock pilot into the slot registry; move panel formatting + polling from JS into Rust.

## 5. Error handling & edge cases

- **Missing anchor element:** `mountPanel` logs and returns if `getElementById` is null (mirrors `native_mount.js:64-66`); commands no-op if the slot is absent.
- **Stale rects:** per-anchor monotonic seq + `seq_wins` drop out-of-order updates; 0.5pt epsilon prevents jitter-driven IPC.
- **Main-thread safety:** all AppKit dereferences happen inside `Queue::main().exec_async`; `install` debug-asserts main thread.
- **Theme before mount:** `NativeThemeState` defaults to white/Menlo, so a slot rendered before the first `native_set_theme` is legible; boot pushes theme right after CSS vars are set.
- **Flags off (default):** no bridge calls, DOM path unchanged — the native path is fully opt-in.

## 6. Testing strategy

- **Rust unit tests** (in-module `#[cfg(test)]`): `seq_wins`, `flip_y`, `ThemeSnapshot` defaults/storage. AppKit view construction is verified by the manual smoke step (no UI test harness exists).
- **JS tests** (`bridge/native_panels.test.js`, Node runner): per-anchor coalesce/epsilon/seq bookkeeping, `setPanelText`/`mountPanel`/`setTheme` invoke shapes — mirroring `bridge/native_mount.test.js`.
- **Validation gate:** `node --check`, `node --test` (all bridge tests), `cargo test`, `cargo fmt --check`, `cargo clippy -- -D warnings`.
- **Manual smoke:** flags on → native sysinfo + hardwareInspector render in theme styling, values update, resize tracks per panel, the other four panels stay DOM, clean quit. Flags off → identical to pre-change DOM behavior (regression check).

## 7. Risks

1. **AppKit layout fidelity** — reproducing the multi-cell panel layout with CATextLayers must match the CSS; mitigated by reconciling against the per-panel specs + CSS during smoke.
2. **Multiple layered NSViews** — N slots over the webview must stay clipped/z-ordered within the column; start with two, validate before fanning out.
3. **Theme parity** — fonts/colors pushed once at boot; theme change triggers `location.reload()` today, which re-pushes, so live re-theming is covered for free — but verify.
4. **Scope creep into Rust formatting** — explicitly held to JS-push for Phase 1.
