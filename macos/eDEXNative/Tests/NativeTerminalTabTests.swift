import XCTest
@testable import EdexDomainSupport

final class NativeTerminalTabTests: XCTestCase {
    func testDefaultsToFiveTabsActiveZero() {
        let tabs = TerminalTabSet()
        XCTAssertEqual(tabs.count, 5)
        XCTAssertEqual(tabs.active, 0)
        XCTAssertEqual(Array(tabs.indices), [0, 1, 2, 3, 4])
    }

    func testInitClampsOutOfRangeActiveIntoBounds() {
        XCTAssertEqual(TerminalTabSet(count: 5, active: 9).active, 4)
        XCTAssertEqual(TerminalTabSet(count: 5, active: -3).active, 0)
    }

    func testSelectMovesToValidIndex() {
        var tabs = TerminalTabSet()
        tabs.select(3)
        XCTAssertEqual(tabs.active, 3)
    }

    func testSelectIgnoresOutOfRangeIndex() {
        var tabs = TerminalTabSet(count: 5, active: 2)
        tabs.select(7)
        XCTAssertEqual(tabs.active, 2, "an invalid index must not move the selection")
        tabs.select(-1)
        XCTAssertEqual(tabs.active, 2)
    }

    func testSelectNextWrapsPastLast() {
        var tabs = TerminalTabSet(count: 5, active: 4)
        tabs.selectNext()
        XCTAssertEqual(tabs.active, 0)
    }

    func testSelectPreviousWrapsPastFirst() {
        var tabs = TerminalTabSet(count: 5, active: 0)
        tabs.selectPrevious()
        XCTAssertEqual(tabs.active, 4)
    }

    func testNextThenPreviousReturnsToStart() {
        var tabs = TerminalTabSet(count: 5, active: 2)
        tabs.selectNext()
        tabs.selectPrevious()
        XCTAssertEqual(tabs.active, 2)
    }

    func testValidReportsAddressableTabs() {
        let tabs = TerminalTabSet()
        XCTAssertEqual(tabs.valid(0), 0)
        XCTAssertEqual(tabs.valid(4), 4)
        XCTAssertNil(tabs.valid(5))
        XCTAssertNil(tabs.valid(-1))
    }
}
