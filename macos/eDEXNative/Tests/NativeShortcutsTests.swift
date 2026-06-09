import XCTest
@testable import EdexDomainSupport

final class NativeShortcutsTests: XCTestCase {

    // MARK: - KeyCombo parsing

    func testParseCtrlShiftC() {
        let combo = KeyCombo(trigger: "Ctrl+Shift+C")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.modifiers, [.control, .shift])
        XCTAssertEqual(combo?.key, .character("c"))
    }

    func testParseCtrlTab() {
        let combo = KeyCombo(trigger: "Ctrl+Tab")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.modifiers, [.control])
        XCTAssertEqual(combo?.key, .special(.tab))
    }

    func testParseCtrlShiftTab() {
        let combo = KeyCombo(trigger: "Ctrl+Shift+Tab")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.modifiers, [.control, .shift])
        XCTAssertEqual(combo?.key, .special(.tab))
    }

    func testParseFunctionKey() {
        let combo = KeyCombo(trigger: "Ctrl+Shift+F5")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.modifiers, [.control, .shift])
        XCTAssertEqual(combo?.key, .function(5))
    }

    func testParseF11() {
        let combo = KeyCombo(trigger: "F11")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.modifiers, [])
        XCTAssertEqual(combo?.key, .function(11))
    }

    func testParseCtrlShiftAltSpace() {
        let combo = KeyCombo(trigger: "Ctrl+Shift+Alt+Space")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.modifiers, [.control, .shift, .option])
        XCTAssertEqual(combo?.key, .special(.space))
    }

    func testParseAltMapsToOption() {
        let combo = KeyCombo(trigger: "Alt+F4")
        XCTAssertNotNil(combo)
        XCTAssertTrue(combo?.modifiers.contains(.option) == true)
    }

    func testParsePlusKey() {
        // "Ctrl++" means Ctrl and the + character — common for zoom/font-size.
        let combo = KeyCombo(trigger: "Ctrl++")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.modifiers, [.control])
        XCTAssertEqual(combo?.key, .character("+"))
    }

    func testParseBareplus() {
        // Bare "+" with no modifiers is a valid (if unusual) shortcut.
        let combo = KeyCombo(trigger: "+")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.modifiers, [])
        XCTAssertEqual(combo?.key, .character("+"))
    }

    func testParseInvalidTriggerReturnsNil() {
        XCTAssertNil(KeyCombo(trigger: ""))
        XCTAssertNil(KeyCombo(trigger: "NotAKey"))
        XCTAssertNil(KeyCombo(trigger: "Ctrl+"))
    }

    func testTabXExpansionRejectsNonXSuffix() {
        // A TAB_X entry whose trigger doesn't end "+x" or "+X" must not
        // expand — bare digit combos would swallow terminal number input.
        let badJSON = """
        [{"type":"app","trigger":"Ctrl+Tab","action":"TAB_X","enabled":true}]
        """
        let doc = try? EdexShortcutsDocument(jsonString: badJSON)
        XCTAssertEqual(doc?.expandedTabCombos().count, 0)
    }

    func testTabXExpansionEmptyTriggerRejects() {
        let badJSON = """
        [{"type":"app","trigger":"","action":"TAB_X","enabled":true}]
        """
        let doc = try? EdexShortcutsDocument(jsonString: badJSON)
        XCTAssertEqual(doc?.expandedTabCombos().count, 0)
    }

    func testKeyComboIsKeyInsensitive() {
        // Trigger keys are case-normalised to lowercase
        XCTAssertEqual(KeyCombo(trigger: "Ctrl+Shift+C")?.key, .character("c"))
        XCTAssertEqual(KeyCombo(trigger: "ctrl+shift+c")?.key, .character("c"))
    }

    // MARK: - AppShortcutAction

    func testKnownActionsParseCorrectly() {
        XCTAssertEqual(AppShortcutAction(rawValue: "COPY"), .copy)
        XCTAssertEqual(AppShortcutAction(rawValue: "PASTE"), .paste)
        XCTAssertEqual(AppShortcutAction(rawValue: "NEXT_TAB"), .nextTab)
        XCTAssertEqual(AppShortcutAction(rawValue: "PREVIOUS_TAB"), .previousTab)
        XCTAssertEqual(AppShortcutAction(rawValue: "SETTINGS"), .settings)
        XCTAssertEqual(AppShortcutAction(rawValue: "SHORTCUTS"), .shortcuts)
        XCTAssertEqual(AppShortcutAction(rawValue: "FUZZY_SEARCH"), .fuzzySearch)
        XCTAssertEqual(AppShortcutAction(rawValue: "FS_LIST_VIEW"), .fsListView)
        XCTAssertEqual(AppShortcutAction(rawValue: "FS_DOTFILES"), .fsDotfiles)
        XCTAssertEqual(AppShortcutAction(rawValue: "KB_PASSMODE"), .kbPassmode)
        XCTAssertEqual(AppShortcutAction(rawValue: "DEV_DEBUG"), .devDebug)
        XCTAssertEqual(AppShortcutAction(rawValue: "DEV_RELOAD"), .devReload)
        XCTAssertEqual(AppShortcutAction(rawValue: "TAB_X"), .tabTemplate)
    }

    func testUnknownActionReturnsNil() {
        XCTAssertNil(AppShortcutAction(rawValue: "NONEXISTENT"))
    }

    // MARK: - EdexShortcutsDocument JSON parsing

    private let defaultJSON = """
    [
      {"type":"app","trigger":"Ctrl+Shift+C","action":"COPY","enabled":true},
      {"type":"app","trigger":"Ctrl+Shift+V","action":"PASTE","enabled":true},
      {"type":"app","trigger":"Ctrl+Tab","action":"NEXT_TAB","enabled":true},
      {"type":"app","trigger":"Ctrl+Shift+Tab","action":"PREVIOUS_TAB","enabled":true},
      {"type":"app","trigger":"Ctrl+X","action":"TAB_X","enabled":true},
      {"type":"app","trigger":"Ctrl+Shift+S","action":"SETTINGS","enabled":true},
      {"type":"app","trigger":"Ctrl+Shift+K","action":"SHORTCUTS","enabled":true},
      {"type":"app","trigger":"Ctrl+Shift+F","action":"FUZZY_SEARCH","enabled":true},
      {"type":"app","trigger":"Ctrl+Shift+L","action":"FS_LIST_VIEW","enabled":true},
      {"type":"app","trigger":"Ctrl+Shift+H","action":"FS_DOTFILES","enabled":true},
      {"type":"app","trigger":"Ctrl+Shift+P","action":"KB_PASSMODE","enabled":true},
      {"type":"app","trigger":"Ctrl+Shift+I","action":"DEV_DEBUG","enabled":false},
      {"type":"app","trigger":"Ctrl+Shift+F5","action":"DEV_RELOAD","enabled":true},
      {"type":"shell","trigger":"Ctrl+Shift+Alt+Space","action":"neofetch","linebreak":true,"enabled":false}
    ]
    """

    func testParsesDefaultShortcutsJSON() throws {
        let doc = try EdexShortcutsDocument(jsonString: defaultJSON)
        XCTAssertEqual(doc.entries.count, 14)
    }

    func testAppEntriesFilteredCorrectly() throws {
        let doc = try EdexShortcutsDocument(jsonString: defaultJSON)
        let appEntries = doc.appEntries()
        XCTAssertEqual(appEntries.count, 13)
        XCTAssertTrue(appEntries.allSatisfy { $0.type == .app })
    }

    func testShellEntriesFilteredCorrectly() throws {
        let doc = try EdexShortcutsDocument(jsonString: defaultJSON)
        let shellEntries = doc.shellEntries()
        XCTAssertEqual(shellEntries.count, 1)
        XCTAssertEqual(shellEntries.first?.action, "neofetch")
        XCTAssertEqual(shellEntries.first?.linebreak, true)
    }

    func testDisabledEntriesRetainedInList() throws {
        let doc = try EdexShortcutsDocument(jsonString: defaultJSON)
        let disabled = doc.entries.filter { !$0.enabled }
        // DEV_DEBUG + shell neofetch are disabled
        XCTAssertEqual(disabled.count, 2)
    }

    func testTabXExpansionProducesFiveCombos() throws {
        let doc = try EdexShortcutsDocument(jsonString: defaultJSON)
        let expanded = doc.expandedTabCombos()
        XCTAssertEqual(expanded.count, 5)
        // Ctrl+1 through Ctrl+5
        for (index, (combo, tabIndex)) in expanded.enumerated() {
            XCTAssertEqual(tabIndex, index + 1)
            XCTAssertEqual(combo.modifiers, [.control])
            XCTAssertEqual(combo.key, .character(Character(String(index + 1))))
        }
    }

    func testTabXEntryTriggerIsTemplate() throws {
        let doc = try EdexShortcutsDocument(jsonString: defaultJSON)
        let tabEntry = doc.entries.first { $0.action == "TAB_X" }
        XCTAssertNotNil(tabEntry)
        // The template trigger itself is NOT parseable as a single combo
        // (trigger "Ctrl+X" has literal "X" which is a valid character, but
        // the action is TAB_X so expansion applies)
        XCTAssertEqual(tabEntry?.trigger, "Ctrl+X")
    }

    func testNonObjectTopLevelThrows() {
        XCTAssertThrowsError(try EdexShortcutsDocument(jsonString: "{}"))
        XCTAssertThrowsError(try EdexShortcutsDocument(jsonString: "42"))
        XCTAssertThrowsError(try EdexShortcutsDocument(jsonString: "\"string\""))
    }

    func testLinebreakDefaultsFalseForAppEntries() throws {
        let doc = try EdexShortcutsDocument(jsonString: defaultJSON)
        let copyEntry = doc.entries.first { $0.action == "COPY" }
        XCTAssertEqual(copyEntry?.linebreak, false)
    }

    func testEnabledActiveEntriesExcludesDisabled() throws {
        let doc = try EdexShortcutsDocument(jsonString: defaultJSON)
        // enabledEntries() returns only enabled non-template entries
        let active = doc.enabledEntries()
        XCTAssertTrue(active.allSatisfy { $0.enabled })
        // DEV_DEBUG and shell neofetch are both disabled
        XCTAssertFalse(active.contains { $0.action == "DEV_DEBUG" })
        XCTAssertFalse(active.contains { $0.action == "neofetch" })
    }

    // MARK: - Identifiable

    func testAllEntriesHaveUniqueIDs() throws {
        let doc = try EdexShortcutsDocument(jsonString: defaultJSON)
        let ids = doc.entries.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
