import XCTest
@testable import EdexRenderingSupport

final class BrightnessProfileTests: XCTestCase {
    func testDefaultIsBuiltInLiquidRetinaXDR() {
        let profile = BrightnessProfile.default
        XCTAssertEqual(profile, BrightnessProfile.builtInLiquidRetinaXDR)
        XCTAssertEqual(profile.id, "liquid-retina-xdr-16")
        XCTAssertEqual(profile.referenceModeName, "P3-1600")
        XCTAssertEqual(profile.gamut, .displayP3)
        XCTAssertEqual(profile.paperWhiteNits, 203, accuracy: 1e-9)
        XCTAssertEqual(profile.maxWindow100Nits, 1600, accuracy: 1e-9)
        XCTAssertEqual(profile.maxWindow10Nits, 1600, accuracy: 1e-9)
        XCTAssertEqual(profile.minLuminanceNits, 0, accuracy: 1e-9)
    }

    func testReferenceHeadroomOfBuiltInXDR() {
        // 1600-nit peak over a 203-nit paper white.
        XCTAssertEqual(BrightnessProfile.default.referenceHeadroom, 1600.0 / 203.0, accuracy: 1e-9)
        XCTAssertTrue(BrightnessProfile.default.isHDR)
        XCTAssertEqual(BrightnessProfile.default.luminanceFloorRatio, 0, accuracy: 1e-12)
    }

    func testGenericSdrHasUnityHeadroomAndIdentityTonemap() {
        let sdr = BrightnessProfile.genericSDR
        XCTAssertEqual(sdr.referenceHeadroom, 1.0, accuracy: 1e-12)
        XCTAssertFalse(sdr.isHDR)
        let tonemap = sdr.makeReferenceTonemap()
        XCTAssertEqual(tonemap.headroom, 1.0, accuracy: 1e-12)
        for x in stride(from: 0.0, through: 1.0, by: 0.25) {
            XCTAssertEqual(tonemap.map(x), x, accuracy: 1e-12)
        }
    }

    func testMakeReferenceTonemapMatchesProfile() {
        let profile = BrightnessProfile.default
        let tonemap = profile.makeReferenceTonemap()
        XCTAssertEqual(tonemap.headroom, profile.referenceHeadroom, accuracy: 1e-12)
        XCTAssertEqual(tonemap.floor, profile.luminanceFloorRatio, accuracy: 1e-12)
    }

    func testPresetLookupRoundTrips() {
        XCTAssertEqual(BrightnessProfile.presets.first, BrightnessProfile.default)
        for preset in BrightnessProfile.presets {
            XCTAssertEqual(BrightnessProfile.preset(id: preset.id), preset)
        }
        XCTAssertNil(BrightnessProfile.preset(id: "does-not-exist"))
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(BrightnessProfile.default)
        let decoded = try JSONDecoder().decode(BrightnessProfile.self, from: data)
        XCTAssertEqual(decoded, BrightnessProfile.default)
    }

    func testLuminanceFloorRatioIsClampedToPaperWhite() {
        // A degenerate profile whose floor exceeds paper white must not produce a
        // ratio > 1.0 (which would lift the tonemap floor above the knee).
        let degenerate = BrightnessProfile(
            id: "x",
            displayName: "x",
            referenceModeName: "x",
            gamut: .displayP3,
            paperWhiteNits: 203,
            maxWindow100Nits: 1600,
            maxWindow10Nits: 1600,
            minLuminanceNits: 5000
        )
        XCTAssertEqual(degenerate.luminanceFloorRatio, 1.0, accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(degenerate.luminanceFloorRatio, 0)
        XCTAssertLessThanOrEqual(degenerate.luminanceFloorRatio, 1.0)
    }

    func testNonFiniteAndNegativeInputsAreSanitized() {
        let degenerate = BrightnessProfile(
            id: "x",
            displayName: "x",
            referenceModeName: "x",
            gamut: .sRGB,
            paperWhiteNits: .nan,
            maxWindow100Nits: -100,
            maxWindow10Nits: .infinity,
            minLuminanceNits: .nan
        )
        // Paper white is floored to a positive value so headroom math is safe.
        XCTAssertGreaterThanOrEqual(degenerate.paperWhiteNits, 1)
        XCTAssertEqual(degenerate.maxWindow100Nits, 0, accuracy: 1e-12)
        XCTAssertEqual(degenerate.maxWindow10Nits, 0, accuracy: 1e-12)
        XCTAssertEqual(degenerate.minLuminanceNits, 0, accuracy: 1e-12)
        XCTAssertTrue(degenerate.referenceHeadroom.isFinite)
        XCTAssertGreaterThanOrEqual(degenerate.referenceHeadroom, 1.0)
    }
}
