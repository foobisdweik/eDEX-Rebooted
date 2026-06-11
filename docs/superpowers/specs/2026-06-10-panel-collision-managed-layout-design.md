# Panel collision-managed layout and physical key illumination (design)

**Date:** 2026-06-10
**Branch:** `master` (implementation branch to be created with `scripts/native-phase start`)
**Plan ref:** `docs/plans/full-native-swift-rust-conversion-2026-05-30.md` (release hardening / UI polish)
**Primary code:** `macos/eDEXNative/Sources/EdexRenderingSupport/Layout/LayoutSupport.swift`, `macos/eDEXNative/Sources/Views/ContentView.swift`, `macos/eDEXNative/Sources/EdexDomainSupport/Modal/ModalSupport.swift`, `macos/eDEXNative/Sources/Stores/ShellState.swift`

## Goal

Prevent overlapping bounding-box barriers across the native eDEX dashboard. The current layout lets major surfaces claim intersecting rectangles: the keyboard and filesystem share almost the same bottom band, and the terminal can extend behind them. This creates a bad visual stack and worse hit testing, because the top SwiftUI view can intercept clicks intended for another panel.

The fix is a managed layout and collision contract: fixed dashboard panels, draggable modals, and keyboard hit regions must not overlap unless a future surface is explicitly marked as a deliberate overlay. The user-confirmed requirement is that the filesystem panel and on-screen keyboard must both remain fully visible at the same time. Draggable modals are also included in the no-overlap rule.

Also add visual keyboard parity: when the user presses a hardware key, the matching on-screen virtual key lights up through the same pressed-state path used by virtual key clicks.

## Scope

In scope:

- fixed-panel collision avoidance for left telemetry, terminal shell, right column, filesystem, keyboard, and status/brand surfaces;
- managed draggable modals that snap or clamp to non-overlapping free regions;
- layout tests that reject accidental intersections;
- physical key-down visual illumination for printable keys and common special keys;
- screenshot/manual smoke checks for fullscreen and windowed layouts.

Out of scope:

- changing terminal input semantics;
- reintroducing a WebView or legacy CSS layout path;
- adding new user-facing panels;
- allowing panels to auto-hide to satisfy the main requirement. Reflow or scale first; hide only for existing unsupported narrow-ratio behavior such as the current classic filesystem fallback.

## Current Problem

`EdexLayoutEngine` computes each surface independently. At 1600x1000, existing tests lock in these overlapping bottom rectangles:

- filesystem: `x=904`, `y=690.75`, `width=688`, `height=300`
- keyboard: `x=356`, `y=680.75`, `width=888`, `height=310`

Those rectangles overlap almost completely along the center-right bottom area. `ContentView` draws filesystem before keyboard, so the keyboard wins the top layer. Because SwiftUI hit testing follows the view stack, this is not only cosmetic; it creates incorrect click barriers.

## Architecture

### 1. Layout surfaces and collision rules

Add pure layout concepts to `EdexRenderingSupport/Layout`:

```swift
public enum EdexSurfaceID: String, Sendable {
    case leftColumn, mainShell, rightColumn, filesystem, keyboard, statusRibbon
}

public struct EdexSurfaceRect: Equatable, Sendable {
    public let id: EdexSurfaceID
    public let rect: LayoutRect
    public let priority: Int
    public let canScale: Bool
    public let canReflow: Bool
}
```

The layout engine continues returning the existing named fields so `ContentView` churn stays low, but internally it builds the result from a surface list and validates intersections. Tests should cover the pure rectangle logic without loading SwiftUI.

Rules:

- fixed surfaces must not intersect when `isHidden == false`;
- `mainShell` must not sit underneath keyboard or filesystem;
- keyboard and filesystem both remain visible at supported 16:10 fullscreen and common windowed sizes;
- status/brand surfaces reserve their own small region and do not steal clicks from panels;
- if the viewport is below the supported minimum, surfaces clamp to non-negative sizes and the result is marked degraded for tests/smoke diagnostics.

### 2. Bottom-band reflow

Replace the current bottom overlap with a bottom-band allocation:

- keyboard remains centered at the bottom, sized from keyboard metrics;
- filesystem receives a separate non-overlapping dock, normally lower-right or above-right depending on available height;
- terminal shell bottom edge is capped above the reserved bottom band;
- right and left columns keep their side rails, but their inner content can compress through existing SwiftUI `VStack` behavior.

The engine should prefer stable eDEX proportions, then use bounded scale/reflow only when the windowed viewport cannot fit full-size surfaces. This avoids tiny unreadable keys while still honoring the no-overlap rule.

### 3. Managed modal placement

Modals remain draggable, but they are no longer free-floating. Modal geometry gets a pure constraint step:

```swift
public enum ModalPlacementResult: Equatable, Sendable {
    case placed(LayoutRect)
    case clamped(LayoutRect)
    case degraded(LayoutRect)
}
```

