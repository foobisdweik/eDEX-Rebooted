import XCTest
@testable import EdexDomainSupport

final class NativeKeyboardInputTests: XCTestCase {
    // MARK: - Helpers

    private func key(
        _ command: String,
        name: String = "k",
        shiftCommand: String? = nil,
        controlCommand: String? = nil,
        alternateCommand: String? = nil,
        alternateShiftCommand: String? = nil,
        functionCommand: String? = nil,
        capsLockCommand: String? = nil
    ) -> NativeKeyboardKey {
        NativeKeyboardKey(
            name: name,
            command: command,
            shiftCommand: shiftCommand,
            controlCommand: controlCommand,
            alternateCommand: alternateCommand,
            alternateShiftCommand: alternateShiftCommand,
            functionCommand: functionCommand,
            capsLockCommand: capsLockCommand
        )
    }

    private func mods(
        shift: Bool = false, capsLock: Bool = false, alt: Bool = false,
        fn: Bool = false, ctrl: Bool = false
    ) -> KeyboardModifierState {
        KeyboardModifierState(shift: shift, capsLock: capsLock, alt: alt, fn: fn, ctrl: ctrl)
    }

    private func resolve(
        _ key: NativeKeyboardKey,
        _ modifiers: KeyboardModifierState,
        armed: DeadKey? = nil,
        shortcuts: EdexShortcutsDocument? = nil
    ) -> KeyboardOutcome {
        KeyboardCommandResolver.resolve(
            key: key, modifiers: modifiers, armedDeadKey: armed, shortcuts: shortcuts
        )
    }

    private func shortcutsDoc() throws -> EdexShortcutsDocument {
        try EdexShortcutsDocument(jsonString: """
        [
          {"type":"app","trigger":"Ctrl+Shift+S","action":"SETTINGS","enabled":true},
          {"type":"app","trigger":"Ctrl+X","action":"TAB_X","enabled":true},
          {"type":"app","trigger":"Ctrl+P","action":"FUZZY_SEARCH","enabled":false},
          {"type":"shell","trigger":"Ctrl+G","action":"git status","enabled":true,"linebreak":true}
        ]
        """)
    }

    // MARK: - Diacritics: one entry per table + special rows + passthrough

    func testDiacriticTablesEachCompose() {
        XCTAssertEqual(KeyboardDiacritics.compose(.circumflex, "a"), "â")
        XCTAssertEqual(KeyboardDiacritics.compose(.trema, "a"), "ä")
        XCTAssertEqual(KeyboardDiacritics.compose(.acute, "e"), "é")
        XCTAssertEqual(KeyboardDiacritics.compose(.grave, "a"), "à")
        XCTAssertEqual(KeyboardDiacritics.compose(.caron, "c"), "č")
        XCTAssertEqual(KeyboardDiacritics.compose(.bar, "d"), "đ")
        XCTAssertEqual(KeyboardDiacritics.compose(.breve, "g"), "ğ")
        XCTAssertEqual(KeyboardDiacritics.compose(.tilde, "n"), "ñ")
        XCTAssertEqual(KeyboardDiacritics.compose(.macron, "a"), "ā")
        XCTAssertEqual(KeyboardDiacritics.compose(.cedilla, "c"), "ç")
        XCTAssertEqual(KeyboardDiacritics.compose(.overring, "a"), "å")
        XCTAssertEqual(KeyboardDiacritics.compose(.greek, "b"), "β")
        XCTAssertEqual(KeyboardDiacritics.compose(.iotaSubscript, "a"), "ą")
    }

    func testDiacriticSuperscriptAndSubscriptNumbers() {
        XCTAssertEqual(KeyboardDiacritics.compose(.circumflex, "2"), "²")
        XCTAssertEqual(KeyboardDiacritics.compose(.caron, "2"), "₂")
    }

    func testDiacriticUppercaseAndPassthrough() {
        XCTAssertEqual(KeyboardDiacritics.compose(.circumflex, "A"), "Â")
        // No mapping → base char returned unchanged (legacy `default: return char`).
        XCTAssertEqual(KeyboardDiacritics.compose(.circumflex, "q"), "q")
        XCTAssertEqual(KeyboardDiacritics.compose(.overring, "x"), "x")
    }

    // MARK: - Modifier command selection (legacy pressKey 419-424)

    func testPlainEmitsBaseCommand() {
        XCTAssertEqual(resolve(key("a", shiftCommand: "A"), mods()), .emit("a"))
    }

    func testShiftSelectsShiftCommand() {
        XCTAssertEqual(resolve(key("a", shiftCommand: "A"), mods(shift: true)), .emit("A"))
    }

    func testCapsLockUsesShiftCommandForLetters() {
        XCTAssertEqual(resolve(key("a", shiftCommand: "A"), mods(capsLock: true)), .emit("A"))
    }

