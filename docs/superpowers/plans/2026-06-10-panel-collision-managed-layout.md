# Panel Collision-Managed Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a collision-managed native layout so fixed dashboard panels and draggable modals do not overlap, while hardware key presses visually light matching virtual keyboard keys.

**Architecture:** Add pure geometry helpers in `EdexRenderingSupport/Layout`, pure modal placement in `EdexDomainSupport/Modal`, and pure physical-key mapping in `EdexDomainSupport/KeyboardView`. Keep SwiftUI integration thin: `ContentView` consumes computed rects, `ShellState` constrains modal movement, and the existing key monitor calls the existing `KeyboardStore.pressVisual(id:)` path.

**Tech Stack:** Swift 6 / SwiftPM, SwiftUI, AppKit `NSEvent`, XCTest, repo helper `scripts/native-phase`.

---

## File Structure

- Modify `macos/eDEXNative/Sources/EdexRenderingSupport/Layout/LayoutSupport.swift`
  - Add `LayoutRect` intersection/inset helpers.
  - Rework `EdexLayoutEngine` to compute non-overlapping fixed surfaces.
  - Add fixed-surface diagnostics used by tests and modal placement.
- Modify `macos/eDEXNative/Tests/EdexLayoutTests.swift`
  - Replace old overlapping-coordinate assertions with no-overlap assertions.
  - Add windowed/fullscreen bottom-band coverage.
- Modify `macos/eDEXNative/Sources/EdexDomainSupport/Modal/ModalSupport.swift`
  - Add pure `ModalPlacement` and `ModalPlacementResult`.
  - Add `move(..., placement:)` overload or equivalent placement-aware move API.
- Modify `macos/eDEXNative/Tests/NativeModalTests.swift`
  - Add modal snap/clamp/no-overlap tests.
- Modify `macos/eDEXNative/Sources/EdexDomainSupport/KeyboardView/KeyboardViewSupport.swift`
  - Add `KeyboardPhysicalKeyMapper`.
- Modify `macos/eDEXNative/Tests/NativeKeyboardViewTests.swift`
  - Add physical key mapping tests.
- Modify `macos/eDEXNative/Sources/Support/KeyEventBridge.swift`
  - Extend `NSEvent.shortcutKey` to cover escape, return, delete/backspace, and arrows.
- Modify `macos/eDEXNative/Sources/Stores/ShellState.swift`
  - Store latest fixed reserved rects and route modal movement through placement.
  - Light physical keys before shortcut consumption.
- Modify `macos/eDEXNative/Sources/Views/ContentView.swift`
  - Publish current fixed reserved rects to `ShellState`.
  - Pass managed modal movement closure.

## Task 1: Fixed-Surface Collision Layout

**Files:**
- Modify: `macos/eDEXNative/Sources/EdexRenderingSupport/Layout/LayoutSupport.swift`
- Test: `macos/eDEXNative/Tests/EdexLayoutTests.swift`

- [ ] **Step 1: Write failing layout intersection tests**

Add helper and tests to `EdexLayoutTests.swift`:

```swift
private func visibleFixedRects(_ layout: EdexLayout) -> [(String, LayoutRect)] {
    [
        ("leftColumn", layout.leftColumn),
        ("mainShell", layout.mainShell),
        ("rightColumn", layout.rightColumn),
        ("filesystem", layout.filesystem),
        ("keyboard", layout.keyboard.frame)
    ].filter { !$0.1.isHidden }
}

private func assertNoIntersections(
    _ rects: [(String, LayoutRect)],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for i in rects.indices {
        for j in rects.indices where j > i {
            XCTAssertFalse(
                rects[i].1.intersects(rects[j].1),
                "\(rects[i].0) overlaps \(rects[j].0): \(rects[i].1) vs \(rects[j].1)",
                file: file,
                line: line
            )
        }
    }
}

func testSixteenByTenLayoutKeepsFixedSurfacesSeparate() {
    let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 1600, height: 1000))

    XCTAssertFalse(layout.filesystem.isHidden)
    XCTAssertFalse(layout.keyboard.isHidden)
    assertNoIntersections(visibleFixedRects(layout))
}

func testWindowedLayoutKeepsKeyboardFilesystemAndTerminalSeparate() {
    let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 1120, height: 700))

    XCTAssertFalse(layout.filesystem.isHidden)
    XCTAssertFalse(layout.keyboard.isHidden)
    XCTAssertFalse(layout.mainShell.intersects(layout.keyboard.frame))
    XCTAssertFalse(layout.mainShell.intersects(layout.filesystem))
    XCTAssertFalse(layout.keyboard.frame.intersects(layout.filesystem))
    assertNoIntersections(visibleFixedRects(layout))
}
```

- [ ] **Step 2: Run red test**

Run:

```bash
cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter EdexLayoutTests
```

Expected: FAIL because `LayoutRect.intersects` is missing or because current keyboard/filesystem rectangles overlap.

- [ ] **Step 3: Implement minimal layout geometry**