Inputs are the proposed modal rect, viewport, fixed reserved rects, and other modal rects ordered by z-index. Output is the nearest valid rect that:

- stays within the viewport;
- does not intersect fixed surfaces;
- does not intersect other modals;
- preserves the user's drag direction where possible.

If no valid full-size slot exists, the modal clamps to the largest visible non-overlapping region and returns `.degraded`. The UI may still render the modal, but tests make the degraded case explicit so unsupported window sizes do not silently pass as healthy.

The modal manager should store logical offsets as it does today, but every drag update flows through this placement step before committing the final displayed rect.

### 4. Physical key illumination

The keyboard already has `KeyboardStore.pressVisual(id:)`, and virtual clicks already pass `KeyboardKeyDescriptor.id` into that path. Physical keys should reuse it.

Add a pure mapper in `EdexDomainSupport/KeyboardView` or nearby keyboard support:

```swift
public enum KeyboardPhysicalKeyMapper {
    public static func descriptorID(
        for combo: KeyCombo,
        in layout: NativeKeyboardLayout,
        modifiers: KeyboardModifierState
    ) -> String?
}
```

Mapping order:

1. special keys first: space, tab, enter/return, backspace/delete, arrows, escape;
2. printable keys by base command or visible base label;
3. shifted printable keys fall back to their unshifted key so pressing `Shift+A` lights the `A` key, while Shift itself lights the Shift key when detectable;
4. unmapped hardware keys do nothing visually.

`ShellState`'s local `NSEvent` monitor should call this mapper on key-down before or alongside shortcut matching, then call `keyboard.pressVisual(id:)`. It must not consume the event unless existing shortcut routing already consumes it.

## Data Flow

Fixed panels:

1. `ContentView.GeometryReader` sends viewport size to `EdexLayoutEngine`.
2. `EdexLayoutEngine` computes candidate surface rects.
3. Collision logic adjusts bottom-band and terminal geometry.
4. `ContentView` renders named frames through the existing `.positioned(in:)` helper.

Modals:

1. User drags modal chrome.
2. `EdexModalChrome` emits proposed delta.
3. `ShellState` / `ModalManager` computes the proposed rect.
4. Modal placement clamps or snaps against fixed and modal rects.
5. Only the placed rect is committed to state.

Physical key illumination:

1. Local `NSEvent` key-down monitor receives event.
2. Event maps to `KeyCombo`.
3. Physical mapper resolves a keyboard descriptor ID from the loaded layout.
4. `keyboard.pressVisual(id:)` lights the matching virtual key briefly.
5. Existing shortcut handling decides whether to consume the event.

## Error Handling And Edge Cases

- No keyboard layout loaded: skip physical-key illumination, keep shortcut behavior unchanged.
- Unknown key code: skip illumination.
- Tiny viewport: keep sizes non-negative, return degraded placement where applicable, and keep tests explicit about the minimum supported layout.
- Modal larger than free space: clamp to viewport and mark degraded rather than allowing invisible hit boxes.
- Multiple modals: focused modal should attempt to move to the nearest free region without pushing hidden collisions onto lower z-index modals.
- Fullscreen/windowed toggle: recompute fixed rects and re-place modals against the new free regions.

## Testing

Add or extend Swift tests:

- `EdexLayoutTests`: assert no intersections between all visible fixed surfaces at 16:10, wide, and representative windowed sizes;
- `EdexLayoutTests`: assert keyboard and filesystem are both visible and non-overlapping at the screenshot-like windowed size;
- `EdexLayoutTests`: assert terminal does not intersect the bottom band;
- modal placement tests: valid drag, overlap snap, viewport clamp, modal-vs-modal avoidance, degraded tiny viewport;
- keyboard mapper tests: letters, numbers, space, tab, enter, backspace/delete, arrows, escape, Shift+letter fallback, unknown key ignored;
- shortcut regression: physical-key illumination does not consume non-shortcut terminal input events.

Manual/smoke checks:

- run the native app fullscreen and windowed;
- verify panel borders and interactive areas do not overlap;
- drag modals around all sides and confirm they stop or snap before colliding;
- press hardware keys and verify matching virtual keys flash.

## Verification

Before opening the PR:

```bash
bash scripts/native-phase precheck
```

For this change, a local smoke pass is recommended because layout and event-monitor behavior are visual:

```bash
bash scripts/native-phase smoke
```

Native CI will run the full gate through `scripts/native-phase verify --full`.

## Acceptance Criteria

- No fixed dashboard panels overlap at supported viewport sizes.
- Draggable modals cannot be left overlapping fixed panels or other modals.
- Filesystem and keyboard are both fully visible at the same time.
- Terminal surface does not extend behind bottom panels.
- Hardware key presses visually light the matching virtual key without changing existing shortcut consumption behavior.
- Tests cover rectangle collision, modal placement, and physical-key mapping.
