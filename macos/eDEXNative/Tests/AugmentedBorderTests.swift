import XCTest
@testable import EdexRenderingSupport

final class AugmentedBorderTests: XCTestCase {
    func testMainShellBorderMatchesLegacyClipAndOpacityMetrics() {
        let style = AugmentedBorderStyle.mainShell(vh: 10)

        XCTAssertEqual(style.corners, [.topRight, .bottomLeft])
        XCTAssertEqual(style.clipLength, 5, accuracy: 0.001)
        XCTAssertEqual(style.borderWidth, 1.8, accuracy: 0.001)
        XCTAssertEqual(style.borderOpacity, 0.5, accuracy: 0.001)
    }

    func testOutlinePointsClipRequestedCornersClockwise() {
        let geometry = AugmentedBorderGeometry(
            size: AugmentedBorderSize(width: 100, height: 80),
            style: AugmentedBorderStyle(
                corners: [.topRight, .bottomLeft],
                clipLength: 10,
                borderWidth: 1,
                borderOpacity: 0.5,
                tickLength: 0,
                tickOpacity: 0
            )
        )

        XCTAssertEqual(
            geometry.outlinePoints,
            [
                AugmentedPoint(x: 0, y: 0),
                AugmentedPoint(x: 90, y: 0),
                AugmentedPoint(x: 100, y: 10),
                AugmentedPoint(x: 100, y: 80),
                AugmentedPoint(x: 10, y: 80),
                AugmentedPoint(x: 0, y: 70)
            ]
        )
    }

    func testClipLengthClampsToHalfOfShortestDimension() {
        let geometry = AugmentedBorderGeometry(
            size: AugmentedBorderSize(width: 80, height: 40),
            style: AugmentedBorderStyle(
                corners: [.topLeft, .topRight, .bottomRight, .bottomLeft],
                clipLength: 80,
                borderWidth: 1,
                borderOpacity: 0.4,
                tickLength: 0,
                tickOpacity: 0
            )
        )

        XCTAssertEqual(geometry.effectiveClipLength, 20, accuracy: 0.001)
    }

    func testPanelTickMarksTrackEdgesInsideTheClippedOutline() {
        let style = AugmentedBorderStyle.panel(vh: 10)
        let geometry = AugmentedBorderGeometry(
            size: AugmentedBorderSize(width: 120, height: 80),
            style: style
        )

        XCTAssertEqual(style.borderWidth, 0.92, accuracy: 0.001)
        XCTAssertEqual(style.borderOpacity, 0.3, accuracy: 0.001)
        XCTAssertEqual(style.tickOpacity, 0.58, accuracy: 0.001)
        XCTAssertEqual(
            geometry.tickSegments,
            [
                AugmentedSegment(start: AugmentedPoint(x: 0, y: 0), end: AugmentedPoint(x: 18, y: 0)),
                AugmentedSegment(start: AugmentedPoint(x: 102, y: 80), end: AugmentedPoint(x: 120, y: 80))
            ]
        )
    }

    func testTopLeftClippingAndTickMarkConstraints() {
        let geometry = AugmentedBorderGeometry(
            size: AugmentedBorderSize(width: 100, height: 80),
            style: AugmentedBorderStyle(
                corners: [.topLeft, .topRight, .bottomRight, .bottomLeft],
                clipLength: 15,
                borderWidth: 1,
                borderOpacity: 0.5,
                tickLength: 90,
                tickOpacity: 0.5
            )
        )

        XCTAssertEqual(
            geometry.outlinePoints,
            [
                AugmentedPoint(x: 15, y: 0),
                AugmentedPoint(x: 85, y: 0),
                AugmentedPoint(x: 100, y: 15),
                AugmentedPoint(x: 100, y: 65),
                AugmentedPoint(x: 85, y: 80),
                AugmentedPoint(x: 15, y: 80),
                AugmentedPoint(x: 0, y: 65),
                AugmentedPoint(x: 0, y: 15)
            ]
        )

        XCTAssertEqual(
            geometry.tickSegments,
            [
                AugmentedSegment(start: AugmentedPoint(x: 15, y: 0), end: AugmentedPoint(x: 85, y: 0)),
                AugmentedSegment(start: AugmentedPoint(x: 15, y: 80), end: AugmentedPoint(x: 85, y: 80))
            ]
        )
    }
}
