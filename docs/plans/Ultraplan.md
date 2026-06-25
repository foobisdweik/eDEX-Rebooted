# HDR/EDR color-brightness platform → GPU-offloaded rendering — configured spike plan

## Context

The repo (eDEX-UI native, macOS Apple-Silicon-only) currently renders its terminal
aesthetic with a SwiftUI `Canvas` (scanlines) + `.blur` (glow) in
`EdexTerminalAesthetic.swift`, plus a do-not-regress `CAShapeLayer`+transform CPU graph.
There is **zero Metal** in the tree today, and no EDR/HDR awareness anywhere (the only
`NSScreen` use reads `backingScaleFactor` for media thumbnails).

The goal is a two-part arc: (1) a correct **XDR/HDR/EDR/SDR color-and-brightness platform**
with user-configurable luminance variables, then (2) an **optimized, GPU-offloaded render
path** for the elements that measurably benefit — without regressing the WindowServer-idle
fix the repo just landed (PR #50: a continuous render-server pan pinned WindowServer at
~46% CPU; fixed with a 10 Hz, occlusion-aware, reduced-motion-aware timer).

This document re-shapes the original 11-slice draft into a small number of **large,
coherent spikes** sized for local AI agents, each mapping to one `native-phase` branch/PR.
Confirmed product decisions (this session):
- **OS floor raised to macOS 27 / `-std=metal4.1` baseline** (Phase 0 is a real prerequisite).
- **Paper-white is a fixed, app-configured value** from `settings.json` (no per-frame slider tracking) — keeps golden-image SDR parity deterministic.
- **CRT post-FX (curvature/bloom/chromatic aberration) is in scope for the first GPU spike**, all behind settings flags.
- **Display auto-identification (draft A3) is OUT OF SCOPE.** The user selects a profile
  (generic-SDR / generic-HDR / named presets) explicitly in `settings.json`. No
  `NSScreen.localizedName`→profile matching in this plan; revisit as a future QoL item.

## The one hard constraint (read first)

**On-demand presentation is non-negotiable.** Every Metal surface introduced here MUST:
draw only on content change (or the existing 10 Hz cadence), set `isPaused`/stop its timer
otherwise, skip commits while the window is occluded (`window.occlusionState`), and honor
`SettingsSummary.reducedMotion`. **No free-running `MTKView`/`CADisplayLink` presenting a
drawable every vsync.** The reusable template already exists in
`Sources/Views/TelemetryPanels.swift` → `CpuGraphNSView` (`startPan`/`panTick`): a
`Timer` at `0.1s` on `RunLoop.main .common`, `occlusionState.contains(.visible)` gate,
timer invalidated when idle, reduced-motion snaps to final state. Mirror that exactly.

## EDR brightness model being targeted

macOS composites in **reference-white-relative extended-linear** space: SDR `1.0` maps to a
*paper-white* luminance; HDR values exceed `1.0` up to live **headroom** =
`displayPeakLuminance / paperWhiteLuminance`. Headroom is dynamic (brightness slider,
thermal, battery) → **read per-frame, never cache.**

## ⚠️ Verify-before-use (SDK symbol audit — do this in Spike 0/A/B before writing dependent code)

The draft flags several symbols as unconfirmed against the live macOS 27 SDK. The
implementing agent MUST confirm each in the active toolchain (inspect headers /
`swift package describe` / a throwaway probe) and **must not invent names**. Track each on
the four-statement honesty matrix (*syntax exists / SDK exposes host API / GPU supports /
tested*):
- Exact SwiftPM `SupportedPlatform` case for macOS 27 (`.v26`? `.v27`?) — inspect the
  PackageDescription module, do not guess.
- `metal` compiler accepts `-std=metal4.1`; `__METAL_VERSION__ >= 410` in a probe shader
  (`xcrun --sdk macosx metal -help | grep metal4.1`).
- `NSScreen.maximumExtendedDynamicRangeColorComponentValue`,
  `…maximumPotentialExtendedDynamicRangeColorComponentValue`,
  `…maximumReferenceExtendedDynamicRangeColorComponentValue` — confirm all three exist and
  are spelled thus.
