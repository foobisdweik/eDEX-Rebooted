import XCTest
@testable import LayoutSupport

final class EdexLayoutTests: XCTestCase {
    func testSixteenByTenLayoutMatchesCssRegionProportions() {
        let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 1600, height: 1000))

        XCTAssertEqual(layout.viewport.width, 1600, accuracy: 0.001)
        XCTAssertEqual(layout.viewport.height, 1000, accuracy: 0.001)

        XCTAssertEqual(layout.leftColumn.x, -5.55, accuracy: 0.001)
        XCTAssertEqual(layout.leftColumn.y, 25, accuracy: 0.001)
        XCTAssertEqual(layout.leftColumn.width, 280, accuracy: 0.001)
        XCTAssertEqual(layout.leftColumn.height, 960, accuracy: 0.001)

        XCTAssertEqual(layout.mainShell.x, 280, accuracy: 0.001)
        XCTAssertEqual(layout.mainShell.y, 198.5, accuracy: 0.001)
        XCTAssertEqual(layout.mainShell.width, 1040, accuracy: 0.001)
        XCTAssertEqual(layout.mainShell.height, 603, accuracy: 0.001)

        XCTAssertEqual(layout.rightColumn.x, 1325.55, accuracy: 0.001)
        XCTAssertEqual(layout.rightColumn.y, 25, accuracy: 0.001)
        XCTAssertEqual(layout.rightColumn.width, 280, accuracy: 0.001)
        XCTAssertEqual(layout.rightColumn.height, 960, accuracy: 0.001)

        XCTAssertEqual(layout.filesystem.x, 904, accuracy: 0.001)
        XCTAssertEqual(layout.filesystem.y, 690.75, accuracy: 0.001)
        XCTAssertEqual(layout.filesystem.width, 688, accuracy: 0.001)
        XCTAssertEqual(layout.filesystem.height, 300, accuracy: 0.001)

        XCTAssertEqual(layout.keyboard.x, 356, accuracy: 0.001)
        XCTAssertEqual(layout.keyboard.y, 680.75, accuracy: 0.001)
        XCTAssertEqual(layout.keyboard.width, 888, accuracy: 0.001)
        XCTAssertEqual(layout.keyboard.height, 310, accuracy: 0.001)
        XCTAssertEqual(layout.keyboard.rowHeight, 52.8, accuracy: 0.001)
        XCTAssertEqual(layout.keyboard.keySide, 40, accuracy: 0.001)
        XCTAssertEqual(layout.keyboard.spacebarWidth, 450, accuracy: 0.001)
    }

    func testFourByThreeLayoutHidesFilesystemAndUsesNarrowKeyboardFallbacks() {
        let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 1200, height: 900))

        XCTAssertTrue(layout.filesystem.isHidden)
        XCTAssertEqual(layout.keyboard.x, 267, accuracy: 0.001)
        XCTAssertEqual(layout.keyboard.width, 666, accuracy: 0.001)
        XCTAssertEqual(layout.keyboard.keySide, 32.4, accuracy: 0.001)
        XCTAssertEqual(layout.keyboard.spacebarWidth, 432, accuracy: 0.001)
    }

    func testLayoutClampsTinyViewportsToNonNegativeFrameSizes() {
        let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 32, height: 20))

        XCTAssertGreaterThanOrEqual(layout.leftColumn.width, 0)
        XCTAssertGreaterThanOrEqual(layout.mainShell.width, 0)
        XCTAssertGreaterThanOrEqual(layout.rightColumn.width, 0)
        XCTAssertGreaterThanOrEqual(layout.filesystem.width, 0)
        XCTAssertGreaterThanOrEqual(layout.keyboard.width, 0)
    }
}