In `LayoutSupport.swift`, add `maxX`, `maxY`, and `intersects(_:)` to `LayoutRect`. Rework `EdexLayoutEngine.layout(in:)` so the app has three zones:

- top margin: `2.5vh`;
- bottom utility band: keyboard and filesystem side-by-side with gap;
- dashboard zone: left column, main shell, right column stop above the bottom band.

Implementation constraints:

- keep `columnWidth` close to legacy `17vw` / `17.5vw`;
- use `gap = max(8, 0.8vw)`;
- hide filesystem only for existing classic narrow ratios;
- keyboard width is `min(55.5vw, availableWidth - filesystemWidth - gaps)` when filesystem is visible;
- filesystem width is `min(32vw, availableWidth * 0.32)` when side-by-side;
- bottom band height is the max of keyboard and filesystem heights;
- main shell bottom is always above bottom band.

- [ ] **Step 4: Run green layout tests**

Run:

```bash
cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter EdexLayoutTests
```

Expected: PASS.

## Task 2: Managed Modal Placement

**Files:**
- Modify: `macos/eDEXNative/Sources/EdexDomainSupport/Modal/ModalSupport.swift`
- Test: `macos/eDEXNative/Tests/NativeModalTests.swift`

- [ ] **Step 1: Write failing modal placement tests**

Add tests:

```swift
func testModalPlacementKeepsRectInsideViewport() {
    let viewport = LayoutRect(x: 0, y: 0, width: 800, height: 600)
    let proposed = LayoutRect(x: 700, y: 540, width: 200, height: 120)

    let result = ModalPlacement.place(proposed: proposed, viewport: viewport, reserved: [], existing: [])

    XCTAssertEqual(result.rect, LayoutRect(x: 600, y: 480, width: 200, height: 120))
    XCTAssertEqual(result.status, .clamped)
}

func testModalPlacementAvoidsReservedRects() {
    let viewport = LayoutRect(x: 0, y: 0, width: 1000, height: 700)
    let terminal = LayoutRect(x: 250, y: 120, width: 500, height: 300)
    let proposed = LayoutRect(x: 350, y: 180, width: 260, height: 180)

    let result = ModalPlacement.place(proposed: proposed, viewport: viewport, reserved: [terminal], existing: [])

    XCTAssertFalse(result.rect.intersects(terminal))
}

func testManagerCanApplyPlacementAwareMove() throws {
    let manager = EdexModalManager(idGenerator: EdexModalIdGenerator(seed: 40))
    let id = manager.present(try .init(type: "info", title: "One", message: "First"))
    let viewport = LayoutRect(x: 0, y: 0, width: 800, height: 600)

    manager.move(
        id,
        dx: 500,
        dy: 500,
        placement: .init(viewport: viewport, modalSize: LayoutSize(width: 300, height: 160), reserved: [])
    )

    let modal = try XCTUnwrap(manager.modal(id: id))
    XCTAssertLessThanOrEqual(modal.offsetX, 250)
    XCTAssertLessThanOrEqual(modal.offsetY, 220)
}
```

- [ ] **Step 2: Run red modal tests**

Run:

```bash
cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter NativeModalTests
```

Expected: FAIL because `ModalPlacement` and placement-aware `move` do not exist.

- [ ] **Step 3: Implement modal placement**

In `ModalSupport.swift`, import `EdexRenderingSupport` if needed by target dependencies, or avoid the dependency by adding a small modal-local `ModalRect` type. Prefer avoiding a new target dependency if `EdexDomainSupport` currently does not depend on rendering.

Implement:

```swift
public enum ModalPlacementStatus: Equatable, Sendable {
    case placed
    case clamped
    case degraded
}

public struct ModalPlacementResult: Equatable, Sendable {
    public let rect: LayoutRect
    public let status: ModalPlacementStatus
}

public struct ModalPlacementContext: Equatable, Sendable {
    public let viewport: LayoutRect
    public let modalSize: LayoutSize
    public let reserved: [LayoutRect]
}
```

Add `ModalPlacement.place(...)` that tries candidate positions in this order:

1. proposed clamped to viewport;
2. just above each intersecting reserved rect;
3. just below each intersecting reserved rect;
4. just left of each intersecting reserved rect;
5. just right of each intersecting reserved rect;
6. viewport-clamped degraded fallback.

Add a placement-aware `move` overload that converts stored offsets to modal rect centered in viewport, places it, then converts the placed rect back to offsets.

- [ ] **Step 4: Run green modal tests**

Run:

```bash
cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter NativeModalTests
```

Expected: PASS.

## Task 3: Physical Key Mapper

**Files:**
- Modify: `macos/eDEXNative/Sources/EdexDomainSupport/KeyboardView/KeyboardViewSupport.swift`
- Modify: `macos/eDEXNative/Sources/Support/KeyEventBridge.swift`
- Test: `macos/eDEXNative/Tests/NativeKeyboardViewTests.swift`

- [ ] **Step 1: Write failing key mapper tests**

Add tests:

