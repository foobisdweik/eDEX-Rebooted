import XCTest
@testable import EdexRenderingSupport

final class DisplayHeadroomTests: XCTestCase {
    private let xdr = BrightnessProfile.builtInLiquidRetinaXDR // referenceHeadroom = 1600/203
    private let sdrProfile = BrightnessProfile.genericSDR       // referenceHeadroom = 1.0

    // MARK: - SDR parity (the no-regression guarantee)

    func testStaticSdrIsFullyClamped() {
        let h = DisplayHeadroom.sdr
        XCTAssertEqual(h.headroom, 1.0, accuracy: 1e-12)
        XCTAssertFalse(h.supportsExtendedRange)
        // Identity tonemap → a reference fill is unchanged → pixel parity.
        XCTAssertEqual(h.tonemap.map(0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(h.tonemap.map(2.0), 1.0, accuracy: 1e-12)
    }

    func testSdrDisplayWithHdrProfileStaysSdr() {
        // A capable profile on a display reporting no live headroom (1.0) must not
        // fabricate headroom — the SDR-correct-first rule.
        let h = DisplayHeadroom(
            profile: xdr, maximumEDR: 1.0, maximumPotentialEDR: 1.0, maximumReferenceEDR: 1.0
        )
        XCTAssertEqual(h.headroom, 1.0, accuracy: 1e-12)
        XCTAssertFalse(h.supportsExtendedRange)
        XCTAssertEqual(h.tonemap.map(0.25), 0.25, accuracy: 1e-12)
    }

    func testCapablePanelCurrentlyAtSdrFallsBack() {
        // Potential headroom is large (HDR panel), but live is 1.0 (e.g. on
        // battery / low brightness). The render path must use the SDR surface
        // until live headroom actually opens up.
        let h = DisplayHeadroom(
            profile: xdr, maximumEDR: 1.0, maximumPotentialEDR: 16.0, maximumReferenceEDR: 16.0
        )
        XCTAssertFalse(h.supportsExtendedRange)
        XCTAssertEqual(h.headroom, 1.0, accuracy: 1e-12)
        // Potential is still surfaced for diagnostics, never drives the surface.
        XCTAssertEqual(h.potentialMaxEDR, 16.0, accuracy: 1e-12)
    }

    // MARK: - HDR resolution: min(profile, live)

    func testLiveCeilingCapsProfile() {
        // Live headroom (2.0) is below the profile's reference (~7.88): the
        // tonemap must target what the display can actually show right now.
        let h = DisplayHeadroom(
            profile: xdr, maximumEDR: 2.0, maximumPotentialEDR: 16.0, maximumReferenceEDR: 16.0
        )
        XCTAssertTrue(h.supportsExtendedRange)
        XCTAssertEqual(h.headroom, 2.0, accuracy: 1e-9)
        XCTAssertEqual(h.tonemap.headroom, 2.0, accuracy: 1e-9)
    }

    func testProfileCapsLiveCeiling() {
        // Live headroom (16.0) exceeds the profile's authored peak (~7.88): never
        // promise more than the profile intends.
        let h = DisplayHeadroom(
            profile: xdr, maximumEDR: 16.0, maximumPotentialEDR: 16.0, maximumReferenceEDR: 16.0
        )
        XCTAssertTrue(h.supportsExtendedRange)
        XCTAssertEqual(h.headroom, xdr.referenceHeadroom, accuracy: 1e-9)
    }

    func testSdrProfileNeverLightsUpHeadroomOnHdrPanel() {
        // An SDR profile clamps to 1.0 even on a 16x-capable panel.
        let h = DisplayHeadroom(
            profile: sdrProfile, maximumEDR: 16.0, maximumPotentialEDR: 16.0, maximumReferenceEDR: 16.0
        )
        XCTAssertEqual(h.headroom, 1.0, accuracy: 1e-12)
        XCTAssertFalse(h.supportsExtendedRange)
    }

    // MARK: - Sanitization (guard the Double inputs, per repo discipline)

    func testNonFiniteAndSubUnityInputsCollapseToSdr() {
        for bad in [Double.nan, .infinity, -1.0, 0.0, 0.5] {
            let h = DisplayHeadroom(
                profile: xdr, maximumEDR: bad, maximumPotentialEDR: bad, maximumReferenceEDR: bad
            )
            XCTAssertEqual(h.headroom, 1.0, accuracy: 1e-12, "bad live EDR \(bad) should be SDR")
            XCTAssertFalse(h.supportsExtendedRange)
            XCTAssertEqual(h.liveMaxEDR, 1.0, accuracy: 1e-12)
            // NSScreen reports 0 for "not in a reference mode"; it normalizes to the
            // SDR sentinel 1.0, never leaks a sub-unity value downstream.
            XCTAssertEqual(h.referenceMaxEDR, 1.0, accuracy: 1e-12)
        }
    }

    func testExtendedRangeGateAgreesWithTonemapNearKnee() {
        // The surface-format gate (supportsExtendedRange) and the tonemap's SDR
        // boundary must not disagree at a headroom a hair above 1.0: an SDR surface
        // paired with a non-identity tonemap (or vice versa) would be incoherent.
        for delta in [1e-12, 1e-10, 1e-7, 1e-3] {
            let h = DisplayHeadroom(
                profile: xdr,
                maximumEDR: 1.0 + delta,
                maximumPotentialEDR: 16.0,
                maximumReferenceEDR: 16.0
            )
            // When we don't allocate an extended-range surface, the tonemap must be
            // the identity on [0, 1] (so the SDR fill is unchanged).
            if !h.supportsExtendedRange {
                XCTAssertEqual(h.tonemap.map(0.9), 0.9, accuracy: 1e-12, "delta \(delta)")
                XCTAssertEqual(h.tonemap.map(2.0), 1.0, accuracy: 1e-12, "delta \(delta)")
            }
        }
    }

    func testPotentialIsNeverBelowLive() {
        // A display reporting a smaller "potential" than "current" (incoherent)
        // must not yield potential < live.
        let h = DisplayHeadroom(
            profile: xdr, maximumEDR: 4.0, maximumPotentialEDR: 1.0, maximumReferenceEDR: 1.0
        )
        XCTAssertGreaterThanOrEqual(h.potentialMaxEDR, h.liveMaxEDR)
    }

    func testFloorPropagatesIntoTonemap() {
        // A profile floor must reach the per-frame operator unchanged.
        let floored = BrightnessProfile(
            id: "x", displayName: "x", referenceModeName: "x", gamut: .displayP3,
            paperWhiteNits: 200, maxWindow100Nits: 1000, maxWindow10Nits: 1000, minLuminanceNits: 20
        )
        let h = DisplayHeadroom(
            profile: floored, maximumEDR: 5.0, maximumPotentialEDR: 5.0, maximumReferenceEDR: 5.0
        )
        XCTAssertEqual(h.tonemap.floor, floored.luminanceFloorRatio, accuracy: 1e-12)
        XCTAssertEqual(h.tonemap.map(0.0), floored.luminanceFloorRatio, accuracy: 1e-12)
    }
}
