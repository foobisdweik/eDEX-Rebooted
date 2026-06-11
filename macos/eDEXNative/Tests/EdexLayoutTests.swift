import XCTest
@testable import EdexRenderingSupport

final class EdexLayoutTests: XCTestCase {
    private func visibleFixedRects(_ layout: EdexLayout) -> [(String, LayoutRect)] {
        [
            ("statusRibbon", layout.statusRibbon),
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

        XCTAssertEqual(layout.viewport.width, 1600, accuracy: 0.001)
        XCTAssertEqual(layout.viewport.height, 1000, accuracy: 0.001)
        XCTAssertFalse(layout.filesystem.isHidden)
        XCTAssertFalse(layout.keyboard.isHidden)
        assertNoIntersections(visibleFixedRects(layout))
        XCTAssertGreaterThanOrEqual(layout.keyboard.width, 420)
        XCTAssertGreaterThanOrEqual(layout.filesystem.width, 360)
        XCTAssertLessThanOrEqual(layout.mainShell.maxY, layout.keyboard.y)
    }

    func testStatusRibbonIsTopAnchoredAndColumnsStartBelowIt() {
        let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 1120, height: 700))

        XCTAssertLessThanOrEqual(layout.statusRibbon.y, 12)
        XCTAssertGreaterThanOrEqual(layout.leftColumn.y, layout.statusRibbon.maxY + 8)
        XCTAssertFalse(layout.statusRibbon.intersects(layout.leftColumn))
    }

    func testPerimeterLayoutFillsFullscreenFrame() {
        let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 1600, height: 1000))

        XCTAssertLessThanOrEqual(layout.leftColumn.y, 60)
        XCTAssertLessThanOrEqual(layout.mainShell.y, layout.leftColumn.y + 1)
        XCTAssertEqual(layout.rightColumn.y, layout.leftColumn.y, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(layout.leftColumn.maxY, 992)
        XCTAssertLessThanOrEqual(layout.rightColumn.maxY, layout.keyboard.y - 8)
        XCTAssertEqual(layout.filesystem.y, layout.keyboard.y, accuracy: 0.001)
        XCTAssertEqual(layout.filesystem.height, layout.keyboard.height, accuracy: 0.001)
    }

    func testKeyboardExtendsIntoBottomRightCornerBelowNetworkPanel() {
        let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 1600, height: 1000))

        XCTAssertLessThan(layout.keyboard.x, layout.rightColumn.x)
        XCTAssertGreaterThanOrEqual(layout.keyboard.frame.maxX, 1590)
        XCTAssertLessThanOrEqual(layout.rightColumn.maxY, layout.keyboard.y - 8)
        XCTAssertFalse(layout.rightColumn.intersects(layout.keyboard.frame))
        XCTAssertLessThanOrEqual(layout.keyboard.keySide, layout.keyboard.rowHeight * 0.85 + 0.001)
        XCTAssertGreaterThan(layout.keyboard.keySide, 40)
    }

    func testBottomBandPlacesFilesystemBeforeExpandedKeyboard() {
        let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 1600, height: 1000))

        XCTAssertFalse(layout.filesystem.isHidden)
        XCTAssertLessThan(layout.filesystem.x, layout.keyboard.x)
        XCTAssertGreaterThan(layout.filesystem.width, 360)
        XCTAssertGreaterThan(layout.keyboard.width, layout.filesystem.width)
        XCTAssertFalse(layout.filesystem.intersects(layout.keyboard.frame))
    }

    func testFourByThreeLayoutHidesFilesystemAndUsesNarrowKeyboardFallbacks() {
        let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 1200, height: 900))

        XCTAssertTrue(layout.filesystem.isHidden)
        XCTAssertFalse(layout.keyboard.isHidden)
        assertNoIntersections(visibleFixedRects(layout))
        XCTAssertGreaterThan(layout.keyboard.width, 0)
        XCTAssertGreaterThan(layout.keyboard.keySide, 0)
        XCTAssertEqual(layout.keyboard.spacebarWidth, 432, accuracy: 0.001)
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

    func testUltraWideLayoutKeepsFixedSurfacesSeparate() {
        let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 2560, height: 1080))

        XCTAssertFalse(layout.filesystem.isHidden)
        XCTAssertFalse(layout.keyboard.isHidden)
        assertNoIntersections(visibleFixedRects(layout))
    }

    func testTiledSixteenTenLayoutKeepsFixedSurfacesSeparate() {
        let layout = EdexLayoutEngine().layout(in: LayoutSize(width: 880, height: 550))

        XCTAssertFalse(layout.filesystem.isHidden)
        XCTAssertFalse(layout.keyboard.isHidden)
        XCTAssertLessThan(layout.filesystem.x, layout.keyboard.x)
        assertNoIntersections(visibleFixedRects(layout))
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