    func testCapsLockCommandOverridesShift() {
        let k = key("a", shiftCommand: "A", capsLockCommand: "Ä")
        XCTAssertEqual(resolve(k, mods(capsLock: true)), .emit("Ä"))
    }

    func testControlSelectsControlCommand() {
        XCTAssertEqual(resolve(key("a", controlCommand: "\u{0001}"), mods(ctrl: true)), .emit("\u{0001}"))
    }

    func testAltSelectsAlternateCommand() {
        XCTAssertEqual(resolve(key("a", alternateCommand: "æ"), mods(alt: true)), .emit("æ"))
    }

    func testAltShiftSelectsAlternateShiftCommand() {
        let k = key("a", shiftCommand: "A", alternateCommand: "æ", alternateShiftCommand: "Æ")
        XCTAssertEqual(resolve(k, mods(shift: true, alt: true)), .emit("Æ"))
    }

    func testFnSelectsFunctionCommand() {
        XCTAssertEqual(resolve(key("a", functionCommand: "F"), mods(fn: true)), .emit("F"))
    }

    // MARK: - Escaped command classification

    func testEscapedCapsLockToggles() {
        XCTAssertEqual(resolve(key("ESCAPED|-- CAPSLCK: ON"), mods()), .setCapsLock(true))
        XCTAssertEqual(resolve(key("ESCAPED|-- CAPSLCK: OFF"), mods()), .setCapsLock(false))
    }

    func testEscapedFnToggles() {
        XCTAssertEqual(resolve(key("ESCAPED|-- FN: ON"), mods()), .setFn(true))
        XCTAssertEqual(resolve(key("ESCAPED|-- FN: OFF"), mods()), .setFn(false))
    }

    func testEscapedDeadKeyArms() {
        XCTAssertEqual(resolve(key("ESCAPED|-- CIRCUM"), mods()), .armDeadKey(.circumflex))
        XCTAssertEqual(resolve(key("ESCAPED|-- GREEK"), mods()), .armDeadKey(.greek))
        XCTAssertEqual(resolve(key("ESCAPED|-- IOTASUB"), mods()), .armDeadKey(.iotaSubscript))
    }

    func testUnknownEscapedCommandIsNone() {
        XCTAssertEqual(resolve(key("ESCAPED|-- WAT"), mods()), .none)
    }

    // MARK: - Dead-key composition flow

    func testArmedDeadKeyComposesNextKey() {
        XCTAssertEqual(resolve(key("a"), mods(), armed: .circumflex), .emit("â"))
    }

    func testArmedDeadKeyComposesShiftedSelection() {
        // Shift selects "A", then circumflex composes "Â".
        XCTAssertEqual(resolve(key("a", shiftCommand: "A"), mods(shift: true), armed: .circumflex), .emit("Â"))
    }

    func testArmedDeadKeyPassthroughWhenNoMapping() {
        XCTAssertEqual(resolve(key("q"), mods(), armed: .circumflex), .emit("q"))
    }

    // MARK: - On-screen shortcut interception

    func testCtrlShiftCharFiresAppShortcut() throws {
        let doc = try shortcutsDoc()
        let outcome = resolve(key("s"), mods(shift: true, ctrl: true), shortcuts: doc)
        XCTAssertEqual(outcome, .shortcut(.app(.settings, tabIndex: nil)))
    }

    func testCtrlDigitFiresTabTemplate() throws {
        let doc = try shortcutsDoc()
        let outcome = resolve(key("1"), mods(ctrl: true), shortcuts: doc)
        XCTAssertEqual(outcome, .shortcut(.app(.tabTemplate, tabIndex: 0)))
    }

    func testShellShortcutFires() throws {
        let doc = try shortcutsDoc()
        let outcome = resolve(key("g"), mods(ctrl: true), shortcuts: doc)
        XCTAssertEqual(outcome, .shortcut(.shell(action: "git status", linebreak: true)))
    }

    func testAppShortcutPreservesArmedDeadKeyShellShortcutClearsIt() throws {
        let doc = try shortcutsDoc()
        let app = resolve(key("s"), mods(shift: true, ctrl: true), armed: .circumflex, shortcuts: doc)
        let shell = resolve(key("g"), mods(ctrl: true), armed: .circumflex, shortcuts: doc)
        XCTAssertTrue(app.preservesArmedDeadKey)
        XCTAssertFalse(shell.preservesArmedDeadKey)
    }

    func testDisabledShortcutDoesNotFire() throws {
        let doc = try shortcutsDoc()
        // FUZZY_SEARCH (Ctrl+P) is disabled → should emit the char, not fire.
        XCTAssertEqual(resolve(key("p"), mods(ctrl: true), shortcuts: doc), .emit("p"))
    }