- `CGColorSpace(name: .extendedLinearDisplayP3)` — confirm exact name constant.
- Extended-range pixel-format runtime gate (the `supportsExtendedRangePixelFormats`-style
  query) — confirm where it actually lives (CAMetalLayer / MTLDevice / NSScreen).
- `CAEDRMetadata` signature/availability — likely **unused** (a UI app driving its own
  linear values relies on headroom + extended-linear space, not `edrMetadata`); confirm
  before adding any dependency on it.

---

## The spikes (large-grained; A→D is the start→end arc)

### Spike 0 — Raise the toolchain floor (prerequisite, lands first, own PR)

A self-contained infra change a human verifies against CI before anything builds on it.
- Bump `macos/eDEXNative/Package.swift` (currently `.macOS(.v15)`, ~line 15) to the
  verified macOS-27 `SupportedPlatform` symbol.
- Establish the **precompiled-`.metallib` delivery path (DECIDED — no runtime shader
  compilation):** build the lib offline (`xcrun … metal -std=metal4.1` → `metallib`), add
  the **first-ever `resources:` block** to the `eDEXNative` executable target
  (e.g. `resources: [.process("Shaders/default.metallib")]`), and load via
  `device.makeDefaultLibrary(bundle:)` / `makeLibrary(URL:)`. Do **not** use
  `makeLibrary(source:options:)` at runtime. (Spike 0 only wires the build/bundle/load
  plumbing with a trivial placeholder shader; real shaders arrive in Spike C.)
- Bump `.github/workflows/native-ci.yml` / runner image to an Xcode-27-era toolchain so CI
  and local `native-phase verify --full` agree.
- **Acceptance:** repo builds + CI green on the new floor; placeholder `.metallib` loads at
  runtime; no behavior change.

### Spike A — Color/brightness platform foundation (pure logic, fully unit-tested, no render change)

All CPU-side, no GPU, no window — lands behind tests like the existing
`TerminalAestheticMetrics`/`NativeTheme` pattern. Targets `EdexRenderingSupport/Theme/`
(pure) + Rust `settings.rs` (defaults).
- **Brightness/profile model** (`EdexRenderingSupport`): per-panel luminance constants —
  paper-white (fixed, app-configured), 100%-window maintained, 10%-window maintained/peak,
  brightness floor, native gamut. Ship **generic-SDR + generic-HDR defaults + a few named
  presets** (e.g. Liquid Retina XDR, Pro Display XDR, Studio Display) as *selectable* data;
  **no auto-detection** (per decision). User selects/tunes via settings.
- **Settings variables** — add every brightness knob to `default_settings()` in
  `crates/edex-core/src/settings.rs` (free-form JSON, no schema change) and, where the UI
  needs typed access, extend the Swift `SettingsFile` Decodable in `EdexCoreClient.swift`
  and `SettingsSummary` in `ShellState.swift`. (`reducedMotion` is the existing precedent.)
- **Tonemapping operator** (`EdexRenderingSupport`, mirrors `TerminalAestheticMetrics`):
  pure, `Sendable`, sanitized inputs. Authored space = extended-linear P3 with values that
  may exceed `1.0`; define reference-white normalization and a hue-preserving soft-clip
  roll-off near a *given* headroom; **identity when headroom == 1.0** (the SDR-parity
  guarantee). Guard every `Double→Int`/non-finite per `RamwatcherSupport.safeInt`.
- **Tests** (`Tests/`): roll-off monotonicity, identity-at-headroom-1.0, floor/peak
  clamping, profile round-trip, settings parse/serialize lossless for unknown keys.
- **Acceptance:** new unit tests pass; zero rendering change; no NSScreen, no Metal.

### Spike B — Metal presentation substrate + live display probe (SDR-correct first)

