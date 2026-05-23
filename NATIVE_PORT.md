# Native Port — Post-Web Runtime

Long-form plan for replacing the WKWebView + JS/HTML/CSS frontend with
native Rust (and, where the macOS surface area justifies it, Swift). Work
on this branch is **surgical and slow on purpose** — each conversion lands
in its own commit, verified against `cargo tauri build`, with the old
component left visually identical until the swap is complete.

This is the planning document for the branch. It is intentionally lean.
Decisions get made as they come up and recorded in the relevant section
below.

---

## Goal

Eliminate the web stack from the runtime path. The final state has no
`window.*` calls, no `<script>` tags, no `xterm.js`, no CSS — the
terminal, panels, keyboard, and chrome are all drawn natively, and the
Rust backend talks to native UI directly instead of via Tauri `invoke`.

The Tauri 2 shell becomes a launcher (lifecycle + window + entitlements)
or is dropped entirely in favor of a pure Rust binary with a Swift
companion app, depending on what the open questions resolve to.

## Non-goals

- Cross-platform support (Windows/Linux). Still `aarch64-apple-darwin`-only.
- Visual redesign. Pixel-for-pixel parity with the current eDEX-UI look.
- Feature regression. Anything `v1` boots today must keep booting at every
  intermediate commit; no "half ported" intermediate states.

---

## Decisions

- **2026-05-22 — UI framework: gpui.** Zed's GPU UI framework, chosen
  for its Metal-backed text rendering, SwiftUI-shaped reactive model,
  and proven ability to carry a dense text UI smoothly on macOS.
  Tradeoffs accepted: documentation is thin ("read Zed's source"),
  ecosystem is young, and breaking changes still happen. The decision
  to host gpui inside an AppKit/SwiftUI shell vs. let gpui own the
  whole window is deferred to Slice 4 (terminal core) since none of
  the panel slices need that distinction yet.

## Open architectural questions

Resolve before — or at the same time as — the slice that needs them.
Q2 and Q4 are tied to Slice 4 (terminal core); Q3 only matters if the
hybrid shell from the Slice 4 sub-decision pulls Swift back in.

1. ~~**What does "native" mean for the UI layer?**~~ → **gpui** (see Decisions above).
2. **Where does the terminal renderer live?** xterm.js is ~284 KB and the
   single biggest reason WKWebView is still here. Candidates: alacritty's
   renderer (`alacritty_terminal` + `wgpu`), wezterm's term crate, or a
   wholly custom renderer.
3. **What is the Rust ↔ Swift boundary?** `swift-bridge`, `uniffi`, or
   hand-rolled `extern "C"` + a Swift `Package.swift`. Affects build
   choreography for `cargo tauri build`.
4. **Do we keep Tauri at all?** If the answer to (1) is "no WKWebView
   anywhere," Tauri's reason-to-exist on this project evaporates. The
   replacement is either `winit` + a Rust GUI, or a Swift `App` that links
   the Rust core as a static lib.

## Inventory — what is web today

### Frontend JS (4,608 LOC across `renderer.js` + `src/classes/*`)

| Module | LOC | Talks to | Notes |
|---|---|---|---|
| `renderer.js` | (boot IIFE) | everything | The orchestrator; converts last or in pieces alongside its consumers. |
| `terminal.class.js` | xterm wrapper | `pty_*` Rust commands | Single largest dependency on the web stack via xterm.js. |
| `terminalTabs.class.js` | tab controller | `Terminal` | Just landed on `master`. Tabs are now a clean seam. |
| `filesystem.class.js` | dir browser | `fs_*` Rust commands | Pure DOM; logic is small. |
| `keyboard.class.js` | on-screen kb | DOM + `Terminal` | SVG keymap rendering. |
| `modal.class.js` | dialog primitive | DOM | Used by settings/file open. |
| `clock.class.js` | wall clock | DOM | Trivial. |
| `cpuinfo.class.js`, `ramwatcher.class.js`, `sysinfo.class.js`, `toplist.class.js`, `hardwareInspector.class.js` | telemetry panels | `si_*` Rust commands | All consume the `window.si` Proxy — natural seam for FFI. |
| `mediaPlayer.class.js`, `audiofx.class.js` | audio | `howler.js` | macOS native audio = `AVAudioPlayer` / `AudioToolbox`. |
| `fuzzyFinder.class.js` | quick-open | DOM + `fs_*` | |
| `netstat.class.js` | (silenced) | — | Deferred for v0.2; ignore until then. |

### Vendored JS/CSS (~2 MB)

| Asset | Size | Replacement when removed |
|---|---|---|
| `vendor/xterm.js` | 284 KB | native terminal renderer (see open question 2) |
| `vendor/addon-ligatures.js` | 196 KB | font shaping via CoreText or `swash` |
| `vendor/addon-webgl.js` | 100 KB | native GPU surface (wgpu/Metal) |
| `vendor/addon-fit.js` | 4 KB | trivial; window/grid math in Rust |
| `vendor/howler.js` | 108 KB | `AVFoundation` (Swift) or `cpal`/`rodio` (Rust) |
| `vendor/smoothie.js` | 48 KB | native chart drawing on the GPU surface |
| `vendor/augmented-ui.css` | 256 KB | port the polygon-clip shapes to SDF shaders or pre-baked masks |
| `vendor/encom-globe.js` | 976 KB | orphan; delete unrelated to this branch |

### CSS (2,339 LOC across `src/assets/css/*`)

20 stylesheets. The visual identity is in `main.css`, `boot_screen.css`,
and the `mod_*` per-panel files. Each gets replaced when its module gets
replaced; nothing converts on its own.

### HTML (`src/ui.html`)

40 lines of script tags + a body shell. Goes away with the last JS module.

## Priorities (TBD)

Filled in once the first open question is answered. Likely starting points
once we pick a UI framework:

- Low-risk pilots: `clock`, `modal`, `audiofx` — small surface, no GPU
  contention, prove the FFI/build path before tackling the terminal.
- Highest-leverage: the terminal renderer — removes the largest vendored
  asset and unblocks deleting `xterm.css` and the WebGL addon.
- Hardest: `keyboard` (SVG rendering + theming) and the `augmented-ui`
  clip shapes that give every panel its silhouette.

## Conversion log

| Date | Module | Old → New | Commit | Notes |
|---|---|---|---|---|
| _empty_ | | | | |

## Reference

- Tauri build: `cargo +stable tauri build --target aarch64-apple-darwin`
- Dev loop: `cargo tauri dev` (only watches `src-tauri/`; reload WKWebView
  with Cmd+R for frontend edits — going away).
- Tests for current JS controllers: `node --test src/classes/*.test.js`.
- Project guidance: `CLAUDE.md`. Backlog for the old web stack: the v0.2
  notes referenced from there.