    func testNoModifiersNeverIntercepts() throws {
        let doc = try shortcutsDoc()
        XCTAssertEqual(resolve(key("s"), mods(), shortcuts: doc), .emit("s"))
    }

    func testCapsAloneNeverIntercepts() throws {
        let doc = try shortcutsDoc()
        // Caps is not a transient modifier; "s" should select shift form and emit.
        XCTAssertEqual(resolve(key("s", shiftCommand: "S"), mods(capsLock: true), shortcuts: doc), .emit("S"))
    }

    // MARK: - Shared shortcut matcher

    func testDocumentMatchAppCombo() throws {
        let doc = try shortcutsDoc()
        let combo = KeyCombo(modifiers: [.control, .shift], key: .character("s"))
        XCTAssertEqual(doc.match(combo), .app(.settings, tabIndex: nil))
    }

    func testDocumentMatchTabExpansion() throws {
        let doc = try shortcutsDoc()
        let combo = KeyCombo(modifiers: [.control], key: .character("3"))
        XCTAssertEqual(doc.match(combo), .app(.tabTemplate, tabIndex: 2))
    }

    func testDocumentMatchShell() throws {
        let doc = try shortcutsDoc()
        let combo = KeyCombo(modifiers: [.control], key: .character("g"))
        XCTAssertEqual(doc.match(combo), .shell(action: "git status", linebreak: true))
    }

    func testDocumentMatchMiss() throws {
        let doc = try shortcutsDoc()
        let combo = KeyCombo(modifiers: [.command], key: .character("z"))
        XCTAssertNil(doc.match(combo))
    }

    // MARK: - Detached field editing

    func testDetachedAppendsPrintable() {
        XCTAssertEqual(KeyboardDetachedEditor.apply(command: "a", to: "fo"), .replace("foa"))
    }

    func testDetachedBackspaceDropsLastChar() {
        XCTAssertEqual(KeyboardDetachedEditor.apply(command: "", to: "foo"), .replace("fo"))
    }

    func testDetachedBackspaceOnEmptyStaysEmpty() {
        XCTAssertEqual(KeyboardDetachedEditor.apply(command: "", to: ""), .replace(""))
    }

    func testDetachedEnterSubmits() {
        XCTAssertEqual(KeyboardDetachedEditor.apply(command: "\r", to: "foo"), .submit)
        XCTAssertEqual(KeyboardDetachedEditor.apply(command: "\n", to: "foo"), .submit)
    }

    func testDetachedControlSequenceIgnored() {
        // A control sequence (e.g. Ctrl+C \u{0003}) has no field meaning.
        XCTAssertEqual(KeyboardDetachedEditor.apply(command: "\u{0003}", to: "foo"), .ignore)
    }

    // MARK: - Review fixes

    /// The legacy `toGreek` table mapped uppercase "A" → "α" and had no lowercase
    /// "a" entry — a latent typo. Lowercase "a" should compose to lowercase alpha.
    func testGreekLowercaseAComposes() {
        XCTAssertEqual(KeyboardDiacritics.compose(.greek, "a"), "α")
    }

    /// The on-screen BACK key emits `\u{8}` (backspace). In a detached field it
    /// must delete the last character, not be ignored as a control sequence.
    func testDetachedBackspaceKeyDeletes() {
        XCTAssertEqual(KeyboardDetachedEditor.apply(command: "\u{8}", to: "foo"), .replace("fo"))
        XCTAssertEqual(KeyboardDetachedEditor.apply(command: "\u{7f}", to: "foo"), .replace("fo"))
    }

    func testDetachedInsertUsesCaretPosition() {
        let state = KeyboardDetachedEditor.State(text: "🇺🇸foo", caret: 4)

        XCTAssertEqual(
            KeyboardDetachedEditor.apply(command: "x", to: state),
            .replace(.init(text: "🇺🇸xfoo", caret: 5))
        )
    }

    func testDetachedArrowsMoveCaretWithoutChangingText() {
        let state = KeyboardDetachedEditor.State(text: "🇺🇸foo", caret: 4)

        XCTAssertEqual(
            KeyboardDetachedEditor.apply(command: "\u{001B}OD", to: state),
            .replace(.init(text: "🇺🇸foo", caret: 0))
        )
        XCTAssertEqual(
            KeyboardDetachedEditor.apply(command: "\u{001B}OC", to: state),
            .replace(.init(text: "🇺🇸foo", caret: 5))
        )
    }

    func testDetachedUpArrowKeepsColumnAcrossLines() {
        // "abc\ndef", caret after 'd' (column 1 on line 2).
        let state = KeyboardDetachedEditor.State(text: "abc\ndef", caret: 5)

        XCTAssertEqual(
            KeyboardDetachedEditor.apply(command: "\u{001B}[A", to: state),
            .replace(.init(text: "abc\ndef", caret: 1))
        )
        XCTAssertEqual(
            KeyboardDetachedEditor.apply(command: "\u{001B}OA", to: state),
            .replace(.init(text: "abc\ndef", caret: 1))
        )
    }