Runtime Swift (needs a window; verify with `native-phase smoke`). App target + a new
service surfaced through `ShellState`.
- **Display capability probe** (Swift service, off-MainActor per repo discipline →
  `Task.detached` then assign on MainActor, like `refreshSysinfo()`): wrap the verified
  `NSScreen` EDR triad + screen-change notifications; expose **live headroom** to
  `ShellState`. AppKit reads happen on MainActor (capture, then detach), as the media
  viewer already does for `backingScaleFactor`.
- **`CAMetalLayer`-backed `NSViewRepresentable` host** implementing the on-demand
  discipline above (manual draw, `isPaused`/timer-stop, occlusion gate, reduced-motion).
  **Reuse the `CpuGraphNSView` cadence template verbatim** — do not invent a new loop.
- **EDR wiring:** `wantsExtendedDynamicRangeContent = true`, `pixelFormat = .rgba16Float`,
  `colorspace = extendedLinearDisplayP3` (all verified symbols). Read headroom per-frame
  from the probe; pass into the Spike-A tonemapper.
- **Capability fallback:** no extended-range support → `bgra8Unorm`/sRGB, same shader,
  clamp at `1.0`. The probe/runtime check still gates this even on the macOS-27 floor
  (OS floor ≠ display capability — an SDR external panel has headroom 1.0).
- **Acceptance:** the host renders a trivial test surface that is **pixel-identical to a
  reference fill when headroom == 1.0** (no SDR regression), lights up headroom on a
  capable display (GPU capture), and falls back cleanly. Feature-flagged off by default.

### Spike C — Port the terminal aesthetic to one GPU pass, incl. CRT FX (first real offload + HDR payoff)

The big payoff spike. Replaces the `Canvas`+`.blur` path with a single fragment shader,
removing the per-frame `Canvas` re-texture cost the repo's own gotcha note warns about.
- **Single fragment shader** (offline-compiled into the Spike-0 `.metallib`) reproducing
  `EdexTerminalAesthetic.swift` scanlines + glow at **parity with `TerminalAestheticMetrics`**
  (drive the shader from the same pure metrics — keep the struct as the single source of
  geometry; do not duplicate constants in MSL).
- **HDR payoff:** author accent/glow in extended-linear and let glow bloom above
  paper-white into live headroom via the Spike-A tonemapper → correct SDR everywhere,
  HDR glow on capable displays with no extra per-display code.
- **CRT post-FX (in scope):** barrel curvature, bloom, chromatic aberration folded into the
  **same pass**, each behind its own `settings.json` flag (default off → SDR-parity gate
  holds when flags are off). Curvature must keep terminal text legible/aligned; coordinate
  with the existing layout so hit-testing/overlay surfaces still register.
- **Tests:** (a) pure metrics parity (extend Spike-A tests); (b) **golden-image SDR
  compare** of the GPU scanline+glow output (all CRT flags off, headroom 1.0) against the
  current `Canvas` render — establishes the golden-image harness the repo lacks today.
- **Acceptance:** with CRT flags off + headroom 1.0, golden-image-identical to today;
  flags on produce the effects; on-demand cadence + occlusion + reduced-motion all hold
  (re-verify no WindowServer idle regression via Activity Monitor/Instruments).

### Spike D — Measure-first broadening (optional; own PR, gated on a measured win)

Do **not** pre-commit elements here. Profile with Instruments / Metal GPU capture to find
genuine wins; likely candidates: full-shell post-FX composite, `BorderSupport`
augmentation (`EdexRenderingSupport/Borders/`), boot-screen FX (`BootView.swift`). Move an
element **only** on a measured win that preserves the on-demand cadence.
- **Explicitly out of scope (do not touch):** the CPU graph (already-optimal
  `CAShapeLayer`+transform — regressing it reintroduces the ~46% WindowServer pin) and
  text (CoreText is already GPU-accelerated and correct).

### Phase E — 4.1-era feature headroom (future, no spike)

The floor unlocks 4.1-only features (cooperative tensors, FP8/block-scaling, etc.) but
**this plan consumes none of them.** If a later effect wants one, it still needs a
**runtime GPU-family capability check** (macOS 27 floor ≠ a given Apple-GPU-family
feature). Gate per-feature; fail clearly with no silent semantic fallback. Noted only so
ultraplan knows the floor-raise's stated upside is deferred, not used here.

