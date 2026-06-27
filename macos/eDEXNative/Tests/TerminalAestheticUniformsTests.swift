import XCTest
@testable import EdexRenderingSupport

// Tests for TerminalAestheticUniforms — the Swift↔MSL uniform struct.
// These are pure-logic tests: no Metal device, no renderer, no window session.
// The memory-layout pin guards the Swift↔MSL layout contract (19 × 4 bytes = 76).

final class TerminalAestheticUniformsTests: XCTestCase {

    // MARK: - Fixtures

    private let stdMetrics = TerminalAestheticMetrics(surfaceHeight: 600, vh: 10, intensity: 1.0)
    private let sdrHeadroom = DisplayHeadroom.sdr
    private let noCRT = CRTSettings(curvature: false, bloom: false, chromaticAberration: false)
    private let allCRT = CRTSettings(curvature: true, bloom: true, chromaticAberration: true)

    // MARK: - Memory-layout pin (Swift↔MSL contract)

    func testMemoryLayoutIs76Bytes() {
        // 19 four-byte scalars (Float or UInt32) must pack to exactly 76 bytes.
        // If this ever fails, the MSL struct needs a matching update — never
        // silence this test by padding; fix the root cause in both languages.
        let expected = MemoryLayout<Float>.size * 19
        XCTAssertEqual(expected, 76)
        XCTAssertEqual(MemoryLayout<TerminalAestheticUniforms>.size, expected)
        XCTAssertEqual(MemoryLayout<TerminalAestheticUniforms>.stride, expected)
    }

    // MARK: - Surface pixel pass-through (inputs already in px; no rescaling)

    func testSurfaceWidthHeightStoredAsIs() {
        let u = makeUniforms(surfaceW: 2560, surfaceH: 1600, scale: 2.0)
        // Inputs are already in pixels; the initializer must NOT multiply by scale.
        XCTAssertEqual(u.surfaceWidthPx, 2560, accuracy: 0.001)
        XCTAssertEqual(u.surfaceHeightPx, 1600, accuracy: 0.001)
    }

    // MARK: - Metric pixel scaling (points × contentScale)

    func testScanlineSpacingScaledByContentScale() {
        let scale: Double = 2.0
        let u = makeUniforms(scale: scale)
        XCTAssertEqual(u.scanlineSpacingPx, Float(stdMetrics.scanlineSpacing * scale), accuracy: 0.001)
    }

    func testScanlineThicknessScaledByContentScale() {
        let scale: Double = 3.0
        let u = makeUniforms(scale: scale)
        XCTAssertEqual(u.scanlineThicknessPx, Float(stdMetrics.scanlineThickness * scale), accuracy: 0.001)
    }

    func testGlowRadiusScaledByContentScale() {
        let scale: Double = 2.0
        let u = makeUniforms(scale: scale)
        XCTAssertEqual(u.glowRadiusPx, Float(stdMetrics.glowRadius * scale), accuracy: 0.001)
    }

    func testOpacitiesNotRescaled() {
        // scanlineOpacity and glowOpacity are dimensionless (0–1); they must be
        // stored verbatim, never multiplied by contentScale.
        let u = makeUniforms(scale: 4.0)
        XCTAssertEqual(u.scanlineOpacity, Float(stdMetrics.scanlineOpacity), accuracy: 0.001)
        XCTAssertEqual(u.glowOpacity, Float(stdMetrics.glowOpacity), accuracy: 0.001)
    }

    // MARK: - Headroom + tonemap

    func testHeadroomAndFloorRatioFromSdr() {
        let u = makeUniforms(headroom: sdrHeadroom)
        XCTAssertEqual(u.headroom, Float(sdrHeadroom.headroom), accuracy: 1e-6)
        XCTAssertEqual(u.floorRatio, Float(sdrHeadroom.tonemap.floor), accuracy: 1e-6)
    }

    func testEncodeToGammaSdrIsOne() {
        // SDR surface → gamma-encode the output → encodeToGamma must be 1.
        XCTAssertFalse(sdrHeadroom.supportsExtendedRange)
        let u = makeUniforms(headroom: sdrHeadroom)
        XCTAssertEqual(u.encodeToGamma, 1)
    }

    func testEncodeToGammaHdrIsZero() {
        // An HDR headroom reports supportsExtendedRange == true → linear output
        // → encodeToGamma must be 0.
        let xdr = BrightnessProfile.builtInLiquidRetinaXDR
        let hdrHeadroom = DisplayHeadroom(
            profile: xdr,
            maximumEDR: 4.0,
            maximumPotentialEDR: 8.0,
            maximumReferenceEDR: 8.0
        )
        XCTAssertTrue(hdrHeadroom.supportsExtendedRange)
        let u = makeUniforms(headroom: hdrHeadroom)
        XCTAssertEqual(u.encodeToGamma, 0)
    }

