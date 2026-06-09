import XCTest
@testable import EdexRenderingSupport

final class TerminalAestheticMetricsTests: XCTestCase {
    func testGlowScalesWithViewportLikeLegacyCss() {
        // Legacy CSS expressed the terminal glow as `0 0 0.6vh rgba(accent, 0.6)`,
        // so at a 1000px viewport (vh = 10) the radius is 6pt and alpha 0.6.
        let metrics = TerminalAestheticMetrics(surfaceHeight: 603, vh: 10, intensity: 1.0)
        XCTAssertEqual(metrics.glowRadius, 6.0, accuracy: 0.0001)
        XCTAssertEqual(metrics.glowOpacity, 0.6, accuracy: 0.0001)
    }

    func testScanlineSpacingScalesWithViewportWithFloor() {
        let large = TerminalAestheticMetrics(surfaceHeight: 600, vh: 10, intensity: 1.0)
        XCTAssertEqual(large.scanlineSpacing, 3.0, accuracy: 0.0001)
        // Tiny viewport clamps to the 2pt floor so lines never collapse.
        let tiny = TerminalAestheticMetrics(surfaceHeight: 100, vh: 1, intensity: 1.0)
        XCTAssertEqual(tiny.scanlineSpacing, 2.0, accuracy: 0.0001)
    }

    func testScanlineCountFillsSurfaceHeight() {
        let metrics = TerminalAestheticMetrics(surfaceHeight: 603, vh: 10, intensity: 1.0)
        XCTAssertEqual(metrics.scanlineCount(forHeight: 603), 201)
    }

    func testIntensityScalesGlowAndScanlineOpacity() {
        let half = TerminalAestheticMetrics(surfaceHeight: 600, vh: 10, intensity: 0.5)
        XCTAssertEqual(half.glowRadius, 3.0, accuracy: 0.0001)
        XCTAssertEqual(half.glowOpacity, 0.3, accuracy: 0.0001)
        XCTAssertEqual(half.scanlineOpacity, 0.03, accuracy: 0.0001)
    }

    func testNonFiniteInputsCollapseToSafeGeometry() {
        let metrics = TerminalAestheticMetrics(surfaceHeight: .nan, vh: .nan, intensity: .nan)
        XCTAssertEqual(metrics.glowRadius, 0.0, accuracy: 0.0001)
        XCTAssertEqual(metrics.glowOpacity, 0.0, accuracy: 0.0001)
        XCTAssertEqual(metrics.scanlineSpacing, 2.0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(metrics.scanlineThickness, 0.0)
        // A degenerate height must not produce lines (guards the Canvas loop).
        XCTAssertEqual(metrics.scanlineCount(forHeight: .nan), 0)
        XCTAssertEqual(metrics.scanlineCount(forHeight: -50), 0)
    }

    func testAbsurdlyLargeHeightDoesNotTrapTheIntCast() {
        // `Int(Double)` traps when the value exceeds Int.max. A height past that
        // bound (divided by the 2pt floor) must clamp to 0 rather than crash —
        // the project's "guard every Double -> Int cast" rule.
        let metrics = TerminalAestheticMetrics(surfaceHeight: 600, vh: 10, intensity: 1.0)
        XCTAssertEqual(metrics.scanlineCount(forHeight: .greatestFiniteMagnitude), 0)
    }
}