---

## Cross-cutting requirements

- **Settings:** every brightness/CRT variable lives in `settings.json` (free-form per
  CLAUDE.md); Rust `default_settings()` is the canonical default list.
- **Discipline:** reduced-motion + occlusion gating on every Metal surface; FFI/`NSScreen`
  reads stay off the MainActor (capture on main → `Task.detached` → assign on main).
- **Anti-churn placement (Ultrareview.md):** pure brightness/tonemap logic →
  `EdexRenderingSupport`; the Metal host + display-probe service → app target / a focused
  service surfaced through `ShellState` (not new feature ownership inside `ContentView` or
  ad-hoc on `ShellState`); views emit `EdexAction`. **Do not** add a new per-feature SwiftPM
  target.
- **Honesty matrix:** for each Metal/EDR symbol, track *syntax exists / SDK exposes host
  API / GPU supports / tested* before claiming it works (see the verify-before-use audit).
- **No network channel** — terminal/render stays in-process (do not reintroduce a socket).

## Critical files

- `macos/eDEXNative/Package.swift` — platform symbol + first `resources:` block (Spike 0).
- `.github/workflows/native-ci.yml` — toolchain bump (Spike 0).
- `crates/edex-core/src/settings.rs` (`default_settings`) — brightness/CRT defaults (A/C).
- `macos/eDEXNative/Sources/EdexRenderingSupport/Theme/TerminalAestheticMetrics.swift` —
  the pure-logic pattern to mirror; stays the geometry source of truth for the shader.
- `macos/eDEXNative/Sources/EdexRenderingSupport/Theme/` — new brightness/profile model +
  tonemap operator (Spike A).
- `macos/eDEXNative/Sources/Views/EdexTerminalAesthetic.swift` — replaced by the GPU pass
  (Spike C).
- `macos/eDEXNative/Sources/Views/TelemetryPanels.swift` (`CpuGraphNSView`) — **read-only
  reference** for the on-demand cadence; do not modify.
- `macos/eDEXNative/Sources/Stores/ShellState.swift` (`refreshSysinfo` pattern,
  `SettingsSummary`) + `Sources/Services/EdexCoreClient.swift` (`SettingsFile`) — probe
  surfacing + typed settings (A/B).
- New: `macos/eDEXNative/Sources/Shaders/*.metal` (offline-compiled) + bundled
  `default.metallib`; a `CAMetalLayer` `NSViewRepresentable` host + display-probe service.

## Verification

- **Per spike:** `scripts/native-phase precheck` before PR (compile floor; auto-run by
  `pr`); `scripts/native-phase verify --full` for the full gate (CI runs the same).
- **Spike 0:** CI green on the raised floor; placeholder `.metallib` loads at runtime.
- **Spike A:** `swift test` — new tonemap/profile/settings unit tests pass; no render change.
- **Spike B:** `native-phase smoke` (needs a window) + Metal GPU capture: SDR pixel-parity
  at headroom 1.0, headroom lights up on a capable display, fallback path verified; confirm
  no WindowServer idle regression (Activity Monitor).
- **Spike C:** golden-image SDR compare (CRT flags off, headroom 1.0) == current `Canvas`;
  metrics-parity unit tests; GPU capture for HDR color correctness; re-verify idle
  WindowServer cost unchanged with the surface visible/occluded and reduced-motion on/off.
- **Spike D:** Instruments before/after showing the specific measured win; cadence
  discipline intact.

## Open items for ultraplan / the user

1. Confirm the exact SwiftPM platform symbol + CI Xcode image once the macOS-27 toolchain
   is in hand (flagged in the symbol audit).
2. "HDR-correct" verification bar: numeric tonemap unit tests + golden-image SDR parity are
   in this plan — is a reference-display **visual sign-off** also required before C ships?
   (Default assumption: numeric + golden only.)