    // MARK: - Accent color

    func testAccentLinearComponentsStoredVerbatim() {
        let u = makeUniforms(accentLinear: (r: 0.2, g: 0.7, b: 0.95))
        XCTAssertEqual(u.accentR, 0.2, accuracy: 1e-6)
        XCTAssertEqual(u.accentG, 0.7, accuracy: 1e-6)
        XCTAssertEqual(u.accentB, 0.95, accuracy: 1e-6)
    }

    func testNonFiniteUniformInputsCollapseToZeroAndDefaultScale() {
        let u = makeUniforms(
            surfaceW: .nan,
            surfaceH: .infinity,
            scale: .nan,
            accentLinear: (r: .nan, g: .infinity, b: -.infinity)
        )

        XCTAssertEqual(u.surfaceWidthPx, 0)
        XCTAssertEqual(u.surfaceHeightPx, 0)
        XCTAssertEqual(u.scanlineSpacingPx, Float(stdMetrics.scanlineSpacing), accuracy: 0.001)
        XCTAssertEqual(u.scanlineThicknessPx, Float(stdMetrics.scanlineThickness), accuracy: 0.001)
        XCTAssertEqual(u.glowRadiusPx, Float(stdMetrics.glowRadius), accuracy: 0.001)
        XCTAssertEqual(u.accentR, 0)
        XCTAssertEqual(u.accentG, 0)
        XCTAssertEqual(u.accentB, 0)
    }

    // MARK: - CRT bool → UInt32 mapping

    func testCrtAllFalseProducesZeroFlags() {
        let u = makeUniforms(crt: noCRT)
        XCTAssertEqual(u.crtCurvature, 0)
        XCTAssertEqual(u.crtBloom, 0)
        XCTAssertEqual(u.crtChromaticAberration, 0)
    }

    func testCrtAllTrueProducesOneFlags() {
        let u = makeUniforms(crt: allCRT)
        XCTAssertEqual(u.crtCurvature, 1)
        XCTAssertEqual(u.crtBloom, 1)
        XCTAssertEqual(u.crtChromaticAberration, 1)
    }

    func testCrtSettingsClampNegativeAndNonFiniteAmounts() {
        let crt = CRTSettings(
            curvature: true,
            bloom: true,
            chromaticAberration: true,
            curvatureAmount: -1,
            bloomAmount: .nan,
            chromaticAmount: .infinity
        )

        XCTAssertEqual(crt.curvatureAmount, 0)
        XCTAssertEqual(crt.bloomAmount, 0)
        XCTAssertEqual(crt.chromaticAmount, 0)
    }

    func testCrtAmountsAreCopiedAndChromaticOffsetScalesToPixels() {
        let crt = CRTSettings(
            curvature: true,
            bloom: true,
            chromaticAberration: true,
            curvatureAmount: 0.25,
            bloomAmount: 2.5,
            chromaticAmount: 1.75
        )
        let u = makeUniforms(scale: 3.0, crt: crt)

        XCTAssertEqual(u.crtCurvatureAmount, 0.25, accuracy: 1e-6)
        XCTAssertEqual(u.crtBloomAmount, 2.5, accuracy: 1e-6)
        XCTAssertEqual(u.crtChromaticAmount, 5.25, accuracy: 1e-6)
    }

    // MARK: - SDR parity (combined default-off intent)

    func testSdrNoCrtIsFullySdrCompatible() {
        // Default-off configuration: encodeToGamma==1, all CRT flags==0.
        // This is the guaranteed SDR parity state; regressions here break
        // the "default-off → identical to pre-Spike-C SDR output" contract.
        let u = makeUniforms(headroom: sdrHeadroom, crt: noCRT)
        XCTAssertEqual(u.encodeToGamma, 1, "SDR must encode to gamma")
        XCTAssertEqual(u.crtCurvature, 0)
        XCTAssertEqual(u.crtBloom, 0)
        XCTAssertEqual(u.crtChromaticAberration, 0)
    }

    // MARK: - Helpers

    private func makeUniforms(
        surfaceW: Double = 1920,
        surfaceH: Double = 1080,
        scale: Double = 2.0,
        accentLinear: (r: Double, g: Double, b: Double) = (r: 0.0, g: 1.0, b: 0.8),
        headroom: DisplayHeadroom? = nil,
        crt: CRTSettings? = nil
    ) -> TerminalAestheticUniforms {
        TerminalAestheticUniforms(
            metrics: stdMetrics,
            surfaceWidthPx: surfaceW,
            surfaceHeightPx: surfaceH,
            contentScale: scale,
            accentLinear: accentLinear,
            headroom: headroom ?? sdrHeadroom,
            crt: crt ?? noCRT
        )
    }
}
