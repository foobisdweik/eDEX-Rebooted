# Slice 1b — Native Mount + Resize Bridge (placeholder, default-off)

**Branch:** `slice-1b-native-mount`
**Date:** 2026-05-23
**Status:** Design approved; implementation underway

## Context

Slice 1 landed the inert `body.native-left-active` CSS seam, a Tauri-agnostic
`SysinfoService`, and an audit table documenting `#mod_column_left` as the
rect-source contract Slice 1b must consume. Slice 1b is the AppKit-interop
half of the panel port: stand up a real sibling `NSView` inside Tauri's
`NSWindow`, drive its frame from the JS-measured rect, and toggle the seam
class on activation. No gpui content yet; that's Slice 1c.

The defining property of Slice 1b is **production boot is bit-for-bit
identical to today**. All new behavior is gated on a new
`experimentalNativePanels` settings flag that defaults to `false`. When the
flag is true, the JS panels in the left column become invisible and a
black-with-cyan-border placeholder NSView appears in their slot.

## Goal

Three deliverables that together let Slice 1c plug a gpui-driven Metal
renderer into a guaranteed-correct AppKit surface with guaranteed-correct
geometry:

1. A native `NSView` (the "mount") inserted as a sibling-above the
   WKWebView in the window's `contentView`. Created at boot, lifetime is
   the app's lifetime. Frame is `NSZeroRect` until the JS bridge ships
   the first rect.
2. A JS bridge (`src/bridge/native_mount.js`) that owns a
   `ResizeObserver` on `#mod_column_left`, coalesces measurements per
   `requestAnimationFrame`, dedupes via 0.5pt epsilon, and ships
   sequence-numbered rects to Rust via `invoke("native_mount_set_rect")`.
3. A settings flag (`experimentalNativePanels: false` by default) read at
   boot. When false, none of the above runs — the only observable diff
   is the new field in `settings.json`.

## Non-goals

- Any gpui dependency or rendering content. The mount draws solid black
  with a 1px cyan border and a small "S1B native" debug label, nothing
  else.
- Settings-modal UI to toggle the flag. Users (and CI smoke tests) edit
  `~/Library/Application Support/eDEX-UI/settings.json` directly. Slice 1c
  or later may add UI.
- Removing the JS panel classes. The slicing plan keeps them as the
  default rendering path through at least Slice 4; Slice 1b only adds a
  side path.
- Theme-color binding for the placeholder border. Fixed cyan
  (`#00FFFF`). Theme bridge is a later slice.
- Native mounts for the right column / main shell / keyboard. Left
  column only.
