import XCTest
@testable import EdexRenderingSupport

final class TonemapTests: XCTestCase {
    func testIdentityWhenHeadroomIsOne() {
        // SDR-parity guarantee: at headroom 1.0 the SDR range is the identity and
        // HDR excursions clamp to paper white.
        let sdr = Tonemap(headroom: 1.0)
        for x in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(sdr.map(x), x, accuracy: 1e-12)
        }
        XCTAssertEqual(sdr.map(2.0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(sdr.map(1000.0), 1.0, accuracy: 1e-12)
    }

    func testHeadroomBelowOneIsTreatedAsSdr() {
        // A non-finite or sub-1.0 headroom is clamped to SDR rather than inverting
        // the roll-off math.
        XCTAssertEqual(Tonemap(headroom: 0.5).headroom, 1.0, accuracy: 1e-12)
        XCTAssertEqual(Tonemap(headroom: .nan).headroom, 1.0, accuracy: 1e-12)
        XCTAssertEqual(Tonemap(headroom: .infinity).headroom, 1.0, accuracy: 1e-12)
    }

    func testSdrRangeIsIdentityWithHeadroom() {
        // Below the paper-white knee the map is untouched even on an HDR display.
        let hdr = Tonemap(headroom: 8.0)
        XCTAssertEqual(hdr.map(0.0), 0.0, accuracy: 1e-12)
        XCTAssertEqual(hdr.map(0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(hdr.map(1.0), 1.0, accuracy: 1e-12) // C0 continuity at the knee
    }

    func testRollOffIsMonotonicAndAsymptotesToHeadroom() {
        let headroom = 8.0
        let hdr = Tonemap(headroom: headroom)
        let samples = [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 4.0, 16.0, 256.0, 1e6]
        var previous = -1.0
        for x in samples {
            let y = hdr.map(x)
            XCTAssertGreaterThanOrEqual(y, previous, "map must be monotonic non-decreasing")
            XCTAssertLessThanOrEqual(y, headroom, "map must never exceed headroom")
            previous = y
        }
        // Far above the knee it approaches, but never reaches, the headroom.
        let extreme = hdr.map(1e9)
        XCTAssertLessThanOrEqual(extreme, headroom)
        XCTAssertGreaterThan(extreme, headroom - 0.01)
    }

    func testFloorClampsTheLowEnd() {
        let withFloor = Tonemap(headroom: 8.0, floor: 0.05)
        XCTAssertEqual(withFloor.map(0.0), 0.05, accuracy: 1e-12)
        // Non-finite collapses to 0 then lifts to the floor.
        XCTAssertEqual(withFloor.map(.nan), 0.05, accuracy: 1e-12)
        // A value above the floor is unaffected by it.
        XCTAssertEqual(withFloor.map(0.5), 0.5, accuracy: 1e-12)
    }

    func testNegativeAndNonFiniteInputsAreSanitized() {
        let hdr = Tonemap(headroom: 8.0)
        XCTAssertEqual(hdr.map(-5.0), 0.0, accuracy: 1e-12)
        XCTAssertEqual(hdr.map(.nan), 0.0, accuracy: 1e-12)
        XCTAssertEqual(hdr.map(-.infinity), 0.0, accuracy: 1e-12)
    }

    func testRgbMapPreservesHue() {
        let hdr = Tonemap(headroom: 8.0)
        // Channels above the knee scale by a common factor, preserving ratios.
        let (r, g, b) = hdr.map(red: 4.0, green: 2.0, blue: 1.0)
        XCTAssertEqual(r / g, 4.0 / 2.0, accuracy: 1e-9)
        XCTAssertEqual(g / b, 2.0 / 1.0, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(r, hdr.headroom)
    }

    func testRgbMapGrayMatchesScalarMap() {
        let hdr = Tonemap(headroom: 8.0)
        let (r, g, b) = hdr.map(red: 2.0, green: 2.0, blue: 2.0)
        let scalar = hdr.map(2.0)
        XCTAssertEqual(r, scalar, accuracy: 1e-9)
        XCTAssertEqual(g, scalar, accuracy: 1e-9)
        XCTAssertEqual(b, scalar, accuracy: 1e-9)
    }

    func testRgbBlackReturnsFloor() {
        let withFloor = Tonemap(headroom: 8.0, floor: 0.05)
        let (r, g, b) = withFloor.map(red: 0.0, green: 0.0, blue: 0.0)
        XCTAssertEqual(r, 0.05, accuracy: 1e-12)
        XCTAssertEqual(g, 0.05, accuracy: 1e-12)
        XCTAssertEqual(b, 0.05, accuracy: 1e-12)
    }
}