    func testDetachedDownArrowKeepsColumnAcrossLines() {
        let state = KeyboardDetachedEditor.State(text: "abc\ndef", caret: 1)

        XCTAssertEqual(
            KeyboardDetachedEditor.apply(command: "\u{001B}[B", to: state),
            .replace(.init(text: "abc\ndef", caret: 5))
        )
        XCTAssertEqual(
            KeyboardDetachedEditor.apply(command: "\u{001B}OB", to: state),
            .replace(.init(text: "abc\ndef", caret: 5))
        )
    }

    func testDetachedVerticalArrowsClampToShorterLine() {
        // Up from column 3 of "wxyz" lands at the end of "ab".
        XCTAssertEqual(
            KeyboardDetachedEditor.apply(
                command: "\u{001B}[A",
                to: .init(text: "ab\nwxyz", caret: 6)
            ),
            .replace(.init(text: "ab\nwxyz", caret: 2))
        )
        // Down from column 4 of "wxyz" lands at the end of "ab".
        XCTAssertEqual(
            KeyboardDetachedEditor.apply(
                command: "\u{001B}[B",
                to: .init(text: "wxyz\nab", caret: 4)
            ),
            .replace(.init(text: "wxyz\nab", caret: 7))
        )
    }

    func testDetachedVerticalArrowsAtEdgesSnapToTextBounds() {
        // Up on the first line moves to the start (NSTextView behavior)…
        XCTAssertEqual(
            KeyboardDetachedEditor.apply(
                command: "\u{001B}[A",
                to: .init(text: "abc\ndef", caret: 2)
            ),
            .replace(.init(text: "abc\ndef", caret: 0))
        )
        // …and down on the last line moves to the end.
        XCTAssertEqual(
            KeyboardDetachedEditor.apply(
                command: "\u{001B}[B",
                to: .init(text: "abc\ndef", caret: 5)
            ),
            .replace(.init(text: "abc\ndef", caret: 7))
        )
    }

    func testDetachedVerticalArrowsCountColumnsInCharactersNotUTF16() {
        // Line 1 is "🇺🇸x" (2 characters, 5 UTF-16 units). Down from after 'x'
        // (column 2) lands after 'b' (column 2 of "ab"), not mid-scalar.
        let state = KeyboardDetachedEditor.State(text: "🇺🇸x\nab", caret: 5)

        XCTAssertEqual(
            KeyboardDetachedEditor.apply(command: "\u{001B}[B", to: state),
            .replace(.init(text: "🇺🇸x\nab", caret: 8))
        )
    }

    func testDetachedVerticalDeltaRecognizesArrowCommands() {
        XCTAssertEqual(KeyboardDetachedEditor.verticalDelta(command: "\u{001B}[A"), -1)
        XCTAssertEqual(KeyboardDetachedEditor.verticalDelta(command: "\u{001B}OA"), -1)
        XCTAssertEqual(KeyboardDetachedEditor.verticalDelta(command: "\u{001B}[B"), 1)
        XCTAssertEqual(KeyboardDetachedEditor.verticalDelta(command: "\u{001B}OB"), 1)
        XCTAssertNil(KeyboardDetachedEditor.verticalDelta(command: "\u{001B}[C"))
        XCTAssertNil(KeyboardDetachedEditor.verticalDelta(command: "a"))
    }

    func testDetachedBackspaceAndDeleteRespectCaret() {
        let state = KeyboardDetachedEditor.State(text: "🇺🇸foo", caret: 4)

        XCTAssertEqual(
            KeyboardDetachedEditor.apply(command: "\u{8}", to: state),
            .replace(.init(text: "foo", caret: 0))
        )
        XCTAssertEqual(
            KeyboardDetachedEditor.apply(command: "\u{7f}", to: state),
            .replace(.init(text: "🇺🇸oo", caret: 4))
        )
    }

    /// An enabled entry whose action is unrecognised must not abort matching; a
    /// later (e.g. TAB_X) shortcut sharing the combo should still match.
    func testMatchSkipsUnrecognisedActionEntry() throws {
        let doc = try EdexShortcutsDocument(jsonString: """
        [
          {"type":"app","trigger":"Ctrl+1","action":"BOGUS_ACTION","enabled":true},
          {"type":"app","trigger":"Ctrl+X","action":"TAB_X","enabled":true}
        ]
        """)
        let combo = KeyCombo(modifiers: [.control], key: .character("1"))
        XCTAssertEqual(doc.match(combo), .app(.tabTemplate, tabIndex: 0))
    }
}
