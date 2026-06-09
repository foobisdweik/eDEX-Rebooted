import XCTest
@testable import EdexDomainSupport

@MainActor
final class NativeActionRoutingTests: XCTestCase {
    func testStubTerminalStoreRecordsInputAndTabSwitches() {
        let terminal = StubTerminalStore(activeCwd: "/tmp/start", activeTab: 1)

        terminal.sendInput("ls -la")
        terminal.switchTab(4)

        XCTAssertEqual(terminal.activeCwd, "/tmp/start")
        XCTAssertEqual(terminal.activeTab, 4)
        XCTAssertEqual(terminal.sentInputs, ["ls -la"])
    }

    func testStubTerminalStoreTabNavigationWrapsAndRecordsCopyPaste() {
        let terminal = StubTerminalStore(activeTab: 4)

        terminal.selectNextTab()
        XCTAssertEqual(terminal.activeTab, 0, "NEXT_TAB wraps past the last tab")

        terminal.selectPreviousTab()
        XCTAssertEqual(terminal.activeTab, 4, "PREVIOUS_TAB wraps past the first tab")

        terminal.switchTab(99)
        XCTAssertEqual(terminal.activeTab, 4, "an out-of-range switch is ignored")

        terminal.copySelection()
        terminal.copySelection()
        terminal.pasteClipboard()
        XCTAssertEqual(terminal.copyCount, 2)
        XCTAssertEqual(terminal.pasteCount, 1)
    }

    func testActionRouterForwardsTerminalAndModalActions() {
        let terminal = StubTerminalStore()
        var openedSettings = 0
        var openedFuzzyFinder = 0
        var closedModal = 0
        let router = EdexActionRouter(
            terminal: terminal,
            openSettings: { openedSettings += 1 },
            openFuzzyFinder: { openedFuzzyFinder += 1 },
            closeModal: { closedModal += 1 }
        )

        router.handle(.keyboardInput("pwd"))
        router.handle(.switchTerminal(2))
        router.handle(.openSettings)
        router.handle(.openFuzzyFinder)
        router.handle(.closeModal)

        XCTAssertEqual(terminal.sentInputs, ["pwd"])
        XCTAssertEqual(terminal.activeTab, 2)
        XCTAssertEqual(openedSettings, 1)
        XCTAssertEqual(openedFuzzyFinder, 1)
        XCTAssertEqual(closedModal, 1)
    }

    func testKeyboardStoreOwnsLayoutStatusModifiersAndPressedKeys() async throws {
        let store = KeyboardStore()

        store.status = "loaded"
        store.modifiers.toggle(.fn)
        store.pressVisual(id: "key-a", clearAfterNanoseconds: 1_000)

        XCTAssertEqual(store.status, "loaded")
        XCTAssertTrue(store.modifiers.fn)
        XCTAssertTrue(store.pressedKeyIDs.contains("key-a"))

        try await Task.sleep(for: .nanoseconds(20_000_000))
        XCTAssertFalse(store.pressedKeyIDs.contains("key-a"))
    }
}
