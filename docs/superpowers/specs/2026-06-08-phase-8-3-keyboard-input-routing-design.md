# Phase 8.3 — Keyboard input routing / command emission (design)

**Date:** 2026-06-08
**Branch:** `codex/native-keyboard-input-routing`
**Plan ref:** `docs/plans/full-native-swift-rust-conversion-2026-05-30.md` (Phase 8.3)
**Legacy source of truth:** `src/classes/keyboard.class.js` (`pressKey` + the 13 `addX`/`toGreek` tables)

## Goal

Make the native on-screen keyboard (rendered in Phase 8.2) actually **resolve and emit commands**. Phase 8.2 wired taps to a visual flash only (`ShellState.pressKeyVisual`). Phase 8.3 turns a tap into the correct emitted string — honouring modifiers, dead-key diacritics, escaped toggles, and on-screen shortcut interception — and routes that string to the active sink (terminal, or a detached native text field).

## Scope constraint (why this is on-screen only)

There is **no native terminal yet** — that is Phase 9. The input sink is the existing `StubTerminalStore.sendInput(_:)`. In the legacy app, *physical* keystrokes flowed straight into xterm; `keyboard.class.js` only animated the on-screen keys for physical input. So:

- **In scope:** on-screen (tap) key resolution + emission; modifiers; full diacritic composition; escaped toggles (Caps/Fn, dead-key arming); on-screen shortcut interception; detached routing to native text fields; password-mode audio gating.
- **Out of scope (Phase 9):** physical-key → terminal *text* emission, the real PTY write/`writelr`, terminal-side interpretation of control sequences, caret-positioning in detached fields. Physical-key **shortcuts** already work via the existing `ShellState` NSEvent monitor and are left as-is (only refactored to share the matcher).

User-confirmed scope calls: **full diacritic port now**, **on-screen modifier-combo shortcut interception now**, **detached routing now**.

## Architecture

Three new pure (FFI-free) units in `Sources/EdexDomainSupport/Keyboard/`, plus a small addition to `ShortcutsSupport`, plus wiring in `ShellState`/`ContentView`/`EdexKeyboardPanel`. Everything load-bearing is unit-testable without AppKit.

### 1. `KeyboardDiacritics.swift` — dead-key tables (pure data)

```swift
public enum DeadKey: String, CaseIterable, Sendable {
    case circumflex, trema, acute, grave, caron, bar, breve,
         tilde, macron, cedilla, overring, greek, iotaSubscript
}

public enum KeyboardDiacritics {
    /// Compose one base character under an armed dead key. Returns the base
    /// unchanged when the table has no mapping (legacy `default: return char`).
    public static func compose(_ deadKey: DeadKey, _ base: String) -> String
}
```

All 13 legacy tables (`addCircum`, `addTrema`, `addAcute`, `addGrave`, `addCaron`, `addBar`, `addBreve`, `addTilde`, `addMacron`, `addCedilla`, `addOverring`, `toGreek`, `addIotasub`) ported **verbatim** as `[String: String]` literals (including the superscript/subscript number rows on circumflex/caron and the multi-codepoint combining entries). Kept in their own file because it is ~700 lines of data and should not bloat the resolver.

### 2. `KeyboardCommandResolver.swift` — the heart (pure logic)

Maps the legacy `pressKey` decision tree onto typed outcomes. The pure resolver takes the pressed key, the current modifier state, the armed dead key, and the loaded shortcuts; it returns one outcome. State mutation (clearing the dead key, toggling Caps/Fn, auto-releasing transient modifiers, firing the shortcut, sending text) is applied by `ShellState`.

```swift
public enum KeyboardOutcome: Equatable, Sendable {
    case shortcut(ShortcutMatch)   // an on-screen modifier combo matched shortcuts.json
    case emit(String)              // text to send to the active sink
    case armDeadKey(DeadKey)       // a diacritic dead key was pressed; compose the next key
    case setCapsLock(Bool)         // escaped "CAPSLCK: ON/OFF"
    case setFn(Bool)               // escaped "FN: ON/OFF"
    case none                      // nothing to emit (e.g. an unmapped escaped cmd)
}

public enum KeyboardCommandResolver {
    public static func resolve(
        key: NativeKeyboardKey,
        modifiers: KeyboardModifierState,
        armedDeadKey: DeadKey?,
        shortcuts: EdexShortcutsDocument?
    ) -> KeyboardOutcome
}
```

Decision order (faithful to `pressKey`):

