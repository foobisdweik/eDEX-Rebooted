# Phase 8.2 Keyboard View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:test-driven-development. Steps use checkbox (`- [ ]`) tracking.

**Goal:** Replace the `keyboard(...)` key-stub placeholder in `ContentView` with a faithful native render of the on-screen keyboard, driven by the Phase 8.1 `NativeKeyboardLayout`: real rows from the loaded layout, per-key roles/sizes, the five legacy label tiers, modifier-driven label emphasis (shift/caps/fn), caps/fn key highlight, password-mode dimming, active/blink press animation, and theme color.

**Scope boundary:** This phase is *rendering + on-screen visual press feedback only*. It does **not** route key commands to the terminal/modals, handle physical-keyboard events, or implement diacritic/shortcut logic — **Phase 8.3 (input router)** owns all of that. On-screen modifier keys toggle a local *visual* state so the modifier-emphasis rendering can be exercised; that state is inert beyond display until 8.3 wires it.

**Architecture (proven per-panel recipe):**
- New pure, FFI-free `KeyboardViewSupport` module: turns a `NativeKeyboardLayout` into per-row `KeyboardKeyDescriptor`s (role, tiered labels, modifier identity) and exposes the modifier-emphasis + opacity display logic. Fully unit-testable, no SwiftUI.
- `EdexKeyboardPanel` SwiftUI view (in `Sources/Views/`) consumes descriptors + `LayoutSupport` metrics + `ShellState` visual state and renders the band.
- `ShellState` gains a `KeyboardModifierState` plus a transient pressed-key set for the active/blink animation.

**Tech Stack:** SwiftPM, XCTest, SwiftUI, existing `KeyboardSupport`, `LayoutSupport`, `ThemeSupport`.

---

## File Structure

- Create: `macos/eDEXNative/Sources/KeyboardViewSupport/KeyboardViewSupport.swift` — pure descriptor + display-logic module.
- Create: `macos/eDEXNative/Tests/NativeKeyboardViewTests.swift` — role assignment, label emphasis, modifier mapping, opacity.
- Create: `macos/eDEXNative/Sources/Views/EdexKeyboardPanel.swift` — SwiftUI keyboard band.
- Modify: `macos/eDEXNative/Package.swift` — register `KeyboardViewSupport` (target list, exe deps, exe exclude, test deps).
- Modify: `macos/eDEXNative/Sources/Stores/ShellState.swift` — add `keyboardModifiers` + `pressedKeyIDs` visual state and toggle/press helpers.
- Modify: `macos/eDEXNative/Sources/Views/ContentView.swift` — replace the `keyboard(...)` stub body (and drop `keyStub`/`keyboardKeyCount`/`keyboardKeyWidth` once unused) with `EdexKeyboardPanel`.

## Constraints

- Drive rows/keys from the actual loaded `NativeKeyboardLayout`; do **not** hardcode key counts. When `state.keyboardLayout == nil`, fall back to the existing stub grid so boot/no-layout still renders.
- Preserve the five legacy label tiers and their positions: h1 = `name` (primary), h2 = `shiftName` (top-left), h3 = `alternateName` (bottom-right), h4 = `functionName` (hidden until Fn), h5 = `alternateShiftName` (top-right).
- Modifier emphasis must match legacy CSS: Fn-on promotes `functionName`; Shift-or-CapsLock-on promotes `shiftName`; otherwise `name`.
- Password mode dims the whole band to 0.5 opacity (legacy `[data-password-mode="true"] { opacity: 0.5 }`).
- Keep `isKeyboardDetached` dimming (0.18) from the current stub.
- Special key roles by command: `" "` → spacebar, `"\r"` with non-empty name → enter, `"\r"` with empty name → enterContinuation, `iconName != nil` → icon, `cmd` beginning `ESCAPED|-- (CTRL|SHIFT|ALT|CAPSLCK|FN)` → modifier; first key of every row and the last key of the first three rows (when not already enter/space) → wide.

---

### Task 1: KeyboardViewSupport module + tests (TDD)

- [ ] Register `KeyboardViewSupport` in `Package.swift` (4 places); depend it on `KeyboardSupport`.
- [ ] Write `NativeKeyboardViewTests` covering: row/descriptor counts for en-US; role assignment (ESC/BACK wide, ENTER/enterContinuation, spacebar, arrow icons, modifier keys); `prominentLabel` under default/shift/fn; modifier identity (CAPS→capsLock, FN→fn, SHIFT→shift, CTRL→ctrl, "ALT GR"→alt); `bandOpacity` (passwordMode → 0.5).
- [ ] Run tests → RED.
- [ ] Implement `KeyboardViewSupport`; run tests → GREEN.
- [ ] Commit.

### Task 2: ShellState visual state

- [ ] Add `var keyboardModifiers = KeyboardModifierState()` and `var pressedKeyIDs: Set<String> = []`.
- [ ] Add `toggleKeyboardModifier(_:)` and `pressKeyVisual(id:)` (insert → schedule blink/clear) helpers — visual only, no routing.
- [ ] `swift test` → GREEN.
- [ ] Commit.

### Task 3: EdexKeyboardPanel view + ContentView wiring

- [ ] Build `EdexKeyboardPanel` rendering rows from descriptors, mapping role→width via `KeyboardLayoutMetrics` + vh constants, drawing tiered labels with theme accent, SVG-free icon glyphs (SF Symbols: arrow.up/left/down/right), active fill + blink animation, caps/fn highlight, password/detached opacity.
- [ ] Replace `ContentView.keyboard(...)` body with `EdexKeyboardPanel`; remove now-unused stub helpers.
- [ ] `swift test` + `swift run eDEXNative --smoke-window` → GREEN.
- [ ] Commit.

### Task 4: Final verification

- [ ] `cd macos/eDEXNative && swift test`
- [ ] `swift run eDEXNative --smoke-window`
- [ ] `cd crates/edex-ffi && cargo test && cargo fmt --check && cargo clippy --release -- -D warnings`
- [ ] `git diff --check`; update plan-of-record status + memory.md; open PR via `scripts/native-phase pr`.

## Self-Review

- Spec coverage: rows, key sizes, modifier states, caps/fn/password opacity, active/blink animation, theme color — all in Tasks 1+3. Input routing explicitly deferred to 8.3.
- Type consistency: `KeyboardViewSupport`, `KeyboardKeyDescriptor`, `KeyboardKeyRole`, `KeyboardModifierState`, `EdexKeyboardPanel`, `keyboardModifiers`, `pressedKeyIDs`.
- No hidden work: diacritics/shortcuts/terminal routing are out of scope by design, not stubbed-in.