- Animation on the panels-to-native swap. Instant cut when the flag is
  flipped.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ Tauri NSWindow (main, fullscreen, decorations=false, bg=#000)        │
│                                                                      │
│   contentView (NSView)                                               │
│   ├── WKWebView         ← Tauri-owned, fills contentView             │
│   │     body[.native-left-active?]                                   │
│   │     ├── #mod_column_left (visibility:hidden when flag on)        │
│   │     └── #main_shell, #mod_column_right, ...                      │
│   │                                                                  │
│   └── NativeMountView   ← NEW: sibling NSView, above WKWebView       │
│         frame = AppKit-converted #mod_column_left rect               │
│         layer:  black bg, 1px cyan border, "S1B native" CATextLayer  │
└──────────────────────────────────────────────────────────────────────┘

Rust (src-tauri/src/)                JS (src/bridge/)
  native_mount.rs        ← invoke ←   native_mount.js
    NativeMountState                    ResizeObserver(#mod_column_left)
      Mutex<Option<MountHandle>>        matchMedia(resolution)
    setup() creates NSView once         rAF coalesce
    cmd: native_mount_set_rect          0.5pt epsilon dedupe
    cmd: native_mount_set_visible       seq numbers (latest-wins)
    NSWindowDidResizeNotification       reads experimentalNativePanels

  settings.rs                        renderer.js
    + experimental_native_panels       if settings.experimentalNativePanels:
      (#[serde(default)] bool)             await bridge.nativeMount.activate()
```

---

## AppKit handles (Rust side)

New module `src-tauri/src/native_mount.rs`. Single state struct managed by
Tauri's `.manage()`:

```rust
pub struct NativeMountState {
    inner: Mutex<Option<MountHandle>>,
    last_seq: AtomicU64,
}

struct MountHandle {
    view: id,             // NSView *
    bg_layer: id,         // CALayer *
    border_layer: id,     // CALayer *
    label_layer: id,      // CATextLayer *
    content_height: Mutex<f64>,
}
```

Pointer types are Objective-C `id` (i.e., `*mut Object`). The handle is
owned by Rust — we `retain` on creation and `release` on drop via a manual
`Drop` impl (or rely on `objc::rc::StrongPtr`; chosen during
implementation).

**Why `Mutex<Option<MountHandle>>`:** the option is `None` until `install()`
runs; the outer mutex serializes access from the Tauri command thread (rare)
and the main thread (always). All actual mutations of `view`, `frame`, and
layer properties happen on the main thread via `dispatch::Queue::main()` —
the mutex protects only the `Option`'s presence + the inner cached
`content_height`.

**Crate choice:** prefer `objc2` + `objc2-foundation` + `objc2-app-kit`
(modern, actively maintained, ergonomic safety wrappers). Fall back to the
older `objc` + `cocoa` pair only if `objc2` causes build-time friction with
the existing Tauri stack. Decision locked at implementation time.

`lib.rs` setup hook gains one line:

```rust
.setup(|app| {
    settings::ensure_userdata(app.handle())?;
    native_mount::install(app.handle())?;   // always installs, frame=zero
    Ok(())
})
```

`install()`:
1. Get the main `WebviewWindow` from the app handle.
2. Call `.ns_window()` → `*mut c_void` (requires `macos-private-api`
   feature, already enabled in `tauri.conf.json`).
3. Assert main-thread (Tauri's `setup` runs there; debug-build `assert!`).
4. Create `NSView initWithFrame: NSZeroRect`.
5. `setWantsLayer: YES`. Configure root layer: `backgroundColor =
   blackCGColor`, `borderWidth = 0`.
6. Create `border_layer` (CALayer): `borderColor = cyanCGColor`,
   `borderWidth = 1.0`, `backgroundColor = nil`,
   `autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable`,
   `frame = view.bounds`. `addSublayer:`.
7. Create `label_layer` (CATextLayer): `string = "S1B native"`,
   `foregroundColor = cyanCGColor`, `fontSize = 11`, `font = Menlo`,
   `frame = NSMakeRect(8, view.bounds.height - 18, 100, 14)`. Anchored
   manually on every `set_rect` update (CATextLayer doesn't autoresize
   well with text). `addSublayer:`.
8. `[[nsWindow contentView] addSubview:view
                              positioned:NSWindowAbove
                              relativeTo:webviewSubview]` where
   `webviewSubview` is `[[nsWindow contentView] subviews][0]` (Tauri's
   WKWebView is always the first/only subview at this point).
9. Register an `NSNotificationCenter` observer for
   `NSWindowDidResizeNotification` that refreshes `content_height` and
   re-applies the current frame with the updated y-flip.
10. Store the retained pointers in `NativeMountState.inner`.

If the flag is off, the view stays at `NSZeroRect` — invisible, no further
work.

---

## JS bridge module

New file `src/bridge/native_mount.js`. Hardened protocol per the
brainstorm: rAF coalesce, 0.5pt epsilon dedupe, monotonic seq numbers,
latest-wins backpressure, first-mount log.

```js
(function (globalScope) {
    if (!globalScope.__TAURI__ || !globalScope.__TAURI__.core) {
        throw new Error("bridge/native_mount.js: window.__TAURI__ must be present.");
    }
    const { invoke } = globalScope.__TAURI__.core;

    let seq = 0;
    let lastRect = null;
    let lastDpr = null;
    let rafId = 0;
    let activated = false;

    function epsilonDiffers(a, b) {
        if (!a || !b) return true;
        return Math.abs(a.x - b.x) > 0.5
            || Math.abs(a.y - b.y) > 0.5
            || Math.abs(a.width - b.width) > 0.5
            || Math.abs(a.height - b.height) > 0.5;
    }

    function measureAndShip() {
        rafId = 0;
        const el = document.getElementById("mod_column_left");
        if (!el) return;
        const r = el.getBoundingClientRect();
        const dpr = globalScope.devicePixelRatio || 1;
        const rect = { x: r.left, y: r.top, width: r.width, height: r.height };
        if (!epsilonDiffers(rect, lastRect) && dpr === lastDpr) return;
        lastRect = rect; lastDpr = dpr;
        const mySeq = ++seq;
        invoke("native_mount_set_rect", { rect, dpr, seq: mySeq })
            .catch(e => console.warn("native_mount_set_rect failed:", e));
    }

    function schedule() {
        if (rafId) return;
        rafId = requestAnimationFrame(measureAndShip);
    }

    async function activate() {
        if (activated) return;
        activated = true;
        document.body.classList.add("native-left-active");
        const target = document.getElementById("mod_column_left");
        if (!target) {
            console.error("native_mount: #mod_column_left missing; aborting activate");
            return;
        }
        new ResizeObserver(schedule).observe(target);
        if (typeof globalScope.matchMedia === "function") {
            globalScope.matchMedia("(resolution: 1dppx)")
                       .addEventListener?.("change", schedule);
        }
        globalScope.addEventListener("resize", schedule);
        schedule();
        await invoke("native_mount_set_visible", { visible: true }).catch(e => {
            console.warn("native_mount_set_visible failed:", e);
        });
        console.info("native_mount: activated");
    }

    globalScope.bridge = globalScope.bridge || {};
    globalScope.bridge.nativeMount = { activate };

    if (typeof module !== "undefined" && module.exports) {
        module.exports = globalScope.bridge.nativeMount;
    }
})(typeof window !== "undefined" ? window : globalThis);
```

`ui.html` loads it alongside the existing bridge scripts. `renderer.js`
calls `bridge.nativeMount.activate()` exactly once, after the existing
settings fetch, conditional on `settings.experimentalNativePanels === true`.

---

## Settings flag

Two places need the new field — adding only one will let the other path
deserialize-fail or skip the gate:

1. **Runtime default** — `settings.rs` `Settings` struct gains
   `#[serde(default)] pub experimental_native_panels: bool` (`Default`
   for `bool` is `false`, so unspecified fields in existing user files
   round-trip correctly). The `#[serde(rename_all = "camelCase")]`
   already on the struct (or per-field renames) makes the JSON key
   `experimentalNativePanels`. Confirm during implementation; add a
   per-field `#[serde(rename)]` if the struct lacks blanket camelCase.
2. **Bundled seed** — wherever `ensure_userdata` reads the default
   `settings.json` template. Likely a `resources/` JSON file or an
   `include_str!`'d string. Add `"experimentalNativePanels": false` to
   the JSON.

Slice 1b ships no UI for the flag.

---

## Tauri commands

Two new `#[tauri::command]` async functions in `native_mount.rs`:

```rust
#[derive(serde::Deserialize)]
pub struct WebRect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[tauri::command]
pub async fn native_mount_set_rect(
    state: tauri::State<'_, NativeMountState>,
    rect: WebRect,
    dpr: f64,
    seq: u64,
) -> Result<(), String> {
    // 1. Stale-drop: if seq < state.last_seq.load(Acquire), return Ok(()).
    // 2. CAS last_seq.
    // 3. Dispatch to main thread, compute AppKit frame, apply.
}

#[tauri::command]
pub async fn native_mount_set_visible(
    state: tauri::State<'_, NativeMountState>,
    visible: bool,
) -> Result<(), String> {
    // Toggle [view setHidden: !visible] on main thread.
}
```

Both are registered in `lib.rs`'s `invoke_handler!` list.

**Capabilities:** application-defined `#[tauri::command]` functions do
not require a Tauri 2 capability entry (only core-plugin permissions do).
No change to `src-tauri/capabilities/default.json` expected. Confirmed
during implementation; if Tauri 2 surprises us here, the spec is updated.

---

## Coordinate-system conversion

Web coordinates: top-left origin, y growing downward, units = CSS pixels.
AppKit (default `isFlipped == NO`): bottom-left origin, y growing upward,
units = points.

CSS pixels == AppKit points by definition (both are 1/96" reference units
scaled to device pixels via the screen's backing scale factor; macOS aligns
CSS pixel = AppKit point on Retina displays at 2x backing). So the only
conversion needed is the y-flip:

```
let content_h = cached_content_height; // refreshed on window resize
frame.origin.x = rect.x;
frame.origin.y = content_h - (rect.y + rect.height);
frame.size.width  = rect.width;
frame.size.height = rect.height;
```

DPR is passed and used only to set `layer.contentsScale` (and the
sublayers') so any future Metal drawable scale is correct. It is NOT
multiplied into frame dimensions.

**Alternative considered:** `layer.isGeometryFlipped = true` removes the
y-math but inverts text and any future content layers. Slice 1c will host
a CAMetalLayer + gpui content that expects standard AppKit bottom-left
geometry — flipping the layer fights that. We do the flip in Rust.

---

## Placeholder visual treatment

Recap of layer hierarchy on the `NativeMountView`:

```
view.layer (root CALayer)
    backgroundColor = blackCGColor
    │
    ├── border_layer (CALayer)
    │     borderColor   = #00FFFF CGColor
    │     borderWidth   = 1.0 pt
    │     backgroundColor = nil
    │     autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable
    │     frame = view.bounds
    │
    └── label_layer (CATextLayer)
          string = "S1B native"
          foregroundColor = #00FFFF
          fontSize = 11
          font = Menlo
          frame = (8, view.bounds.height - 18, 100, 14)
          (re-anchored on every set_rect since view height changes)
```

All three layers and the view itself come down in Slice 1c when gpui
takes over — `bg_layer` is replaced by a `CAMetalLayer` and
`border_layer` / `label_layer` are removed.

---

## Verification

1. **JS unit test** — `src/bridge/native_mount.test.js`, picked up by the
   existing `js-tests` CI job. Mocks `invoke`, `ResizeObserver`,
   `matchMedia`, `requestAnimationFrame`, `document.getElementById`,
   `globalThis.devicePixelRatio`. Cases:
   - `activate()` adds `native-left-active` to body, attaches observer,
     ships first rect with seq=1, logs success.
   - Two ResizeObserver fires within one rAF cycle invoke once
     (latest-wins coalesce).
   - Identical second measurement (within 0.5pt epsilon on every dim)
     does NOT invoke a second time.
   - 0.6pt delta on width DOES invoke.
   - DPR change with same rect DOES invoke.
   - Second `activate()` call is a no-op (idempotent).
   - Missing `#mod_column_left` → error logged, no invoke, no throw.
2. **Cargo build** — `cargo +stable tauri build --target aarch64-apple-darwin`
   green; binary runs (no AppKit-symbol link failures).
3. **Clippy** — `cargo +stable clippy ... --all-targets -- -D warnings`
   clean. objc-family crates have known noisy lints; we'll allow a
   minimum set per-call with documented justifications in
   `native_mount.rs`, not globally.
4. **Manual smoke, default-off (the primary regression gate)** —
   `cargo tauri dev`, app boots, visually identical to today, all six JS
   panels render, terminal works, theme swap works, tab spawn works.
   Console shows no `native_mount: activated` line. DevTools confirms
   `body` has no `native-left-active` class.
5. **Manual smoke, flag-on** — Edit user settings JSON to set
   `"experimentalNativePanels": true`, restart. JS panels invisible in
   left column; cyan-bordered black region in their slot with "S1B
   native" label top-left of the region; label stays top-left when the
   window is resized; border tracks `#mod_column_left`'s width on
   viewport-ratio CSS changes. Console shows the activated line.
6. **CI** — all five existing jobs (`rust-fmt`, `rust-clippy`,
   `rust-test`, `js-tests`, `tauri-build`) still pass; `js-tests` picks
   up the new bridge test automatically; `tauri-build` confirms the
   build still links cleanly with the new objc dep.

---

## What this enables

After Slice 1b merges:

- **Slice 1c** can implement `TauriHostedPlatform: gpui::Platform`, drop
  in a `CAMetalLayer` in place of `bg_layer`, and attach gpui's renderer
  to it. The view, frame management, resize tracking, and seam toggle
  are all done.
- **The default boot path is unchanged**, so users (including anyone
  pulling `master` mid-port) see no regression. The experimental
  surface is opt-in via the settings file.
- **The protocol between JS measurement and native frame application is
  locked** — Slice 1c doesn't touch `native_mount.js` or
  `native_mount_set_rect`. Only the layer hierarchy beneath
  `NativeMountView.layer` changes.

---

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| `objc2` vs `objc`/`cocoa` build friction with Tauri's existing macOS deps. | Try `objc2` first; fall back to `objc`/`cocoa` if compile errors. Both are mature; the spec doesn't depend on the choice. |
| `tauri::WebviewWindow::ns_window()` returns a raw `*mut c_void` that may not always be `NSWindow` (Tauri internals could change). | Tauri 2.x stable contract: with `macos-private-api`, this is `NSWindow *`. Sanity-check at install-time via `[ptr isKindOfClass:NSWindow.class]`. If false, log + bail (don't crash); flag stays effectively off. |
| WKWebView is not the first/only subview at install-time (Tauri internal layout change). | Find it by class name (`isKindOfClass: WKWebView`) rather than index. If not found, log + bail; flag stays off. |
| `dispatch::Queue::main().exec_async` deadlocks if called from main thread. | Use `exec_async` (non-blocking) for `set_rect` / `set_visible` (called from Tauri command thread, not main). For `install()` we assert main-thread + apply synchronously. |
| `NSWindowDidResizeNotification` arrives faster than the ResizeObserver in JS; brief geometry mismatch. | Acceptable. The window-resize observer just refreshes `content_height` and re-applies the *current* rect; the next JS measurement (which always follows window resize within one rAF) overwrites with the correct rect. Mismatch window is sub-frame. |
| New `experimental_native_panels` field deserialization breaks existing user settings files. | `#[serde(default)]` on the field makes missing-from-JSON deserialize to `false`. Existing files round-trip unchanged. CI catches the rust-test job if not. |
| Settings UI bug: someone toggles the flag in a future settings modal during a live session. | Slice 1b doesn't expose UI. Flag is read once at boot; runtime flip requires restart. Document this in the activate-success log message. |
| The JS bridge `activate()` is called twice (e.g., by buggy renderer code). | `activated` flag guards. Idempotent. Tested. |
| Border layer's `borderWidth = 1.0` looks fuzzy on non-Retina displays. | `layer.contentsScale = dpr` set on every `set_rect`. Slice 1c may revisit if it matters for gpui rendering. |

---

## Reference

- Slice 1 design: `docs/superpowers/specs/2026-05-22-slice-1-panels-prep-design.md`
- Slice 1 plan: `docs/superpowers/plans/2026-05-22-slice-1-panels-prep.md`
- Slicing plan: `~/.claude/plans/how-would-you-slice-compiled-hoare.md`
- Native port plan + decisions: `NATIVE_PORT.md`
- gpui decision: `NATIVE_PORT.md` Decisions, 2026-05-22
- Existing CSS seam: `src/assets/css/mod_column.css`
- Bridge event bus: `src/bridge/events.js`
- Settings module: `src-tauri/src/settings.rs`
- Tauri private-API NSWindow access: `tauri.conf.json` `macOSPrivateApi: true`
- Project guidance: `CLAUDE.md`, `AGENTS.md`