1. **Shortcut interception.** If any of Ctrl/Alt/Shift is engaged, build a `KeyCombo` from those modifiers + the key's **base** command (legacy matches the base `data-cmd`, before modifier selection), and ask `shortcuts.match(combo:)`. On a hit → `.shortcut(match)` and stop. (Legacy gate is `shortcutsCat.length > 1`, which is true for *any* single modifier since the shortest category string is "Alt" — so the real gate is "≥1 transient modifier held", and TAB_X = Ctrl+1…5 works.)
2. **Modifier command selection** (legacy 419–424, in order): `shiftCommand` when Shift **or** Caps and a `shiftCommand` exists; then `capsLockCommand` when Caps; then `controlCommand` when Ctrl; then `alternateCommand` when Alt; then `alternateShiftCommand` when Alt+Shift; then `functionCommand` when Fn.
3. **Dead-key composition.** If a dead key is armed and the selected command is a single base char, compose it via `KeyboardDiacritics.compose`. (The resolver consumes the armed key; `ShellState` clears it.)
4. **Escaped command classification.** If the (possibly composed) command begins with `ESCAPED|-- `: `CAPSLCK: ON/OFF` → `.setCapsLock`, `FN: ON/OFF` → `.setFn`, a dead-key name → `.armDeadKey`, anything else → `.none`. (CTRL/SHIFT/ALT/ICON escapes never reach here — modifier keys go through `onToggleModifier`, icon keys carry real commands.)
5. **Emit.** Otherwise → `.emit(command)` (enter's `\r` and every other resolved string are emitted verbatim; terminal-side `writelr` semantics are Phase 9).

### 3. `KeyboardDetachedEditor.swift` — detached field editing (pure)

When the keyboard is detached (a keyboard-owning modal is open — fuzzy finder / text editor / settings), an emitted string edits the focused field instead of the terminal. Pure transform mirroring the legacy `document.activeElement` branch, reduced to the realistic on-screen cases:

```swift
public enum KeyboardFieldEdit: Equatable, Sendable {
    case replace(String)   // new field text
    case submit            // enter pressed (legacy "change"/"enter" event)
    case ignore            // control sequence with no field meaning
}

public enum KeyboardDetachedEditor {
    public static func apply(command: String, to text: String) -> KeyboardFieldEdit
}
```

Rules: empty command (Backspace/Escape key) → drop last char; `\r`/`\n` → `.submit`; a command whose first scalar is a C0 control char → `.ignore`; otherwise append. **Caret-move (legacy `OD`/`OC` on `selectionStart`) is deferred** — SwiftUI plain `TextField` exposes no caret seam without an AppKit escape hatch, and on-screen arrow-in-searchbox is an edge of an edge; arrows degrade to `.ignore` in detached mode. Noted as a known limitation.

### 4. `ShortcutsSupport.swift` — shared matcher (de-dup)

Extract the matching currently inlined in `ShellState.handleShortcutKeyEvent` into a pure method so both the NSEvent path and the on-screen path use one implementation:

```swift
public enum ShortcutMatch: Equatable, Sendable {
    case app(AppShortcutAction, tabIndex: Int?)
    case shell(action: String, linebreak: Bool)
}

extension EdexShortcutsDocument {
    /// Match a combo against enabled entries (regular first, then TAB_X expansion).
    public func match(_ combo: KeyCombo) -> ShortcutMatch?
}
```

`handleShortcutKeyEvent` is refactored to call `match` and dispatch; behaviour is unchanged.

## Wiring (`ShellState` + views)

- **`KeyboardStore`** gains `armedDeadKey: DeadKey?` (compose state) and a `passwordMode` accessor already on `KeyboardModifierState`.
- **`onPressKey` now passes the descriptor**, not just the id: `ContentView` → `EdexKeyboardPanel.onPressKey: (KeyboardKeyDescriptor) -> Void` → `state.pressKey(_:)`. The id is still used for the visual flash.
- **`ShellState.pressKey(_ descriptor:)`** (replaces the visual-only call site):
  1. flash the key (`keyboard.pressVisual(id:)`), as today;
  2. `let outcome = KeyboardCommandResolver.resolve(key: descriptor.key, modifiers:, armedDeadKey:, shortcuts:)`;
  3. apply: `.setCapsLock/.setFn` → set modifier; `.armDeadKey` → store it; `.shortcut` → `dispatchShortcutMatch`; `.emit` → route to sink; `.none` → nothing;
  4. **clear the armed dead key** unless the outcome itself armed one;
  5. **auto-release transient modifiers** (Shift/Ctrl/Alt) after any non-modifier press (on-screen taps can't press-and-hold; one-shot mirrors "modifier + next key"). Caps/Fn persist (sticky latch, legacy behaviour);
  6. **audio:** play `.stdin` on a normal emit and `.granted` on an enter (`\r`/`\n`) emit, both gated off when `passwordMode` is on (legacy `passwordMode == "false"` checks).
- **Sink routing:** if `modalManager.isKeyboardDetached` and an active detached text target exists, apply `KeyboardDetachedEditor` to that field's binding (fuzzy query when the fuzzy modal is open; editor text when the text editor is open; `.submit` triggers the field's submit action). Otherwise `handle(.keyboardInput(text))` → terminal.
- **Password mode:** `dispatchAppShortcut(.kbPassmode, …)` toggles `keyboard.modifiers.passwordMode` (replaces the legacy `togglePasswordMode`), driving the existing band-dim and the audio gate.

## Testing

New `Tests/NativeKeyboardInputTests.swift` (resolver + diacritics + detached) and matcher coverage added to the shortcuts tests:

- modifier selection: plain, Shift, Caps, Ctrl, Alt, Alt+Shift, Fn, and the Caps-uses-shiftCommand rule;
- diacritics: a representative entry from **every** one of the 13 tables, the superscript/subscript number rows, and the `default: return char` passthrough for an unmapped base;
- dead-key flow: arm → next key composes → armed key cleared; arming twice replaces;
- escaped classification: Caps ON/OFF, Fn ON/OFF, each dead-key name, unmapped escaped → `.none`;
- shortcut interception: single- and multi-modifier hits, TAB_X expansion, no-modifier never intercepts;
- detached editor: append, backspace-empties, submit on enter, control-seq ignore;
- transient-modifier auto-release and Caps/Fn persistence (via the resolver-level expectations; the store step is exercised through the pure outcomes).

## Verification

`bash scripts/native-phase precheck` before the PR (compile floor). The PR triggers `verify --full` in CI (Rust + Swift build/test/fmt/clippy). `smoke` is optional (no FFI/bootstrap change here, but the keyboard now emits — a manual smoke is reasonable).

## Out of scope / deferred (tracked)

- Physical-key → terminal text emission and real `writelr` (Phase 9).
- Detached caret movement (`OD`/`OC`); arrows degrade to `.ignore` in fields.
- Multi-touch / press-and-hold key repeat (legacy `holdTimeout`/`holdInterval`); on-screen taps are single-shot in native.