```swift
func testPhysicalKeyMapperFindsPrintableKeys() throws {
    let layout = try enUSLayout()

    XCTAssertEqual(
        KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .character("a")), in: layout),
        try descriptors().flatMap { $0 }.first { $0.key.name == "A" }?.id
    )
}

func testPhysicalKeyMapperFallsBackFromShiftedPrintableKeys() throws {
    let layout = try enUSLayout()

    XCTAssertEqual(
        KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [.shift], key: .character("a")), in: layout),
        try descriptors().flatMap { $0 }.first { $0.key.name == "A" }?.id
    )
}

func testPhysicalKeyMapperFindsSpecialKeys() throws {
    let layout = try enUSLayout()
    let all = try descriptors().flatMap { $0 }

    XCTAssertEqual(
        KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .special(.space)), in: layout),
        all.first { $0.role == .spacebar }?.id
    )
    XCTAssertEqual(
        KeyboardPhysicalKeyMapper.descriptorID(for: KeyCombo(modifiers: [], key: .special(.tab)), in: layout),
        all.first { $0.key.name == "TAB" }?.id
    )
}
```

- [ ] **Step 2: Run red mapper tests**

Run:

```bash
cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter NativeKeyboardViewTests
```

Expected: FAIL because `KeyboardPhysicalKeyMapper` does not exist.

- [ ] **Step 3: Implement mapper and event key coverage**

In `KeyboardViewSupport.swift`, add `KeyboardPhysicalKeyMapper.descriptorID(...)`. Flatten `KeyboardViewModel.descriptors(for:)` and map:

- `.special(.space)` -> descriptor with `.spacebar`;
- `.special(.tab)` -> name `TAB`;
- `.character(ch)` -> first descriptor whose base `key.command.lowercased()` or `key.name.lowercased()` equals `String(ch).lowercased()`;
- function keys -> descriptor with matching `F1` etc. function label;
- unknown -> nil.

In `KeyEventBridge.swift`, extend `ShortcutKey.SpecialKey` first if needed, then map AppKit key codes for return, escape, delete, and arrows. If `ShortcutKey.SpecialKey` is extended, update parser tests only where necessary.

- [ ] **Step 4: Run green mapper tests**

Run:

```bash
cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter NativeKeyboardViewTests
```

Expected: PASS.

## Task 4: SwiftUI / Store Integration

**Files:**
- Modify: `macos/eDEXNative/Sources/Stores/ShellState.swift`
- Modify: `macos/eDEXNative/Sources/Views/ContentView.swift`
- Test indirectly through previous support tests and `swift build --build-tests`.

- [ ] **Step 1: Add fixed reserved rect publication**

In `ShellState`, add a property for current fixed panel rects:

```swift
var fixedReservedRects: [LayoutRect] = []

func updateFixedReservedRects(_ rects: [LayoutRect]) {
    fixedReservedRects = rects.filter { !$0.isHidden && $0.width > 0 && $0.height > 0 }
}
```

In `ContentView.body`, after computing `layout`, publish:

```swift
.task(id: layout) {
    state.updateFixedReservedRects(layout.fixedReservedRects)
}
```

If `EdexLayout` cannot be used as a `.task(id:)` due to observation churn, use `.onChange(of: layout)` or a lightweight `layout.fixedReservedRects` identity value.

- [ ] **Step 2: Constrain modal movement**

Add a modal size helper in `ContentView` or `ShellState` matching `EdexModalChrome` modal width/height logic. Route `onMove` through:

```swift
state.moveModal(modal.id, dx: dx, dy: dy, containerSize: size, modalSize: computedSize)
```

In `ShellState.moveModal`, call `modalManager.move(..., placement:)` with `fixedReservedRects`.

- [ ] **Step 3: Light physical keys in the existing event monitor**

In `ShellState.installShortcutMonitor`, before `handleShortcutKeyCombo(combo)`, add:

```swift
if let combo,
   let layout = self.keyboard.layout,
   let id = KeyboardPhysicalKeyMapper.descriptorID(for: combo, in: layout) {
    self.keyboard.pressVisual(id: id)
}
```

Keep the existing consumed-event behavior unchanged.

- [ ] **Step 4: Build**

Run:

```bash
cd macos/eDEXNative && ~/.swiftly/bin/swift build --build-tests
```

Expected: PASS.

## Task 5: Verification

**Files:**
- No production changes expected unless verification finds a bug.

- [ ] **Step 1: Run focused Swift tests**

Run:

```bash
cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter EdexLayoutTests
cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter NativeModalTests
cd macos/eDEXNative && ~/.swiftly/bin/swift test --filter NativeKeyboardViewTests
```

Expected: all PASS.

- [ ] **Step 2: Run compile floor**

Run:

```bash
bash scripts/native-phase precheck
```

Expected: PASS.

- [ ] **Step 3: Run smoke window**

Run:

```bash
bash scripts/native-phase smoke
```

Expected: app launches and smoke output reports window chrome and FFI bootstrap OK. Before launching, terminate any previous eDEX-UI instance.

- [ ] **Step 4: Review diff**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intended files changed plus untracked screenshot folder.
